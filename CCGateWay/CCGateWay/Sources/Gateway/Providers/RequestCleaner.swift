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
            // Anthropic-style tool definition used before adapter conversion.
            if var inputSchema = tools[i]["input_schema"] as? [String: Any] {
                inputSchema.removeValue(forKey: "$schema")
                tools[i]["input_schema"] = inputSchema
            }

            // OpenAI-style tool definition used after conversion.
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
