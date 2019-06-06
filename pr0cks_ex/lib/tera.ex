defmodule Tera do
  @moduledoc """
  Documentation for Tera.
  """

  def start(_,_) do
    #to be removed
    :ets.new :packets_counter, [:public, :named_table,:ordered_set]
    :ets.new :packets_log, [:public, :named_table,:ordered_set]

    :ets.new :routing_table, [:public, :named_table, :ordered_set]

    # :ets.insert :routing_table, {{"192.168.3.90", :*, :*, 7500}, componentx}
    # :ets.insert :routing_table, {{"192.168.3.90", :*, :*, {7200, 7300}}, componenty}

    Mitme.Acceptor.Supervisor.start_link 8086

  end
end
