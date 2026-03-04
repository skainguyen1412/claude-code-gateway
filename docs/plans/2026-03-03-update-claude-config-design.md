# Update Claude Code Config Design

## Purpose
Allow users to easily configure their Claude Code (and Oh My OpenCode wrapper) instances to securely point to the local CCGateWay macOS proxy app.

## Target Config File
The target configuration file is `~/.claude/settings.json`.
(Note: older versions of Claude Code used `~/.claude.json`, but current wrappers use the `~/.claude/settings.json` path. We will update `~/.claude/settings.json`).

## Approach: Direct Swift JSON Parsing (Selected)
We will natively parse the JSON configuration in Swift and inject the necessary environment variables required by the Oh My OpenCode wrapper.

### Target JSON Structure
We need to ensure the following keys exist under the `"env"` object:
```json
{
  "env": {
    "ENABLE_EXPERIMENTAL_MCP_CLI": "true",
    "ANTHROPIC_AUTH_TOKEN": "dummy_key_gateway",
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:<PORT>/v1/messages",
    "ANTHROPIC_MODEL": "gemini-3-pro-high[1m]",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "gemini-3-pro-high[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "gemini-3-flash[1m]",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "gemini-3-flash[1m]",
    "CLAUDE_CODE_SUBAGENT_MODEL": "gemini-3-flash[1m]"
  }
}
```

### Implementation Details

1. **File Path:**
   - Resolve `~/.claude/settings.json`.
   - If `~/.claude/` directory doesn't exist, create it.

2. **Parsing:**
   - Attempt to read the existing `settings.json` file.
   - If it exists, deserialize `Data` to `[String: Any]`.
   - If it doesn't exist or is invalid JSON, start with an empty `[String: Any]`.

3. **Injection:**
   - Extract the `"env"` dictionary (or create a new `[String: Any]` if missing).
   - Set the required keys:
     - `ANTHROPIC_AUTH_TOKEN` = `"dummy_key_gateway"`
     - `ANTHROPIC_BASE_URL` = `"http://127.0.0.1:\(config.port)"`
     - Keep string values for `ENABLE_EXPERIMENTAL_MCP_CLI` and the default model mappings based on the example structure.
   - Reassign the updated `"env"` dictionary back to the root JSON object.

4. **Serialization & Saving:**
   - Serialize the root object to `Data` using `JSONSerialization` (with `.prettyPrinted` and `.sortedKeys`).
   - Write `Data` to the file URL `~/.claude/settings.json` atomically.

5. **UI Feedback:**
   - Show the success alert `showUpdateConfigSuccessAlert` on the main thread.
   - Print errors to the console on failure.

## Trade-offs
- **Pros:** Robust, safe from overwriting other user settings, fast, doesn't depend on fragile CLI bash commands.
- **Cons:** Requires a bit of Swift dictionary casting boilerplate but guarantees safety.
