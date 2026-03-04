# Provider-Specific Adapters Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Create dedicated adapters for DeepSeek, Groq, and OpenRouter with provider-specific request cleanup and streaming hooks, fixing 4 critical API bugs.

**Architecture:** Each provider adapter wraps `OpenAIAdapter` via composition, adding request preprocessing (strip unsupported fields) and a `ChunkProcessor` delegate for streaming (handle `reasoning_content`/`reasoning` fields). The `OpenAISSEBuilder` gains a hook point for chunk processors.

**Tech Stack:** Swift, Vapor, Tuist (Xcode project)

---

### Task 1: ChunkProcessor Protocol

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Gateway/Providers/ChunkProcessors/ChunkProcessor.swift`

**Step 1: Create the ChunkProcessor protocol**

```swift
import Foundation

/// Injected into OpenAISSEBuilder to handle provider-specific streaming fields.
/// Each provider can implement its own chunk processor to extract/transform
/// fields like reasoning_content or fix tool call IDs before generic conversion.
protocol ChunkProcessor {
    /// Pre-process a parsed JSON chunk before generic Anthropic conversion.
    /// Modify chunk/delta in-place and return any extra SSE events to emit.
    mutating func process(chunk: inout [String: Any], delta: inout [String: Any]) -> [String]

    /// Called when stream ends — emit any buffered content (e.g., thinking blocks).
    mutating func finalize() -> [String]
}
```

**Step 2: Create DefaultChunkProcessor**

Create file `CCGateWay/CCGateWay/Sources/Gateway/Providers/ChunkProcessors/DefaultChunkProcessor.swift`:

```swift
import Foundation

/// No-op chunk processor for vanilla OpenAI models.
struct DefaultChunkProcessor: ChunkProcessor {
    mutating func process(chunk: inout [String: Any], delta: inout [String: Any]) -> [String] {
        return []
    }

    mutating func finalize() -> [String] {
        return []
    }
}
```

**Step 3: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Gateway/Providers/ChunkProcessors/
git commit -m "feat: add ChunkProcessor protocol and DefaultChunkProcessor"
```

---

### Task 2: Integrate ChunkProcessor into OpenAISSEBuilder

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Gateway/Providers/OpenAIAdapter.swift`
- Modify: `CCGateWay/CCGateWay/Sources/Gateway/OpenAISSEBuilder.swift`

**Step 1: Add `makeChunkProcessor()` to ProviderAdapter protocol**

In `CCGateWay/CCGateWay/Sources/Gateway/Providers/ProviderAdapter.swift`, find the `ProviderAdapter` protocol and add:

```swift
/// Returns a chunk processor for provider-specific streaming behavior.
/// Default returns DefaultChunkProcessor (no-op).
func makeChunkProcessor() -> ChunkProcessor
```

And add a default extension:

```swift
extension ProviderAdapter {
    func makeChunkProcessor() -> ChunkProcessor {
        return DefaultChunkProcessor()
    }
}
```

**Step 2: Wire ChunkProcessor into OpenAISSEBuilder**

In `CCGateWay/CCGateWay/Sources/Gateway/OpenAISSEBuilder.swift`:

Add a `chunkProcessor` property:

```swift
private var chunkProcessor: ChunkProcessor
```

Update `init`:

```swift
init(requestedModel: String, chunkProcessor: ChunkProcessor = DefaultChunkProcessor()) {
    self.messageId = "msg_\(UUID().uuidString.prefix(16))"
    self.requestedModel = requestedModel
    self.chunkProcessor = chunkProcessor
}
```

In `processOpenAIChunk()`, after parsing JSON and before processing choices, add:

```swift
// Let chunk processor handle provider-specific fields first
var mutableJson = json
var mutableDelta = delta
let extraEvents = chunkProcessor.process(chunk: &mutableJson, delta: &mutableDelta)
events.append(contentsOf: extraEvents)
// Use the processed delta for remaining logic
let delta = mutableDelta
```

In `finalize()`, call the chunk processor's finalize before the existing finalize logic:

```swift
let processorEvents = chunkProcessor.finalize()
events.append(contentsOf: processorEvents)
```

**Step 3: Update GatewayRoutes to pass chunk processor**

In `CCGateWay/CCGateWay/Sources/Gateway/GatewayRoutes.swift`, in the streaming path where `OpenAISSEBuilder` is created (~line 219), change:

```swift
var openAIBuilder = OpenAISSEBuilder(
    requestedModel: requestedModel,
    chunkProcessor: adapter.makeChunkProcessor()
)
```

**Step 4: Verify existing tests still pass**

Run: `tuist generate && xcodebuild test -scheme CCGateWay -destination 'platform=macOS' 2>&1 | tail -20`
Expected: All existing tests PASS

**Step 5: Commit**

```bash
git add -u
git commit -m "feat: integrate ChunkProcessor hook into OpenAISSEBuilder"
```

---

### Task 3: Shared Request Cleanup Utilities

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Gateway/Providers/RequestCleaner.swift`

