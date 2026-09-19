import CryptoKit
import Foundation

public enum EvidenceIntegrity {
    public static func sha256(of data: Data) -> EvidenceSHA256 {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return try! EvidenceSHA256(hex)
    }
}
