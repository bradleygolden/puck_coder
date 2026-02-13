defmodule PuckCoder.Plugin do
  @moduledoc """
  Behaviour for extending PuckCoder with custom action types.

  Plugins are plain modules passed as `plugins: [MyPlugin]` in opts.
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
        def execute(%Action{url: url}, _opts) do
          case Req.get(url) do
            {:ok, %{status: 200, body: body}} -> {:ok, body}
            {:ok, %{status: status}} -> {:error, "HTTP \#{status}"}
            {:error, reason} -> {:error, reason}
          end
        end
      end

  """

  @doc "Unique action name (matches the `type` field in the JSON schema)."
  @callback name() :: String.t()

  @doc "One-line description injected into the LLM prompt."
  @callback description() :: String.t()

  @doc "Zoi schema for parsing the action from LLM output."
  @callback schema() :: term()

  @doc "Execute the parsed action struct. Receives executor_opts from the loop."
  @callback execute(action :: struct(), opts :: keyword()) ::
              {:ok, String.t()} | :ok | {:error, term()}

  @doc "Fields for future BAML @@dynamic TypeBuilder integration."
  @callback type_builder_fields() :: [map()]

  @doc "Custom summary for the result message fed back to the LLM."
  @callback action_summary(action :: struct()) :: String.t()

  @optional_callbacks [action_summary: 1, type_builder_fields: 0]
end
