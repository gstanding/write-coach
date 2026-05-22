import Foundation

public protocol LLMProvider: Sendable {
    func complete(prompt: String, context: String) async throws -> String
}
