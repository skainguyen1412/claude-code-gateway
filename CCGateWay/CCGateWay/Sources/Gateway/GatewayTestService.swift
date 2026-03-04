import Foundation

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

            // Try to extract a clean message from JSON if possible
            if let data = payload.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                // Typical format: {"error": {"message": "..."}}
                if let errorObj = json["error"] as? [String: Any],
                    let msg = errorObj["message"] as? String
                {
                    return "API \(code): \(msg)"
                }
            }

            // Fallback for non-JSON or unparseable JSON
            let cleanPayload = payload.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(
                in: .whitespacesAndNewlines)
            let truncated =
                cleanPayload.count > 100 ? cleanPayload.prefix(100) + "..." : cleanPayload
            return "API Error \(code): \(truncated)"
        case .invalidResponse: return "Invalid response from server"
        }
    }
}

@MainActor
final class GatewayTestService {
    static let shared = GatewayTestService()

    var session: URLSession = .shared

    private init() {}

    func testConnection(baseUrl: String, apiKey: String, type: String, model: String) async throws
        -> Bool
    {
        let cleanBaseUrl = baseUrl.hasSuffix("/") ? baseUrl : baseUrl + "/"

        var requestURL: URL?
        var request: URLRequest?

        if type == "gemini" {
            // Gemini uses URL parameters for the API key and a specific format
            // e.g., https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=...
            guard let url = URL(string: "\(cleanBaseUrl)\(model):generateContent?key=\(apiKey)")
            else {
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
            if !fullUrlStr.contains("/chat/completions") {
                // Most OpenAI-compatible APIs use /v1/chat/completions
                if fullUrlStr.hasSuffix("/v1/") || fullUrlStr.hasSuffix("/v1") {
                    fullUrlStr =
                        (fullUrlStr.hasSuffix("/") ? fullUrlStr : fullUrlStr + "/")
                        + "chat/completions"
                } else {
                    fullUrlStr = cleanBaseUrl + "v1/chat/completions"
                }
            }
            guard let url = URL(string: fullUrlStr) else {
                throw TestConnectionError.invalidURL
            }
            requestURL = url
            request = URLRequest(url: url)
            request?.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request?.addValue("application/json", forHTTPHeaderField: "Content-Type")

            // Determine token parameter based on model
            let useCompletionTokens = ["o1", "o3", "o4", "gpt"].contains {
                model.hasPrefix($0) || model.contains("/\($0)") || model.contains("-\($0)")
            }

            // Minimal payload
            var payload: [String: Any] = [
                "model": model,
                "messages": [
                    ["role": "user", "content": "Hi"]
                ],
            ]

            if useCompletionTokens {
                payload["max_completion_tokens"] = 50
            } else {
                payload["max_tokens"] = 50
            }
            request?.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        }

        guard let finalRequest = request, requestURL != nil else {
            throw TestConnectionError.invalidURL
        }

        var mutableReq = finalRequest
        mutableReq.httpMethod = "POST"
        mutableReq.timeoutInterval = 10.0  // 10s timeout

        do {
            let (data, response) = try await session.data(for: mutableReq)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TestConnectionError.invalidResponse
            }

            if (200...299).contains(httpResponse.statusCode) {
                return true
            } else {
                let payload = String(data: data, encoding: .utf8) ?? ""
                throw TestConnectionError.apiError(
                    statusCode: httpResponse.statusCode, payload: payload)
            }
        } catch let error as TestConnectionError {
            throw error
        } catch {
            throw TestConnectionError.networkError(error)
        }
    }
}
