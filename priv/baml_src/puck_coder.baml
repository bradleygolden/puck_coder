class ReadFile {
  type "read_file" @stream.not_null
  path string @description("Absolute path to the file to read")
}

class WriteFile {
  type "write_file" @stream.not_null
  path string @description("Absolute path to write to")
  content string @description("Complete file content to write")
}

class EditFile {
  type "edit_file" @stream.not_null
  path string @description("Absolute path to the file to edit")
  old_string string @description("Exact string to find and replace (first occurrence only)")
  new_string string @description("Replacement string")
}

class Shell {
  type "shell" @stream.not_null
  command string @description("Shell command to execute")
}

class Done {
  type "done" @stream.not_null
  message string @description("Final message summarizing what was accomplished")
}

class PluginAction {
  type string
  @@dynamic
}

class Message {
  role string
  content string
}

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
  provider "anthropic"
  options {
    model "claude-sonnet-4-5"
  }
}

function CoderRun(messages: Message[], instructions: string) -> ReadFile | WriteFile | EditFile | Shell | Done | PluginAction {
  client PuckCoderClient
  prompt #"
    {{ _.role("system") }}
    You are an expert coding agent. You modify codebases by reading files, writing files, editing files, and running shell commands.

    Guidelines:
    - Read files before editing to understand current content.
    - Use edit_file for surgical changes. Use write_file only for new files or complete rewrites.
    - Run tests after making changes when applicable.
    - If a tool call fails, read the error and try a different approach.
    - If the user requests something that does not match any available action, use the done action to explain what you can do instead.

    {{ instructions }}

    {% for msg in messages %}
    {{ _.role(msg.role) }}
    {{ msg.content }}
    {% endfor %}

    Respond with exactly one action. Available actions and their schemas:

    {{ ctx.output_format }}
  "#
}
