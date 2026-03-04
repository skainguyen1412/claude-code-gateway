# Test Connection Feature Design

## Overview
The "Test Connection" feature allows users to verify their API provider credentials (Base URL and API Key) before saving them. This provides immediate feedback and prevents runtime errors when `claude-code` attempts to use the gateway.

## Approach
We will use an **Inline Status + Gateway Service** approach. The UI will show the test status inline next to the button, and the actual test will be performed by a new `GatewayTestService` to ensure the validation logic matches the actual runtime logic of the gateway.

## UI Component (`ProviderEditView`)

### State Management
```swift
enum ConnectionTestState: Equatable {
    case idle
    case testing
    case success
    case failure(String)
}
```

### Layout
The test status will be displayed in an `HStack` inline with the "Test Connection" button:
- **Idle:** Just the "Test Connection" button.
- **Testing:** The button is disabled. A `ProgressView` and "Testing..." text are shown next to it.
- **Success:** A green checkmark (`Image(systemName: "checkmark.circle.fill")`) and "Success" text are shown.
- **Failure:** A red x-mark (`Image(systemName: "xmark.circle.fill")`) and the error message (truncated or with a help popover) are shown. The text should be red.

## Backend Integration (`GatewayTestService`)

A new service or function (e.g. `func testConnection(for config: ProviderConfig, apiKey: String) async throws`) will be introduced.

### Test Logic
1.  **Construct Request:** Create an ad-hoc configuration using the currently entered values in the UI (not necessarily the saved values).
2.  **API Call:** Send a lightweight request to the provider. For OpenAI/DeepSeek/OpenRouter, this could be a `[{"role": "user", "content": "Hi"}]` chat completion request using a fast model (like `gemini-2.5-flash` or the user's default slot). Alternatively, it could be a request to the `/models` endpoint if the provider supports it.
    *   *Decision:* The simplest universal test is a basic chat completion request for 1 token.
3.  **Result:**
    *   If HTTP 200, return `.success`.
    *   If HTTP 401/403, return `.failure("Invalid API Key")`.
    *   If HTTP 404, return `.failure("Invalid Base URL")`.
    *   Otherwise, return `.failure(error.localizedDescription)`.

## Error Handling
- Network errors (e.g., DNS resolution failure) should be gracefully caught and displayed to the user.
- The UI should not block or crash during the test.
- The test task should be cancellable if the user dismisses the view.
