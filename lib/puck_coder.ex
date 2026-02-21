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

  ## With Skills

      {:ok, result} = PuckCoder.run("Extract text from the PDF",
        skills: [
          %{name: "pdf-processing", description: "Extract text from PDFs.", path: "/skills/pdf/SKILL.md"}
        ]
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
  - `:skills` - List of `PuckCoder.Skill` structs or maps with `:name`, `:description`, `:path`
  - `:executor` - Module implementing `PuckCoder.Executor` (default: `PuckCoder.Executors.Local`)
  - `:executor_opts` - Keyword list passed to executor callbacks (e.g., `[cwd: "/path"]`)
  - `:hooks` - `Puck.Hooks` module(s) for lifecycle events (set on the client)
  - `:on_llm_chunk` - Optional callback invoked for each streamed LLM chunk
  - `:on_llm_response` - Optional callback invoked after each parsed LLM response
  - `:max_turns` - Maximum loop iterations (default: #{@default_max_turns})
  - `:context` - Initial `Puck.Context` (default: fresh)

  ## Returns

  - `{:ok, %{message: String.t(), turns: integer(), context: Puck.Context.t()}}` on success
  - `{:halt, %{message: String.t(), turns: integer(), context: Puck.Context.t(), halt_metadata: map()}}` when execution requests halt
  - `{:error, reason}` on failure
  - `{:error, :max_turns_exceeded, metadata}` if the agent didn't finish in time

  ## Examples

      {:ok, result} = PuckCoder.run("Add a test for the User module")
      IO.puts(result.message)
      # => "Added test/user_test.exs with 3 test cases covering create, update, and delete."

  """
  def run(task, opts \\ []) do
    {client_opts, loop_opts} = split_opts(opts)
    reject_plugins!(opts)

    skills = normalize_skills(client_opts)

    client = build_client(client_opts, skills)

    loop_opts =
      loop_opts
      |> Keyword.put(:client, client)
      |> Keyword.put_new(:max_turns, @default_max_turns)

    PuckCoder.Loop.run(task, loop_opts)
  end

  @doc """
  Returns the default system prompt used when bypassing BAML.

  Use this when passing a custom `:client` to preserve the agent's
  core behavior.

  ## Example

      client = Puck.Client.new(
        {Puck.Backends.ReqLLM, "anthropic:claude-sonnet-4-5"},
        system_prompt: PuckCoder.default_system_prompt()
      )

  """
  def default_system_prompt(skills \\ []) do
    base = """
    You are an expert coding agent. You modify codebases by reading files, writing files, editing files, and running shell commands.

    Guidelines:
    - Read files before editing to understand current content.
    - Use edit_file for surgical changes. Use write_file only for new files or complete rewrites.
    - Run tests after making changes when applicable.
    - If a tool call fails, read the error and try a different approach.
    - If the user requests something that does not match any available action, use the done action to explain what you can do instead.
    """

    case build_skill_instructions(skills) do
      "" -> base
      skill_text -> base <> "\n" <> skill_text <> "\n"
    end
  end

  defp split_opts(opts) do
    {client_keys, loop_keys} =
      Enum.split_with(opts, fn {k, _} ->
        k in [:client, :client_registry, :instructions, :skills, :hooks]
      end)

    {client_keys, loop_keys}
  end

  defp build_client(opts, skills) do
    case Keyword.get(opts, :client) do
      %Puck.Client{} = client ->
        client

      nil ->
        build_baml_client(opts, skills)
    end
  end

  defp build_baml_client(opts, skills) do
    base_instructions = Keyword.get(opts, :instructions, "")
    skill_text = build_skill_instructions(skills)

    instructions =
      [base_instructions]
      |> maybe_append(skill_text, skill_text != "")
      |> Enum.join("\n\n")

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

    hooks = Keyword.get(opts, :hooks)
    Puck.Client.new({Puck.Backends.Baml, backend_config}, hooks: hooks)
  end

  defp build_skill_instructions([]), do: ""
  defp build_skill_instructions(skills), do: PuckCoder.Skill.to_prompt(skills)

  defp normalize_skills(opts) do
    opts
    |> Keyword.get(:skills, [])
    |> Enum.map(fn
      %PuckCoder.Skill{} = skill -> skill
      attrs -> PuckCoder.Skill.new!(attrs)
    end)
  end

  defp maybe_append(list, _text, false), do: list
  defp maybe_append(list, text, true), do: list ++ [text]

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

  defp reject_plugins!(opts) do
    if Keyword.has_key?(opts, :plugins) do
      raise ArgumentError,
            "plugins are no longer supported by PuckCoder; use built-in actions (read_file, write_file, edit_file, shell, done)"
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
