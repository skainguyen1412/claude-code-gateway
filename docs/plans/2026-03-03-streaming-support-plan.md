# Streaming Support Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Implement SSE streaming translation so Claude Code receives real-time token-by-token responses from Gemini, eliminating the current full-buffer delay.

**Architecture:** Use AsyncHTTPClient (already bundled with Vapor) to make streaming HTTP requests to Gemini's `streamGenerateContent?alt=sse` endpoint. Parse each Gemini SSE chunk, transform it to Anthropic SSE format, and pipe it back to Claude Code via Vapor's `managedAsyncStream` response body. The existing non-streaming path remains as fallback.

**Tech Stack:** Swift, Vapor 4.99+, AsyncHTTPClient, NIOCore (ByteBuffer)

---

### Task 1: SSE Line Parser Utility

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Gateway/SSELineParser.swift`

**Step 1: Create the SSE line parser**

This struct accumulates raw byte chunks into complete SSE `data: {...}` lines. Gemini sends SSE as:
```
data: {"candidates":[...]}\n\n
data: {"candidates":[...]}\n\n
```

We need to buffer partial lines and emit complete JSON payloads.

```swift
import Foundation
import NIOCore

/// Parses raw byte stream into complete SSE data lines.
/// Accumulates partial data across ByteBuffer boundaries.
struct SSELineParser: Sendable {
    private var buffer: String = ""

    /// Feed raw bytes, returns any complete SSE data payloads (JSON strings).
    mutating func feed(_ byteBuffer: ByteBuffer) -> [String] {
        guard let chunk = byteBuffer.getString(at: byteBuffer.readerIndex, length: byteBuffer.readableBytes) else {
            return []
        }
        buffer += chunk

        var results: [String] = []

        // Split on double newline (SSE event boundary)
        while let range = buffer.range(of: "\n\n") {
            let eventBlock = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])

            // Extract the data line(s) from the event block
            let lines = eventBlock.components(separatedBy: "\n")
            for line in lines {
                if line.hasPrefix("data: ") {
                    let jsonStr = String(line.dropFirst(6))
                    if !jsonStr.isEmpty {
                        results.append(jsonStr)
                    }
                }
            }
        }

        return results
    }
}
```

**Step 2: Verify it compiles**

Run:
```bash
cd CCGateWay && xcodebuild -workspace CCGateWay.xcworkspace -scheme CCGateWay build 2>&1 | grep -E "(error:|BUILD)"
```
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Gateway/SSELineParser.swift
git commit -m "feat: add SSE line parser utility for streaming support"
```

---

### Task 2: Anthropic SSE Event Builder

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Gateway/AnthropicSSEBuilder.swift`

**Step 1: Create the Anthropic SSE event builder**

This struct tracks streaming state and generates properly sequenced Anthropic SSE events from Gemini chunk data. It handles the full Anthropic streaming protocol:
- `message_start` → `content_block_start` → `content_block_delta` (repeated) → `content_block_stop` → `message_delta` → `message_stop`

Reference: `claude-code-router/packages/core/src/transformer/anthropic.transformer.ts` lines 256-900.

```swift
import Foundation

/// Builds Anthropic-format SSE event strings from parsed Gemini response chunks.
/// Tracks state across chunks to properly sequence content blocks.
struct AnthropicSSEBuilder: Sendable {
    private let messageId: String
    private let requestedModel: String
    private var hasStarted = false
    private var hasTextBlockStarted = false
    private var contentBlockIndex = 0
    private var currentBlockIndex = -1

    // Token tracking for final usage
    private var lastInputTokens = 0
    private var lastOutputTokens = 0

    init(requestedModel: String) {
        self.messageId = "msg_\(UUID().uuidString.prefix(16))"
        self.requestedModel = requestedModel
    }

