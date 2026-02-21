defmodule PuckCoder.Loop do
  @moduledoc """
  Recursive agent loop that calls the LLM and dispatches tool actions.

  Each iteration:
  1. Calls `Puck.stream/4` with the current context
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
  - `:on_llm_chunk` - Optional callback invoked for each streamed LLM chunk
  - `:on_llm_response` - Optional callback invoked after each parsed LLM response
  """
  def run(task, opts) do
    client = Keyword.fetch!(opts, :client)
    executor = Keyword.get(opts, :executor, PuckCoder.Executors.Local)
    executor_opts = Keyword.get(opts, :executor_opts, [])
    max_turns = Keyword.get(opts, :max_turns, 200)
    context = Keyword.get(opts, :context, Context.new())

    callbacks = %{
      on_llm_chunk: Keyword.get(opts, :on_llm_chunk),
      on_llm_response: Keyword.get(opts, :on_llm_response)
    }

    loop(client, task, context, executor, executor_opts, max_turns, 0, callbacks)
  end

  defp loop(
         _client,
         _input,
         context,
         _executor,
         _executor_opts,
         max_turns,
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
         turn,
         callbacks
       ) do
    case call_llm(client, input, context, callbacks) do
      {:ok, action, new_context} ->
        maybe_invoke_on_llm_response(callbacks, action, new_context, turn + 1)

        case action do
          %Done{message: message} ->
            {:ok, %{message: message, turns: turn + 1, context: new_context}}

          action ->
            result = execute_action(action, executor, executor_opts)

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
                label = action_label(action)
                result_text = format_result(label, action, result)

                loop(
                  client,
                  result_text,
                  new_context,
                  executor,
                  executor_opts,
                  max_turns,
                  turn + 1,
                  callbacks
                )
            end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call_llm(client, input, context, callbacks) do
    case Puck.stream(client, input, context, []) do
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
            with {:ok, parsed_action} <- parse_final_action(content) do
              metadata = chunk_metadata(last_chunk)

              maybe_invoke_on_llm_chunk(
                callbacks,
                final_chunk(parsed_action, metadata),
                stream_context
              )

              new_context =
                Context.add_message(stream_context, :assistant, parsed_action, metadata)

              {:ok, parsed_action, new_context}
            end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp content_from_chunk(%{type: :content, content: content}, _acc), do: content
  defp content_from_chunk(_chunk, acc), do: acc

  defp chunk_metadata(%{metadata: metadata}) when is_map(metadata), do: metadata
  defp chunk_metadata(_), do: %{}

  defp final_chunk(content, metadata) when is_map(metadata) do
    %{
      type: :content,
      content: content,
      metadata: Map.put(metadata, :partial, false)
    }
  end

  defp final_chunk(content, _metadata),
    do: %{type: :content, content: content, metadata: %{partial: false}}

  defp parse_final_action(%mod{} = action)
       when mod in [ReadFile, WriteFile, EditFile, Shell, Done],
       do: {:ok, action}

  defp parse_final_action(content), do: Zoi.parse(Tools.schema(), content)

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

  defp execute_action(%ReadFile{path: path}, executor, opts), do: executor.read_file(path, opts)

  defp execute_action(%WriteFile{path: path, content: content}, executor, opts),
    do: executor.write_file(path, content, opts)

  defp execute_action(%EditFile{path: path, old_string: old, new_string: new}, executor, opts),
    do: executor.edit_file(path, old, new, opts)

  defp execute_action(%Shell{command: command}, executor, opts), do: executor.exec(command, opts)

  defp execute_action(action, _executor, _opts), do: {:error, {:unknown_action, inspect(action)}}

  defp action_label(%ReadFile{}), do: "read_file"
  defp action_label(%WriteFile{}), do: "write_file"
  defp action_label(%EditFile{}), do: "edit_file"
  defp action_label(%Shell{}), do: "shell"
  defp action_label(_), do: "unknown"

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
  defp action_summary(action), do: inspect(action)
end
