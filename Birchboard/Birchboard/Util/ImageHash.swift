import Foundation
import CryptoKit

/// Thin wrapper around CryptoKit for the few places we hash bytes.
enum ImageHash {
    static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
