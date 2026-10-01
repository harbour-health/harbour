import SwiftUI
import LocalAuthentication
import Security
import CommonCrypto

private enum LockMode: String, Codable, Sendable { case off, biometrics, pin }
private struct LockCredential: Codable, Sendable {
    var mode: LockMode
    var salt: Data?
    var verifier: Data?
    var pinLength: Int?
    var failures = 0
    var retryAfter: Date?
}
private enum LockFailure: LocalizedError {
    case storage, invalidPIN, mismatch, authentication
    var errorDescription: String? {
        switch self {
        case .storage: "The app lock could not access its saved settings. Try again."
        case .invalidPIN: "Use four digits for your PIN."
        case .mismatch: "Those PINs don’t match."
        case .authentication: "Confirm your current app lock before changing it."
        }
    }
}
private enum PINVerifier {
    static func valid(_ pin: String, length: Int = 4) -> Bool { [4, 6].contains(length) && pin.utf8.count == length && pin.utf8.allSatisfy { (48...57).contains($0) } }
    static func derive(_ pin: String, salt: Data, length: Int = 4) throws -> Data {
        guard valid(pin, length: length), salt.count == 32 else { throw LockFailure.invalidPIN }
        let password = Array(pin.utf8)
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = password.withUnsafeBytes { p in salt.withUnsafeBytes { s in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.baseAddress!.assumingMemoryBound(to: Int8.self), password.count, s.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 200_000, &bytes, bytes.count)
        } }
        guard result == kCCSuccess else { throw LockFailure.storage }
        return Data(bytes)
    }
    static func create(_ pin: String) throws -> LockCredential {
        var salt = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt) == errSecSuccess else { throw LockFailure.storage }
        return LockCredential(mode: .pin, salt: Data(salt), verifier: try derive(pin, salt: Data(salt)), pinLength: 4)
    }
    static func matches(_ pin: String, credential: LockCredential) throws -> Bool {
        guard let salt = credential.salt, let stored = credential.verifier, stored.count == 32 else { throw LockFailure.storage }
        let proposed = try derive(pin, salt: salt, length: credential.pinLength ?? 6)
        return zip(proposed, stored).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
private enum LockKeychain {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.matteopolak.harbour.app-lock", kSecAttrAccount as String: "configuration"]
    static func read() throws -> LockCredential? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw LockFailure.storage }
        let credential = try JSONDecoder().decode(LockCredential.self, from: data)
        if credential.mode == .pin {
            guard credential.salt?.count == 32, credential.verifier?.count == 32, credential.failures >= 0, [4, 6].contains(credential.pinLength ?? 6) else { throw LockFailure.storage }
        }
        return credential
    }
    static func write(_ credential: LockCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let changes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let update = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if update == errSecItemNotFound {
            var request = query; changes.forEach { request[$0.key] = $0.value }
            guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else { throw LockFailure.storage }
        } else if update != errSecSuccess { throw LockFailure.storage }
    }
}

