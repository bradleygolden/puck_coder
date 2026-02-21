function CoderRun(messages: Message[], instructions: string) -> AgentLoopOutput {
  client PuckCoderClient
  prompt #"
    {{ CoderPrompt(messages, instructions) }}
  "#
}