    /// Process a single Gemini JSON chunk and return Anthropic SSE event strings.
    /// Each returned string is a complete SSE event (e.g. "event: content_block_delta\ndata: {...}\n\n").
    mutating func processGeminiChunk(_ jsonString: String) -> [String] {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        var events: [String] = []

        // Check for error responses from Gemini
        if let error = json["error"] as? [String: Any] {
            let errorMsg = error["message"] as? String ?? "Unknown error"
            let errorEvent: [String: Any] = [
                "type": "error",
                "error": [
                    "type": "api_error",
                    "message": "Gemini API error: \(errorMsg)"
                ]
            ]
            events.append(sseEvent("error", data: errorEvent))
            return events
        }

        // Track usage metadata
        if let usage = json["usageMetadata"] as? [String: Any] {
            lastInputTokens = usage["promptTokenCount"] as? Int ?? lastInputTokens
            lastOutputTokens = usage["candidatesTokenCount"] as? Int ?? lastOutputTokens
        }

        // 1. Emit message_start on first chunk
        if !hasStarted {
            hasStarted = true
            let messageStart: [String: Any] = [
                "type": "message_start",
                "message": [
                    "id": messageId,
                    "type": "message",
                    "role": "assistant",
                    "content": [] as [Any],
                    "model": requestedModel,
                    "stop_reason": NSNull(),
                    "stop_sequence": NSNull(),
                    "usage": [
                        "input_tokens": 0,
                        "output_tokens": 0
                    ]
                ] as [String: Any]
            ]
            events.append(sseEvent("message_start", data: messageStart))
        }

        // 2. Extract candidate parts
        guard let candidates = json["candidates"] as? [[String: Any]],
              let candidate = candidates.first,
              let content = candidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else {
            // Chunk without candidates (e.g. usage-only chunk) — skip
            return events
        }

        let finishReason = candidate["finishReason"] as? String

        // 3. Process each part
        for part in parts {
            if let text = part["text"] as? String {
                // Text content
                if !hasTextBlockStarted {
                    hasTextBlockStarted = true
                    let blockIndex = nextBlockIndex()
                    let blockStart: [String: Any] = [
                        "type": "content_block_start",
                        "index": blockIndex,
                        "content_block": [
                            "type": "text",
                            "text": ""
                        ]
                    ]
                    events.append(sseEvent("content_block_start", data: blockStart))
                }

                let delta: [String: Any] = [
                    "type": "content_block_delta",
                    "index": currentBlockIndex,
                    "delta": [
                        "type": "text_delta",
                        "text": text
                    ]
                ]
                events.append(sseEvent("content_block_delta", data: delta))
            }

            if let funcCall = part["functionCall"] as? [String: Any] {
                // Close text block if open
                if hasTextBlockStarted {
                    events.append(contentBlockStop(index: currentBlockIndex))
                    hasTextBlockStarted = false
                }

                let toolName = funcCall["name"] as? String ?? "unknown"
                let toolArgs = funcCall["args"] as? [String: Any] ?? [:]
                let toolId = funcCall["id"] as? String ?? "call_\(UUID().uuidString.prefix(12))"

                let blockIndex = nextBlockIndex()

                // tool_use content_block_start
                let toolStart: [String: Any] = [
                    "type": "content_block_start",
                    "index": blockIndex,
                    "content_block": [
                        "type": "tool_use",
                        "id": toolId,
                        "name": toolName,
                        "input": [String: Any]()
                    ] as [String: Any]
                ]
                events.append(sseEvent("content_block_start", data: toolStart))

                // Send args as input_json_delta
                if let argsData = try? JSONSerialization.data(withJSONObject: toolArgs),
                   let argsStr = String(data: argsData, encoding: .utf8) {
                    let inputDelta: [String: Any] = [
                        "type": "content_block_delta",
                        "index": blockIndex,
                        "delta": [
                            "type": "input_json_delta",
                            "partial_json": argsStr
                        ]
                    ]
                    events.append(sseEvent("content_block_delta", data: inputDelta))
                }

                // Close tool block
                events.append(contentBlockStop(index: blockIndex))
            }
        }

        // 4. If finish reason present, close everything
        if let finishReason = finishReason, finishReason == "STOP" || finishReason == "MAX_TOKENS" {
            // Close open text block
            if hasTextBlockStarted {
                events.append(contentBlockStop(index: currentBlockIndex))
                hasTextBlockStarted = false
            }

            let stopReason = finishReason == "MAX_TOKENS" ? "max_tokens" : "end_turn"

            let messageDelta: [String: Any] = [
                "type": "message_delta",
                "delta": [
                    "stop_reason": stopReason,
                    "stop_sequence": NSNull()
                ] as [String: Any],
                "usage": [
                    "input_tokens": lastInputTokens,
                    "output_tokens": lastOutputTokens
                ]
            ]
            events.append(sseEvent("message_delta", data: messageDelta))
            events.append(sseEvent("message_stop", data: ["type": "message_stop"]))
        }

        return events
    }

