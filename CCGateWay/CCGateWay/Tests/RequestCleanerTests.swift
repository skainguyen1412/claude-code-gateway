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

    @Test("Strips cache_control from top-level message fields")
    func stripsCacheControlFromTopLevel() {
        var body: [String: Any] = [
            "messages": [
                [
                    "role": "user",
                    "content": "Hello",
                    "cache_control": ["type": "ephemeral"],
                ] as [String: Any]
            ]
        ]

        RequestCleaner.stripCacheControl(from: &body)

        let messages = body["messages"] as! [[String: Any]]
        #expect(messages[0]["cache_control"] == nil)
        #expect(messages[0]["content"] as? String == "Hello")
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

    @Test("No-op when no messages or tools")
    func noOpWhenEmpty() {
        var body: [String: Any] = ["model": "test"]

        RequestCleaner.stripCacheControl(from: &body)
        RequestCleaner.stripSchemaFromTools(from: &body)

        #expect(body["model"] as? String == "test")
    }
}
