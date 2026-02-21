class ReadFile {
  type "read_file" @description("Action discriminator. Use exactly 'read_file'. Required fields: type, path, description.") @stream.not_null
  path string @description("Absolute file path")
  description string @description("Brief status for user")
}

class WriteFile {
  type "write_file" @description("Action discriminator. Use exactly 'write_file'. Required fields: type, path, content, description.") @stream.not_null
  path string @description("Absolute path to write")
  content string @description("Complete file content")
  description string @description("Brief status for user")
}

class EditFile {
  type "edit_file" @description("Action discriminator. Use exactly 'edit_file'. Required fields: type, path, old_string, new_string, description.") @stream.not_null
  path string @description("Absolute file path")
  old_string string @description("Exact string to find (first match)")
  new_string string @description("Replacement string")
  description string @description("Brief status for user")
}

class Shell {
  type "shell" @description("Action discriminator. Use exactly 'shell'. Required fields: type, command, description.") @stream.not_null
  command string @description("Shell command to run")
  description string @description("Brief status for user")
}

class Done {
  type "done" @description("Action discriminator. Use exactly 'done'. Required fields: type, message.") @stream.not_null
  message string @description("Summary of what was done")
}

class Message {
  role string
  content string
}

type CoreActions = ReadFile | WriteFile | EditFile | Shell | Done
