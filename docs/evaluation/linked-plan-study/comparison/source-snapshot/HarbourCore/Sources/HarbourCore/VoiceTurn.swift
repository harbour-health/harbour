import Foundation

/// A turn is emitted once. Cancellation invalidates late recognition callbacks.
public struct VoiceTurn: Sendable {
    public private(set) var id = UUID()
    public private(set) var text = ""
    public private(set) var emitted = false
    private var closed = true
    public init() {}
    public mutating func begin() -> UUID { id = UUID(); text = ""; emitted = false; closed = false; return id }
    /// Returns whether the accepted text changed; duplicate ASR callbacks are not new speech.
    @discardableResult public mutating func partial(_ value: String, id: UUID) -> Bool {
        guard id == self.id, !closed else { return false }
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value != text else { return false }
        text = value; return true
    }
    public mutating func finish(id: UUID) -> String? {
        guard id == self.id, !closed else { return nil }
        closed = true
        guard !text.isEmpty else { return nil }
        emitted = true; return text
    }
    public mutating func cancel() { id = UUID(); text = ""; emitted = false; closed = true }
}
