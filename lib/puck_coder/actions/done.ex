defmodule PuckCoder.Actions.Done do
  @moduledoc """
  Action struct signaling task completion.
  """
  defstruct type: "done", message: nil
end
