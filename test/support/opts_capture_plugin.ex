defmodule PuckCoder.OptsCapturePlugin do
  @moduledoc false
  @behaviour PuckCoder.Plugin

  defmodule Action do
    @moduledoc false
    defstruct type: "capture", value: nil
  end

  @impl true
  def name, do: "capture"

  @impl true
  def description, do: "Captures opts for testing."

  @impl true
  def schema do
    Zoi.struct(
      Action,
      %{
        type: Zoi.enum(["capture"]),
        value: Zoi.string()
      },
      coerce: true
    )
  end

  @impl true
  def execute(%Action{value: value}, executor_opts, plugin_opts) do
    send(self(), {:captured, value, executor_opts, plugin_opts})
    {:ok, "captured"}
  end
end
