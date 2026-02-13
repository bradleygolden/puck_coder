defmodule PuckCoder.Executors.Local do
  @moduledoc """
  Executes tool actions directly on the local filesystem.

  ## Options

  - `:cwd` - Working directory for shell commands (default: `File.cwd!/0`)
  - `:timeout` - Shell command timeout in milliseconds (default: `60_000`)

  """

  @behaviour PuckCoder.Executor

  @default_timeout 60_000

  @impl true
  def read_file(path, _opts) do
    File.read(path)
  end

  @impl true
  def write_file(path, content, _opts) do
    File.mkdir_p!(Path.dirname(path))
    File.write(path, content)
  end

  @impl true
  def edit_file(path, old_string, new_string, _opts) do
    case File.read(path) do
      {:ok, content} ->
        if String.contains?(content, old_string) do
          new_content = String.replace(content, old_string, new_string, global: false)
          File.write(path, new_content)
        else
          {:error, "old_string not found in #{path}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def exec(command, opts) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    task =
      Task.async(fn ->
        System.cmd("sh", ["-c", command], stderr_to_stdout: true, cd: cwd)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, 0}} ->
        {:ok, output}

      {:ok, {output, status}} ->
        {:error, "exit status #{status}: #{output}"}

      nil ->
        {:error, "command timed out after #{timeout}ms"}
    end
  end
end
