defmodule Mitme.Acceptor.Supervisor do
  use Supervisor
  def start_link(args) do
    Supervisor.start_link __MODULE__, args, [name: __MODULE__]
  end
  def init args do
    children = [
      worker(Mitme.Acceptor, [args, :so])
    ]
    supervise(children, strategy: :one_for_one)
  end
end

defmodule Mitme.Acceptor do
  use GenServer
  def start_link port, type \\ nil do
    GenServer.start __MODULE__, [port, type], [name: __MODULE__]
  end

  def init [port, type] do
    IO.puts "listen on port #{port}"
    {:ok, listenSocket} = :gen_tcp.listen port, [
      {:ip, {0, 0, 0, 0}}, {:active, false}, {:reuseaddr, true}, {:nodelay, true}]
    {:ok, _} = :prim_inet.async_accept(listenSocket, -1)
    :ets.new :mitme_cache, [:public, :named_table, :ordered_set]
    {:ok, %{listen_socket: listenSocket, type: type, clients: []}}
  end

  def handle_info {:inet_async, listenSocket, _, {:ok, clientSocket}}, state=%{type: type} do
    :prim_inet.async_accept(listenSocket, -1)
    {:ok, pid} = Mitme.Gsm.start(nil)
    :inet_db.register_socket(clientSocket, :inet_tcp)
    :gen_tcp.controlling_process(clientSocket, pid)
    send pid, {:pass_socket, clientSocket}

    Process.monitor pid

    {:noreply, %{state | clients: [pid | state.clients]}}
  end

  def handle_call :get_clients, _from, state do

    {:reply, state.clients, state}
  end

  def handle_info {:inet_async, _listenSocket, _, error}, state do
    IO.puts "#{inspect __MODULE__}: Error in inet_async accept, shutting down. #{inspect error}"
    {:stop, error, state}
  end

  def handle_info _, state do
    {:noreply, state}
  end
end

defmodule Mitme.Gsm do
  use GenServer

  def start type do
    GenServer.start __MODULE__, type, []
  end

  def init type do

    {:ok,  %{}}
  end

  def handle_info {:tcp_closed, _}, state do
    IO.puts "connection closed"
    {:stop, {:shutdown, :tcp_closed}, state}
  end


  def handle_info {:tcp_error, _, _err}, state do
    IO.puts "connection closed"
    {:stop, {:shutdown, :tcp_error}, state}
  end

  def handle_info {:tcp, socket, bin}, flow = %{mode: :raw} do
     #proc bin

     %{sm: sm, dest: servs, source: clients} = flow

    case socket do
      ^servs ->
       :gen_tcp.send clients, bin
      clients ->
       :gen_tcp.send servs, bin
    end
     {:noreply, flow}
  end

  #test mode
  def handle_info {:pass_socket, clientSocket}, state do
    {:ok, {sourceAddr, sourcePort}} = :inet.peername(clientSocket)
    sourceAddrBin = :unicode.characters_to_binary(:inet_parse.ntoa(sourceAddr))
    sourceAddrBin = to_charlist sourceAddrBin

    #get SO_origdestination
    {:ok, [{:raw,0,80,info}]} = :inet.getopts(clientSocket,[{:raw, 0, 80, 16}])
    <<l::integer-size(16),
      destPort::big-integer-size(16),
      a::integer-size(8),
      b::integer-size(8),
      c::integer-size(8),
      d::integer-size(8),
      _::binary>> = info
    destAddr = {a,b,c,d}

    destAddrBin = :unicode.characters_to_binary(:inet_parse.ntoa(destAddr))
    destAddrBin = to_charlist destAddrBin

    #IO.inspect destAddrBin
    #IO.inspect destPort

    :ok = :inet.setopts(clientSocket, [{:active, true}, :binary])


    {:ok, serverSocket} = :gen_tcp.connect :binary.bin_to_list("127.0.0.1"), 1080, [{:active, false}, :binary]
    IO.inspect "connecting via proxy to #{destAddrBin}:#{destPort}"
    :gen_tcp.send serverSocket, <<5, 1, 0>>
    {:ok, <<5,0>>} = :gen_tcp.recv serverSocket, 0
    :gen_tcp.send serverSocket, <<5,1,0,1, a,b,c,d, destPort::integer-size(16)>>
    {:ok, realsocketreply} = :gen_tcp.recv serverSocket, 0
    if <<5, 0, 0, 1, 0, 0, 0, 0, 0, 0>> != realsocketreply do
      IO.inspect {"discarted reply from real sock server:", realsocketreply}
    end




    # {:ok, serverSocket} = :gen_tcp.connect destAddrBin, destPort, [
    #         {:active, true}, :binary]

    :inet.setopts(serverSocket, [{:active, :true}, :binary])

    #mode := [ :tera / :raw ]
    mode = :raw

    {:noreply,  %{
                  mode: mode,
                  sm: %{},
                  dest: serverSocket,
                  source: clientSocket,
                 }
            }

  end

  #sock5 implementation
  def handle_info {:pass_socket, clientSocket}, state do

    {:ok, [5, 1, 0]} = :gen_tcp.recv clientSocket, 3

    :gen_tcp.send clientSocket, <<5,0>>


    {:ok, moredata} = :gen_tcp.recv clientSocket, 0

    {destAddr, destPort} = case :binary.list_to_bin(moredata) do
      <<5,_,0,3, len, addr::binary-size(len), port::integer-size(16)>> ->
        {addr, port}
      <<5,_,0,1, a,b,c,d, port::integer-size(16)>> ->

        addr = :unicode.characters_to_binary(:inet_parse.ntoa({a,b,c,d}))

        {addr, port}

    end

    IO.inspect {"connecting to:", destAddr, destPort}

    {serverSocket, mode} = if (destPort == 443) or (destPort == 80) do

      {:ok, serverSocket} = :gen_tcp.connect :binary.bin_to_list("192.168.182.128"), 1081, [{:active, false}, :binary]

      :gen_tcp.send serverSocket, <<5, 1, 0>>

      {:ok, realsocketreply} = :gen_tcp.recv serverSocket, 0

      IO.inspect {"discarted reply from real sock server:", realsocketreply}

      :gen_tcp.send serverSocket, moredata


      {:ok, realsocketreply} = :gen_tcp.recv serverSocket, 0

      IO.inspect {"discarted reply from real sock server:", realsocketreply}

      {serverSocket, :raw}
    else
      {:ok, serverSocket} = :gen_tcp.connect :binary.bin_to_list(destAddr), destPort, [:binary]

      {serverSocket, :tera}
    end

    :gen_tcp.send clientSocket, <<5, 0, 0, 1, 0, 0, 0, 0, 0, 0>>

   :ok = :inet.setopts(clientSocket, [{:active, true}, :binary])

   :inet.setopts(serverSocket, [{:active, :true}])

    IO.inspect "connected"

    {:noreply,  %{
                  mode: mode,
                  sm: MSM.SM.create(),
                  xorkey: 0x0f,
                  dest: serverSocket,
                  source: clientSocket,
                  sdata: "",
                  cdata: ""
                 }
            }

  end
end
