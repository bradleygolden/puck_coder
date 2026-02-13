defmodule PuckCoder.ToolsTest do
  use ExUnit.Case, async: true

  alias PuckCoder.Actions.{Done, EditFile, ReadFile, Shell, WriteFile}
  alias PuckCoder.Tools

  describe "schema/0" do
    test "parses read_file action" do
      input = %{"type" => "read_file", "path" => "/tmp/foo.ex"}

      assert {:ok, %ReadFile{type: "read_file", path: "/tmp/foo.ex"}} =
               Zoi.parse(Tools.schema(), input)
    end

    test "parses write_file action" do
      input = %{"type" => "write_file", "path" => "/tmp/bar.ex", "content" => "hello"}

      assert {:ok, %WriteFile{type: "write_file", path: "/tmp/bar.ex", content: "hello"}} =
               Zoi.parse(Tools.schema(), input)
    end

    test "parses edit_file action" do
      input = %{
        "type" => "edit_file",
        "path" => "/tmp/baz.ex",
        "old_string" => "foo",
        "new_string" => "bar"
      }

      assert {:ok,
              %EditFile{
                type: "edit_file",
                path: "/tmp/baz.ex",
                old_string: "foo",
                new_string: "bar"
              }} =
               Zoi.parse(Tools.schema(), input)
    end

    test "parses shell action" do
      input = %{"type" => "shell", "command" => "mix test"}
      assert {:ok, %Shell{type: "shell", command: "mix test"}} = Zoi.parse(Tools.schema(), input)
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

  describe "schema/1 with plugins" do
    test "parses plugin action" do
      input = %{"type" => "list_dir", "path" => "/tmp"}

      assert {:ok, %PuckCoder.TestPlugin.Action{type: "list_dir", path: "/tmp"}} =
               Zoi.parse(Tools.schema([PuckCoder.TestPlugin]), input)
    end

    test "still parses built-in actions with plugins" do
      input = %{"type" => "done", "message" => "finished"}

      assert {:ok, %Done{message: "finished"}} =
               Zoi.parse(Tools.schema([PuckCoder.TestPlugin]), input)
    end
  end
end