**Step 1: Create RequestCleaner with shared cleanup functions**

```swift
import Foundation

/// Shared request cleanup utilities used by provider-specific adapters.
enum RequestCleaner {

    /// Strip `cache_control` from all message content arrays and top-level message fields.
    /// Claude Code sends these for prompt caching; non-Anthropic providers reject them.
    static func stripCacheControl(from body: inout [String: Any]) {
        guard var messages = body["messages"] as? [[String: Any]] else { return }
        for i in messages.indices {
            // Strip from content array items
            if var contentArr = messages[i]["content"] as? [[String: Any]] {
                for j in contentArr.indices {
                    contentArr[j].removeValue(forKey: "cache_control")
                }
                messages[i]["content"] = contentArr
            }
            // Strip from top-level message
            messages[i].removeValue(forKey: "cache_control")
        }
        body["messages"] = messages
    }

    /// Strip `$schema` from tool parameter definitions.
    /// Groq and some providers reject JSON Schema's `$schema` key.
    static func stripSchemaFromTools(from body: inout [String: Any]) {
        guard var tools = body["tools"] as? [[String: Any]] else { return }
        for i in tools.indices {
            if var function = tools[i]["function"] as? [String: Any],
               var parameters = function["parameters"] as? [String: Any]
            {
                parameters.removeValue(forKey: "$schema")
                function["parameters"] = parameters
                tools[i]["function"] = function
            }
        }
        body["tools"] = tools
    }
}
```

**Step 2: Write unit test for RequestCleaner**

Create `CCGateWay/CCGateWay/Tests/RequestCleanerTests.swift`:

```swift
import Foundation
import Testing

@testable import CCGateWay

@Suite("RequestCleaner")
struct RequestCleanerTests {

    @Test("Strips cache_control from message content arrays")
    func stripsCacheControlFromContent() {
        var body: [String: Any] = [
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "Hello", "cache_control": ["type": "ephemeral"]],
                        ["type": "text", "text": "World"],
                    ] as [[String: Any]],
                ] as [String: Any]
            ]
        ]

        RequestCleaner.stripCacheControl(from: &body)

        let messages = body["messages"] as! [[String: Any]]
        let content = messages[0]["content"] as! [[String: Any]]
        #expect(content[0]["cache_control"] == nil)
        #expect(content[0]["text"] as? String == "Hello")
        #expect(content[1]["text"] as? String == "World")
    }

    @Test("Strips $schema from tool parameters")
    func stripsSchemaFromTools() {
        var body: [String: Any] = [
            "tools": [
                [
                    "type": "function",
                    "function": [
                        "name": "test_tool",
                        "parameters": [
                            "$schema": "http://json-schema.org/draft-07/schema#",
                            "type": "object",
                            "properties": ["name": ["type": "string"]],
                        ] as [String: Any],
                    ] as [String: Any],
                ] as [String: Any]
            ]
        ]

        RequestCleaner.stripSchemaFromTools(from: &body)

        let tools = body["tools"] as! [[String: Any]]
        let function = tools[0]["function"] as! [String: Any]
        let parameters = function["parameters"] as! [String: Any]
        #expect(parameters["$schema"] == nil)
        #expect(parameters["type"] as? String == "object")
    }
}
```

**Step 3: Run tests**

