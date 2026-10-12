import SwiftUI
import HarbourCore

struct MedicationDraftReview: View {
    let medication: Medicine
    let times: [DoseTime]
    let frequency: MedicationFrequency?
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    private var schedule: MedicineSchedule {
        var value = store.care.schedules.first { $0.medicineID == medication.id } ?? MedicineSchedule(medicineID: medication.id)
        if frequency != nil || !times.isEmpty {
            value.times = times; value.frequency = frequency
            if times.isEmpty && value.refill == nil { value.notify = false }
        }
        return value
    }
    var body: some View {
        Group {
            if editing { MedicineEditor(initial: medication, suggestedTimes: times, suggestedFrequency: frequency) }
            else {
                Form {
                    Section {
                        Text(L10n.medicineName(medication)).font(.title3.weight(.semibold))
                        if !medication.instructions.isEmpty { Text(medication.instructions) }
                        if let frequency = schedule.frequency { LabeledContent("Frequency", value: L10n.frequency(frequency)) }
                        if !schedule.times.isEmpty { LabeledContent("Times", value: L10n.doseTimes(schedule.times)) }
                        LabeledContent("Active ingredients", value: medication.ingredients.isEmpty ? L10n.string("Unconfirmed") : L10n.ingredientNames(medication.ingredients))
                    }
                    Section { Button("Edit details", systemImage: "square.and.pencil") { editing = true } }
                }.scrollContentBackground(.hidden).background(Palette.canvas).foregroundStyle(Palette.ink)
                    .navigationTitle("Add medication").navigationBarTitleDisplayMode(.inline).drawerHeight(400)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                        ToolbarItem(placement: .confirmationAction) { Button("Save") {
                            if store.saveMedicine(medication, schedule: schedule) { dismiss() }
                        }.accessibilityIdentifier("approveMedication") }
                    }
            }
        }
    }
}
