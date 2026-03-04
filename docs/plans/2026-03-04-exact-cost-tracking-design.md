# Cost Tracking Implementation Design

## 1. Goal
Implement exact cost tracking for each requested model within the CCGateWay macOS app, replacing the current hardcoded approximation.

## 2. Approach: Hardcoded Pricing Dictionary (Approach A)
We will maintain an internal registry of prices for known models and calculate the exact cost for each gateway request.

## 3. Architecture & Data Flow
1.  **Pricing Models**: Create a `ModelPricing.swift` structure/enum to store pricing details (cost per million input tokens, cost per million output tokens, cost per million cached input tokens - though we can start with just input/output).
2.  **Pricing Registry**: Create a `PricingManager` (or similar utility) that holds a dictionary mapping the `providerModel` string (e.g., `"gpt-4o"`, `"gemini-2.5-flash"`) to its exact input/output cost per 1M tokens.
3.  **Calculation Logic**: Update the `logSuccess` and `logStreamingSuccess` methods in `GatewayRoutes.swift`. Instead of using `$3/M` and `$15/M` globally, it will:
    *   Look up the exact model string in the `PricingManager`.
    *   If found, apply the correct math `(inputTokens / 1_000_000.0 * exactInputCost) + (outputTokens / 1_000_000.0 * exactOutputCost)`.
    *   If not found (fallback/unknown model), it can log a warning and either default to a fallback price or record $0.00.
    *   *Note*: Some models support cached token prices (which we might capture if returned in usage blocks, but we'll focus on just input/output first to keep it simple).
4.  **UI Updates**: The `RequestLog` structure already has a `cost: Double` property, and the UI correctly formats `costStr`. If the tracked cost is $0.00 or an extreme fraction, the display logic `String(format: "$%.4f", cost)` should handle it up to 4 decimal places.

## 4. Initial Pricing Data to Include
We can bootstrap the dictionary with the most common Claude Code models used today via Gemini and OpenAI APIs:

**Gemini:**
*   `gemini-2.5-pro`: Input: $2.00 / Output: $8.00 (Prices vary by prompt length, we'll start with standard <128K cost or a generalized average).
*   `gemini-2.5-flash`: Input: $0.075 / Output: $0.30

**OpenAI:**
*   `gpt-4o`: Input: $2.50 / Output: $10.00
*   `gpt-4o-mini`: Input: $0.150 / Output: $0.60
*   `o1`: Input: $15.00 / Output: $60.00
*   `o3-mini`: Input: $1.10 / Output: $4.40

*(We will refine the exact numbers during implementation to match current pricing schedules)*.
