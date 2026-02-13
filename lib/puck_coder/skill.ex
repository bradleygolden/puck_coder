defmodule PuckCoder.Skill do
  @moduledoc """
  Agent Skills support for PuckCoder.

  Skills are contextual instruction packs the agent loads on demand via `read_file`.
  Only `name` + `description` (~100 tokens each) are injected into the system prompt.
  The full SKILL.md body is read only when the agent decides a skill is relevant.

  See the [Agent Skills specification](https://agentskills.io/specification) for details.

  ## Primary API

  Build skills from any source — the caller decides where skills come from:

      PuckCoder.run("task", skills: [
        %{name: "pdf-processing", description: "Extract text from PDFs.", path: "/skills/SKILL.md"}
      ])

  ## Filesystem Convenience

  Discover skills from local directories containing SKILL.md files:

      skills = PuckCoder.Skill.discover(["/path/to/skills"])
      PuckCoder.run("task", skills: skills)

  """

  require Logger

  @enforce_keys [:name, :description, :path]
  defstruct [:name, :description, :path, :license, :compatibility, :allowed_tools, :metadata]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          path: String.t(),
          license: String.t() | nil,
          compatibility: String.t() | nil,
          allowed_tools: [String.t()] | nil,
          metadata: map() | nil
        }

  @name_regex ~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/

  @doc """
  Build a `%Skill{}` from a map or keyword list.

  Validates required fields (`name`, `description`, `path`) and name format
  (kebab-case, 1-64 chars, no leading/trailing hyphens, no consecutive hyphens).

  ## Examples

      iex> PuckCoder.Skill.new(%{name: "pdf", description: "Extract PDFs.", path: "/skills/SKILL.md"})
      {:ok, %PuckCoder.Skill{name: "pdf", description: "Extract PDFs.", path: "/skills/SKILL.md"}}

      iex> PuckCoder.Skill.new(name: "pdf", description: "Extract PDFs.", path: "/skills/SKILL.md")
      {:ok, %PuckCoder.Skill{name: "pdf", description: "Extract PDFs.", path: "/skills/SKILL.md"}}

  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    attrs = normalize_keys(attrs)

    with :ok <- validate_required(attrs, :name),
         :ok <- validate_required(attrs, :description),
         :ok <- validate_required(attrs, :path),
         :ok <- validate_name(attrs.name) do
      {:ok,
       %__MODULE__{
         name: attrs.name,
         description: attrs.description,
         path: attrs.path,
         license: Map.get(attrs, :license),
         compatibility: Map.get(attrs, :compatibility),
         allowed_tools: Map.get(attrs, :allowed_tools),
         metadata: Map.get(attrs, :metadata)
       }}
    end
  end

  @doc """
  Like `new/1` but raises on invalid input.
  """
  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, skill} -> skill
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Generate an `<available_skills>` XML block for prompt injection.

  Returns `""` for an empty list (zero token cost).

  ## Example

      iex> skill = PuckCoder.Skill.new!(%{name: "pdf", description: "Extract PDFs.", path: "/skills/SKILL.md"})
      iex> PuckCoder.Skill.to_prompt([skill])
      ~s(<available_skills>\\n<skill name="pdf" description="Extract PDFs.">\\n  <location>/skills/SKILL.md</location>\\n</skill>\\n</available_skills>\\nTo use a skill, read its SKILL.md file to get full instructions.)

  """
  @spec to_prompt([t()]) :: String.t()
  def to_prompt([]), do: ""

  def to_prompt(skills) when is_list(skills) do
    entries =
      Enum.map_join(skills, "\n", fn skill ->
        name = html_escape(skill.name)
        desc = html_escape(skill.description)
        path = html_escape(skill.path)

        """
        <skill name="#{name}" description="#{desc}">
          <location>#{path}</location>
        </skill>\
        """
      end)

    "<available_skills>\n#{entries}\n</available_skills>\n" <>
      "To use a skill, read its SKILL.md file to get full instructions."
  end

  @doc """
  Parse a single SKILL.md file into a `%Skill{}`.

  Reads the file, extracts YAML frontmatter, and builds a skill struct.
  The `path` field is set to the resolved absolute path of the file.

  ## Example

      PuckCoder.Skill.parse("/path/to/my-skill/SKILL.md")
      #=> {:ok, %PuckCoder.Skill{name: "my-skill", ...}}

  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse(skill_md_path) do
    with {:ok, content} <- read_file(skill_md_path),
         {:ok, frontmatter} <- parse_frontmatter(content) do
      new(Map.put(frontmatter, :path, skill_md_path))
    end
  end

  @doc """
  Discover skills from local filesystem directories.

  Scans each directory for subdirectories containing a SKILL.md (or skill.md) file,
  parses their frontmatter, and returns a sorted list of `%Skill{}` structs.
  Logs warnings for invalid skills and never crashes.

  ## Example

      PuckCoder.Skill.discover(["/path/to/skills"])
      #=> [%PuckCoder.Skill{name: "data-analysis", ...}, %PuckCoder.Skill{name: "pdf", ...}]

  """
  @spec discover([String.t()]) :: [t()]
  def discover(dirs) when is_list(dirs) do
    dirs
    |> Enum.flat_map(&scan_directory/1)
    |> Enum.sort_by(& &1.name)
  end

  # --- Private helpers ---

  defp normalize_keys(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
    end)
  rescue
    ArgumentError -> map
  end

  defp validate_required(attrs, key) do
    case Map.get(attrs, key) do
      nil -> {:error, "#{key} is required"}
      "" -> {:error, "#{key} is required"}
      _ -> :ok
    end
  end

  defp validate_name(name) when is_binary(name) do
    cond do
      String.length(name) > 64 ->
        {:error, "name must be 1-64 characters, got #{String.length(name)}"}

      String.contains?(name, "--") ->
        {:error, "name must not contain consecutive hyphens"}

      not Regex.match?(@name_regex, name) ->
        {:error,
         "name must be kebab-case (lowercase alphanumeric and hyphens, no leading/trailing hyphens)"}

      true ->
        :ok
    end
  end

  defp validate_name(_), do: {:error, "name must be a string"}

  defp html_escape(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, "failed to read #{path}: #{reason}"}
    end
  end

  defp parse_frontmatter(content) do
    case String.split(content, "---", parts: 3) do
      ["" | [yaml_str | _rest]] ->
        case YamlElixir.read_from_string(yaml_str) do
          {:ok, map} when is_map(map) ->
            {:ok, normalize_keys(map)}

          {:ok, _} ->
            {:error, "frontmatter is not a valid YAML map"}

          {:error, _} ->
            {:error, "invalid YAML in frontmatter"}
        end

      _ ->
        {:error, "missing YAML frontmatter delimiters (---)"}
    end
  end

  defp find_skill_md(dir) do
    upper = Path.join(dir, "SKILL.md")
    lower = Path.join(dir, "skill.md")

    cond do
      File.regular?(upper) -> {:ok, upper}
      File.regular?(lower) -> {:ok, lower}
      true -> :error
    end
  end

  defp scan_directory(dir) do
    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.map(&Path.join(dir, &1))
      |> Enum.filter(&File.dir?/1)
      |> Enum.flat_map(&parse_skill_dir/1)
    else
      Logger.warning("Skill discovery: directory not found: #{dir}")
      []
    end
  rescue
    e ->
      Logger.warning("Skill discovery: error scanning #{dir}: #{Exception.message(e)}")
      []
  end

  defp parse_skill_dir(subdir) do
    case find_skill_md(subdir) do
      {:ok, path} ->
        case parse(path) do
          {:ok, skill} ->
            [skill]

          {:error, reason} ->
            Logger.warning("Skill discovery: skipping #{subdir}: #{reason}")
            []
        end

      :error ->
        []
    end
  end
end
