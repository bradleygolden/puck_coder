class ReadFile {
  type string @description("Always 'read_file'")
  path string @description("Absolute path to the file to read")
}

class WriteFile {
  type string @description("Always 'write_file'")
  path string @description("Absolute path to write to")
  content string @description("Complete file content to write")
}

class EditFile {
  type string @description("Always 'edit_file'")
  path string @description("Absolute path to the file to edit")
  old_string string @description("Exact string to find and replace (first occurrence only)")
  new_string string @description("Replacement string")
}

class Shell {
  type string @description("Always 'shell'")
  command string @description("Shell command to execute")
}

class Done {
  type string @description("Always 'done'")
  message string @description("Final message summarizing what was accomplished")
}

class Message {
  role string
  content string
}

client<llm> PuckCoderClient {
  provider "anthropic"
  options {
    model "claude-sonnet-4-5"
  }
}

function CoderRun(messages: Message[], instructions: string) -> ReadFile | WriteFile | EditFile | Shell | Done {
  client PuckCoderClient
  prompt #"
    {{ _.role("system") }}
    You are an expert coding agent. You modify codebases by reading files, writing files, editing files, and running shell commands.

    Available actions (respond with exactly one per turn):
    - read_file: Read a file at the given path.
    - write_file: Write content to a file, creating it if needed.
    - edit_file: Replace old_string with new_string in a file. The old_string must match exactly. Only the first occurrence is replaced.
    - shell: Execute a shell command.
    - done: Signal that the task is complete.

    Guidelines:
    - Read files before editing to understand current content.
    - Use edit_file for surgical changes. Use write_file only for new files or complete rewrites.
    - Run tests after making changes when applicable.
    - If a tool call fails, read the error and try a different approach.

    {{ instructions }}

    {{ ctx.output_format }}

    {% for msg in messages %}
    {{ _.role(msg.role) }}
    {{ msg.content }}
    {% endfor %}
  "#
}
