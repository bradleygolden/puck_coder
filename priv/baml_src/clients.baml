retry_policy DefaultRetry {
  max_retries 3
  strategy {
    type exponential_backoff
    delay_ms 200
    multiplier 1.5
    max_delay_ms 10000
  }
}

client<llm> PuckCoderClient {
  provider "openai-generic"
  options {
    base_url "https://api.fireworks.ai/inference/v1"
    api_key env.FIREWORKS_API_KEY
    model "accounts/fireworks/models/glm-4p7"
  }
}
