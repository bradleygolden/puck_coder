defmodule PuckCoder.ToolsTest do
  use ExUnit.Case, async: true

  alias PuckCoder.Actions.{Done, EditFile, ReadFile, Shell, WriteFile}
  alias PuckCoder.Tools

  describe "schema/0" do
    test "parses read_file action" do
      input = %{
        "action" => "read_file",
        "path" => "/tmp/foo.ex",
        "description" => "Reading config"
      }

      assert {:ok,
              %ReadFile{action: "read_file", path: "/tmp/foo.ex", description: "Reading config"}} =
               Zoi.parse(Tools.schema(), input)
    end

    test "parses write_file action" do
      input = %{
        "action" => "write_file",
        "path" => "/tmp/bar.ex",
        "content" => "hello",
        "description" => "Saving file"
      }

      assert {:ok,
              %WriteFile{
                action: "write_file",
                path: "/tmp/bar.ex",
                content: "hello",
                description: "Saving file"
              }} =
               Zoi.parse(Tools.schema(), input)
    end

    test "parses edit_file action" do
      input = %{
        "action" => "edit_file",
        "path" => "/tmp/baz.ex",
        "old_string" => "foo",
        "new_string" => "bar",
        "description" => "Updating value"
      }

      assert {:ok,
              %EditFile{
                action: "edit_file",
                path: "/tmp/baz.ex",
                old_string: "foo",
                new_string: "bar",
                description: "Updating value"
              }} =
               Zoi.parse(Tools.schema(), input)
    end

    test "parses shell action" do
      input = %{"action" => "shell", "command" => "mix test", "description" => "Running tests"}

      assert {:ok, %Shell{action: "shell", command: "mix test", description: "Running tests"}} =
               Zoi.parse(Tools.schema(), input)
    end

    test "parses done action" do
      input = %{"action" => "done", "message" => "All done!"}
      assert {:ok, %Done{action: "done", message: "All done!"}} = Zoi.parse(Tools.schema(), input)
    end

    test "rejects unknown action" do
      input = %{"action" => "unknown", "foo" => "bar"}
      assert {:error, _} = Zoi.parse(Tools.schema(), input)
    end
  end
end
