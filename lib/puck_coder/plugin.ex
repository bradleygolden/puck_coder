defmodule PuckCoder.Plugin do
  @moduledoc """
  Behaviour for extending PuckCoder with custom action types.

  Plugins are passed as `plugins: [MyPlugin]` or `plugins: [{MyPlugin, opts}]`.
  No registry, no process, no global state — just functions.

  ## Example

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
            {:ok, %{status: status}} -> {:error, "HTTP \#{status}"}
            {:error, reason} -> {:error, reason}
          end
        end
      end

  """

  @typedoc "A plugin is either a bare module or a `{module, keyword()}` tuple."
  @type plugin :: module() | {module(), keyword()}

  @doc "Unique action name (matches the `type` field in the JSON schema)."
  @callback name() :: String.t()

  @doc "One-line description injected into the LLM prompt."
  @callback description() :: String.t()

  @doc "Zoi schema for parsing the action from LLM output."
  @callback schema() :: term()

  @doc "Execute the parsed action struct. Receives executor_opts and plugin_opts."
  @callback execute(action :: struct(), executor_opts :: keyword(), plugin_opts :: keyword()) ::
              {:ok, String.t()} | :ok | {:error, term()}

  @doc "Fields for future BAML @@dynamic TypeBuilder integration."
  @callback type_builder_fields() :: [map()]

  @doc "Custom summary for the result message fed back to the LLM."
  @callback action_summary(action :: struct()) :: String.t()

  @optional_callbacks [action_summary: 1, type_builder_fields: 0]

  @doc "Normalize a plugin to `{module, keyword()}` tuple form."
  @spec normalize(plugin()) :: {module(), keyword()}
  def normalize({mod, opts}) when is_atom(mod) and is_list(opts), do: {mod, opts}
  def normalize(mod) when is_atom(mod), do: {mod, []}
end
