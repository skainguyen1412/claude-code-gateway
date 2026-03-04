# OpenAI-Compatible Provider Adapter — Design Document

**Date:** 2026-03-03
**Status:** Approved

## Overview

Add an OpenAI-compatible adapter to CCGateWay so it can proxy Claude Code requests to **any provider that speaks the OpenAI `/v1/chat/completions` format** — including OpenAI, DeepSeek, Groq, Cerebras, and most self-hosted LLMs (Ollama, vLLM, etc.).

## Problem

Currently CCGateWay only supports Gemini. The reference project `claude-code-router` supports 9+ providers. Most of those (6 out of 9) use the OpenAI-compatible chat completions API, making it the single highest-ROI adapter to implement.

## Data Flow

### Non-Streaming

```
Claude Code                    CCGateWay                         OpenAI-compatible API
────────────                   ─────────                         ─────────────────────
POST /v1/messages          →   OpenAIAdapter.transformRequest()
(Anthropic format)             ├─ system → messages[0] role:system
                               ├─ messages → role-converted messages
                               ├─ tools → functions format
                               └─ auth → Bearer token header
                                                              →   POST /v1/chat/completions
                                                                   (OpenAI format)
                                                              ←   JSON response
                               OpenAIAdapter.transformResponse()
                               ├─ choices[0].message → content[]
                               ├─ tool_calls → tool_use blocks
                               ├─ usage → input/output tokens
                               └─ finish_reason → stop_reason
Claude Code              ←     Anthropic-format JSON response
```

### Streaming (SSE)

```
Claude Code                    CCGateWay                         OpenAI-compatible API
────────────                   ─────────                         ─────────────────────
POST /v1/messages          →   OpenAIAdapter.transformRequest()
  stream: true                 ├─ stream: true
                               └─ stream_options: { include_usage: true }
                                                              →   POST /v1/chat/completions
                                                                   stream: true

                                   SSELineParser                ←   data: {"choices":[{"delta":{"content":"Hi"}}]}
                                       ↓                            data: {"choices":[{"delta":{"content":" there"}}]}
                                   OpenAISSEBuilder                 data: {"choices":[{"finish_reason":"stop"}]}
                                       ↓                            data: [DONE]
                               event: message_start
                               event: content_block_start
                               event: content_block_delta  ←──→   token-by-token
                               event: content_block_stop
                               event: message_delta
Claude Code              ←     event: message_stop
```

## Format Mappings

### Request: Anthropic → OpenAI

| Anthropic Field | OpenAI Field | Notes |
|----------------|-------------|-------|
| `system` (string) | `messages[0]` with `role: "system"` | Prepended to messages array |
| `system` (array of text blocks) | `messages[0]` with joined text | Concatenated with `\n` |
| `messages[].role: "user"` | `messages[].role: "user"` | Direct mapping |
| `messages[].role: "assistant"` | `messages[].role: "assistant"` | Text extracted from content blocks |
| `messages[].content` (tool_use blocks) | `messages[].tool_calls` | `{id, function: {name, arguments}}` |
| `messages[].content` (tool_result blocks) | `messages[]` with `role: "tool"` | Each tool_result → separate tool message |
| `tools[].input_schema` | `tools[].function.parameters` | Wrapped in `{type: "function", function: {...}}` |
| `max_tokens` | `max_tokens` | Direct mapping |
| `temperature` | `temperature` | Direct mapping |
| `stream: true` | `stream: true` + `stream_options` | Adds `include_usage: true` for token tracking |

### Response: OpenAI → Anthropic

| OpenAI Field | Anthropic Field | Notes |
|-------------|----------------|-------|
| `choices[0].message.content` | `content[]: {type: "text", text: ...}` | |
| `choices[0].message.tool_calls` | `content[]: {type: "tool_use", ...}` | Arguments parsed from JSON string |
| `usage.prompt_tokens` | `usage.input_tokens` | |
| `usage.completion_tokens` | `usage.output_tokens` | |
| `finish_reason: "stop"` | `stop_reason: "end_turn"` | |
| `finish_reason: "length"` | `stop_reason: "max_tokens"` | |
| `finish_reason: "tool_calls"` | `stop_reason: "tool_use"` | |

### Streaming: OpenAI Chunks → Anthropic SSE Events

| OpenAI Streaming | Anthropic SSE Event | When |
|-----------------|--------------------|----|
| First chunk received | `message_start` | Once, on first chunk |
| `delta.content` (first non-empty) | `content_block_start` (type: text) | Once per text block |
| `delta.content` | `content_block_delta` (text_delta) | Per content chunk |
| `delta.tool_calls` (new index) | `content_block_start` (type: tool_use) | Per new tool call |
| `delta.tool_calls[].function.arguments` | `content_block_delta` (input_json_delta) | Per args chunk |
| `finish_reason` set | `content_block_stop` + `message_delta` + `message_stop` | Once, at end |
| `usage` chunk | Token counts in `message_delta` | Tracked via `stream_options` |
| `data: [DONE]` | Ignored | OpenAI terminator |

## Authentication

| Gemini | OpenAI-Compatible |
|--------|-------------------|
| `x-goog-api-key: <key>` header | `Authorization: Bearer <key>` header |
| Key per request header | Standard Bearer token |

## New Files

| File | Purpose |
|------|---------|
| `Providers/OpenAIAdapter.swift` | `ProviderAdapter` implementation — request/response transform |
| `Gateway/OpenAISSEBuilder.swift` | Streaming chunk → Anthropic SSE event conversion |

## Modified Files

| File | Change |
|------|--------|
| `GatewayRoutes.swift` | `adapter(for:)` switch adds `"openai"` case; `handleStreaming` branches on adapter type; generalize log messages |
| `ProviderConfig.swift` | Add `static let openAIDefault` |

## Key Design Decisions

1. **Reuse existing `SSELineParser`** — OpenAI SSE uses same `data: {...}\n\n` format as Gemini
2. **Separate `OpenAISSEBuilder`** instead of making `AnthropicSSEBuilder` generic — different chunk formats (Gemini `candidates[].content.parts` vs OpenAI `choices[].delta`) make a shared builder overly complex
3. **`stream_options.include_usage: true`** — OpenAI only sends usage data in streaming when explicitly requested
4. **Skip `[DONE]` sentinel** — OpenAI sends `data: [DONE]` to end streams; we filter it out in the loop
5. **Tool call argument accumulation** — OpenAI sends tool arguments incrementally across chunks; `OpenAISSEBuilder` tracks active tool calls by index
6. **No Codable structs for JSON** — matches existing pattern of using `[String: Any]` dictionaries with `JSONSerialization`, consistent with `GeminiAdapter`