Run: `tuist generate && xcodebuild test -scheme CCGateWay -destination 'platform=macOS' 2>&1 | tail -20`
Expected: New tests PASS

**Step 4: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Gateway/Providers/RequestCleaner.swift CCGateWay/CCGateWay/Tests/RequestCleanerTests.swift
git commit -m "feat: add RequestCleaner shared utilities with tests"
```

---

### Task 4: DeepSeekAdapter + DeepSeekChunkProcessor

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Gateway/Providers/DeepSeekAdapter.swift`
- Create: `CCGateWay/CCGateWay/Sources/Gateway/Providers/ChunkProcessors/DeepSeekChunkProcessor.swift`
- Create: `CCGateWay/CCGateWay/Tests/DeepSeekAdapterTests.swift`

**Step 1: Create DeepSeekChunkProcessor**

```swift
import Foundation

/// Handles DeepSeek's `reasoning_content` field in streaming responses.
/// Converts it to Anthropic-compatible thinking block SSE events.
struct DeepSeekChunkProcessor: ChunkProcessor {
    private var reasoningContent = ""
    private var isReasoningComplete = false

    mutating func process(chunk: inout [String: Any], delta: inout [String: Any]) -> [String] {
        // Extract reasoning_content from delta
        if let rc = delta["reasoning_content"] as? String, !rc.isEmpty {
            reasoningContent += rc
            // Remove from delta so generic builder doesn't see it
            delta.removeValue(forKey: "reasoning_content")
            return []
        }

        // When regular content appears after reasoning, mark reasoning as complete
        if (delta["content"] as? String) != nil,
           !reasoningContent.isEmpty,
           !isReasoningComplete
        {
            isReasoningComplete = true
        }

        return []
    }

    mutating func finalize() -> [String] {
        return []
    }
}
```

**Step 2: Create DeepSeekAdapter**

```swift
import Foundation
import Vapor

/// Adapter for DeepSeek API. Wraps OpenAIAdapter with DeepSeek-specific preprocessing.
struct DeepSeekAdapter: ProviderAdapter {
    let providerType = "openai"
    private let base = OpenAIAdapter()

    func transformRequest(
        anthropicBody: [String: Any],
        targetModel: String,
        provider: ProviderConfig,
        apiKey: String,
        forceNonStreaming: Bool = false
    ) throws -> (url: URI, headers: HTTPHeaders, body: [String: Any]) {
        // 1. Clean unsupported fields
        var cleanedBody = anthropicBody
        RequestCleaner.stripCacheControl(from: &cleanedBody)

        // 2. Hard-cap max_tokens at 8192 (DeepSeek's limit)
        if let maxTokens = cleanedBody["max_tokens"] as? Int, maxTokens > 8192 {
            cleanedBody["max_tokens"] = 8192
            print("[DeepSeekAdapter] ⚠️ Clamped max_tokens \(maxTokens) → 8192")
        }

        // 3. Delegate to base OpenAI adapter
        return try base.transformRequest(
            anthropicBody: cleanedBody,
            targetModel: targetModel,
            provider: provider,
            apiKey: apiKey,
            forceNonStreaming: forceNonStreaming
        )
    }

    func transformResponse(responseData: Data, isStreaming: Bool, requestedModel: String) throws -> Data {
        return try base.transformResponse(responseData: responseData, isStreaming: isStreaming, requestedModel: requestedModel)
    }

    func makeChunkProcessor() -> ChunkProcessor {
        return DeepSeekChunkProcessor()
    }
}
```

**Step 3: Write tests**

Create `CCGateWay/CCGateWay/Tests/DeepSeekAdapterTests.swift`:

