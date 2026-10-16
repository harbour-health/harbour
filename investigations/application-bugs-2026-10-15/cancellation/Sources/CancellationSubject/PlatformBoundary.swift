import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Combine)
import Combine
typealias ObservableObject = Combine.ObservableObject
typealias Published<Value> = Combine.Published<Value>
#else
// Observation/UI publication is not exercised by the Linux state-value tests.
protocol ObservableObject: AnyObject {}
@propertyWrapper struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
extension ProcessInfo {
    enum ThermalState { case nominal, fair, serious, critical }
    var isLowPowerModeEnabled: Bool { false }
    var thermalState: ThermalState { .nominal }
}
#endif

#if canImport(FoundationNetworking)
typealias SystemSessionConfiguration = FoundationNetworking.URLSessionConfiguration
#else
typealias SystemSessionConfiguration = Foundation.URLSessionConfiguration
#endif

// Name resolution redirects only configuration construction. The session,
// download task, cancellation handler and delegate callbacks remain Foundation.
enum URLSessionConfiguration {
    static var ephemeral: SystemSessionConfiguration {
        let config = SystemSessionConfiguration.ephemeral
        config.protocolClasses = [HeldDownloadProtocol.self]
        return config
    }
}

enum DownloadBarrier {
    private static let lock = NSLock()
    private static var started = 0
    private static var stopped = 0
    private static var didStart: (@Sendable () -> Void)?
    static func reset(onStart: @escaping @Sendable () -> Void) {
        lock.lock(); started = 0; stopped = 0; didStart = onStart; lock.unlock()
    }
    static func start() {
        lock.lock(); started += 1; let callback = didStart; lock.unlock(); callback?()
    }
    static func stop() { lock.lock(); stopped += 1; lock.unlock() }
    static var counts: (starts: Int, stops: Int) {
        lock.lock(); defer { lock.unlock() }; return (started, stopped)
    }
}

private final class HeldDownloadProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        // Intentionally never returns HTTP bytes or a successful download.
        // Cancellation is the sole completion path; no network is used.
        DownloadBarrier.start()
    }
    override func stopLoading() { DownloadBarrier.stop() }
}