    /// Generate final events if the stream ends without a finishReason.
    /// Call this after all chunks have been processed.
    mutating func finalize() -> [String] {
        var events: [String] = []

        if hasTextBlockStarted {
            events.append(contentBlockStop(index: currentBlockIndex))
        }

        let messageDelta: [String: Any] = [
            "type": "message_delta",
            "delta": [
                "stop_reason": "end_turn",
                "stop_sequence": NSNull()
            ] as [String: Any],
            "usage": [
                "input_tokens": lastInputTokens,
                "output_tokens": lastOutputTokens
            ]
        ]
        events.append(sseEvent("message_delta", data: messageDelta))
        events.append(sseEvent("message_stop", data: ["type": "message_stop"]))

        return events
    }

    // MARK: - Helpers

    private mutating func nextBlockIndex() -> Int {
        let idx = contentBlockIndex
        contentBlockIndex += 1
        currentBlockIndex = idx
        return idx
    }

    private func contentBlockStop(index: Int) -> String {
        sseEvent("content_block_stop", data: [
            "type": "content_block_stop",
            "index": index
        ])
    }

    private func sseEvent(_ event: String, data: [String: Any]) -> String {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonStr = String(data: jsonData, encoding: .utf8)
        else { return "" }
        return "event: \(event)\ndata: \(jsonStr)\n\n"
    }
}
```

**Step 2: Verify it compiles**

Run:
```bash
cd CCGateWay && xcodebuild -workspace CCGateWay.xcworkspace -scheme CCGateWay build 2>&1 | grep -E "(error:|BUILD)"
```
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Gateway/AnthropicSSEBuilder.swift
git commit -m "feat: add Anthropic SSE event builder for streaming translation"
```

---

### Task 3: Update GeminiAdapter for Streaming URL

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Gateway/Providers/GeminiAdapter.swift:7-23`
- Modify: `CCGateWay/CCGateWay/Sources/Gateway/Providers/ProviderAdapter.swift:7-12`
- Modify: `CCGateWay/CCGateWay/Sources/Gateway/GatewayRoutes.swift:44-54`

**Step 1: Update ProviderAdapter protocol**

In `ProviderAdapter.swift`, update the `transformRequest` signature to add `forceNonStreaming`:

```swift
protocol ProviderAdapter {
    var providerType: String { get }

    func transformRequest(
        anthropicBody: [String: Any],
        targetModel: String,
        provider: ProviderConfig,
        apiKey: String,
        forceNonStreaming: Bool
    ) throws -> (url: URI, headers: HTTPHeaders, body: [String: Any])

