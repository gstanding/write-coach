import Foundation

public enum WritingCoachHash {
    public static func sha256Hex(_ s: String) -> String {
        let data = Data(s.utf8)
        let digest = SHA256Hasher.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
