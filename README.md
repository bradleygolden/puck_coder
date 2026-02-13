# PuckCoder

A native Elixir coding agent built on [Puck](https://github.com/bradleygolden/puck).

Point it at a task, and it reads files, makes changes, runs commands, and self-corrects — all inside your BEAM process.

```elixir
{:ok, result} = PuckCoder.run("Add a test for the User module")
IO.puts(result.message)
# => "Added test/user_test.exs with 3 test cases covering create, update, and delete."
```

## Installation

Add `puck_coder` to your dependencies:

```elixir
def deps do
  [
    {:puck_coder, github: "bradleygolden/puck_coder"}
  ]
end
```

PuckCoder uses [BAML](https://docs.boundaryml.com/) for structured LLM outputs. After adding the dependency, generate the BAML client:

```bash
mix deps.get
mix baml.generate
```

## Usage

### Run a coding task

```elixir
{:ok, result} = PuckCoder.run("Fix the failing test in test/user_test.exs")
```

### Add custom instructions

```elixir
{:ok, result} = PuckCoder.run("Refactor the auth module",
  instructions: "Always use pattern matching over if/else. Follow existing test patterns."
)
```

### Observe each turn

```elixir
{:ok, result} = PuckCoder.run("Add logging to the API module",
  on_action: fn action, turn ->
    IO.puts("[Turn #{turn}] #{inspect(action)}")
  end
)
```

## Supported Providers

PuckCoder works with any LLM provider. Anthropic is the default.

| Provider |
|----------|
| Anthropic |
| OpenAI |
| Google AI (Gemini) |
| Google Vertex AI |
| AWS Bedrock |
| Azure OpenAI |
| Ollama (Local) |
| OpenRouter |
| OpenAI Compatible APIs |

### Default (Anthropic via BAML)

Set your API key and you're ready to go:

```bash
export ANTHROPIC_API_KEY=your-key-here
```

### Swap providers at runtime

Use `:client_registry` to switch providers without changing code:

```elixir
{:ok, result} = PuckCoder.run("Add input validation",
  client_registry: %{
    "primary" => "MyClient",
    "clients" => [
      %{"name" => "MyClient", "provider" => "openai", "options" => %{"model" => "gpt-4o"}}
    ]
  }
)
```

See the [BAML Client Registry docs](https://docs.boundaryml.com/guide/baml-advanced/llm-client-registry) for all supported provider options.

### Use a non-BAML backend

Bypass BAML entirely and use any [Puck](https://github.com/bradleygolden/puck) backend directly:

```elixir
client = Puck.Client.new(
  {Puck.Backends.ReqLLM, "anthropic:claude-sonnet-4-5"},
  system_prompt: PuckCoder.default_system_prompt()
)

{:ok, result} = PuckCoder.run("Fix the bug", client: client)
```

## Tools

The agent has 4 tools:

| Tool | Purpose |
|------|---------|
| `read_file` | Read a file at an absolute path |
| `write_file` | Create or overwrite a file |
| `edit_file` | Replace the first occurrence of a string in a file |
| `shell` | Execute a shell command |

## Plugins

Add custom action types without modifying core code. Plugins are plain modules — no GenServers, no ETS, no global state.

```elixir
defmodule MyApp.Plugins.HttpGet do
  @behaviour PuckCoder.Plugin

  defmodule Action do
    defstruct type: "http_get", url: nil
  end

  @impl true
  def name, do: "http_get"

  @impl true
  def description, do: "Fetch a URL and return its body. Params: url (string)."

  @impl true
  def schema do
    Zoi.struct(Action, %{
      type: Zoi.literal("http_get"),
      url: Zoi.string()
    }, coerce: true)
  end

  @impl true
  def execute(%Action{url: url}, _opts, _plugin_opts) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

Then pass it to `run/2`:

```elixir
{:ok, result} = PuckCoder.run("Check if example.com is up",
  plugins: [MyApp.Plugins.HttpGet]
)
```

Plugins also accept a `{module, opts}` tuple for per-invocation configuration:

```elixir
{:ok, result} = PuckCoder.run("Check if example.com is up",
  plugins: [{MyApp.Plugins.HttpGet, [timeout: 5_000]}]
)
```

The opts are passed as the third argument to `execute/3`.

The LLM learns about plugins via instruction injection — each plugin's `name/0` and `description/0` are appended to the prompt. This keeps overhead to ~15 tokens per plugin.

### Plugin Behaviour Callbacks

| Callback | Required | Description |
|----------|----------|-------------|
| `name/0` | Yes | Action name (matches `type` field in JSON) |
| `description/0` | Yes | One-line description injected into LLM prompt |
| `schema/0` | Yes | Zoi schema for parsing LLM output |
| `execute/3` | Yes | Runs the action; receives parsed struct, `executor_opts`, and `plugin_opts` |
| `action_summary/1` | No | Custom summary for result messages fed back to LLM |
| `type_builder_fields/0` | No | Reserved for future BAML `@@dynamic` integration |

## Custom Executors

By default, tools run directly on your local filesystem. Implement `PuckCoder.Executor` to run them elsewhere:

```elixir
{:ok, result} = PuckCoder.run("Fix the tests",
  executor: MyApp.DockerExecutor,
  executor_opts: [container: "dev-env"]
)
```

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `:client` | BAML | Custom `Puck.Client` (bypasses BAML) |
| `:client_registry` | `nil` | BAML client registry for runtime LLM config |
| `:instructions` | `""` | Extra instructions for the agent |
| `:plugins` | `[]` | List of `PuckCoder.Plugin` modules for custom actions |
| `:executor` | `PuckCoder.Executors.Local` | Tool execution backend |
| `:executor_opts` | `[]` | Options passed to executor (e.g., `cwd`, `timeout`) |
| `:max_turns` | `200` | Maximum agent loop iterations |
| `:on_action` | `nil` | `fn action, turn -> :ok end` callback |
| `:context` | fresh | Initial `Puck.Context` |

## License

Apache-2.0
