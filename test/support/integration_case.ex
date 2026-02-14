defmodule PuckCoder.IntegrationCase do
  @moduledoc """
  ExUnit case template for integration tests against the Anthropic API.

  Tags every test with `:integration` (excluded by default in test_helper.exs)
  and provides a setup that builds a BAML client_registry pointing at Anthropic.
  Requires the ANTHROPIC_API_KEY environment variable to be set.

  ## Usage

      defmodule MyIntegrationTest do
        use PuckCoder.IntegrationCase

        test "agent reads a file", %{client_registry: client_registry, tmp_dir: tmp_dir} do
          # ...
        end
      end

  Run with: `mix test --include integration`
  """

  use ExUnit.CaseTemplate

  @model "claude-haiku-4-5"

  using do
    quote do
      @moduletag :integration
    end
  end

  setup do
    check_api_key!()

    tmp_dir =
      Path.join(System.tmp_dir!(), "puck_coder_integration_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    client_registry = %{
      "clients" => [
        %{
          "name" => "AnthropicClient",
          "provider" => "anthropic",
          "options" => %{
            "model" => @model
          }
        }
      ],
      "primary" => "AnthropicClient"
    }

    %{client_registry: client_registry, tmp_dir: tmp_dir}
  end

  defp check_api_key! do
    unless System.get_env("ANTHROPIC_API_KEY") do
      raise "ANTHROPIC_API_KEY environment variable must be set to run integration tests"
    end
  end
end
