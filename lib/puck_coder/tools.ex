defmodule PuckCoder.Tools do
  @moduledoc """
  Zoi schema for parsing LLM tool outputs into action structs.

  Builds a discriminated union over the `action` field, converting raw maps
  from BAML into typed Elixir structs.

  ## Example

      {:ok, %PuckCoder.Actions.ReadFile{path: "/tmp/foo.ex"}} =
        Zoi.parse(PuckCoder.Tools.schema(), %{"action" => "read_file", "path" => "/tmp/foo.ex"})

  """

  alias PuckCoder.Actions.{Done, EditFile, ReadFile, Shell, WriteFile}

  @doc """
  Returns the Zoi union schema for all coding agent actions.
  """
  def schema do
    Zoi.union([
      read_file_schema(),
      write_file_schema(),
      edit_file_schema(),
      shell_schema(),
      done_schema()
    ])
  end

  defp read_file_schema do
    Zoi.struct(
      ReadFile,
      %{
        action: Zoi.enum(["read_file"]),
        path: Zoi.string(),
        description: Zoi.string(description: "Brief user-friendly status shown to the user")
      },
      coerce: true
    )
  end

  defp write_file_schema do
    Zoi.struct(
      WriteFile,
      %{
        action: Zoi.enum(["write_file"]),
        path: Zoi.string(),
        content: Zoi.string(),
        description: Zoi.string(description: "Brief user-friendly status shown to the user")
      },
      coerce: true
    )
  end

  defp edit_file_schema do
    Zoi.struct(
      EditFile,
      %{
        action: Zoi.enum(["edit_file"]),
        path: Zoi.string(),
        old_string: Zoi.string(),
        new_string: Zoi.string(),
        description: Zoi.string(description: "Brief user-friendly status shown to the user")
      },
      coerce: true
    )
  end

  defp shell_schema do
    Zoi.struct(
      Shell,
      %{
        action: Zoi.enum(["shell"]),
        command: Zoi.string(),
        description: Zoi.string(description: "Brief user-friendly status shown to the user")
      },
      coerce: true
    )
  end

  defp done_schema do
    Zoi.struct(
      Done,
      %{
        action: Zoi.enum(["done"]),
        message: Zoi.string()
      },
      coerce: true
    )
  end
end
