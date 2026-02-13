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
  - `:plugins` - List of `PuckCoder.Plugin` modules for custom actions
  """
  def run(task, opts) do
    client = Keyword.fetch!(opts, :client)
    executor = Keyword.get(opts, :executor, PuckCoder.Executors.Local)
    executor_opts = Keyword.get(opts, :executor_opts, [])
    max_turns = Keyword.get(opts, :max_turns, 200)
    on_action = Keyword.get(opts, :on_action)
    context = Keyword.get(opts, :context, Context.new())
    plugins = Keyword.get(opts, :plugins, [])

    plugin_map = build_plugin_map(plugins)
    context = Context.add_message(context, :user, task)

    loop(client, context, executor, executor_opts, max_turns, on_action, plugins, plugin_map, 0)
  end

  defp build_plugin_map(plugins) do
    Map.new(plugins, fn {mod, _opts} = plugin -> {mod.name(), plugin} end)
  end

  defp loop(
         _client,
         context,
         _executor,
         _executor_opts,
         max_turns,
         _on_action,
         _plugins,
         _plugin_map,
         turn
       )
       when turn >= max_turns do
    {:error, :max_turns_exceeded, %{turns: turn, context: context}}
  end

  defp loop(
         client,
         context,
         executor,
         executor_opts,
         max_turns,
         on_action,
         plugins,
         plugin_map,
         turn
       ) do
    case call_llm(client, context, plugins) do
      {:ok, action, new_context} ->
        if on_action, do: on_action.(action, turn)

        case action do
          %Done{message: message} ->
            {:ok, %{message: message, turns: turn + 1, context: new_context}}

          action ->
            result = execute_action(action, executor, executor_opts, plugin_map)

            case result do
              {:halt, message, metadata} ->
                {:halt,
                 %{
                   message: message,
                   turns: turn + 1,
                   context: new_context,
                   halt_metadata: metadata
                 }}

              _ ->
                label = action_label(action, plugin_map)
                result_text = format_result(label, action, result, plugin_map)
                updated_context = Context.add_message(new_context, :user, result_text)

                loop(
                  client,
                  updated_context,
                  executor,
                  executor_opts,
                  max_turns,
                  on_action,
                  plugins,
                  plugin_map,
                  turn + 1
                )
            end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call_llm(client, context, plugins) do
    case Puck.call(client, "Continue.", context, output_schema: Tools.schema(plugins)) do
      {:ok, response, new_context} ->
        {:ok, response.content, new_context}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Built-in action execution
  defp execute_action(%ReadFile{path: path}, executor, opts, _plugin_map) do
    executor.read_file(path, opts)
  end

  defp execute_action(%WriteFile{path: path, content: content}, executor, opts, _plugin_map) do
    executor.write_file(path, content, opts)
  end

  defp execute_action(
         %EditFile{path: path, old_string: old, new_string: new},
         executor,
         opts,
         _plugin_map
       ) do
    executor.edit_file(path, old, new, opts)
  end

  defp execute_action(%Shell{command: command}, executor, opts, _plugin_map) do
    executor.exec(command, opts)
  end

  # Plugin action dispatch
  defp execute_action(%{type: type_name} = action, _executor, opts, plugin_map) do
    case Map.get(plugin_map, type_name) do
      nil -> {:error, {:unknown_action, type_name}}
      {mod, plugin_opts} -> mod.execute(action, opts, plugin_opts)
    end
  end

  # Built-in action labels
  defp action_label(%ReadFile{}, _plugin_map), do: "read_file"
  defp action_label(%WriteFile{}, _plugin_map), do: "write_file"
  defp action_label(%EditFile{}, _plugin_map), do: "edit_file"
  defp action_label(%Shell{}, _plugin_map), do: "shell"
  defp action_label(%{type: type_name}, _plugin_map), do: type_name

  defp format_result(label, action, {:ok, output}, plugin_map) do
    "[#{label}] #{action_summary(action, plugin_map)}\n#{output}"
  end

  defp format_result(label, action, :ok, plugin_map) do
    "[#{label}] #{action_summary(action, plugin_map)}\nOK"
  end

  defp format_result(label, action, {:error, reason}, plugin_map) do
    "[#{label}] #{action_summary(action, plugin_map)}\n[ERROR] #{inspect(reason)}"
  end

  # Built-in action summaries
  defp action_summary(%ReadFile{path: path}, _plugin_map), do: path
  defp action_summary(%WriteFile{path: path}, _plugin_map), do: path
  defp action_summary(%EditFile{path: path}, _plugin_map), do: path
  defp action_summary(%Shell{command: cmd}, _plugin_map), do: cmd

  # Plugin action summaries
  defp action_summary(%{type: type_name} = action, plugin_map) do
    case Map.get(plugin_map, type_name) do
      nil ->
        inspect(action)

      {mod, _plugin_opts} ->
        if function_exported?(mod, :action_summary, 1) do
          mod.action_summary(action)
        else
          inspect(action)
        end
    end
  end
end
