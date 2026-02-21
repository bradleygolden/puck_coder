class ReadFile {
  action "read_file" @description("Action discriminator. Use exactly 'read_file'. Required fields: action, path, description.") @stream.done @stream.not_null
  path string @description("Absolute file path") @stream.done @stream.not_null
  description string @description("Brief status for user") @stream.done @stream.not_null
  @@stream.done
}

class WriteFile {
  action "write_file" @description("Action discriminator. Use exactly 'write_file'. Required fields: action, path, content, description.") @stream.done @stream.not_null
  path string @description("Absolute path to write") @stream.done @stream.not_null
  content string @description("Complete file content") @stream.done @stream.not_null
  description string @description("Brief status for user") @stream.done @stream.not_null
  @@stream.done
}

class EditFile {
  action "edit_file" @description("Action discriminator. Use exactly 'edit_file'. Required fields: action, path, old_string, new_string, description.") @stream.done @stream.not_null
  path string @description("Absolute file path") @stream.done @stream.not_null
  old_string string @description("Exact string to find (first match)") @stream.done @stream.not_null
  new_string string @description("Replacement string") @stream.done @stream.not_null
  description string @description("Brief status for user") @stream.done @stream.not_null
  @@stream.done
}

class Shell {
  action "shell" @description("Action discriminator. Use exactly 'shell'. Required fields: action, command, description.") @stream.done @stream.not_null
  command string @description("Shell command to run") @stream.done @stream.not_null
  description string @description("Brief status for user") @stream.done @stream.not_null
  @@stream.done
}

class Done {
  action "done" @description("Action discriminator. Use exactly 'done'. Required fields: action, message.") @stream.done @stream.not_null
  message string @description("Summary of what was done") @stream.done @stream.not_null
  @@stream.done
}

class Message {
  role string
  content string
}

type CoreActions = ReadFile | WriteFile | EditFile | Shell | Done
