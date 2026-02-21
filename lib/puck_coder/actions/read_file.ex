defmodule PuckCoder.Actions.ReadFile do
  @moduledoc """
  Action struct for reading a file.
  """
  defstruct action: "read_file", path: nil, description: nil
end
