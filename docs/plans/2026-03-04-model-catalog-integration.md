# Model Catalog Integration Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Wire ModelCatalog data into the gateway pipeline — clamp output tokens, rename fields for reasoning models, and use real per-model pricing.

**Architecture:** Three independent changes to the gateway pipeline: (1) clamp `max_tokens` in each adapter's `transformRequest` using the model's `maxOutputTokens`, (2) rename `max_tokens` → `max_completion_tokens` for OpenAI reasoning models, (3) replace hardcoded cost in `GatewayRoutes` logging with `ModelCatalog.find(modelId:)?.cost`.

**Tech Stack:** Swift, Swift Testing, existing CCGateWay project

---

### Task 1: Token Clamping in GeminiAdapter

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Gateway/Providers/GeminiAdapter.swift:50-60`
- Test: `CCGateWay/CCGateWay/Tests/GeminiAdapterClampTests.swift`

**Step 1: Write the failing test**

Create `CCGateWay/CCGateWay/Tests/GeminiAdapterClampTests.swift`:

```swift
import Foundation
import Testing

@testable import CCGateWay

@Suite("Gemini Adapter Token Clamping")
struct GeminiAdapterClampTests {

    static let provider = ProviderConfig(
        name: "Gemini",
        type: "gemini",
        baseUrl: "https://generativelanguage.googleapis.com/v1beta/models/",
        slots: ["default": "gemini-2.5-flash"]
    )

    @Test("Clamps max_tokens to model maxOutputTokens when exceeded")
    func clampsExcessiveMaxTokens() throws {
        let adapter = GeminiAdapter()
        // gemini-2.5-flash maxOutputTokens = 65535
        // Request 100,000 — should be clamped to 65535
        let anthropicBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 100_000,
            "messages": [["role": "user", "content": "Hello"]],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "gemini-2.5-flash",
            provider: Self.provider,
            apiKey: "test-key",
            forceNonStreaming: true
        )

        let genConfig = body["generationConfig"] as? [String: Any]
        let maxOutput = genConfig?["maxOutputTokens"] as? Int
        #expect(maxOutput == 65535)
    }

    @Test("Passes through max_tokens when within model limit")
    func passesValidMaxTokens() throws {
        let adapter = GeminiAdapter()
        let anthropicBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "messages": [["role": "user", "content": "Hello"]],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "gemini-2.5-flash",
            provider: Self.provider,
            apiKey: "test-key",
            forceNonStreaming: true
        )

        let genConfig = body["generationConfig"] as? [String: Any]
        let maxOutput = genConfig?["maxOutputTokens"] as? Int
        #expect(maxOutput == 4096)
    }

    @Test("Falls back to original value when model not in catalog")
    func fallsBackForUnknownModel() throws {
        let adapter = GeminiAdapter()
        let anthropicBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 100_000,
            "messages": [["role": "user", "content": "Hello"]],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "gemini-unknown-model",
            provider: Self.provider,
            apiKey: "test-key",
            forceNonStreaming: true
        )

        let genConfig = body["generationConfig"] as? [String: Any]
        let maxOutput = genConfig?["maxOutputTokens"] as? Int
        #expect(maxOutput == 100_000) // no clamping for unknown models
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter GeminiAdapterClampTests` from `CCGateWay/`
Expected: FAIL — max_tokens not clamped

**Step 3: Implement clamping in GeminiAdapter**

In `GeminiAdapter.swift`, replace lines 55-56:

```swift
// Before (line 55-56):
if let maxTokens = anthropicBody["max_tokens"] as? Int {
    generationConfig["maxOutputTokens"] = maxTokens
}

