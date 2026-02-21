defmodule PuckCoder.Actions.Done do
  @moduledoc """
  Action struct signaling task completion.
  """
  defstruct action: "done", message: nil
end
