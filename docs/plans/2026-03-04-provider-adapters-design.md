# Provider-Specific Adapters Design

**Date**: 2026-03-04  
**Status**: Approved  
**Problem**: Our single `OpenAIAdapter` handles all OpenAI-compatible providers (OpenAI, DeepSeek, Groq, OpenRouter). Each provider has unique API quirks that cause failures: missing `cache_control` stripping, missing `$schema` removal, missing `reasoning_content`/`reasoning` handling in streaming.

## Architecture

### Adapter Composition Pattern

Each provider gets its own adapter that **wraps** `OpenAIAdapter` via composition (not inheritance). The provider adapter preprocesses the request, delegates to the base OpenAI logic, then postprocesses if needed.

```
GatewayRoutes
  └── adapter(for: type, providerName: name)
        ├── GeminiAdapter         (unchanged)
        ├── OpenAIAdapter         (base — vanilla OpenAI)
        ├── DeepSeekAdapter       (wraps OpenAIAdapter)
        ├── GroqAdapter           (wraps OpenAIAdapter)
        └── OpenRouterAdapter     (wraps OpenAIAdapter)
```

### Adapter Selection

`GatewayRoutes.adapter(for:providerName:)` uses both `type` and `providerName` to select:

```swift
private func adapter(for type: String, providerName: String) -> ProviderAdapter {
    switch type {
    case "gemini": return GeminiAdapter()
    case "openai":
        switch providerName.lowercased() {
        case "deepseek":    return DeepSeekAdapter()
        case "groq":        return GroqAdapter()
        case "openrouter":  return OpenRouterAdapter()
        default:            return OpenAIAdapter()
        }
    default: return GeminiAdapter()
    }
}
```

### ChunkProcessor Protocol (SSE Streaming Hook)

A delegate injected into `OpenAISSEBuilder` to handle provider-specific streaming fields:

```swift
protocol ChunkProcessor {
    mutating func process(chunk: inout [String: Any], delta: inout [String: Any]) -> [String]
    mutating func finalize() -> [String]
}
```

- Called on each parsed JSON chunk **before** the generic Anthropic conversion
- Returns extra SSE events to emit (e.g., thinking blocks)
- `finalize()` called on stream end for any buffered content

## Provider-Specific Behaviors

### DeepSeekAdapter

**Request preprocessing:**
- Hard-cap `max_tokens` at 8192 (DeepSeek's limit)
- Strip `cache_control` from all message content

**Streaming (DeepSeekChunkProcessor):**
- Extract `reasoning_content` from delta → buffer it
- Emit thinking SSE events during reasoning
- On reasoning completion, emit final thinking block with signature
- Increment `choices[0].index` for content after reasoning

### GroqAdapter

**Request preprocessing:**
- Strip `cache_control` from all message content
- Strip `$schema` from all tool parameter definitions

**Streaming (GroqChunkProcessor):**
- Regenerate tool call IDs as `call_UUID` format (Groq returns numeric IDs)
- Track `hasTextContent` for correct tool call index incrementing

### OpenRouterAdapter

**Request preprocessing:**
- If target model contains "claude": keep `cache_control`
- If target model is non-Claude: strip `cache_control`

**Streaming (OpenRouterChunkProcessor):**
- Extract `reasoning` field (OpenRouter's name, different from DeepSeek's `reasoning_content`)
- Fix numeric tool call IDs → `call_UUID`
- Track `hasToolCall` for correct `finish_reason` in usage chunks

### OpenAIAdapter (vanilla)

**Request preprocessing:** No changes (existing logic stays).  
**Streaming:** Uses `DefaultChunkProcessor` (no-op).

## File Structure

```
Sources/Gateway/Providers/
├── ProviderAdapter.swift              (existing protocol)
├── OpenAIAdapter.swift                (existing, base for OpenAI-compat)
├── GeminiAdapter.swift                (existing, unchanged)
├── DeepSeekAdapter.swift              (NEW)
├── GroqAdapter.swift                  (NEW)
├── OpenRouterAdapter.swift            (NEW)
└── ChunkProcessors/
    ├── ChunkProcessor.swift           (NEW — protocol)
    ├── DefaultChunkProcessor.swift    (NEW — no-op)
    ├── DeepSeekChunkProcessor.swift   (NEW)
    ├── GroqChunkProcessor.swift       (NEW)
    └── OpenRouterChunkProcessor.swift (NEW)
```

## Testing Strategy

- **Unit tests per adapter** — mock Anthropic payloads with `cache_control`, `$schema`, verify they're stripped
- **Unit tests per ChunkProcessor** — mock streaming chunks with `reasoning_content`/`reasoning`, verify correct SSE events
- **Existing tests** — `OpenAIAdapterClampTests` continue to validate token clamping

## What Stays Unchanged

- `GeminiAdapter` — already well-implemented
- `AnthropicSSEBuilder` — Gemini streaming, untouched
- `SlotRouter` — unchanged
- `ModelCatalog` — unchanged
- `GatewayTestService` — unchanged (already uses correct `max_completion_tokens`)