@MainActor final class AppLock: ObservableObject {
    @Published private(set) var locked = true
    @Published private(set) var working = false
    @Published private(set) var configured = false
    @Published var error: String?
    private var credential: LockCredential?
    private var context: LAContext?
    private var generation = UUID()
    private var authorizationExpires = Date.distantPast
    private var canChange: Bool { !enabled || authorizationExpires > .now }
    var usesPIN: Bool { credential?.mode == .pin }
    var pinLength: Int { usesPIN ? credential?.pinLength ?? 6 : 4 }
    var presentingAuthentication: Bool { context != nil && working }
    var enabled: Bool { credential?.mode != .off && credential != nil }
    var modeName: String { usesPIN ? "PIN" : enabled ? biometricName : "Off" }
    var retryAfter: Date? { credential?.retryAfter }
    var biometricName: String {
        let context = LAContext(); _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .touchID ? "Touch ID" : "Face ID"
    }
    init() { reload() }
    func reload() {
        do { credential = try LockKeychain.read(); configured = true; locked = enabled; error = nil }
        catch { configured = false; locked = true; self.error = error.localizedDescription }
    }
    func lock() { authorizationExpires = .distantPast; generation = UUID(); context?.invalidate(); context = nil; working = false; if enabled || !configured { locked = true } }
    private func persist(_ next: LockCredential) throws { try LockKeychain.write(next); credential = next; configured = true; error = nil }
    func enablePIN(_ pin: String, confirmation: String) async -> Bool {
        guard canChange, !working else { error = LockFailure.authentication.localizedDescription; return false }
        guard pin == confirmation else { error = LockFailure.mismatch.localizedDescription; return false }
        working = true; let current = generation
        defer { if generation == current { working = false } }
        do {
            let next = try await Task.detached(priority: .userInitiated) { try PINVerifier.create(pin) }.value
            guard generation == current else { return false }
            guard canChange else { throw LockFailure.authentication }; try persist(next); authorizationExpires = .distantPast; locked = false; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func verifyPIN(_ pin: String, unlock: Bool = false) async -> Bool {
        guard !working, var saved = credential, saved.mode == .pin else { return false }
        guard saved.retryAfter.map({ $0 <= .now }) ?? true else { error = "Please wait before trying again."; return false }
        guard PINVerifier.valid(pin, length: saved.pinLength ?? 6) else { error = LockFailure.invalidPIN.localizedDescription; return false }
        working = true; let current = generation
        defer { if generation == current { working = false } }
        do {
            let snapshot = saved
            let correct = try await Task.detached(priority: .userInitiated) { try PINVerifier.matches(pin, credential: snapshot) }.value
            guard generation == current else { return false }
            if correct { saved.failures = 0; saved.retryAfter = nil }
            else {
                saved.failures += 1
                if saved.failures >= 5 { saved.retryAfter = .now.addingTimeInterval(min(3600, 30 * pow(2, Double(min(saved.failures - 5, 7))))) }
            }
            try persist(saved)
            if correct { if unlock { locked = false } else { authorizationExpires = .now.addingTimeInterval(180) }; return true }
            error = saved.retryAfter == nil ? "Incorrect PIN. Try again." : "Too many attempts. Please wait before trying again."
        } catch { self.error = error.localizedDescription }
        return false
    }
    func authenticateBiometrics(allowChanges: Bool = false) async -> Bool {
        guard !working else { return false }
        let attempt = generation, next = LAContext()
        next.localizedCancelTitle = "Cancel"
        var failure: NSError?
        guard next.canEvaluatePolicy(.deviceOwnerAuthentication, error: &failure) else { error = failure?.localizedDescription ?? "Set up a device passcode to use Face ID."; return false }
        context = next; working = true
        defer { if generation == attempt { context = nil; working = false } }
        do {
            let success = try await next.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your Harbour health records.")
            guard generation == attempt else { return false }
            error = nil; if success && allowChanges { authorizationExpires = .now.addingTimeInterval(180) }; return success
        } catch { if generation == attempt { self.error = error.localizedDescription }; return false }
    }
    func unlockBiometrics() async { if await authenticateBiometrics() { locked = false } }
    func enableBiometrics() async -> Bool {
        guard canChange else { error = LockFailure.authentication.localizedDescription; return false }
        let availability = LAContext(); var failure: NSError?
        guard availability.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &failure) else { error = failure?.localizedDescription ?? "Set up Face ID in your phone settings."; return false }
        guard await authenticateBiometrics() else { return false }
        guard canChange else { error = LockFailure.authentication.localizedDescription; return false }
        do { try persist(LockCredential(mode: .biometrics)); authorizationExpires = .distantPast; locked = false; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func disableAfterVerification() -> Bool {
        guard canChange else { error = LockFailure.authentication.localizedDescription; return false }
        do { try persist(LockCredential(mode: .off)); authorizationExpires = .distantPast; locked = false; return true }
        catch { self.error = error.localizedDescription; return false }
    }
}

private struct PINEntry: View {
    var title: String
    var length = 4
    @Binding var code: String
    var disabled: Bool
    var error: String?
    var retryAfter: Date?
    var restart: (() -> Void)?
    var complete: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 650
            VStack(spacing: compact ? 12 : 20) {
                Spacer(minLength: 8)
                if !compact { HarbourMark(size: 36).foregroundStyle(Palette.blue) }
                Text(title).font(.system(compact ? .title2 : .largeTitle, design: .rounded, weight: .bold)).multilineTextAlignment(.center)
                HStack(spacing: length == 4 ? 12 : 6) {
                    ForEach(0..<length, id: \.self) { index in
                        ZStack {
                            RoundedRectangle(cornerRadius: 14).fill(Palette.surface)
                            if index < code.count { Circle().fill(Palette.ink).frame(width: 12, height: 12) }
                        }.frame(width: length == 4 ? (compact ? 48 : 54) : (compact ? 38 : 44), height: compact ? 48 : 54)
                    }
                }.accessibilityElement(children: .ignore).accessibilityLabel("PIN")
                    .accessibilityValue("\(code.count) of \(length) digits entered").accessibilityIdentifier("pinSlots")
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: code.count)
                VStack(spacing: 8) {
                    if let error { Text(error).font(.subheadline).foregroundStyle(Palette.coral).multilineTextAlignment(.center) }
                    if let retryAfter {
                        TimelineView(.periodic(from: .now, by: 1)) { tick in
                            if retryAfter > tick.date { Text("Try again in \(Int(ceil(retryAfter.timeIntervalSince(tick.date)))) seconds").font(.subheadline).foregroundStyle(Palette.muted) }
                        }
                    }
                }.frame(minHeight: 24)
                Spacer(minLength: 8)
                TimelineView(.periodic(from: .now, by: 1)) { tick in
                    keypad(height: compact ? 48 : 64).disabled(disabled || (retryAfter.map { $0 > tick.date } ?? false))
                }
                if let restart { Button("Start over", action: restart).frame(minHeight: 44) }
                Spacer(minLength: 8)
            }.padding(compact ? 16 : 24).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(Palette.canvas).foregroundStyle(Palette.ink)
            .onChange(of: code.count) { if code.count == length && !disabled { complete(code) } }
    }
    private func keypad(height: CGFloat) -> some View {
        VStack(spacing: 8) {
            ForEach(0..<3) { row in HStack(spacing: 18) { ForEach(1..<4) { column in digit(row * 3 + column, height: height) } } }
            HStack(spacing: 18) {
                Color.clear.frame(maxWidth: .infinity).frame(height: height).accessibilityHidden(true)
                digit(0, height: height)
                Button { if !code.isEmpty { code.removeLast() } } label: { Image(systemName: "delete.left").font(.title2).frame(maxWidth: .infinity).frame(height: height).contentShape(Rectangle()) }
                    .accessibilityLabel("Delete last digit").accessibilityIdentifier("pin-delete").disabled(code.isEmpty)
            }
        }.frame(maxWidth: 320).buttonStyle(PressFeedback())
    }
    private func digit(_ digit: Int, height: CGFloat) -> some View {
        Button { if code.count < length { code += String(digit) } } label: { Text(String(digit)).font(.system(size: 32, weight: .medium, design: .rounded)).frame(maxWidth: .infinity).frame(height: height).contentShape(Rectangle()) }
            .accessibilityLabel(String(digit)).accessibilityIdentifier("pin-key-\(digit)")
    }
}

struct LockScreen: View {
    @EnvironmentObject var lock: AppLock
    @State private var pin = ""
    @State private var submitting = false
    var body: some View {
        if lock.configured && lock.usesPIN {
            PINEntry(title: "Enter PIN", length: lock.pinLength, code: $pin, disabled: lock.working || submitting, error: lock.error, retryAfter: lock.retryAfter) { entered in
                submitting = true
                Task { _ = await lock.verifyPIN(entered, unlock: true); pin = ""; submitting = false }
            }
        } else {
            VStack(spacing: 28) {
                Spacer(); HarbourMark(size: 60).foregroundStyle(Palette.blue)
                Text("Harbour is locked").font(.system(.largeTitle, design: .rounded, weight: .bold))
                if !lock.configured { Button("Try again") { lock.reload() } }
                else { Button { Task { await lock.unlockBiometrics() } } label: { Label("Unlock with \(lock.biometricName)", systemImage: "faceid").font(.title3.weight(.semibold)) }.buttonStyle(.borderedProminent).disabled(lock.working) }
                if lock.working { ProgressView() }
                if let error = lock.error { Text(error).foregroundStyle(Palette.coral).multilineTextAlignment(.center) }
                Spacer(); Spacer()
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas).foregroundStyle(Palette.ink)
        }
    }
}

struct AppLockSettings: View {
    @EnvironmentObject var lock: AppLock
    @State private var request: LockRequest?
    @State private var verifying = false
    @State private var settingPIN = false
    private enum LockRequest { case off, biometrics, pin }
    var body: some View {
        List {
            Section {
                option("Off", symbol: "lock.open", selected: !lock.enabled) { begin(.off) }
                option(lock.biometricName, symbol: "faceid", selected: lock.enabled && !lock.usesPIN) { begin(.biometrics) }
                option("PIN", symbol: "number", selected: lock.usesPIN) { begin(.pin) }
            } footer: { Text("Lock Harbour when you leave the app. Face ID can fall back to your phone’s passcode.") }
            if lock.enabled { Button("Lock now") { lock.lock() }.accessibilityIdentifier("lockNow") }
            if lock.working { ProgressView() }
            if let error = lock.error { Text(error).foregroundStyle(Palette.coral).accessibilityIdentifier("lockSettingsError") }
        }.scrollContentBackground(.hidden).background(Palette.canvas).navigationTitle("App lock").navigationBarTitleDisplayMode(.inline)
            .drawerHeight(lock.enabled ? 450 : 390)
            .sheet(isPresented: $verifying) { NavigationStack { PINChallenge { verifying = false; Task { await apply() } } }.floatingDrawer(height: 560) }
            .sheet(isPresented: $settingPIN) { NavigationStack { PINSetup() }.floatingDrawer(height: 560) }
    }
    private func option(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack(spacing: 16) { Image(systemName: symbol).font(.title2).frame(width: 30); Text(title).font(.title3.weight(.medium)); Spacer(); if selected { Image(systemName: "checkmark") } }.foregroundStyle(Palette.ink).padding(.vertical, 12).contentShape(Rectangle()) }
            .disabled(lock.working).listRowBackground(Palette.surface).accessibilityIdentifier("lock-option-" + (title == "PIN" ? "pin" : title == "Off" ? "off" : "biometrics")).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func begin(_ change: LockRequest) {
        guard !(change == .off && !lock.enabled) else { return }
        request = change; lock.error = nil
        if lock.usesPIN { verifying = true }
        else { Task { if !lock.enabled { await apply() } else if await lock.authenticateBiometrics(allowChanges: true) { await apply() } } }
    }
    private func apply() async {
        switch request { case .off: _ = lock.disableAfterVerification(); case .biometrics: _ = await lock.enableBiometrics(); case .pin: settingPIN = true; case nil: break }
        request = nil
    }
}
private struct PINChallenge: View {
    @EnvironmentObject var lock: AppLock
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var submitting = false
    var verified: () -> Void
    var body: some View {
        PINEntry(title: "Current PIN", length: lock.pinLength, code: $pin, disabled: lock.working || submitting, error: lock.error, retryAfter: lock.retryAfter) { entered in
            submitting = true
            Task { if await lock.verifyPIN(entered) { verified() }; pin = ""; submitting = false }
        }.navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}
private struct PINSetup: View {
    @EnvironmentObject var lock: AppLock
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var first = ""
    @State private var submitting = false
    private var confirming: Bool { !first.isEmpty }
    var body: some View {
        PINEntry(title: confirming ? "Confirm PIN" : "Choose a PIN", code: $pin, disabled: lock.working || submitting, error: lock.error, restart: confirming ? { first = ""; pin = ""; lock.error = nil } : nil) { entered in
            if !confirming { first = entered; pin = ""; lock.error = nil }
            else {
                submitting = true
                Task {
                    if await lock.enablePIN(first, confirmation: entered) { first = ""; dismiss() }
                    else { first = "" }
                    pin = ""; submitting = false
                }
            }
        }.navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pin = ""; first = ""; dismiss() } } }
    }
}

struct PrivacyCurtain: UIViewRepresentable {
    var covered: Bool
    func makeUIView(context: Context) -> CurtainHost { CurtainHost() }
    func updateUIView(_ view: CurtainHost, context: Context) { view.covered = covered }
}
final class CurtainHost: UIView {
    var covered = false { didSet { refresh() } }
    private var curtain: UIWindow?
    override func didMoveToWindow() { super.didMoveToWindow(); refresh() }
    private func refresh() {
        guard covered, let scene = window?.windowScene else { curtain?.isHidden = true; curtain = nil; return }
        guard curtain == nil else { return }
        let next = UIWindow(windowScene: scene)
        next.windowLevel = .alert + 1
        next.rootViewController = UIHostingController(rootView: ZStack { Palette.canvas.ignoresSafeArea(); HarbourMark(size: 54).foregroundStyle(Palette.blue) })
        next.isHidden = false; curtain = next
    }
}
