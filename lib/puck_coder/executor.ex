defmodule PuckCoder.Executor do
  @moduledoc """
  Behaviour for executing coding agent tool actions.

  Implement this behaviour to control where and how file operations
  and shell commands run. The default implementation is
  `PuckCoder.Executors.Local` which operates directly on the local filesystem.

  ## Example

      defmodule MyExecutor do
        @behaviour PuckCoder.Executor

        @impl true
        def read_file(path, _opts), do: File.read(path)

        @impl true
        def write_file(path, content, _opts) do
          File.mkdir_p!(Path.dirname(path))
          File.write(path, content)
        end

        @impl true
        def edit_file(path, old_string, new_string, _opts) do
          case File.read(path) do
            {:ok, content} ->
              File.write(path, String.replace(content, old_string, new_string, global: false))
            error -> error
          end
        end

        @impl true
        def exec(command, _opts) do
          {output, status} = System.cmd("sh", ["-c", command], stderr_to_stdout: true)
          if status == 0, do: {:ok, output}, else: {:error, output}
        end
      end

  """

  @callback read_file(path :: String.t(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @callback write_file(path :: String.t(), content :: String.t(), opts :: keyword()) ::
              :ok | {:error, term()}

  @callback edit_file(
              path :: String.t(),
              old_string :: String.t(),
              new_string :: String.t(),
              opts :: keyword()
            ) :: :ok | {:error, term()}

  @callback exec(command :: String.t(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}
end
