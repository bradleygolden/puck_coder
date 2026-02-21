defmodule PuckCoder.ToolsTest do
  use ExUnit.Case, async: true

  alias PuckCoder.Actions.{Done, EditFile, ReadFile, Shell, WriteFile}
  alias PuckCoder.Tools

  describe "schema/0" do
    test "parses read_file action" do
      input = %{"type" => "read_file", "path" => "/tmp/foo.ex", "description" => "Reading config"}

      assert {:ok,
              %ReadFile{type: "read_file", path: "/tmp/foo.ex", description: "Reading config"}} =
               Zoi.parse(Tools.schema(), input)
    end

    test "parses write_file action" do
      input = %{
        "type" => "write_file",
        "path" => "/tmp/bar.ex",
        "content" => "hello",
        "description" => "Saving file"
      }

      assert {:ok,
              %WriteFile{
                type: "write_file",
                path: "/tmp/bar.ex",
                content: "hello",
                description: "Saving file"
              }} =
               Zoi.parse(Tools.schema(), input)
    end

    test "parses edit_file action" do
      input = %{
        "type" => "edit_file",
        "path" => "/tmp/baz.ex",
        "old_string" => "foo",
        "new_string" => "bar",
        "description" => "Updating value"
      }

      assert {:ok,
              %EditFile{
                type: "edit_file",
                path: "/tmp/baz.ex",
                old_string: "foo",
                new_string: "bar",
                description: "Updating value"
              }} =
               Zoi.parse(Tools.schema(), input)
    end

    test "parses shell action" do
      input = %{"type" => "shell", "command" => "mix test", "description" => "Running tests"}

      assert {:ok, %Shell{type: "shell", command: "mix test", description: "Running tests"}} =
               Zoi.parse(Tools.schema(), input)
    end

    test "parses done action" do
      input = %{"type" => "done", "message" => "All done!"}
      assert {:ok, %Done{type: "done", message: "All done!"}} = Zoi.parse(Tools.schema(), input)
    end

    test "rejects unknown type" do
      input = %{"type" => "unknown", "foo" => "bar"}
      assert {:error, _} = Zoi.parse(Tools.schema(), input)
    end
  end
end