// After:
if let maxTokens = anthropicBody["max_tokens"] as? Int {
    if let modelInfo = ModelCatalog.find(modelId: targetModel),
       maxTokens > modelInfo.maxOutputTokens {
        generationConfig["maxOutputTokens"] = modelInfo.maxOutputTokens
        print("[GeminiAdapter] ⚠️ Clamped max_tokens \(maxTokens) → \(modelInfo.maxOutputTokens) for \(targetModel)")
    } else {
        generationConfig["maxOutputTokens"] = maxTokens
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter GeminiAdapterClampTests`
Expected: PASS

**Step 5: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Gateway/Providers/GeminiAdapter.swift \
        CCGateWay/CCGateWay/Tests/GeminiAdapterClampTests.swift
git commit -m "feat: clamp max_tokens in GeminiAdapter using ModelCatalog"
```

---

### Task 2: Token Clamping + max_completion_tokens in OpenAIAdapter

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Gateway/Providers/OpenAIAdapter.swift:39-44`
- Test: `CCGateWay/CCGateWay/Tests/OpenAIAdapterClampTests.swift`

**Step 1: Write the failing test**

Create `CCGateWay/CCGateWay/Tests/OpenAIAdapterClampTests.swift`:

```swift
import Foundation
import Testing

@testable import CCGateWay

@Suite("OpenAI Adapter Token Clamping & Reasoning Models")
struct OpenAIAdapterClampTests {

    static let provider = ProviderConfig(
        name: "OpenAI",
        type: "openai",
        baseUrl: "https://api.openai.com/v1",
        slots: ["default": "gpt-5", "think": "o3"]
    )

    @Test("Clamps max_tokens for standard models")
    func clampsForStandardModel() throws {
        let adapter = OpenAIAdapter()
        // gpt-5 maxOutputTokens = 128_000
        let anthropicBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 200_000,
            "messages": [["role": "user", "content": "Hello"]],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "gpt-5",
            provider: Self.provider,
            apiKey: "sk-test",
            forceNonStreaming: true
        )

        #expect(body["max_tokens"] as? Int == 128_000)
        #expect(body["max_completion_tokens"] == nil) // standard model keeps max_tokens
    }

    @Test("Renames max_tokens to max_completion_tokens for o3")
    func renamesForO3() throws {
        let adapter = OpenAIAdapter()
        let anthropicBody: [String: Any] = [
            "model": "claude-opus-4-20250514",
            "max_tokens": 8192,
            "messages": [["role": "user", "content": "Think hard"]],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "o3",
            provider: Self.provider,
            apiKey: "sk-test",
            forceNonStreaming: true
        )

        // For reasoning models: max_tokens should be renamed to max_completion_tokens
        #expect(body["max_completion_tokens"] as? Int == 8192)
        #expect(body["max_tokens"] == nil)
    }

    @Test("Renames max_tokens to max_completion_tokens for o4-mini")
    func renamesForO4Mini() throws {
        let adapter = OpenAIAdapter()
        let anthropicBody: [String: Any] = [
            "model": "claude-opus-4-20250514",
            "max_tokens": 50_000,
            "messages": [["role": "user", "content": "Think hard"]],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "o4-mini",
            provider: Self.provider,
            apiKey: "sk-test",
            forceNonStreaming: true
        )

        #expect(body["max_completion_tokens"] as? Int == 50_000)
        #expect(body["max_tokens"] == nil)
    }

    @Test("Clamps AND renames for reasoning model when over limit")
    func clampsAndRenamesForO3() throws {
        let adapter = OpenAIAdapter()
        // o3 maxOutputTokens = 100_000
        let anthropicBody: [String: Any] = [
            "model": "claude-opus-4-20250514",
            "max_tokens": 200_000,
            "messages": [["role": "user", "content": "Think very hard"]],
        ]

        let (_, _, body) = try adapter.transformRequest(
            anthropicBody: anthropicBody,
            targetModel: "o3",
            provider: Self.provider,
            apiKey: "sk-test",
            forceNonStreaming: true
        )

        #expect(body["max_completion_tokens"] as? Int == 100_000) // clamped + renamed
        #expect(body["max_tokens"] == nil)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter OpenAIAdapterClampTests` from `CCGateWay/`
Expected: FAIL

**Step 3: Implement clamping + rename in OpenAIAdapter**

In `OpenAIAdapter.swift`, replace lines 39-41:

```swift
// Before (lines 39-41):
if let maxTokens = anthropicBody["max_tokens"] as? Int {
    body["max_tokens"] = maxTokens
}

// After:
if let maxTokens = anthropicBody["max_tokens"] as? Int {
    // 1. Clamp to model's maxOutputTokens if known
    var clampedTokens = maxTokens
    if let modelInfo = ModelCatalog.find(modelId: targetModel),
       maxTokens > modelInfo.maxOutputTokens {
        clampedTokens = modelInfo.maxOutputTokens
        print("[OpenAIAdapter] ⚠️ Clamped max_tokens \(maxTokens) → \(clampedTokens) for \(targetModel)")
    }

    // 2. Reasoning models (o3, o4-mini, etc.) use max_completion_tokens instead
    let isReasoningModel = targetModel.hasPrefix("o3") || targetModel.hasPrefix("o4")
    if isReasoningModel {
        body["max_completion_tokens"] = clampedTokens
    } else {
        body["max_tokens"] = clampedTokens
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter OpenAIAdapterClampTests`
Expected: PASS

**Step 5: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Gateway/Providers/OpenAIAdapter.swift \
        CCGateWay/CCGateWay/Tests/OpenAIAdapterClampTests.swift
git commit -m "feat: clamp max_tokens + rename for reasoning models in OpenAIAdapter"
```

---

### Task 3: Real Cost Estimation Using ModelCatalog

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Gateway/GatewayRoutes.swift:303-358`

**Step 1: Write a helper function for cost calculation**

Add a private helper to `GatewayRoutes`:

```swift
/// Calculate cost using ModelCatalog pricing, with fallback to default rates.
private func estimateCost(model: String, inputTokens: Int, outputTokens: Int) -> Double {
    if let modelInfo = ModelCatalog.find(modelId: model) {
        return modelInfo.cost.estimate(inputTokens: inputTokens, outputTokens: outputTokens)
    }
    // Fallback: $1.25/M input, $10/M output (GPT-5 tier)
    let costIn = Double(inputTokens) / 1_000_000.0 * 1.25
    let costOut = Double(outputTokens) / 1_000_000.0 * 10.0
    return costIn + costOut
}
```

**Step 2: Update logSuccess to use estimateCost**

In `GatewayRoutes.swift`, replace lines 318-321:

```swift
// Before (lines 318-321):
// Cost estimation placeholder: assume $3/M in, $15/M out
let costIn = Double(inToks) / 1_000_000.0 * 3.0
let costOut = Double(outToks) / 1_000_000.0 * 15.0
let totalCost = costIn + costOut

// After:
let totalCost = estimateCost(model: model, inputTokens: inToks, outputTokens: outToks)
```

**Step 3: Update logStreamingSuccess to use estimateCost**

In `GatewayRoutes.swift`, replace lines 342-344:

```swift
// Before (lines 342-344):
let costIn = Double(inputTokens) / 1_000_000.0 * 3.0
let costOut = Double(outputTokens) / 1_000_000.0 * 15.0
let totalCost = costIn + costOut

// After:
let totalCost = estimateCost(model: model, inputTokens: inputTokens, outputTokens: outputTokens)
```

**Step 4: Verify build**

Run: `xcodebuild -project CCGateWay.xcodeproj -scheme CCGateWay build 2>&1 | grep error: | grep -v Vapor`
Expected: No errors from our code

**Step 5: Commit**

```bash
git add CCGateWay/CCGateWay/Sources/Gateway/GatewayRoutes.swift
git commit -m "feat: use ModelCatalog pricing for cost estimation instead of hardcoded rates"
```

---

### Task 4: Integration Verification & Push

**Step 1: Run all tests**

```bash
cd CCGateWay && swift test 2>&1
```

Expected: All tests pass (existing + new)

**Step 2: Manual smoke test**

Start the gateway, configure a provider with API key, and verify:
- A request with `max_tokens: 999999` doesn't fail (gets clamped)
- Cost in the request log reflects real pricing (not $3/$15)
- The gateway log shows `⚠️ Clamped max_tokens` warnings when clamping occurs

**Step 3: Push**

```bash
git push
```
