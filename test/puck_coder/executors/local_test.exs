defmodule PuckCoder.Executors.LocalTest do
  use ExUnit.Case, async: true

  alias PuckCoder.Executors.Local

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "puck_coder_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    [tmp_dir: tmp_dir]
  end

  describe "read_file/2" do
    test "reads an existing file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "hello.txt")
      File.write!(path, "hello world")

      assert {:ok, "hello world"} = Local.read_file(path, [])
    end

    test "returns error for missing file" do
      assert {:error, :enoent} = Local.read_file("/nonexistent/path.txt", [])
    end
  end

  describe "write_file/3" do
    test "creates file and parent directories", %{tmp_dir: tmp_dir} do
      path = Path.join([tmp_dir, "nested", "dir", "file.ex"])

      assert :ok = Local.write_file(path, "defmodule Foo do\nend", [])
      assert File.read!(path) == "defmodule Foo do\nend"
    end

    test "overwrites existing file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "overwrite.txt")
      File.write!(path, "old")

      assert :ok = Local.write_file(path, "new", [])
      assert File.read!(path) == "new"
    end
  end

  describe "edit_file/4" do
    test "replaces first occurrence of old_string", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "edit.txt")
      File.write!(path, "foo bar foo baz")

      assert :ok = Local.edit_file(path, "foo", "qux", [])
      assert File.read!(path) == "qux bar foo baz"
    end

    test "returns error when old_string not found", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "edit2.txt")
      File.write!(path, "hello world")

      assert {:error, "old_string not found in " <> _} = Local.edit_file(path, "missing", "x", [])
    end

    test "returns error for missing file" do
      assert {:error, :enoent} = Local.edit_file("/nonexistent/path.txt", "a", "b", [])
    end
  end

  describe "exec/2" do
    test "runs a successful command" do
      assert {:ok, "hello\n"} = Local.exec("echo hello", [])
    end

    test "returns error for failed command" do
      assert {:error, "exit status 1:" <> _} = Local.exec("exit 1", [])
    end

    test "uses cwd option", %{tmp_dir: tmp_dir} do
      assert {:ok, output} = Local.exec("pwd", cwd: tmp_dir)
      assert String.ends_with?(String.trim(output), Path.basename(tmp_dir))
    end

    test "captures stderr" do
      assert {:error, "exit status 1:" <> output} = Local.exec("echo oops >&2 && exit 1", [])
      assert String.contains?(output, "oops")
    end
  end
end
