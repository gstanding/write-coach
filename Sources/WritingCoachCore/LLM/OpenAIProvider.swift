import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenAIProvider: LLMProvider {
    public var apiKey: String
    public var model: String
    public var baseURL: String
    
    public init(apiKey: String, model: String = "gpt-4o", baseURL: String = "https://api.openai.com/v1") {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }
    
    public func complete(prompt: String, context: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let messages: [[String: String]] = [
            ["role": "system", "content": prompt],
            ["role": "user", "content": context]
        ]
        
        let payload: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.3
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown Error"
            throw NSError(domain: "OpenAI", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "OpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"])
        }
        
        return content
    }
}
