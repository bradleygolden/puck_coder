defmodule PuckCoder.Actions.Shell do
  @moduledoc """
  Action struct for executing a shell command.
  """
  defstruct action: "shell", command: nil, description: nil
end
