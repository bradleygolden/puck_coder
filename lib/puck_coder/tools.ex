defmodule PuckCoder.Tools do
  @moduledoc """
  Zoi schema for parsing LLM tool outputs into action structs.

  Builds a discriminated union over the `type` field, converting raw maps
  from BAML into typed Elixir structs.

  ## Example

      {:ok, %PuckCoder.Actions.ReadFile{path: "/tmp/foo.ex"}} =
        Zoi.parse(PuckCoder.Tools.schema(), %{"type" => "read_file", "path" => "/tmp/foo.ex"})

  """

  alias PuckCoder.Actions.{Done, EditFile, ReadFile, Shell, WriteFile}

  @doc """
  Returns the Zoi union schema for all coding agent actions.

  Accepts an optional list of plugin modules whose schemas are appended
  to the built-in union. With no arguments, returns built-in actions only.
  """
  def schema(plugins \\ []) do
    plugin_schemas = Enum.map(plugins, & &1.schema())

    Zoi.union(
      [
        read_file_schema(),
        write_file_schema(),
        edit_file_schema(),
        shell_schema(),
        done_schema()
      ] ++ plugin_schemas
    )
  end

  defp read_file_schema do
    Zoi.struct(
      ReadFile,
      %{
        type: Zoi.literal("read_file"),
        path: Zoi.string()
      },
      coerce: true
    )
  end

  defp write_file_schema do
    Zoi.struct(
      WriteFile,
      %{
        type: Zoi.literal("write_file"),
        path: Zoi.string(),
        content: Zoi.string()
      },
      coerce: true
    )
  end

  defp edit_file_schema do
    Zoi.struct(
      EditFile,
      %{
        type: Zoi.literal("edit_file"),
        path: Zoi.string(),
        old_string: Zoi.string(),
        new_string: Zoi.string()
      },
      coerce: true
    )
  end

  defp shell_schema do
    Zoi.struct(
      Shell,
      %{
        type: Zoi.literal("shell"),
        command: Zoi.string()
      },
      coerce: true
    )
  end

  defp done_schema do
    Zoi.struct(
      Done,
      %{
        type: Zoi.literal("done"),
        message: Zoi.string()
      },
      coerce: true
    )
  end
end
