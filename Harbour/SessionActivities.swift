import ActivityKit
import UIKit

/// Serializes system updates so a late start cannot outlive stop/cancellation.
@MainActor final class SessionActivities {
    static let shared = SessionActivities()
    private struct Desired {
        var attributes: HarbourActivityAttributes
        var state: HarbourActivityAttributes.ContentState
    }
    private var desired: [HarbourActivityAttributes.Mode: Desired] = [:]
    private var known: [HarbourActivityAttributes.Mode: Activity<HarbourActivityAttributes>] = [:]
    private var dismissed = Set<UUID>()
    private var queue: Task<Void, Never>?
    private init() {
        let orphans = Activity<HarbourActivityAttributes>.activities
        queue = Task { for activity in orphans { await activity.end(nil, dismissalPolicy: .immediate) } }
    }
    func update(_ mode: HarbourActivityAttributes.Mode, phase: HarbourActivityAttributes.Phase, elapsed: TimeInterval = 0) {
        let attributes = desired[mode]?.attributes ?? HarbourActivityAttributes(sessionID: UUID(), mode: mode, french: L10n.isFrench)
        desired[mode] = Desired(attributes: attributes, state: .init(phase: phase, elapsed: max(0, elapsed), timerStart: phase == .recording ? .now.addingTimeInterval(-max(0, elapsed)) : nil))
        enqueue(mode)
    }
    func end(_ mode: HarbourActivityAttributes.Mode) { desired[mode] = nil; enqueue(mode) }
    func refreshPreferences() { enqueue(.recording); enqueue(.voice) }
    private func enqueue(_ mode: HarbourActivityAttributes.Mode) {
        let previous = queue
        queue = Task { await previous?.value; await self.apply(mode) }
    }
    private func apply(_ mode: HarbourActivityAttributes.Mode) async {
        let enabled = UserDefaults.standard.object(forKey: "liveActivitiesEnabled") as? Bool ?? true
        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled, let target = desired[mode] else {
            for activity in Activity<HarbourActivityAttributes>.activities where activity.attributes.mode == mode { await activity.end(nil, dismissalPolicy: .immediate) }
            known[mode] = nil
            return
        }
        if let activity = known[mode], activity.activityState == .dismissed { dismissed.insert(activity.attributes.sessionID) }
        guard !dismissed.contains(target.attributes.sessionID) else { return }
        let content = ActivityContent(state: target.state, staleDate: .now.addingTimeInterval(mode == .recording ? 180 : 90))
        if let activity = known[mode], activity.activityState == .active || activity.activityState == .stale {
            await activity.update(content)
        } else if UIApplication.shared.applicationState == .active {
            do { known[mode] = try Activity.request(attributes: target.attributes, content: content, pushType: nil) }
            catch { /* Optional system UI must never prevent recording or conversation. */ }
        }
    }
}
