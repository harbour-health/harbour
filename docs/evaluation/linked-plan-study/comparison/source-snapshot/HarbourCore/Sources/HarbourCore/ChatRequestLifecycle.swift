import Foundation

/// Owns a chat operation until its work has actually returned, including after
/// cooperative cancellation. UI readiness must follow this state, not cancel().
@MainActor public final class ChatRequestLifecycle {
    public enum State: Equatable, Sendable {
        case idle
        case running(UUID)
        case cancelling(UUID)

        public var isBusy: Bool { self != .idle }
        public var isCancelling: Bool {
            if case .cancelling = self { return true }
            return false
        }
    }

    public private(set) var state: State = .idle
    public var onStateChange: (@MainActor (State) -> Void)?
    private var task: Task<Void, Never>?

    public init() {}

    /// A rejected start performs no work. Callers must wait for admission before
    /// clearing the composer or appending the new user message.
    @discardableResult
    public func start(
        operation: @escaping @MainActor (UUID) async -> Void,
        onCompletion: @escaping @MainActor (Bool) -> Void = { _ in }
    ) -> UUID? {
        guard !state.isBusy else { return nil }
        let id = UUID()
        task = Task { @MainActor in
            // Stop may arrive before this newly scheduled task has begun.
            if !Task.isCancelled { await operation(id) }
            let acceptsCompletion = canApplyResult(for: id) && !Task.isCancelled
            task = nil
            transition(to: .idle)
            onCompletion(acceptsCompletion)
        }
        // Install the handle before publishing: a synchronous observer may Stop
        // in response to the running transition, before startup has yielded.
        transition(to: .running(id))
        return id
    }

    /// Invalidate effects immediately, but retain ownership and busy state until
    /// the operation returns. Repeated Stop/background/disappear calls are safe.
    @discardableResult
    public func cancel() -> Bool {
        guard case .running(let id) = state else { return false }
        transition(to: .cancelling(id))
        task?.cancel()
        return true
    }

    public func canApplyResult(for id: UUID) -> Bool {
        state == .running(id)
    }

    private func transition(to newState: State) {
        state = newState
        onStateChange?(newState)
    }
}
