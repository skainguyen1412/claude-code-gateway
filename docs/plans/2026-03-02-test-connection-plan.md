# Test Connection Feature Implementation Plan

> **For Antigravity:** REQUIRED WORKFLOW: Use `.agent/workflows/execute-plan.md` to execute this plan in single-flow mode.

**Goal:** Allow users to test their API provider credentials directly from the Provider Edit UI before saving them.

**Architecture:** Introduce a `GatewayTestService` that makes a minimal ad-hoc API call to the provider using the currently entered credentials. The `ProviderEditView` will use this service and display the test status inline using a new `ConnectionTestState` enum. We will use the native Vapor client since the app is already a Vapor server.

**Tech Stack:** Swift, SwiftUI, Vapor (Vapor Client)

---

### Task 1: Create GatewayTestService

**Files:**
- Create: `CCGateWay/CCGateWay/Sources/Gateway/GatewayTestService.swift`

**Step 1: Write minimal implementation**

```swift
import Foundation
import Vapor

enum TestConnectionError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case apiError(status: HTTPStatus, message: String)
    case invalidConfig
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Base URL"
        case .networkError(let error): return error.localizedDescription
        case .apiError(let status, let message):
            var errStr = "\(status.code) \(status.reasonPhrase)"
            if !message.isEmpty { errStr += ": \(message)" }
            return errStr
        case .invalidConfig: return "Invalid Configuration"
        }
    }
}

actor GatewayTestService {
    static let shared = GatewayTestService()
    
    private let client: Client
    
    // We create a minimal standalone app just to use its client for testing
    // In a real app we might inject the running application's client, but since 
    // we test *before* the server might be configuring a new route, a fresh client is safe.
    // Or simpler: use URLSession for testing to avoid Vapor App lifecycle issues in the UI.
    
    init() {
        // We'll use URLSession since it's easier to use standalone in a SwiftUI View
        // without depending on the GatewayServer's Vapor Application which might be stopped.
        let app = Application(.testing)
        self.client = app.client
    }
    
    func testConnection(baseUrl: String, apiKey: String, type: String, model: String) async throws -> Bool {
        // Using URLSession directly is safer here to avoid managing a Vapor App lifecycle just for the client.
        // We will implement using URLSession in Step 3 to keep it lightweight.
        return true
    }
}
```

**Step 2: Refine implementation with URLSession**

Actually, let's use `URLSession` for the test. It avoids having to spin up another Vapor `Application` just to use its HTTP client, which can be tricky with Swift concurrency and app lifecycles.

Change `GatewayTestService.swift` to:

```swift
import Foundation

// Note: Add this to CCGateWay/CCGateWay/Sources/Gateway/GatewayTestService.swift

enum TestConnectionError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case apiError(statusCode: Int, payload: String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Base URL"
        case .networkError(let error): return error.localizedDescription
        case .apiError(let code, let payload):
            if code == 401 || code == 403 {
                return "Invalid API Key (\(code))"
            }
            if code == 404 {
                return "Model or Endpoint not found (404)"
            }
            return "API Error: \(code)\n\(payload.prefix(100))"
        case .invalidResponse: return "Invalid response from server"
        }
    }
}

@MainActor
final class GatewayTestService {
    static let shared = GatewayTestService()
    
    private init() {}
    
    func testConnection(baseUrl: String, apiKey: String, type: String, model: String) async throws -> Bool {
        let cleanBaseUrl = baseUrl.hasSuffix("/") ? baseUrl : baseUrl + "/"
        
        var requestURL: URL?
        var request: URLRequest?
        
        if type == "gemini" {
            // Gemini uses URL parameters for the API key and a specific format
            // e.g., https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=...
            guard let url = URL(string: "\(cleanBaseUrl)\(model):generateContent?key=\(apiKey)") else {
                throw TestConnectionError.invalidURL
            }
            requestURL = url
            request = URLRequest(url: url)
            request?.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Minimal payload for Gemini
            let payload: [String: Any] = [
                "contents": [
                    ["role": "user", "parts": [["text": "Hi"]]]
                ]
            ]
            request?.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            
        } else {
            // OpenAI / OpenRouter / DeepSeek
            // Append /chat/completions if not already there, for testing.
            var fullUrlStr = cleanBaseUrl
            if !fullUrlStr.hasSuffix("/chat/completions") && !fullUrlStr.hasSuffix("/chat/completions/") {
                fullUrlStr = cleanBaseUrl + "chat/completions"
            }
            guard let url = URL(string: fullUrlStr) else {
                throw TestConnectionError.invalidURL
            }
            requestURL = url
            request = URLRequest(url: url)
            request?.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request?.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Minimal payload
            let payload: [String: Any] = [
                "model": model,
                "messages": [
                    ["role": "user", "content": "Hi"]
                ],
                "max_tokens": 1
            ]
            request?.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        }
        
        guard let finalRequest = request, let _ = requestURL else {
            throw TestConnectionError.invalidURL
        }
        
        var mutableReq = finalRequest
        mutableReq.httpMethod = "POST"
        mutableReq.timeoutInterval = 10.0 // 10s timeout
        
        do {
            let (data, response) = try await URLSession.shared.data(for: mutableReq)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TestConnectionError.invalidResponse
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                return true
            } else {
                let payload = String(data: data, encoding: .utf8) ?? ""
                throw TestConnectionError.apiError(statusCode: httpResponse.statusCode, payload: payload)
            }
        } catch let error as TestConnectionError {
            throw error
        } catch {
            throw TestConnectionError.networkError(error)
        }
    }
}
```

