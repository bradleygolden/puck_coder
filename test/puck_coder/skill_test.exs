defmodule PuckCoder.SkillTest do
  use ExUnit.Case, async: true

  alias PuckCoder.Skill

  describe "new/1" do
    test "builds a skill from a map" do
      assert {:ok, skill} =
               Skill.new(%{name: "pdf", description: "Extract PDFs.", path: "/skills/SKILL.md"})

      assert skill.name == "pdf"
      assert skill.description == "Extract PDFs."
      assert skill.path == "/skills/SKILL.md"
    end

    test "builds a skill from a keyword list" do
      assert {:ok, skill} =
               Skill.new(name: "pdf", description: "Extract PDFs.", path: "/skills/SKILL.md")

      assert skill.name == "pdf"
    end

    test "builds a skill from string keys" do
      assert {:ok, skill} =
               Skill.new(%{
                 "name" => "pdf",
                 "description" => "Extract PDFs.",
                 "path" => "/skills/SKILL.md"
               })

      assert skill.name == "pdf"
    end

    test "includes optional fields" do
      assert {:ok, skill} =
               Skill.new(%{
                 name: "pdf",
                 description: "Extract PDFs.",
                 path: "/skills/SKILL.md",
                 license: "MIT",
                 compatibility: "claude-code",
                 allowed_tools: ["read_file"],
                 metadata: %{version: "1.0"}
               })

      assert skill.license == "MIT"
      assert skill.compatibility == "claude-code"
      assert skill.allowed_tools == ["read_file"]
      assert skill.metadata == %{version: "1.0"}
    end

    test "returns error for missing name" do
      assert {:error, "name is required"} =
               Skill.new(%{description: "desc", path: "/path"})
    end

    test "returns error for missing description" do
      assert {:error, "description is required"} =
               Skill.new(%{name: "pdf", path: "/path"})
    end

    test "returns error for missing path" do
      assert {:error, "path is required"} =
               Skill.new(%{name: "pdf", description: "desc"})
    end

    test "returns error for empty name" do
      assert {:error, "name is required"} =
               Skill.new(%{name: "", description: "desc", path: "/path"})
    end
  end

  describe "new/1 name validation" do
    test "accepts simple kebab-case" do
      assert {:ok, _} = Skill.new(%{name: "my-skill", description: "d", path: "p"})
    end

    test "accepts single character" do
      assert {:ok, _} = Skill.new(%{name: "a", description: "d", path: "p"})
    end

    test "accepts alphanumeric" do
      assert {:ok, _} = Skill.new(%{name: "skill123", description: "d", path: "p"})
    end

    test "accepts multi-segment kebab-case" do
      assert {:ok, _} = Skill.new(%{name: "my-cool-skill", description: "d", path: "p"})
    end

    test "rejects leading hyphen" do
      assert {:error, msg} = Skill.new(%{name: "-pdf", description: "d", path: "p"})
      assert msg =~ "kebab-case"
    end

    test "rejects trailing hyphen" do
      assert {:error, msg} = Skill.new(%{name: "pdf-", description: "d", path: "p"})
      assert msg =~ "kebab-case"
    end

    test "rejects consecutive hyphens" do
      assert {:error, msg} = Skill.new(%{name: "my--skill", description: "d", path: "p"})
      assert msg =~ "consecutive hyphens"
    end

    test "rejects uppercase" do
      assert {:error, msg} = Skill.new(%{name: "MySkill", description: "d", path: "p"})
      assert msg =~ "kebab-case"
    end

    test "rejects names longer than 64 characters" do
      long_name = String.duplicate("a", 65)
      assert {:error, msg} = Skill.new(%{name: long_name, description: "d", path: "p"})
      assert msg =~ "1-64 characters"
    end

    test "accepts name exactly 64 characters" do
      name = String.duplicate("a", 64)
      assert {:ok, _} = Skill.new(%{name: name, description: "d", path: "p"})
    end

    test "rejects underscores" do
      assert {:error, _} = Skill.new(%{name: "my_skill", description: "d", path: "p"})
    end

    test "rejects spaces" do
      assert {:error, _} = Skill.new(%{name: "my skill", description: "d", path: "p"})
    end
  end

  describe "new!/1" do
    test "returns skill on valid input" do
      skill = Skill.new!(%{name: "pdf", description: "Extract PDFs.", path: "/p"})
      assert skill.name == "pdf"
    end

    test "raises on invalid input" do
      assert_raise ArgumentError, ~r/name is required/, fn ->
        Skill.new!(%{description: "d", path: "p"})
      end
    end
  end

  describe "to_prompt/1" do
    test "returns empty string for empty list" do
      assert Skill.to_prompt([]) == ""
    end

    test "generates XML for a single skill" do
      skill = Skill.new!(%{name: "pdf", description: "Extract PDFs.", path: "/skills/SKILL.md"})
      prompt = Skill.to_prompt([skill])

      assert prompt =~ "<available_skills>"
      assert prompt =~ ~s(name="pdf")
      assert prompt =~ ~s(description="Extract PDFs.")
      assert prompt =~ "<location>/skills/SKILL.md</location>"
      assert prompt =~ "</available_skills>"
      assert prompt =~ "read its SKILL.md file"
    end

    test "generates XML for multiple skills" do
      s1 = Skill.new!(%{name: "pdf", description: "PDFs.", path: "/a/SKILL.md"})
      s2 = Skill.new!(%{name: "csv", description: "CSVs.", path: "/b/SKILL.md"})
      prompt = Skill.to_prompt([s1, s2])

      assert prompt =~ ~s(name="pdf")
      assert prompt =~ ~s(name="csv")
    end

    test "escapes HTML entities in name, description, and path" do
      skill =
        Skill.new!(%{
          name: "a",
          description: "Use <b>bold</b> & \"quotes\"",
          path: "/path/<dir>/SKILL.md"
        })

      prompt = Skill.to_prompt([skill])

      assert prompt =~ "&lt;b&gt;bold&lt;/b&gt;"
      assert prompt =~ "&amp;"
      assert prompt =~ "&quot;quotes&quot;"
      assert prompt =~ "&lt;dir&gt;"
    end
  end

  describe "parse/1" do
    setup do
      tmp_dir =
        Path.join(System.tmp_dir!(), "skill_parse_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)
      %{tmp_dir: tmp_dir}
    end

    test "parses a valid SKILL.md", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "SKILL.md")

      File.write!(path, """
      ---
      name: pdf-processing
      description: Extract text from PDFs.
      ---
      # PDF Processing

      Full instructions here.
      """)

      assert {:ok, skill} = Skill.parse(path)
      assert skill.name == "pdf-processing"
      assert skill.description == "Extract text from PDFs."
      assert skill.path == path
    end

    test "parses optional fields", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "SKILL.md")

      File.write!(path, """
      ---
      name: pdf-processing
      description: Extract text from PDFs.
      license: MIT
      compatibility: claude-code
      ---
      Body here.
      """)

      assert {:ok, skill} = Skill.parse(path)
      assert skill.license == "MIT"
      assert skill.compatibility == "claude-code"
    end

    test "returns error for missing frontmatter delimiters", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "SKILL.md")
      File.write!(path, "No frontmatter here.")

      assert {:error, msg} = Skill.parse(path)
      assert msg =~ "missing YAML frontmatter"
    end

    test "returns error for invalid YAML", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "SKILL.md")

      File.write!(path, """
      ---
      name: [invalid
      ---
      """)

      assert {:error, msg} = Skill.parse(path)
      assert msg =~ "invalid YAML"
    end

    test "returns error for missing required fields", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "SKILL.md")

      File.write!(path, """
      ---
      name: pdf
      ---
      Body.
      """)

      assert {:error, "description is required"} = Skill.parse(path)
    end

    test "returns error for nonexistent file" do
      assert {:error, msg} = Skill.parse("/nonexistent/SKILL.md")
      assert msg =~ "failed to read"
    end
  end

  describe "discover/1" do
    setup do
      tmp_dir =
        Path.join(System.tmp_dir!(), "skill_discover_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)
      %{tmp_dir: tmp_dir}
    end

    test "discovers skills from a directory", %{tmp_dir: tmp_dir} do
      create_skill_dir(tmp_dir, "alpha-skill", "Alpha skill.")
      create_skill_dir(tmp_dir, "beta-skill", "Beta skill.")

      skills = Skill.discover([tmp_dir])

      assert length(skills) == 2
      assert Enum.map(skills, & &1.name) == ["alpha-skill", "beta-skill"]
    end

    test "discovers from multiple directories", %{tmp_dir: tmp_dir} do
      dir1 = Path.join(tmp_dir, "dir1")
      dir2 = Path.join(tmp_dir, "dir2")
      File.mkdir_p!(dir1)
      File.mkdir_p!(dir2)

      create_skill_dir(dir1, "skill-a", "Skill A.")
      create_skill_dir(dir2, "skill-b", "Skill B.")

      skills = Skill.discover([dir1, dir2])

      assert length(skills) == 2
      assert Enum.map(skills, & &1.name) == ["skill-a", "skill-b"]
    end

    test "returns sorted by name", %{tmp_dir: tmp_dir} do
      create_skill_dir(tmp_dir, "zebra", "Z skill.")
      create_skill_dir(tmp_dir, "alpha", "A skill.")
      create_skill_dir(tmp_dir, "middle", "M skill.")

      skills = Skill.discover([tmp_dir])

      assert Enum.map(skills, & &1.name) == ["alpha", "middle", "zebra"]
    end

    test "skips invalid skills without crashing", %{tmp_dir: tmp_dir} do
      create_skill_dir(tmp_dir, "valid-skill", "Valid.")

      # Create invalid skill (missing description)
      invalid_dir = Path.join(tmp_dir, "invalid-skill")
      File.mkdir_p!(invalid_dir)

      File.write!(Path.join(invalid_dir, "SKILL.md"), """
      ---
      name: invalid-skill
      ---
      Missing description.
      """)

      skills = Skill.discover([tmp_dir])

      assert length(skills) == 1
      assert hd(skills).name == "valid-skill"
    end

    test "returns empty list for nonexistent directory" do
      assert Skill.discover(["/nonexistent/dir"]) == []
    end

    test "returns empty list for empty directory", %{tmp_dir: tmp_dir} do
      empty_dir = Path.join(tmp_dir, "empty")
      File.mkdir_p!(empty_dir)

      assert Skill.discover([empty_dir]) == []
    end

    test "finds lowercase skill.md", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "my-skill")
      File.mkdir_p!(skill_dir)

      File.write!(Path.join(skill_dir, "skill.md"), """
      ---
      name: my-skill
      description: A lowercase skill.
      ---
      Body.
      """)

      skills = Skill.discover([tmp_dir])

      assert length(skills) == 1
      assert hd(skills).name == "my-skill"
    end

    # SKILL.md vs skill.md preference is tested via find_skill_md priority.
    # On case-insensitive filesystems (macOS default), both names resolve to
    # the same file, so we only test that at least one is found.
    test "finds either SKILL.md or skill.md", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "my-skill")
      File.mkdir_p!(skill_dir)

      File.write!(Path.join(skill_dir, "SKILL.md"), """
      ---
      name: my-skill
      description: Found the skill.
      ---
      """)

      skills = Skill.discover([tmp_dir])

      assert length(skills) == 1
      assert hd(skills).description == "Found the skill."
    end

    test "skips subdirectories without SKILL.md", %{tmp_dir: tmp_dir} do
      create_skill_dir(tmp_dir, "valid-skill", "Valid.")

      no_skill_dir = Path.join(tmp_dir, "no-skill")
      File.mkdir_p!(no_skill_dir)
      File.write!(Path.join(no_skill_dir, "README.md"), "Not a skill.")

      skills = Skill.discover([tmp_dir])

      assert length(skills) == 1
    end
  end

  defp create_skill_dir(parent, name, description) do
    dir = Path.join(parent, name)
    File.mkdir_p!(dir)

    File.write!(Path.join(dir, "SKILL.md"), """
    ---
    name: #{name}
    description: #{description}
    ---
    # #{name}

    Full instructions here.
    """)

    dir
  end
end
