defmodule PuckCoder.LoopTest do
  use ExUnit.Case, async: true

  import Puck.Test, only: [verify_on_exit!: 1]

  alias PuckCoder.Actions.{Done, Shell}

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
          %{"type" => "read_file", "path" => tmp},
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
          %{"type" => "write_file", "path" => tmp, "content" => "new content"},
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
          %{"type" => "shell", "command" => "echo hello"},
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
            %{"type" => "shell", "command" => "echo 1"},
            %{"type" => "shell", "command" => "echo 2"},
            %{"type" => "shell", "command" => "echo 3"}
          ],
          default: %{"type" => "shell", "command" => "echo loop"}
        )

      assert {:error, :max_turns_exceeded, %{turns: 2}} =
               PuckCoder.Loop.run("Loop forever", client: client, max_turns: 2)
    end

    test "feeds error results back to LLM" do
      client =
        Puck.Test.mock_client([
          %{"type" => "read_file", "path" => "/nonexistent/does_not_exist.txt"},
          %{"type" => "done", "message" => "Handled the error."}
        ])

      assert {:ok, result} =
               PuckCoder.Loop.run("Try reading missing file", client: client)

      assert result.message == "Handled the error."
    end

    test "calls on_action callback" do
      test_pid = self()

      client =
        Puck.Test.mock_client([
          %{"type" => "shell", "command" => "echo hi"},
          %{"type" => "done", "message" => "Done."}
        ])

      on_action = fn action, turn ->
        send(test_pid, {:action, action, turn})
      end

      assert {:ok, _result} =
               PuckCoder.Loop.run("Test callback", client: client, on_action: on_action)

      assert_received {:action, %Shell{command: "echo hi"}, 0}
      assert_received {:action, %Done{message: "Done."}, 1}
    end

    test "dispatches plugin action to plugin.execute/2" do
      tmp_dir = System.tmp_dir!()

      client =
        Puck.Test.mock_client([
          %{"type" => "list_dir", "path" => tmp_dir},
          %{"type" => "done", "message" => "Listed directory."}
        ])

      assert {:ok, result} =
               PuckCoder.Loop.run("List the temp dir",
                 client: client,
                 plugins: [PuckCoder.TestPlugin]
               )

      assert result.message == "Listed directory."
      assert result.turns == 2
    end
  end
end
