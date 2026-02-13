defmodule PuckCoder.IntegrationCase do
  @moduledoc """
  ExUnit case template for integration tests against a local Ollama instance.

  Tags every test with `:integration` (excluded by default in test_helper.exs)
  and provides a setup that builds a BAML client_registry pointing at Ollama.

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

  @ollama_model "qwen3:1.7b"
  @ollama_base_url "http://localhost:11434/v1"

  using do
    quote do
      @moduletag :integration
    end
  end

  setup do
    check_ollama_available!()

    tmp_dir =
      Path.join(System.tmp_dir!(), "puck_coder_integration_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    client_registry = %{
      "clients" => [
        %{
          "name" => "OllamaClient",
          "provider" => "ollama",
          "options" => %{
            "model" => @ollama_model,
            "base_url" => @ollama_base_url
          }
        }
      ],
      "primary" => "OllamaClient"
    }

    %{client_registry: client_registry, tmp_dir: tmp_dir}
  end

  defp check_ollama_available! do
    case :httpc.request(:get, {~c"http://localhost:11434/api/tags", []}, [timeout: 5_000], []) do
      {:ok, {{_, 200, _}, _, _}} ->
        :ok

      _ ->
        raise "Ollama is not running at localhost:11434. Start it with: ollama serve"
    end
  end
end
