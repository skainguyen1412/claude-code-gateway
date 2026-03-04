# OpenAI-Compatible Provider Adapter Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Add an OpenAI-compatible adapter so CCGateWay can proxy Claude Code requests to any OpenAI-compatible API (OpenAI, DeepSeek, Groq, Cerebras, etc.)

**Architecture:** The OpenAI adapter implements the existing `ProviderAdapter` protocol. It converts Anthropic-format requests to OpenAI `/v1/chat/completions` format and converts OpenAI responses back to Anthropic format. A new `OpenAISSEBuilder` (analogous to `AnthropicSSEBuilder`) converts OpenAI streaming chunks to Anthropic SSE events. The `GatewayRoutes.adapter(for:)` switch is updated to return `OpenAIAdapter()` for `"openai"` type.

**Tech Stack:** Swift, Vapor, AsyncHTTPClient, OpenAI Chat Completions API

**Reference:** `claude-code-router/packages/core/src/transformer/anthropic.transformer.ts`

---

### Task 1: Create OpenAIAdapter — Request & Response Transform

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Gateway/Providers/OpenAIAdapter.swift`
- Create: `CCGateWay/CCGateWay/Tests/OpenAIAdapterTests.swift`

**Step 1: Write the failing tests for request transformation**

Create `CCGateWay/CCGateWay/Tests/OpenAIAdapterTests.swift` with these tests:

- `transformBasicRequest` — verifies URL, headers (Bearer auth), model, max_tokens, stream:false, messages
- `transformWithSystemPrompt` — system string becomes system message
- `transformWithSystemPromptArray` — system array joined into one system message
- `transformWithTools` — Anthropic tools → OpenAI function tools format
- `transformWithToolResult` — tool_result in user message → tool role message + assistant tool_calls
- `transformStreamingRequest` — stream:true + stream_options.include_usage

**Step 2: Run test to verify it fails**

Run: `cd CCGateWay && swift test --filter OpenAIAdapterTests 2>&1 | head -30`
Expected: FAIL — `OpenAIAdapter` does not exist

**Step 3: Write OpenAIAdapter implementation**

Create `CCGateWay/CCGateWay/Sources/Gateway/Providers/OpenAIAdapter.swift`:
- `providerType = "openai"`
- `transformRequest()` — builds `/v1/chat/completions` URL, Bearer auth headers, converts messages/system/tools
- `transformResponse()` — converts OpenAI choices/message/tool_calls/usage to Anthropic format
- Private helpers: `extractSystemText()`, `convertMessage()` for role-based conversion

Key mappings:
- Anthropic `system` → OpenAI `messages[0].role = "system"`
- Anthropic `tool_use` in assistant `content → OpenAI `tool_calls` array
- Anthropic `tool_result` in user content → OpenAI `role: "tool"` message
- Anthropic `input_schema` → OpenAI `parameters`
- OpenAI `finish_reason: "stop"` → Anthropic `stop_reason: "end_turn"`
- OpenAI `finish_reason: "tool_calls"` → Anthropic `stop_reason: "tool_use"`

**Step 4: Run tests to verify they pass**

Run: `cd CCGateWay && swift test --filter OpenAIAdapterTests 2>&1 | tail -20`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add OpenAIAdapter with request/response transform"
```

---

### Task 2: Create OpenAISSEBuilder for Streaming

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Gateway/OpenAISSEBuilder.swift`
- Modify: `CCGateWay/CCGateWay/Tests/OpenAIAdapterTests.swift`

**Step 1: Write failing tests for SSE building**

Add to `OpenAIAdapterTests.swift`:
- `sseBuilderMessageStart` — first chunk emits `message_start`
- `sseBuilderTextDelta` — content chunks emit `content_block_start` + `text_delta`
- `sseBuilderToolUse` — tool_calls chunks emit `tool_use` content blocks
- `sseBuilderFinish` — `finish_reason: "stop"` emits `message_delta` + `message_stop`
- `sseBuilderUsage` — usage chunk updates `tokenUsage`
- `sseBuilderFinalize` — missing finish_reason still emits closing events

**Step 2: Run test to verify it fails**

Run: `cd CCGateWay && swift test --filter OpenAIAdapterTests 2>&1 | head -30`
Expected: FAIL — `OpenAISSEBuilder` does not exist

**Step 3: Implement OpenAISSEBuilder**

