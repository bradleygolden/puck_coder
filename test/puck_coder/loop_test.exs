defmodule PuckCoder.LoopTest do
  use ExUnit.Case, async: true

  import Puck.Test, only: [verify_on_exit!: 1]

  setup :verify_on_exit!

  describe "run/2" do
    test "completes immediately when LLM returns reply_to_user" do
      client =
        Puck.Test.mock_client([
          %{"action" => "reply_to_user", "message" => "Here is your answer."}
        ])

      assert {:ok, result} =
               PuckCoder.Loop.run("Answer directly", client: client)

      assert result.message == "Here is your answer."
      assert result.turns == 1
    end

    test "executes read_file then reply_to_user" do
      tmp = Path.join(System.tmp_dir!(), "loop_test_#{System.unique_integer([:positive])}.txt")
      File.write!(tmp, "file content here")
      on_exit(fn -> File.rm(tmp) end)

      client =
        Puck.Test.mock_client([
          %{"action" => "read_file", "path" => tmp, "description" => "Reading file"},
          %{"action" => "reply_to_user", "message" => "Read the file."}
        ])

      assert {:ok, result} =
               PuckCoder.Loop.run("Read a file", client: client)

      assert result.message == "Read the file."
      assert result.turns == 2
    end

    test "executes write_file then reply_to_user" do
      tmp_dir = Path.join(System.tmp_dir!(), "loop_write_#{System.unique_integer([:positive])}")
      tmp = Path.join(tmp_dir, "new.txt")
      on_exit(fn -> File.rm_rf(tmp_dir) end)

      client =
        Puck.Test.mock_client([
          %{
            "action" => "write_file",
            "path" => tmp,
            "content" => "new content",
            "description" => "Writing file"
          },
          %{"action" => "reply_to_user", "message" => "Wrote the file."}
        ])

      assert {:ok, result} =
               PuckCoder.Loop.run("Write a file", client: client)

      assert result.message == "Wrote the file."
      assert File.read!(tmp) == "new content"
    end

    test "executes shell then reply_to_user" do
      client =
        Puck.Test.mock_client([
          %{"action" => "shell", "command" => "echo hello", "description" => "Running echo"},
          %{"action" => "reply_to_user", "message" => "Ran the command."}
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
            %{"action" => "shell", "command" => "echo 1", "description" => "Step 1"},
            %{"action" => "shell", "command" => "echo 2", "description" => "Step 2"},
            %{"action" => "shell", "command" => "echo 3", "description" => "Step 3"}
          ],
          default: %{"action" => "shell", "command" => "echo loop", "description" => "Looping"}
        )

      assert {:error, :max_turns_exceeded, %{turns: 2}} =
               PuckCoder.Loop.run("Loop forever", client: client, max_turns: 2)
    end

    test "feeds error results back to LLM" do
      client =
        Puck.Test.mock_client([
          %{
            "action" => "read_file",
            "path" => "/nonexistent/does_not_exist.txt",
            "description" => "Reading missing file"
          },
          %{"action" => "reply_to_user", "message" => "Handled the error."}
        ])

      assert {:ok, result} =
               PuckCoder.Loop.run("Try reading missing file", client: client)

      assert result.message == "Handled the error."
    end

    test "invokes streaming callbacks for chunks and parsed responses" do
      test_pid = self()

      client =
        Puck.Test.mock_client([
          %{"action" => "reply_to_user", "message" => "Streamed completion."}
        ])

      assert {:ok, result} =
               PuckCoder.Loop.run("Do nothing",
                 client: client,
                 on_llm_chunk: fn chunk, _context -> send(test_pid, {:llm_chunk, chunk}) end,
                 on_llm_response: fn action, _context, turn ->
                   send(test_pid, {:llm_response, action, turn})
                 end
               )

      assert result.message == "Streamed completion."

      assert_receive {:llm_chunk,
                      %{
                        type: :content,
                        content: %PuckCoder.Actions.ReplyToUser{message: "Streamed completion."}
                      }}

      assert_receive {:llm_response,
                      %PuckCoder.Actions.ReplyToUser{message: "Streamed completion."}, 1}
    end
  end
end
