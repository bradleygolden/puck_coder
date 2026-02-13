defmodule PuckCoder do
  @moduledoc """
  A native Elixir coding agent built on Puck.

  PuckCoder gives you a programmable coding agent with 4 tools
  (read, write, edit, bash) that runs entirely inside your BEAM process.
  Point it at a task, and it reads files, makes changes, runs tests,
  and self-corrects until done.

  ## Quick Start

      {:ok, result} = PuckCoder.run("Add a test for the User module")
      IO.puts(result.message)

  ## With Custom Instructions

      {:ok, result} = PuckCoder.run("Refactor the auth module",
        instructions: "Always use pattern matching over if/else."
      )

  ## With Custom LLM Provider

      {:ok, result} = PuckCoder.run("Fix the failing test",
        client_registry: %{
          "primary" => "MyClient",
          "clients" => [
            %{"name" => "MyClient", "provider" => "anthropic",
              "options" => %{"model" => "claude-sonnet-4-5"}}
          ]
        }
      )

  ## With Non-BAML Backend

      client = Puck.Client.new(
        {Puck.Backends.ReqLLM, "anthropic:claude-sonnet-4-5"},
        system_prompt: PuckCoder.default_system_prompt()
      )
      {:ok, result} = PuckCoder.run("Fix the bug", client: client)

  ## With Plugins

      {:ok, result} = PuckCoder.run("Check if example.com is up",
        plugins: [MyApp.Plugins.HttpGet],
        executor_opts: [cwd: "/my/project"]
      )

  """

  @default_max_turns 200

  @doc """
  Runs the coding agent on a task.

  ## Arguments

  - `task` - String describing what to do
  - `opts` - Options (see below)

  ## Options

  - `:client` - Custom `Puck.Client` (bypasses BAML, use your own system prompt)
  - `:client_registry` - BAML client registry for runtime LLM provider config
  - `:instructions` - Extra instructions injected into the BAML prompt
  - `:plugins` - List of `PuckCoder.Plugin` modules for custom actions
  - `:executor` - Module implementing `PuckCoder.Executor` (default: `PuckCoder.Executors.Local`)
  - `:executor_opts` - Keyword list passed to executor callbacks (e.g., `[cwd: "/path"]`)
  - `:max_turns` - Maximum loop iterations (default: #{@default_max_turns})
  - `:on_action` - Callback `fn action, turn -> :ok end` for per-turn observation
  - `:context` - Initial `Puck.Context` (default: fresh)

  ## Returns

  - `{:ok, %{message: String.t(), turns: integer(), context: Puck.Context.t()}}` on success
  - `{:error, reason}` on failure
  - `{:error, :max_turns_exceeded, metadata}` if the agent didn't finish in time

  ## Examples

      {:ok, result} = PuckCoder.run("Add a test for the User module")
      IO.puts(result.message)
      # => "Added test/user_test.exs with 3 test cases covering create, update, and delete."

  """
  def run(task, opts \\ []) do
    {client_opts, loop_opts} = split_opts(opts)
    plugins = Keyword.get(loop_opts, :plugins, [])
    client = build_client(client_opts, plugins)

    loop_opts =
      loop_opts
      |> Keyword.put(:client, client)
      |> Keyword.put_new(:max_turns, @default_max_turns)

    PuckCoder.Loop.run(task, loop_opts)
  end

  @doc """
  Returns the default system prompt used when bypassing BAML.

  Use this when passing a custom `:client` to preserve the agent's
  core behavior. Pass plugins to include their descriptions in the prompt.

  ## Example

      client = Puck.Client.new(
        {Puck.Backends.ReqLLM, "anthropic:claude-sonnet-4-5"},
        system_prompt: PuckCoder.default_system_prompt()
      )

  """
  def default_system_prompt(plugins \\ []) do
    base = """
    You are an expert coding agent. You modify codebases by reading files, writing files, editing files, and running shell commands.

    Available actions (respond with exactly one JSON object per turn):
    - {"type": "read_file", "path": "<absolute path>"} — Read a file.
    - {"type": "write_file", "path": "<absolute path>", "content": "<full content>"} — Write a file (creates if needed).
    - {"type": "edit_file", "path": "<absolute path>", "old_string": "<exact match>", "new_string": "<replacement>"} — Replace first occurrence of old_string.
    - {"type": "shell", "command": "<command>"} — Execute a shell command.
    - {"type": "done", "message": "<summary>"} — Signal task completion.

    Guidelines:
    - Read files before editing to understand current content.
    - Use edit_file for surgical changes. Use write_file only for new files or complete rewrites.
    - Run tests after making changes when applicable.
    - If a tool call fails, read the error and try a different approach.
    """

    case build_plugin_instructions(plugins) do
      "" -> base
      plugin_text -> base <> "\nAdditional actions:\n" <> plugin_text <> "\n"
    end
  end

  defp split_opts(opts) do
    {client_keys, loop_keys} =
      Enum.split_with(opts, fn {k, _} ->
        k in [:client, :client_registry, :instructions]
      end)

    {client_keys, loop_keys}
  end

  defp build_client(opts, plugins) do
    case Keyword.get(opts, :client) do
      %Puck.Client{} = client ->
        client

      nil ->
        build_baml_client(opts, plugins)
    end
  end

  defp build_baml_client(opts, plugins) do
    base_instructions = Keyword.get(opts, :instructions, "")
    plugin_text = build_plugin_instructions(plugins)

    instructions =
      case plugin_text do
        "" -> base_instructions
        text -> base_instructions <> "\n\nAdditional actions:\n" <> text
      end

    client_registry = Keyword.get(opts, :client_registry)

    backend_config =
      %{
        function: "CoderRun",
        args_format: :auto,
        args: fn messages ->
          %{
            messages: format_messages(messages),
            instructions: instructions
          }
        end,
        path: Application.app_dir(:puck_coder, "priv/baml_src")
      }
      |> maybe_put(:client_registry, client_registry)

    Puck.Client.new({Puck.Backends.Baml, backend_config})
  end

  defp build_plugin_instructions([]), do: ""

  defp build_plugin_instructions(plugins) do
    Enum.map_join(plugins, "\n", fn plugin ->
      "- #{plugin.name()}: #{plugin.description()}"
    end)
  end

  defp format_messages(messages) do
    Enum.map(messages, fn %Puck.Message{role: role, content: content} ->
      %{
        role: to_string(role),
        content: extract_text(content)
      }
    end)
  end

  defp extract_text(parts) when is_list(parts) do
    parts
    |> Enum.filter(&(&1.type == :text))
    |> Enum.map_join("\n", & &1.text)
  end

  defp extract_text(other) when is_binary(other), do: other
  defp extract_text(_), do: ""

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
