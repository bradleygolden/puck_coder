defmodule PuckCoder.Actions.Shell do
  @moduledoc """
  Action struct for executing a shell command.
  """
  defstruct type: "shell", command: nil
end
