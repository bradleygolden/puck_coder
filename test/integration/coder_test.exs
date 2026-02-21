defmodule PuckCoder.Integration.CoderTest do
  use PuckCoder.IntegrationCase, async: false

  @moduletag timeout: 300_000

  describe "read_file" do
    test "agent reads a file and reports its contents", %{
      client_registry: client_registry,
      tmp_dir: tmp_dir
    } do
      file_path = Path.join(tmp_dir, "hello.txt")
      File.write!(file_path, "The magic number is 42.")

      assert {:ok, result} =
               PuckCoder.run(
                 "Read the file at #{file_path} and tell me what it says. Include the exact contents in your reply_to_user message.",
                 client_registry: client_registry,
                 executor_opts: [cwd: tmp_dir],
                 max_turns: 10
               )

      assert result.message =~ "42"
    end
  end

  describe "write_file" do
    test "agent creates a new file with specific content", %{
      client_registry: client_registry,
      tmp_dir: tmp_dir
    } do
      file_path = Path.join(tmp_dir, "greeting.txt")

      assert {:ok, _result} =
               PuckCoder.run(
                 "Create a file at #{file_path} with the exact content: Hello from PuckCoder!",
                 client_registry: client_registry,
                 executor_opts: [cwd: tmp_dir],
                 max_turns: 10
               )

      assert File.exists?(file_path)
      assert File.read!(file_path) =~ "Hello from PuckCoder!"
    end
  end

  describe "edit_file" do
    test "agent edits an existing file", %{
      client_registry: client_registry,
      tmp_dir: tmp_dir
    } do
      file_path = Path.join(tmp_dir, "config.txt")
      File.write!(file_path, "color = red\nsize = large\n")

      assert {:ok, _result} =
               PuckCoder.run(
                 "Edit the file at #{file_path} and change the color from red to blue. Do not change anything else.",
                 client_registry: client_registry,
                 executor_opts: [cwd: tmp_dir],
                 max_turns: 10
               )

      content = File.read!(file_path)
      assert content =~ "blue"
      refute content =~ "red"
    end
  end

  describe "shell" do
    test "agent runs a shell command and reports output", %{
      client_registry: client_registry,
      tmp_dir: tmp_dir
    } do
      assert {:ok, result} =
               PuckCoder.run(
                 "Run the shell command: echo PUCK_TEST_OUTPUT_12345 — then include the output in your reply_to_user message.",
                 client_registry: client_registry,
                 executor_opts: [cwd: tmp_dir],
                 max_turns: 10
               )

      assert result.message =~ "PUCK_TEST_OUTPUT_12345"
    end
  end

  describe "multi-step task" do
    test "agent fixes a bug and verifies the fix", %{
      client_registry: client_registry,
      tmp_dir: tmp_dir
    } do
      script_path = Path.join(tmp_dir, "greet.sh")

      File.write!(script_path, """
      #!/bin/sh
      echo "Helo, World!"
      """)

      File.chmod!(script_path, 0o755)

      assert {:ok, _result} =
               PuckCoder.run(
                 """
                 The shell script at #{script_path} has a typo: it prints "Helo, World!" instead of "Hello, World!".
                 Fix the typo in the file, then run the script to verify it prints "Hello, World!".
                 """,
                 client_registry: client_registry,
                 executor_opts: [cwd: tmp_dir],
                 max_turns: 10
               )

      content = File.read!(script_path)
      assert content =~ "Hello, World!"
      refute content =~ "Helo, World!"
    end
  end
end
