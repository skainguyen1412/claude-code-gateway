import Foundation
import Testing

@testable import CCGateWay

class MockURLProtocol: URLProtocol {
    static var mockData: Data?
    static var mockResponse: URLResponse?
    static var mockError: Error?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        if let error = MockURLProtocol.mockError {
            self.client?.urlProtocol(self, didFailWithError: error)
        } else {
            if let response = MockURLProtocol.mockResponse {
                self.client?.urlProtocol(
                    self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data = MockURLProtocol.mockData {
                self.client?.urlProtocol(self, didLoad: data)
            }
        }
        self.client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Gateway Test Service Tests")
@MainActor
struct GatewayTestServiceTests {

    let service: GatewayTestService

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        service = GatewayTestService.shared
        service.session = session
    }

    @Test("Successful connection returns true")
    func testSuccessfulConnection() async throws {
        // Arrange
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://test.com")!, statusCode: 200, httpVersion: nil,
            headerFields: nil)
        MockURLProtocol.mockResponse = mockResponse
        MockURLProtocol.mockError = nil
        MockURLProtocol.mockData = Data("{}".utf8)

        // Act
        let result = try await service.testConnection(
            baseUrl: "https://test.com", apiKey: "test_key", type: "openai", model: "gpt-4")

        // Assert
        #expect(result == true)
    }

    @Test("401 Unauthorized returns apiError")
    func testUnauthorizedConnection() async {
        // Arrange
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://test.com")!, statusCode: 401, httpVersion: nil,
            headerFields: nil)
        MockURLProtocol.mockResponse = mockResponse
        MockURLProtocol.mockError = nil
        MockURLProtocol.mockData = Data("Unauthorized".utf8)

        // Act & Assert
        do {
            _ = try await service.testConnection(
                baseUrl: "https://test.com", apiKey: "wrong_key", type: "openai", model: "gpt-4")
            Issue.record("Expected testConnection to throw, but it succeeded")
        } catch let error as TestConnectionError {
            if case .apiError(let code, _) = error {
                #expect(code == 401)
            } else {
                Issue.record("Expected apiError(401), but got \(error)")
            }
        } catch {
            Issue.record("Expected TestConnectionError, but got \(error)")
        }
    }
}
