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

enum PluginActionType {
  @@dynamic
}

class PluginAction {
  type PluginActionType
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
    model "claude-haiku-4-5"
  }
}


template_string CoderPrompt(messages: Message[], instructions: string) #"
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

function CoderRun(messages: Message[], instructions: string) -> ReadFile | WriteFile | EditFile | Shell | Done {
  client PuckCoderClient
  prompt #"
    {{ CoderPrompt(messages, instructions) }}
  "#
}

function CoderRunWithPlugins(messages: Message[], instructions: string) -> ReadFile | WriteFile | EditFile | Shell | Done | PluginAction {
  client PuckCoderClient
  prompt #"
    {{ CoderPrompt(messages, instructions) }}
  "#
}

test ReadFileAction {
  functions [CoderRun]
  args {
    messages [
      {
        role "user"
        content "Read the file at /tmp/example.txt"
      }
    ]
    instructions ""
  }
  @@assert( {{ this.type == "read_file" }} )
  @@assert( {{ "/tmp/example.txt" in this.path }} )
}

test WriteFileAction {
  functions [CoderRun]
  args {
    messages [
      {
        role "user"
        content "Create a new file at /tmp/hello.txt with the content: Hello, world!"
      }
    ]
    instructions ""
  }
  @@assert( {{ this.type == "write_file" }} )
  @@assert( {{ "/tmp/hello.txt" in this.path }} )
  @@assert( {{ "Hello, world!" in this.content }} )
}

test EditFileAction {
  functions [CoderRun]
  args {
    messages [
      {
        role "user"
        content #"
          Edit /tmp/config.yml and replace "debug: false" with "debug: true"
        "#
      },
      {
        role "assistant"
        content #"{"type": "read_file", "path": "/tmp/config.yml"}"#
      },
      {
        role "user"
        content "debug: false\nlog_level: info"
      }
    ]
    instructions ""
  }
  @@assert( {{ this.type == "edit_file" }} )
  @@assert( {{ "/tmp/config.yml" in this.path }} )
  @@assert( {{ "debug: false" in this.old_string }} )
  @@assert( {{ "debug: true" in this.new_string }} )
}

test ShellAction {
  functions [CoderRun]
  args {
    messages [
      {
        role "user"
        content "Run the test suite with mix test"
      }
    ]
    instructions ""
  }
  @@assert( {{ this.type == "shell" }} )
  @@assert( {{ "mix test" in this.command }} )
}

test DoneAction {
  functions [CoderRun]
  args {
    messages [
      {
        role "user"
        content "I just wanted to say thanks, the task is complete."
      }
    ]
    instructions ""
  }
  @@assert( {{ this.type == "done" }} )
}

test InstructionsAreFollowed {
  functions [CoderRun]
  args {
    messages [
      {
        role "user"
        content "Read /app/src/main.rs"
      }
    ]
    instructions "Always run shell commands instead of reading files directly. Use cat to read files."
  }
  @@assert( {{ this.type == "shell" }} )
  @@assert( {{ "cat" in this.command }} )
}