    func transformResponse(
        responseData: Data,
        isStreaming: Bool,
        requestedModel: String
    ) throws -> Data
}
```

**Step 2: Update GeminiAdapter.transformRequest**

In `GeminiAdapter.swift`, update the method signature and URL building to respect `forceNonStreaming`:

```swift
func transformRequest(
    anthropicBody: [String: Any],
    targetModel: String,
    provider: ProviderConfig,
    apiKey: String,
    forceNonStreaming: Bool = false
) throws -> (url: URI, headers: HTTPHeaders, body: [String: Any]) {

    let isStreaming = !forceNonStreaming && ((anthropicBody["stream"] as? Bool) ?? false)
    let action = isStreaming ? "streamGenerateContent?alt=sse" : "generateContent"
```

**Step 3: Update GatewayRoutes call site**

In `GatewayRoutes.swift`, re-add the `isStreaming` variable and pass `forceNonStreaming`:

Add before the adapter call:
```swift
let isStreaming = (anthropicBody["stream"] as? Bool) ?? false
```

Update the adapter call:
```swift
let (url, headers, transformedBody) = try adapter.transformRequest(
    anthropicBody: anthropicBody,
    targetModel: providerModel,
    provider: configProvider,
    apiKey: apiKey,
    forceNonStreaming: !isStreaming
)
```

**Step 4: Verify it compiles**

Run:
```bash
cd CCGateWay && xcodebuild -workspace CCGateWay.xcworkspace -scheme CCGateWay build 2>&1 | grep -E "(error:|BUILD)"
```
Expected: `BUILD SUCCEEDED`

**Step 5: Commit**

```bash
git add -A
git commit -m "refactor: update adapter interface to support streaming URL selection"
```

---

### Task 4: Add Streaming Route Handler

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Gateway/GatewayRoutes.swift`

**Step 1: Add AsyncHTTPClient import and convert route to async**

At the top of `GatewayRoutes.swift`, add:
```swift
import AsyncHTTPClient
```

Change the route handler from `EventLoopFuture` to async:
```swift
app.post("v1", "messages") { req async throws -> Response in
```

**Step 2: Add streaming branch in route handler**

After building the transformed request, branch on `isStreaming`:

```swift
if isStreaming {
    return try await self.handleStreaming(
        req: req,
        adapter: adapter,
        url: url,
        headers: headers,
        transformedBody: transformedBody,
        requestedModel: requestedModel,
        slot: slot,
        providerModel: providerModel,
        providerName: configProvider.name,
        startTime: startTime
    )
} else {
    // Non-streaming: existing buffered code
    // ...
}
```

**Step 3: Add the handleStreaming method**

Add a new private method to `GatewayRoutes`:

```swift
private func handleStreaming(
    req: Request,
    adapter: ProviderAdapter,
    url: URI,
    headers: HTTPHeaders,
    transformedBody: [String: Any],
    requestedModel: String,
    slot: String,
    providerModel: String,
    providerName: String,
    startTime: Date
) async throws -> Response {
    let clientRequestData = try JSONSerialization.data(withJSONObject: transformedBody)

    var httpRequest = HTTPClientRequest(url: url.string)
    httpRequest.method = .POST
    for (name, value) in headers {
        httpRequest.headers.add(name: name, value: value)
    }
    httpRequest.body = .bytes(ByteBuffer(data: clientRequestData))

    print("[Gateway] ➡️ Streaming to Gemini: \(url) (model: \(providerModel), slot: \(slot))")

    let httpClient = req.application.http.client.shared
    let httpResponse = try await httpClient.execute(httpRequest, timeout: .seconds(300))

    print("[Gateway] ⬅️ Gemini streaming response status: \(httpResponse.status.code)")

    guard httpResponse.status == .ok else {
        let body = try await httpResponse.body.collect(upTo: 1024 * 1024)
        let responseData = Data(buffer: body)
        let transformedResponseData = try adapter.transformResponse(
            responseData: responseData,
            isStreaming: false,
            requestedModel: requestedModel
        )
        var responseHeaders = HTTPHeaders()
        responseHeaders.add(name: "Content-Type", value: "application/json")
        return Response(
            status: .ok,
            headers: responseHeaders,
            body: .init(data: transformedResponseData)
        )
    }

    var responseHeaders = HTTPHeaders()
    responseHeaders.add(name: "Content-Type", value: "text/event-stream")
    responseHeaders.add(name: "Cache-Control", value: "no-cache")
    responseHeaders.add(name: "Connection", value: "keep-alive")

    let geminiBody = httpResponse.body

    let response = Response(
        status: .ok,
        headers: responseHeaders,
        body: .init(managedAsyncStream: { writer in
            var parser = SSELineParser()
            var builder = AnthropicSSEBuilder(requestedModel: requestedModel)
            var receivedFinishReason = false

            for try await chunk in geminiBody {
                let jsonPayloads = parser.feed(chunk)

                for payload in jsonPayloads {
                    let sseEvents = builder.processGeminiChunk(payload)
                    for event in sseEvents {
                        if event.contains("message_stop") {
                            receivedFinishReason = true
                        }
                        try await writer.write(.buffer(ByteBuffer(string: event)))
                    }
                }
            }

            if !receivedFinishReason {
                let finalEvents = builder.finalize()
                for event in finalEvents {
                    try await writer.write(.buffer(ByteBuffer(string: event)))
                }
            }

            self.logSuccess(
                slot: slot,
                model: providerModel,
                provider: providerName,
                authropicResp: Data(),
                startTime: startTime
            )
        })
    )

    return response
}
```

**Step 4: Convert existing non-streaming code to async**

Since the route handler is now async, replace `req.client.send(clientRequest).flatMapThrowing` with:

```swift
let clientResponse = try await req.client.send(clientRequest)
let responseData = clientResponse.body.flatMap { Data(buffer: $0) } ?? Data()
// ... rest of existing transform logic, but synchronously ...
```

**Step 5: Verify it compiles**

Run:
```bash
cd CCGateWay && xcodebuild -workspace CCGateWay.xcworkspace -scheme CCGateWay build 2>&1 | grep -E "(error:|BUILD)"
```
Expected: `BUILD SUCCEEDED`

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: add streaming SSE translation route handler"
```

---

### Task 5: Manual End-to-End Test

**Files:** None (testing only)

**Step 1: Test non-streaming (verify no regression)**

1. Build and run CCGateWay from Xcode
2. Run: `claude -p "say hello"`
3. Expected: Response comes back (may take a moment since it buffers the full response)
4. Check Xcode console for `[Gateway] ➡️` and `[Gateway] ⬅️` logs

**Step 2: Test streaming**

1. With CCGateWay running, use `claude` in interactive chat mode (which uses streaming)
2. Type: "say hello"
3. Expected: Response streams in progressively (tokens appear one by one)
4. Check Xcode console for `[Gateway] ➡️ Streaming to Gemini:` log

**Step 3: Test error handling**

1. Temporarily change the API key to an invalid value in the app
2. Run: `claude -p "hello"`
3. Expected: Error message appears (not a hang), showing the actual Gemini error
4. Restore the correct API key

**Step 4: Commit (if any test-fix adjustments were needed)**

```bash
git add -A
git commit -m "fix: address issues found during streaming E2E testing"
```

---

### Task 6: Final Cleanup and Push

**Files:**
- Optionally modify: any files that needed fixes from Task 5

**Step 1: Clean up debug logging**

Review all `print("[Gateway]")` statements. Keep them but ensure they're not dumping full response bodies in streaming mode (which would be excessive).

**Step 2: Final build verification**

Run:
```bash
cd CCGateWay && xcodebuild -workspace CCGateWay.xcworkspace -scheme CCGateWay build 2>&1 | grep -E "(error:|warning:|BUILD)"
```
Expected: `BUILD SUCCEEDED` with no warnings.

**Step 3: Commit and push**

```bash
git add -A
git commit -m "feat: streaming SSE support for Gemini → Anthropic proxy"
git push
```
