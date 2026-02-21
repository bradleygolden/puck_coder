function CoderRun(messages: Message[], instructions: string) -> CoreActions {
  client PuckCoderClient
  prompt #"
    {{ CoderPrompt(messages, instructions) }}
  "#
}
