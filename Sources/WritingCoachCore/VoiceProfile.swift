import Foundation

public struct VoiceProfile: Equatable, Codable {
    public var id: String
    public var name: String
    public var sentenceLengthMean: Double
    public var sentenceLengthStd: Double
    public var connectorPreference: [String: Double]
    public var bannedPhrases: [String]
    public var favoredPhrases: [String]

    public init(
        id: String,
        name: String,
        sentenceLengthMean: Double,
        sentenceLengthStd: Double,
        connectorPreference: [String: Double] = [:],
        bannedPhrases: [String] = [],
        favoredPhrases: [String] = []
    ) {
        self.id = id
        self.name = name
        self.sentenceLengthMean = sentenceLengthMean
        self.sentenceLengthStd = sentenceLengthStd
        self.connectorPreference = connectorPreference
        self.bannedPhrases = bannedPhrases
        self.favoredPhrases = favoredPhrases
    }
}

public enum VoiceProfileBuilder {
    public static func build(id: String, name: String, bodies: [String]) -> VoiceProfile {
        let sentences = bodies.flatMap(TextSegmenter.sentences)
        let lengths = sentences.map { ($0.text as NSString).length }.map(Double.init)
        let mean = lengths.isEmpty ? 0 : lengths.reduce(0, +) / Double(lengths.count)
        let variance = lengths.isEmpty ? 0 : lengths.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(lengths.count)
        let std = sqrt(variance)
        return .init(id: id, name: name, sentenceLengthMean: mean, sentenceLengthStd: std)
    }
}