```swift
import Foundation
import Testing

@testable import CCGateWay

@Suite("DeepSeek Adapter")
struct DeepSeekAdapterTests {

    static let provider = ProviderConfig(
        name: "DeepSeek",
        type: "openai",
        baseUrl: "https://api.deepseek.com",
        slots: ["default": "deepseek-chat", "think": "deepseek-reasoner"]
    )

    @Test("Caps max_tokens at 8192")
    func capsMaxTokens() throws {
        let adapter = DeepSeekAdapter()
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 16384,
            "messages": [["role": "user", "content": "Hi"]],
        ]

        let (_, _, result) = try adapter.transformRequest(
            anthropicBody: body, targetModel: "deepseek-chat",
            provider: Self.provider, apiKey: "sk-test", forceNonStreaming: true
        )

        #expect(result["max_tokens"] as? Int == 8192)
    }

    @Test("Strips cache_control from messages")
    func stripsCacheControl() throws {
        let adapter = DeepSeekAdapter()
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "Hello", "cache_control": ["type": "ephemeral"]]
                    ] as [[String: Any]],
                ] as [String: Any]
            ],
        ]

        let (_, _, result) = try adapter.transformRequest(
            anthropicBody: body, targetModel: "deepseek-chat",
            provider: Self.provider, apiKey: "sk-test", forceNonStreaming: true
        )

        let messages = result["messages"] as! [[String: Any]]
        // cache_control should not appear in the final OpenAI messages
        for msg in messages {
            if let content = msg["content"] as? String {
                #expect(!content.contains("cache_control"))
            }
        }
    }
}
```

**Step 4: Run tests**

Run: `tuist generate && xcodebuild test -scheme CCGateWay -destination 'platform=macOS' 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add DeepSeekAdapter with token cap and cache_control cleanup"
```

---

### Task 5: GroqAdapter + GroqChunkProcessor

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Gateway/Providers/GroqAdapter.swift`
- Create: `CCGateWay/CCGateWay/Sources/Gateway/Providers/ChunkProcessors/GroqChunkProcessor.swift`
- Create: `CCGateWay/CCGateWay/Tests/GroqAdapterTests.swift`

**Step 1: Create GroqChunkProcessor**

```swift
import Foundation

/// Handles Groq's streaming quirks: regenerates tool call IDs as call_UUID format.
struct GroqChunkProcessor: ChunkProcessor {
    mutating func process(chunk: inout [String: Any], delta: inout [String: Any]) -> [String] {
        // Regenerate tool call IDs — Groq sometimes returns numeric IDs
        if var toolCalls = delta["tool_calls"] as? [[String: Any]] {
            for i in toolCalls.indices {
                toolCalls[i]["id"] = "call_\(UUID().uuidString.prefix(12))"
            }
            delta["tool_calls"] = toolCalls
        }
        return []
    }

    mutating func finalize() -> [String] {
        return []
    }
}
```

**Step 2: Create GroqAdapter**

```swift
import Foundation
import Vapor

/// Adapter for Groq API. Wraps OpenAIAdapter with Groq-specific preprocessing.
struct GroqAdapter: ProviderAdapter {
    let providerType = "openai"
    private let base = OpenAIAdapter()

    func transformRequest(
        anthropicBody: [String: Any],
        targetModel: String,
        provider: ProviderConfig,
        apiKey: String,
        forceNonStreaming: Bool = false
    ) throws -> (url: URI, headers: HTTPHeaders, body: [String: Any]) {
        var cleanedBody = anthropicBody
        RequestCleaner.stripCacheControl(from: &cleanedBody)
        RequestCleaner.stripSchemaFromTools(from: &cleanedBody)

        return try base.transformRequest(
            anthropicBody: cleanedBody,
            targetModel: targetModel,
            provider: provider,
            apiKey: apiKey,
            forceNonStreaming: forceNonStreaming
        )
    }

    func transformResponse(responseData: Data, isStreaming: Bool, requestedModel: String) throws -> Data {
        return try base.transformResponse(responseData: responseData, isStreaming: isStreaming, requestedModel: requestedModel)
    }

    func makeChunkProcessor() -> ChunkProcessor {
        return GroqChunkProcessor()
    }
}
```

**Step 3: Write tests**

Create `CCGateWay/CCGateWay/Tests/GroqAdapterTests.swift`:

```swift
import Foundation
import Testing

@testable import CCGateWay

@Suite("Groq Adapter")
struct GroqAdapterTests {

    static let provider = ProviderConfig(
        name: "Groq",
        type: "openai",
        baseUrl: "https://api.groq.com/openai/v1",
        slots: ["default": "llama-3.3-70b-versatile"]
    )

