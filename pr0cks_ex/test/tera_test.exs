defmodule TeraTest do
  use ExUnit.Case
  doctest Tera

  test "the truth" do
    assert 1 + 1 == 2
  end

end

defmodule FormatPacketsTest do
  use ExUnit.Case, async: true
  
  doctest FormatPackets

end
