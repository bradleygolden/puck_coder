defmodule PuckCoder.TestPlugin do
  @moduledoc false
  @behaviour PuckCoder.Plugin

  defmodule Action do
    @moduledoc false
    defstruct type: "list_dir", path: nil
  end

  @impl true
  def name, do: "list_dir"

  @impl true
  def description, do: "List files in a directory. Params: path (string)."

  @impl true
  def schema do
    Zoi.struct(
      Action,
      %{
        type: Zoi.literal("list_dir"),
        path: Zoi.string()
      },
      coerce: true
    )
  end

  @impl true
  def execute(%Action{path: path}, _opts) do
    case File.ls(path) do
      {:ok, entries} -> {:ok, Enum.join(entries, "\n")}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def action_summary(%Action{path: path}), do: path
end
