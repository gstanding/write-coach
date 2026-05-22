import Foundation

struct LLMResponseItem: Codable {
    var message: String
    var range: TextRange
    var fix_title: String
    var replacement: String
}

public struct LLMRule: Rule {
    public let id: String
    public let category: SuggestionCategory
    public let provider: LLMProvider
    public let prompt: String
    
    public init(id: String, category: SuggestionCategory, provider: LLMProvider, prompt: String) {
        self.id = id
        self.category = category
        self.provider = provider
        self.prompt = prompt
    }
    
    public func analyze(_ ctx: AnalysisContext) async throws -> [Suggestion] {
        let responseString = try await provider.complete(prompt: prompt, context: ctx.body)
        
        // Extract JSON array from the response string, assuming LLM might wrap it in markdown block
        var jsonString = responseString.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst("```json".count))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst("```".count))
        }
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast("```".count))
        }
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = jsonString.data(using: .utf8) else {
            return []
        }
        
        do {
            let items = try JSONDecoder().decode([LLMResponseItem].self, from: data)
            return items.map { item in
                let fixes = [
                    Fix(title: item.fix_title, range: item.range, replacement: item.replacement)
                ]
                let suggestionId = WritingCoachHash.sha256Hex("\(ctx.documentId)|\(id)|\(item.range.start)-\(item.range.end)|\(item.message)")
                
                return Suggestion(
                    id: suggestionId,
                    ruleId: id,
                    category: category,
                    severity: .info,
                    range: item.range,
                    message: item.message,
                    fixes: fixes
                )
            }
        } catch {
            print("Failed to decode LLM response: \(error), response: \(jsonString)")
            return []
        }
    }
}