**Step 2: Commit Test Service**

```bash
git add CCGateWay/CCGateWay/Sources/Gateway/GatewayTestService.swift
git commit -m "feat: add GatewayTestService using URLSession"
```

---

### Task 2: Implement UI State and Logic in `ProviderEditView`

**Files:**
- Modify: `CCGateWay/CCGateWay/Sources/Views/ProviderEditView.swift`

**Step 1: Add ConnectionTestState enum (at the top of file or outside the struct)**

```swift
enum ConnectionTestState: Equatable {
    case idle
    case testing
    case success
    case failure(String)
}
```

**Step 2: Add State property to ProviderEditView**

Add `@State private var testState: ConnectionTestState = .idle` to the state property list in `ProviderEditView`.

**Step 3: Modify the "Test Connection" Button Area**

Replace:
```swift
                Button("Test Connection") {
                    // MVP implementation assumes test connection logic would go here
                    print("Testing connection to \(baseUrl) with key \(apiKey.prefix(4))...")
                }
                Spacer()
```

With:
```swift
                HStack(spacing: 12) {
                    Button("Test Connection") {
                        runTestConnection()
                    }
                    .disabled(testState == .testing || baseUrl.isEmpty || apiKey.isEmpty)
                    
                    switch testState {
                    case .idle:
                        EmptyView()
                    case .testing:
                        ProgressView()
                            .controlSize(.small)
                        Text("Testing...")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Success")
                            .foregroundColor(.green)
                            .font(.caption)
                    case .failure(let errorMsg):
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text(errorMsg)
                            .foregroundColor(.red)
                            .font(.caption)
                            .lineLimit(2)
                            .help(errorMsg) // Tooltip for full error
                    }
                }
                Spacer()
```

**Step 4: Add the `runTestConnection()` logic**

Add this function to `ProviderEditView`:

```swift
    private func runTestConnection() {
        // Reset state
        testState = .testing
        
        // Build parameters
        let testBaseUrl = self.baseUrl
        let testApiKey = self.apiKey
        let testType = self.type
        // Try to pick a model to test with
        let testModel = !self.defaultSlot.isEmpty ? self.defaultSlot :
                        (!self.backgroundSlot.isEmpty ? self.backgroundSlot :
                        (testType == "gemini" ? "gemini-2.5-flash" : "gpt-4o-mini"))
        
        Task {
            do {
                _ = try await GatewayTestService.shared.testConnection(
                    baseUrl: testBaseUrl,
                    apiKey: testApiKey,
                    type: testType,
                    model: testModel
                )
                // If we get here, no error was thrown
                if !Task.isCancelled {
                    testState = .success
                }
            } catch {
                if !Task.isCancelled {
                    testState = .failure(error.localizedDescription)
                }
            }
        }
    }
```

**Step 5: Modify `saveProvider` and `.onChange` handlers to reset state (Optional but good UX)**

Whenever `baseUrl`, `apiKey`, `type`, or slots change, reset `testState` back to `.idle`.
Add these to the `Form` modifier chain in `ProviderEditView` (e.g., just after `.frame(...)`):

```swift
        .onChange(of: baseUrl) { _ in testState = .idle }
        .onChange(of: apiKey) { _ in testState = .idle }
        .onChange(of: type) { _ in testState = .idle }
        .onChange(of: defaultSlot) { _ in testState = .idle }
```

**Step 6: Build and Commit UI Changes**

1. Build the project using Xcode or Tuist to ensure there are no syntax errors.
2. Commit:

```bash
git add CCGateWay/CCGateWay/Sources/Views/ProviderEditView.swift
git commit -m "feat: implement test connection UI logic and state machine"
```
