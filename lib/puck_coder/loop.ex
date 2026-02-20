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
  - `:context` - Initial `Puck.Context` (default: fresh)
  - `:plugins` - List of `PuckCoder.Plugin` modules for custom actions
  - `:on_llm_chunk` - Optional callback invoked for each streamed LLM chunk
  - `:on_llm_response` - Optional callback invoked after each parsed LLM response
  """
  def run(task, opts) do
    client = Keyword.fetch!(opts, :client)
    executor = Keyword.get(opts, :executor, PuckCoder.Executors.Local)
    executor_opts = Keyword.get(opts, :executor_opts, [])
    max_turns = Keyword.get(opts, :max_turns, 200)
    context = Keyword.get(opts, :context, Context.new())
    plugins = Keyword.get(opts, :plugins, [])

    callbacks = %{
      on_llm_chunk: Keyword.get(opts, :on_llm_chunk),
      on_llm_response: Keyword.get(opts, :on_llm_response)
    }

    plugin_map = build_plugin_map(plugins)

    loop(
      client,
      task,
      context,
      executor,
      executor_opts,
      max_turns,
      plugins,
      plugin_map,
      0,
      callbacks
    )
  end

  defp build_plugin_map(plugins) do
    Map.new(plugins, fn {mod, _opts} = plugin -> {mod.name(), plugin} end)
  end

  defp loop(
         _client,
         _input,
         context,
         _executor,
         _executor_opts,
         max_turns,
         _plugins,
         _plugin_map,
         turn,
         _callbacks
       )
       when turn >= max_turns do
    {:error, :max_turns_exceeded, %{turns: turn, context: context}}
  end

  defp loop(
         client,
         input,
         context,
         executor,
         executor_opts,
         max_turns,
         plugins,
         plugin_map,
         turn,
         callbacks
       ) do
    case call_llm(client, input, context, plugins, callbacks) do
      {:ok, action, new_context} ->
        maybe_invoke_on_llm_response(callbacks, action, new_context, turn + 1)

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

                loop(
                  client,
                  result_text,
                  new_context,
                  executor,
                  executor_opts,
                  max_turns,
                  plugins,
                  plugin_map,
                  turn + 1,
                  callbacks
                )
            end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call_llm(client, input, context, plugins, callbacks) do
    backend_opts =
      []
      |> maybe_put_dynamic_classes(plugins)
      |> maybe_put_schema_descriptions(plugins)

    opts = [output_schema: Tools.schema(plugins), backend_opts: backend_opts]

    case Puck.stream(client, input, context, opts) do
      {:ok, stream, stream_context} ->
        {last_chunk, final_content} =
          Enum.reduce(stream, {nil, nil}, fn chunk, {_last_chunk, acc_content} ->
            maybe_invoke_on_llm_chunk(callbacks, chunk, stream_context)
            {chunk, content_from_chunk(chunk, acc_content)}
          end)

        case final_content do
          nil ->
            {:error, :empty_stream}

          content ->
            metadata = chunk_metadata(last_chunk)
            new_context = Context.add_message(stream_context, :assistant, content, metadata)
            {:ok, content, new_context}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp content_from_chunk(%{type: :content, content: content}, _acc), do: content
  defp content_from_chunk(_chunk, acc), do: acc

  defp chunk_metadata(%{metadata: metadata}) when is_map(metadata), do: metadata
  defp chunk_metadata(_), do: %{}

  defp maybe_invoke_on_llm_chunk(%{on_llm_chunk: nil}, _chunk, _context), do: :ok

  defp maybe_invoke_on_llm_chunk(%{on_llm_chunk: callback}, chunk, context) do
    try do
      cond do
        is_function(callback, 2) -> callback.(chunk, context)
        is_function(callback, 1) -> callback.(chunk)
        true -> :ok
      end
    rescue
      _ -> :ok
    end
  end

  defp maybe_invoke_on_llm_response(%{on_llm_response: nil}, _action, _context, _turn), do: :ok

  defp maybe_invoke_on_llm_response(%{on_llm_response: callback}, action, context, turn) do
    try do
      cond do
        is_function(callback, 3) -> callback.(action, context, turn)
        is_function(callback, 2) -> callback.(action, context)
        is_function(callback, 1) -> callback.(action)
        true -> :ok
      end
    rescue
      _ -> :ok
    end
  end

  defp maybe_put_dynamic_classes(backend_opts, plugins) do
    dc =
      plugins
      |> Enum.filter(fn {mod, _opts} -> function_exported?(mod, :type_builder_fields, 0) end)
      |> Enum.reduce(%{}, fn {mod, _opts}, acc ->
        Enum.reduce(mod.type_builder_fields(), acc, fn
          %{class: class, modules: modules}, inner ->
            Map.update(inner, class, modules, &(&1 ++ modules))

          invalid, _inner ->
            raise ArgumentError,
                  "#{inspect(mod)}.type_builder_fields/0 returned invalid entry: #{inspect(invalid)}. " <>
                    "Each entry must be a map with :class and :modules keys."
        end)
      end)

    plugin_modules =
      Enum.flat_map(plugins, fn {mod, _opts} ->
        case mod.schema() do
          %Zoi.Types.Struct{module: action_mod} -> [action_mod]
          _ -> []
        end
      end)

    dc =
      if plugin_modules != [] do
        Map.update(dc, "PluginAction", plugin_modules, &(&1 ++ plugin_modules))
      else
        dc
      end

    case dc do
      dc when map_size(dc) > 0 -> Keyword.put(backend_opts, :dynamic_classes, dc)
      _ -> backend_opts
    end
  end

  defp maybe_put_schema_descriptions(backend_opts, plugins) do
    desc = Map.new(plugins, fn {mod, _opts} -> {mod.name(), mod.description()} end)

    case desc do
      desc when map_size(desc) > 0 -> Keyword.put(backend_opts, :schema_descriptions, desc)
      _ -> backend_opts
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
