defmodule PuckCoder.HaltPlugin do
  @moduledoc false
  @behaviour PuckCoder.Plugin

  defmodule Action do
    @moduledoc false
    defstruct type: "halt_me", reason: nil, seconds: nil
  end

  @impl true
  def name, do: "halt_me"

  @impl true
  def description, do: "Halts the agent loop for testing."

  @impl true
  def schema do
    Zoi.struct(
      Action,
      %{
        type: Zoi.literal("halt_me"),
        reason: Zoi.string(),
        seconds: Zoi.integer()
      },
      coerce: true
    )
  end

  @impl true
  def execute(%Action{reason: reason, seconds: seconds}, _executor_opts, _plugin_opts) do
    {:halt, "Halt recorded.", %{reason: reason, seconds: seconds}}
  end
end
