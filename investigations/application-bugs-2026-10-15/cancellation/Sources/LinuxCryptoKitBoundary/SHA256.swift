import Foundation

// Linux compile boundary ONLY. The cancellation tests must never reach hashing.
// Apple builds use the real CryptoKit framework instead of this target.
public struct SHA256 {
    public init() {}
    public mutating func update(data: Data) {
        preconditionFailure("Crypto verification was unexpectedly reached; cancellation-only fixture must not complete a download")
    }
    public mutating func finalize() -> [UInt8] {
        preconditionFailure("No CryptoKit behavior is implemented or tested on Linux")
    }
}