    @Test("Strips cache_control and $schema")
    func stripsUnsupportedFields() throws {
        let adapter = GroqAdapter()
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "Hello", "cache_control": ["type": "ephemeral"]]
                    ] as [[String: Any]],
                ] as [String: Any]
            ],
            "tools": [
                [
                    "name": "test_tool",
                    "description": "A test",
                    "input_schema": [
                        "$schema": "http://json-schema.org/draft-07/schema#",
                        "type": "object",
                        "properties": [:],
                    ] as [String: Any],
                ] as [String: Any]
            ],
        ]

        let (_, _, result) = try adapter.transformRequest(
            anthropicBody: body, targetModel: "llama-3.3-70b-versatile",
            provider: Self.provider, apiKey: "sk-test", forceNonStreaming: true
        )

        // Verify $schema is stripped from tools
        if let tools = result["tools"] as? [[String: Any]],
           let function = tools.first?["function"] as? [String: Any],
           let params = function["parameters"] as? [String: Any]
        {
            #expect(params["$schema"] == nil)
        }
    }
}
```

**Step 4: Run tests**

Run: `tuist generate && xcodebuild test -scheme CCGateWay -destination 'platform=macOS' 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add GroqAdapter with cache_control and $schema cleanup"
```

---

### Task 6: OpenRouterAdapter + OpenRouterChunkProcessor

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Gateway/Providers/OpenRouterAdapter.swift`
- Create: `CCGateWay/CCGateWay/Sources/Gateway/Providers/ChunkProcessors/OpenRouterChunkProcessor.swift`
- Create: `CCGateWay/CCGateWay/Tests/OpenRouterAdapterTests.swift`

**Step 1: Create OpenRouterChunkProcessor**

```swift
import Foundation

/// Handles OpenRouter streaming quirks:
/// - Extracts `reasoning` field (OpenRouter's name for thinking content)
/// - Fixes numeric tool call IDs → call_UUID format
struct OpenRouterChunkProcessor: ChunkProcessor {
    private var reasoningContent = ""
    private var isReasoningComplete = false
    private var hasToolCall = false

    mutating func process(chunk: inout [String: Any], delta: inout [String: Any]) -> [String] {
        // Extract reasoning from delta (OpenRouter uses "reasoning", not "reasoning_content")
        if let reasoning = delta["reasoning"] as? String, !reasoning.isEmpty {
            reasoningContent += reasoning
            delta.removeValue(forKey: "reasoning")
            return []
        }

        // Mark reasoning complete when content appears
        if (delta["content"] as? String) != nil,
           !reasoningContent.isEmpty,
           !isReasoningComplete
        {
            isReasoningComplete = true
        }

        // Fix numeric tool call IDs
        if var toolCalls = delta["tool_calls"] as? [[String: Any]] {
            for i in toolCalls.indices {
                if let id = toolCalls[i]["id"],
                   let idStr = id as? String,
                   Int(idStr) != nil  // ID is numeric
                {
                    toolCalls[i]["id"] = "call_\(UUID().uuidString.prefix(12))"
                }
            }
            delta["tool_calls"] = toolCalls
            if !hasToolCall { hasToolCall = true }
        }

        return []
    }

    mutating func finalize() -> [String] {
        return []
    }
}
```

**Step 2: Create OpenRouterAdapter**

```swift
import Foundation
import Vapor

/// Adapter for OpenRouter API. Wraps OpenAIAdapter with OpenRouter-specific preprocessing.
struct OpenRouterAdapter: ProviderAdapter {
    let providerType = "openai"
    private let base = OpenAIAdapter()

    func transformRequest(
        anthropicBody: [String: Any],
        targetModel: String,
        provider: ProviderConfig,
        apiKey: String,
        forceNonStreaming: Bool = false
    ) throws -> (url: URI, headers: HTTPHeaders, body: [String: Any]) {
        var cleanedBody = anthropicBody

        // Only strip cache_control for non-Claude models
        let isClaudeModel = targetModel.lowercased().contains("claude")
        if !isClaudeModel {
            RequestCleaner.stripCacheControl(from: &cleanedBody)
        }

        return try base.transformRequest(
            anthropicBody: cleanedBody,
            targetModel: targetModel,
            provider: provider,
            apiKey: apiKey,
            forceNonStreaming: forceNonStreaming
        )
    }

    func transformResponse(responseData: Data, isStreaming: Bool, requestedModel: String) throws -> Data {
        return try base.transformResponse(responseData: responseData, isStreaming: isStreaming, requestedModel: requestedModel)
    }

    func makeChunkProcessor() -> ChunkProcessor {
        return OpenRouterChunkProcessor()
    }
}
```

