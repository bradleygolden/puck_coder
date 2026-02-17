defmodule PuckCoder.Actions.WriteFile do
  @moduledoc """
  Action struct for writing a file.
  """
  defstruct type: "write_file", path: nil, content: nil, description: nil
end
