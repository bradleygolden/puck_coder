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

  describe "run/2 with plugins" do
    test "runs a bare module plugin end-to-end" do
      tmp_dir = System.tmp_dir!()

      client =
        Puck.Test.mock_client([
          %{"type" => "list_dir", "path" => tmp_dir},
          %{"type" => "done", "message" => "Listed it."}
        ])

      assert {:ok, result} =
               PuckCoder.run("List the temp directory",
                 client: client,
                 plugins: [PuckCoder.TestPlugin]
               )

      assert result.message == "Listed it."
      assert result.turns == 2
    end

    test "runs a {Plugin, opts} tuple plugin end-to-end" do
      tmp_dir = System.tmp_dir!()

      client =
        Puck.Test.mock_client([
          %{"type" => "list_dir", "path" => tmp_dir},
          %{"type" => "done", "message" => "Listed it."}
        ])

      assert {:ok, result} =
               PuckCoder.run("List the temp directory",
                 client: client,
                 plugins: [{PuckCoder.TestPlugin, [some: "opt"]}]
               )

      assert result.message == "Listed it."
      assert result.turns == 2
    end
  end

  describe "run/2 with skills" do
    test "agent completes with skills as maps" do
      client =
        Puck.Test.mock_client([
          %{"type" => "done", "message" => "Done with skills."}
        ])

      assert {:ok, result} =
               PuckCoder.run("Do something",
                 client: client,
                 skills: [
                   %{name: "pdf", description: "Extract PDFs.", path: "/skills/pdf/SKILL.md"}
                 ]
               )

      assert result.message == "Done with skills."
    end

    test "agent completes with skills as structs" do
      client =
        Puck.Test.mock_client([
          %{"type" => "done", "message" => "Done with skills."}
        ])

      skill =
        PuckCoder.Skill.new!(%{
          name: "pdf",
          description: "Extract PDFs.",
          path: "/skills/pdf/SKILL.md"
        })

      assert {:ok, result} =
               PuckCoder.run("Do something",
                 client: client,
                 skills: [skill]
               )

      assert result.message == "Done with skills."
    end

    test "works with empty skills list" do
      client =
        Puck.Test.mock_client([
          %{"type" => "done", "message" => "Done."}
        ])

      assert {:ok, result} = PuckCoder.run("Do something", client: client, skills: [])
      assert result.message == "Done."
    end

    test "works with skills and plugins together" do
      tmp_dir = System.tmp_dir!()

      client =
        Puck.Test.mock_client([
          %{"type" => "list_dir", "path" => tmp_dir},
          %{"type" => "done", "message" => "Done."}
        ])

      assert {:ok, result} =
               PuckCoder.run("Do something",
                 client: client,
                 plugins: [PuckCoder.TestPlugin],
                 skills: [
                   %{name: "pdf", description: "Extract PDFs.", path: "/skills/pdf/SKILL.md"}
                 ]
               )

      assert result.message == "Done."
      assert result.turns == 2
    end
  end

  describe "default_system_prompt/0" do
    test "returns a non-empty string" do
      prompt = PuckCoder.default_system_prompt()
      assert is_binary(prompt)
      assert String.contains?(prompt, "coding agent")
    end

    test "includes plugin descriptions when plugins are provided" do
      prompt = PuckCoder.default_system_prompt([PuckCoder.TestPlugin])
      assert String.contains?(prompt, "list_dir")
      assert String.contains?(prompt, "List files in a directory")
    end

    test "includes plugin descriptions for tuple format" do
      prompt = PuckCoder.default_system_prompt([{PuckCoder.TestPlugin, [some: "opt"]}])
      assert String.contains?(prompt, "list_dir")
      assert String.contains?(prompt, "List files in a directory")
    end

    test "returns base prompt with no plugins" do
      with_plugins = PuckCoder.default_system_prompt([PuckCoder.TestPlugin])
      without_plugins = PuckCoder.default_system_prompt()
      assert String.length(with_plugins) > String.length(without_plugins)
    end
  end

  describe "default_system_prompt with skills" do
    test "includes skill XML when skills are provided" do
      skill =
        PuckCoder.Skill.new!(%{
          name: "pdf",
          description: "Extract PDFs.",
          path: "/skills/pdf/SKILL.md"
        })

      prompt = PuckCoder.default_system_prompt([], [skill])

      assert prompt =~ "<available_skills>"
      assert prompt =~ ~s(name="pdf")
      assert prompt =~ "read its SKILL.md file"
    end

    test "includes both plugins and skills" do
      skill =
        PuckCoder.Skill.new!(%{
          name: "pdf",
          description: "Extract PDFs.",
          path: "/skills/pdf/SKILL.md"
        })

      prompt = PuckCoder.default_system_prompt([PuckCoder.TestPlugin], [skill])

      assert prompt =~ "list_dir"
      assert prompt =~ "<available_skills>"
      assert prompt =~ ~s(name="pdf")
    end

    test "returns base prompt with empty skills list" do
      with_skills =
        PuckCoder.default_system_prompt([], [
          PuckCoder.Skill.new!(%{name: "pdf", description: "d", path: "p"})
        ])

      without_skills = PuckCoder.default_system_prompt([], [])
      assert String.length(with_skills) > String.length(without_skills)
    end
  end
end
