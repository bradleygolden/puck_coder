defmodule PuckCoder.LoopTest do
  use ExUnit.Case, async: true

  import Puck.Test, only: [verify_on_exit!: 1]

  setup :verify_on_exit!

  describe "run/2" do
    test "completes immediately when LLM returns Done" do
      client =
        Puck.Test.mock_client([
          %{"type" => "done", "message" => "Nothing to do."}
        ])

      assert {:ok, result} =
               PuckCoder.Loop.run("Do nothing", client: client)

      assert result.message == "Nothing to do."
      assert result.turns == 1
    end

    test "executes read_file then done" do
      tmp = Path.join(System.tmp_dir!(), "loop_test_#{System.unique_integer([:positive])}.txt")
      File.write!(tmp, "file content here")
      on_exit(fn -> File.rm(tmp) end)

      client =
        Puck.Test.mock_client([
          %{"type" => "read_file", "path" => tmp, "description" => "Reading file"},
          %{"type" => "done", "message" => "Read the file."}
        ])

      assert {:ok, result} =
               PuckCoder.Loop.run("Read a file", client: client)

      assert result.message == "Read the file."
      assert result.turns == 2
    end

    test "executes write_file then done" do
      tmp_dir = Path.join(System.tmp_dir!(), "loop_write_#{System.unique_integer([:positive])}")
      tmp = Path.join(tmp_dir, "new.txt")
      on_exit(fn -> File.rm_rf(tmp_dir) end)

      client =
        Puck.Test.mock_client([
          %{
            "type" => "write_file",
            "path" => tmp,
            "content" => "new content",
            "description" => "Writing file"
          },
          %{"type" => "done", "message" => "Wrote the file."}
        ])

      assert {:ok, result} =
               PuckCoder.Loop.run("Write a file", client: client)

      assert result.message == "Wrote the file."
      assert File.read!(tmp) == "new content"
    end

    test "executes shell then done" do
      client =
        Puck.Test.mock_client([
          %{"type" => "shell", "command" => "echo hello", "description" => "Running echo"},
          %{"type" => "done", "message" => "Ran the command."}
        ])

      assert {:ok, result} =
               PuckCoder.Loop.run("Run echo", client: client)

      assert result.message == "Ran the command."
      assert result.turns == 2
    end

    test "handles max_turns exceeded" do
      client =
        Puck.Test.mock_client(
          [
            %{"type" => "shell", "command" => "echo 1", "description" => "Step 1"},
            %{"type" => "shell", "command" => "echo 2", "description" => "Step 2"},
            %{"type" => "shell", "command" => "echo 3", "description" => "Step 3"}
          ],
          default: %{"type" => "shell", "command" => "echo loop", "description" => "Looping"}
        )

      assert {:error, :max_turns_exceeded, %{turns: 2}} =
               PuckCoder.Loop.run("Loop forever", client: client, max_turns: 2)
    end

    test "feeds error results back to LLM" do
      client =
        Puck.Test.mock_client([
          %{
            "type" => "read_file",
            "path" => "/nonexistent/does_not_exist.txt",
            "description" => "Reading missing file"
          },
          %{"type" => "done", "message" => "Handled the error."}
        ])

      assert {:ok, result} =
               PuckCoder.Loop.run("Try reading missing file", client: client)

      assert result.message == "Handled the error."
    end

    test "dispatches plugin action to plugin.execute/3" do
      tmp_dir = System.tmp_dir!()

      client =
        Puck.Test.mock_client([
          %{"type" => "list_dir", "path" => tmp_dir},
          %{"type" => "done", "message" => "Listed directory."}
        ])

      assert {:ok, result} =
               PuckCoder.Loop.run("List the temp dir",
                 client: client,
                 plugins: [{PuckCoder.TestPlugin, []}]
               )

      assert result.message == "Listed directory."
      assert result.turns == 2
    end

    test "plugin halt stops the loop" do
      client =
        Puck.Test.mock_client([
          %{"type" => "halt_me", "reason" => "sleepy", "seconds" => 30},
          %{"type" => "done", "message" => "Should never reach here."}
        ])

      assert {:halt, result} =
               PuckCoder.Loop.run("Halt test",
                 client: client,
                 plugins: [{PuckCoder.HaltPlugin, []}]
               )

      assert result.message == "Halt recorded."
      assert result.halt_metadata == %{reason: "sleepy", seconds: 30}
      assert result.turns == 1
    end

    test "passes plugin_opts to plugin.execute/3" do
      client =
        Puck.Test.mock_client([
          %{"type" => "capture", "value" => "hello"},
          %{"type" => "done", "message" => "Done."}
        ])

      assert {:ok, _result} =
               PuckCoder.Loop.run("Capture opts",
                 client: client,
                 plugins: [{PuckCoder.OptsCapturePlugin, [some: "opt"]}],
                 executor_opts: [cwd: "/tmp"]
               )

      assert_received {:captured, "hello", executor_opts, plugin_opts}
      assert executor_opts == [cwd: "/tmp"]
      assert plugin_opts == [some: "opt"]
    end
  end
end
