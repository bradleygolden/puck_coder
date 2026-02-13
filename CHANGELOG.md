# Changelog

## v0.1.0

Initial release.

- Coding agent with 4 tools: `read_file`, `write_file`, `edit_file`, `shell`
- BAML-first structured outputs with `client_registry` for runtime LLM swapping
- Pluggable executor behaviour with local filesystem default
- `on_action` callback for per-turn observation
- Custom instructions support via `:instructions` option
- Non-BAML escape hatch via `:client` option
