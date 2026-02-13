defmodule PuckCoderTest do
  use ExUnit.Case, async: true

  import Puck.Test, only: [verify_on_exit!: 1]

  setup :verify_on_exit!

  describe "run/2" do
    test "runs a simple task to completion" do
      client =
        Puck.Test.mock_client([
          %{"type" => "done", "message" => "Task complete."}
        ])

      assert {:ok, result} = PuckCoder.run("Do something", client: client)
      assert result.message == "Task complete."
    end

    test "passes executor option through" do
      tmp = Path.join(System.tmp_dir!(), "api_test_#{System.unique_integer([:positive])}.txt")
      File.write!(tmp, "original")
      on_exit(fn -> File.rm(tmp) end)

      client =
        Puck.Test.mock_client([
          %{"type" => "read_file", "path" => tmp},
          %{"type" => "done", "message" => "Read it."}
        ])

      assert {:ok, result} =
               PuckCoder.run("Read the file",
                 client: client,
                 executor: PuckCoder.Executors.Local
               )

      assert result.message == "Read it."
    end
  end

  describe "default_system_prompt/0" do
    test "returns a non-empty string" do
      prompt = PuckCoder.default_system_prompt()
      assert is_binary(prompt)
      assert String.contains?(prompt, "coding agent")
    end
  end
end
