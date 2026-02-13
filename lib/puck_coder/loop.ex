defmodule PuckCoder.Loop do
  @moduledoc """
  Recursive agent loop that calls the LLM and dispatches tool actions.

  Each iteration:
  1. Calls `Puck.call/4` with the current context
  2. Pattern matches the returned action struct
  3. Executes the action via the configured executor
  4. Feeds the result back as a user message
  5. Loops until `Done` or `max_turns` is reached
  """

  alias Puck.Context
  alias PuckCoder.Actions.{Done, EditFile, ReadFile, Shell, WriteFile}
  alias PuckCoder.Tools

  @doc """
  Runs the agent loop.

  ## Options

  - `:client` - `Puck.Client` to use for LLM calls (required)
  - `:executor` - Module implementing `PuckCoder.Executor` (default: `PuckCoder.Executors.Local`)
  - `:executor_opts` - Keyword list passed to executor callbacks
  - `:max_turns` - Maximum loop iterations (default: 200)
  - `:on_action` - Callback `fn action, turn -> :ok end` for observation
  - `:context` - Initial `Puck.Context` (default: fresh)
  """
  def run(task, opts) do
    client = Keyword.fetch!(opts, :client)
    executor = Keyword.get(opts, :executor, PuckCoder.Executors.Local)
    executor_opts = Keyword.get(opts, :executor_opts, [])
    max_turns = Keyword.get(opts, :max_turns, 200)
    on_action = Keyword.get(opts, :on_action)
    context = Keyword.get(opts, :context, Context.new())

    context = Context.add_message(context, :user, task)

    loop(client, context, executor, executor_opts, max_turns, on_action, 0)
  end

  defp loop(_client, context, _executor, _executor_opts, max_turns, _on_action, turn)
       when turn >= max_turns do
    {:error, :max_turns_exceeded, %{turns: turn, context: context}}
  end

  defp loop(client, context, executor, executor_opts, max_turns, on_action, turn) do
    case call_llm(client, context) do
      {:ok, action, new_context} ->
        if on_action, do: on_action.(action, turn)

        case action do
          %Done{message: message} ->
            {:ok, %{message: message, turns: turn + 1, context: new_context}}

          action ->
            result = execute_action(action, executor, executor_opts)
            label = action_label(action)
            result_text = format_result(label, action, result)
            updated_context = Context.add_message(new_context, :user, result_text)

            loop(
              client,
              updated_context,
              executor,
              executor_opts,
              max_turns,
              on_action,
              turn + 1
            )
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call_llm(client, context) do
    case Puck.call(client, "Continue.", context, output_schema: Tools.schema()) do
      {:ok, response, new_context} ->
        {:ok, response.content, new_context}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_action(%ReadFile{path: path}, executor, opts) do
    executor.read_file(path, opts)
  end

  defp execute_action(%WriteFile{path: path, content: content}, executor, opts) do
    executor.write_file(path, content, opts)
  end

  defp execute_action(%EditFile{path: path, old_string: old, new_string: new}, executor, opts) do
    executor.edit_file(path, old, new, opts)
  end

  defp execute_action(%Shell{command: command}, executor, opts) do
    executor.exec(command, opts)
  end

  defp action_label(%ReadFile{}), do: "read_file"
  defp action_label(%WriteFile{}), do: "write_file"
  defp action_label(%EditFile{}), do: "edit_file"
  defp action_label(%Shell{}), do: "shell"

  defp format_result(label, action, {:ok, output}) do
    "[#{label}] #{action_summary(action)}\n#{output}"
  end

  defp format_result(label, action, :ok) do
    "[#{label}] #{action_summary(action)}\nOK"
  end

  defp format_result(label, action, {:error, reason}) do
    "[#{label}] #{action_summary(action)}\n[ERROR] #{inspect(reason)}"
  end

  defp action_summary(%ReadFile{path: path}), do: path
  defp action_summary(%WriteFile{path: path}), do: path
  defp action_summary(%EditFile{path: path}), do: path
  defp action_summary(%Shell{command: cmd}), do: cmd
end
