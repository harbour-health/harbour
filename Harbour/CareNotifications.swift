import Foundation
import UserNotifications
import HarbourCore

@MainActor protocol CareNotificationDelivery {
    func authorized() async -> Bool
    func pending() async -> [String]
    func delivered() async -> [(id: String, date: Date)]
    func add(_ plan: CareNotificationPlan) async throws
    func removePending(_ ids: [String])
    func removeDelivered(_ ids: [String])
}
@MainActor final class NativeCareNotificationDelivery: CareNotificationDelivery {
    private let center = UNUserNotificationCenter.current()
    func authorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
    func pending() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }
    func delivered() async -> [(id: String, date: Date)] { await center.deliveredNotifications().map { ($0.request.identifier, $0.date) } }
    func add(_ plan: CareNotificationPlan) async throws {
        let content = UNMutableNotificationContent(); content.title = "Harbour"; content.body = "You have a reminder. Open Harbour to view it."; content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: plan.components, repeats: plan.repeating)
        try await center.add(UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger))
    }
    func removePending(_ ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    func removeDelivered(_ ids: [String]) { center.removeDeliveredNotifications(withIdentifiers: ids) }
}

@MainActor final class CareNotifications: ObservableObject {
    @Published private(set) var status = "Notifications use a private message on your lock screen."
    private let delivery: any CareNotificationDelivery
    private let prefix: String
    private var generation = UUID()
    private var queued: (care: CareData, medicines: [Medicine], generation: UUID)?
    private var syncing = false
    init(delivery: (any CareNotificationDelivery)? = nil, prefix: String = "harbour-care-") {
        self.delivery = delivery ?? NativeCareNotificationDelivery(); self.prefix = prefix
    }
    func requestAccess() async {
        do { let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]); status = allowed ? "Notifications enabled" : "Notifications are off. Enable them in iPhone Settings." }
        catch { status = "Couldn’t enable notifications. " + error.localizedDescription }
    }
    func sync(care: CareData, medicines: [Medicine]) async {
        generation = UUID(); queued = (care, medicines, generation)
        guard !syncing else { return }
        syncing = true; defer { syncing = false }
        // One worker owns all center mutations. A superseded add must finish before
        // the next snapshot removes its requests; generation checks alone cannot do that.
        while let snapshot = queued {
            queued = nil
            await reconcile(care: snapshot.care, medicines: snapshot.medicines, current: snapshot.generation)
        }
    }
    private func reconcile(care: CareData, medicines: [Medicine], current: UUID) async {
        let allowed = await delivery.authorized()
        guard generation == current else { return }
        let pending = await delivery.pending()
        guard generation == current else { return }
        delivery.removePending(pending.filter { $0.hasPrefix(prefix) })
        guard allowed else {
            if care.reminders.contains(where: \.notify) || care.schedules.contains(where: \.notify) || care.doses.contains(where: { $0.status == .later }) { status = "Notifications are off. Enable them in iPhone Settings." }
            return
        }
        let plans = CareNotificationPlan.make(care: care, medicineIDs: Set(medicines.map(\.id))).map { plan in
            var plan = plan; plan.id = prefix + plan.id.dropFirst("harbour-care-".count); return plan
        }
        status = plans.count >= 60 ? "The next 60 notifications are scheduled." : "Notifications enabled"
        for plan in plans {
            guard generation == current else { return }
            do { try await delivery.add(plan) }
            catch { if generation == current { status = "Couldn’t schedule a notification. " + error.localizedDescription } }
        }
        let delivered = await delivery.delivered()
        guard generation == current else { return }
        let active = Set(plans.map(\.id))
        let calendar = Calendar.current
        let removed = delivered.filter { item in
            guard item.id.hasPrefix(prefix) else { return false }
            if !active.contains(item.id) { return true }
            return care.doses.contains { log in
                guard log.status != .later, calendar.isDate(log.scheduled, inSameDayAs: item.date) else { return false }
                return item.id == prefix + "dose-" + log.medicineID + "-" + String(calendar.component(.hour, from: log.scheduled)) + ":" + String(calendar.component(.minute, from: log.scheduled))
            }
        }
        delivery.removeDelivered(removed.map(\.id))
    }
}