Create `CCGateWay/CCGateWay/Sources/Gateway/OpenAISSEBuilder.swift`:
- Same pattern as `AnthropicSSEBuilder` but parses OpenAI `choices[0].delta` format
- Handles `delta.content` → `text_delta` events
- Handles `delta.tool_calls` → `tool_use` content blocks with incremental `input_json_delta`
- Tracks `activeToolCalls` map for multi-chunk tool argument streaming
- `finalize()` emits closing events if stream ends without `finish_reason`
- `tokenUsage` property for logging

**Step 4: Run tests to verify they pass**

Run: `cd CCGateWay && swift test --filter OpenAIAdapterTests 2>&1 | tail -20`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add OpenAISSEBuilder for streaming conversion"
```

---

### Task 3: Wire Up OpenAI Adapter in GatewayRoutes + Streaming

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Gateway/GatewayRoutes.swift:142-147` (adapter switch)
- Modify: `CCGateWay/CCGateWay/Sources/Gateway/GatewayRoutes.swift:82,94,170,175` (log messages)
- Modify: `CCGateWay/CCGateWay/Sources/Gateway/GatewayRoutes.swift:204-221` (streaming body)

**Step 1: Update `adapter(for:)` switch**

```swift
private func adapter(for type: String) -> ProviderAdapter {
    switch type {
    case "gemini": return GeminiAdapter()
    case "openai": return OpenAIAdapter()
    default: return GeminiAdapter()  // Fallback to gemini
    }
}
```

**Step 2: Update streaming handler to branch on adapter type**

In `handleStreaming`, the managed async stream body needs to use `OpenAISSEBuilder` when adapter is OpenAI:

```swift
// Replace the single builder path with:
if adapter.providerType == "openai" {
    var parser = SSELineParser()
    var builder = OpenAISSEBuilder(requestedModel: requestedModel)
    // ... same loop but using builder.processOpenAIChunk()
    // ... skip "[DONE]" payloads
} else {
    var parser = SSELineParser()
    var builder = AnthropicSSEBuilder(requestedModel: requestedModel)
    // ... existing Gemini logic
}
```

**Step 3: Generalize hardcoded "Gemini" log messages**

Replace `"Gemini"` with `providerName` parameter in 4 print statements.

**Step 4: Run all tests**

Run: `cd CCGateWay && swift test 2>&1 | tail -20`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: wire OpenAI adapter into GatewayRoutes with streaming support"
```

---

### Task 4: Add OpenAI Response Transform Tests

**Files:**
- Modify: `CCGateWay/CCGateWay/Tests/OpenAIAdapterTests.swift`

**Step 1: Write response transform tests**

Add to `OpenAIAdapterTests.swift`:
- `transformBasicResponse` — OpenAI text response → Anthropic message format
- `transformToolCallResponse` — OpenAI tool_calls → Anthropic tool_use content blocks
- `transformErrorResponse` — OpenAI error object → throws Abort

**Step 2: Run tests (should already pass since implementation was in Task 1)**

Run: `cd CCGateWay && swift test --filter OpenAIAdapterTests 2>&1 | tail -20`
Expected: All PASS

**Step 3: Commit**

```bash
git add -A && git commit -m "test: add OpenAI response transform tests"
```

---

### Task 5: Add OpenAI Provider Default Config

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Models/ProviderConfig.swift`

**Step 1: Add static OpenAI default**

```swift
static let openAIDefault = ProviderConfig(
    name: "OpenAI",
    type: "openai",
    baseUrl: "https://api.openai.com",
    slots: [
        "default": "gpt-4o",
        "background": "gpt-4o-mini",
        "think": "gpt-4o",
        "longContext": "gpt-4o",
    ]
)
```

**Step 2: Run all tests**

Run: `cd CCGateWay && swift test 2>&1 | tail -20`
Expected: All PASS

**Step 3: Commit**

```bash
git add -A && git commit -m "feat: add OpenAI default provider config"
```

---

### Task 6: Full Integration Verification

**Step 1: Build the entire project**

Run: `cd CCGateWay && swift build 2>&1 | tail -20`
Expected: Build succeeded

**Step 2: Run all tests**

Run: `cd CCGateWay && swift test 2>&1 | tail -30`
Expected: All tests pass

**Step 3: Final commit if any cleanup needed**

```bash
git add -A && git commit -m "chore: cleanup and verify full build"
```