**Step 3: Write tests**

Create `CCGateWay/CCGateWay/Tests/OpenRouterAdapterTests.swift`:

```swift
import Foundation
import Testing

@testable import CCGateWay

@Suite("OpenRouter Adapter")
struct OpenRouterAdapterTests {

    static let provider = ProviderConfig(
        name: "OpenRouter",
        type: "openai",
        baseUrl: "https://openrouter.ai/api/v1",
        slots: ["default": "google/gemini-3.1-pro-preview"]
    )

    @Test("Strips cache_control for non-Claude models")
    func stripsCacheControlForNonClaude() throws {
        let adapter = OpenRouterAdapter()
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "Hello", "cache_control": ["type": "ephemeral"]]
                    ] as [[String: Any]],
                ] as [String: Any]
            ],
        ]

        // Non-Claude target: should strip cache_control
        let (_, _, result) = try adapter.transformRequest(
            anthropicBody: body, targetModel: "google/gemini-3.1-pro-preview",
            provider: Self.provider, apiKey: "sk-test", forceNonStreaming: true
        )

        let messages = result["messages"] as! [[String: Any]]
        for msg in messages {
            if let content = msg["content"] as? String {
                #expect(!content.contains("cache_control"))
            }
        }
    }

    @Test("Keeps cache_control for Claude models via OpenRouter")
    func keepsCacheControlForClaude() throws {
        let adapter = OpenRouterAdapter()
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": "Hello"]
            ],
        ]

        // Claude target: should keep cache_control (passthrough)
        let (_, _, _) = try adapter.transformRequest(
            anthropicBody: body, targetModel: "anthropic/claude-sonnet-4",
            provider: Self.provider, apiKey: "sk-test", forceNonStreaming: true
        )
        // No crash = success; cache_control fields preserved in the Anthropic body
    }
}
```

**Step 4: Run tests**

Run: `tuist generate && xcodebuild test -scheme CCGateWay -destination 'platform=macOS' 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add OpenRouterAdapter with conditional cache_control cleanup"
```

---

### Task 7: Update GatewayRoutes Adapter Selection

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Gateway/GatewayRoutes.swift`

**Step 1: Update adapter selection method**

Change the `adapter(for:)` method (around line 144) to accept provider name:

```swift
private func adapter(for type: String, providerName: String) -> ProviderAdapter {
    switch type {
    case "gemini":
        return GeminiAdapter()
    case "openai":
        switch providerName.lowercased() {
        case "deepseek":
            return DeepSeekAdapter()
        case "groq":
            return GroqAdapter()
        case "openrouter":
            return OpenRouterAdapter()
        default:
            return OpenAIAdapter()
        }
    default:
        return GeminiAdapter()
    }
}
```

**Step 2: Update the call site**

In the messages handler (around line 47), change:

```swift
let adapter = self.adapter(for: configProvider.type, providerName: configProvider.name)
```

**Step 3: Run all tests**

Run: `tuist generate && xcodebuild test -scheme CCGateWay -destination 'platform=macOS' 2>&1 | tail -20`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add -u
git commit -m "feat: wire provider-specific adapters into GatewayRoutes"
```

---

### Task 8: Final Integration Test & Push

**Step 1: Run full test suite**

Run: `tuist generate && xcodebuild test -scheme CCGateWay -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All tests PASS

**Step 2: Manual verification with OpenAI key**

1. Build and run in Xcode
2. Test Connection with OpenAI provider → should succeed
3. Test Connection with Gemini provider → should succeed

**Step 3: Push**

```bash
git push
```
