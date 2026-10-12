import SwiftUI
import HarbourCore

struct AppointmentRow: View {
    let appointment: Appointment
    var showsDisclosure = true
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            FeatureIcon(symbol: "calendar", colour: Palette.blue)
            VStack(alignment: .leading, spacing: 5) {
                Text(appointment.title).font(.body.weight(.medium)).foregroundStyle(Palette.ink)
                Text(L10n.date(appointment.date, time: appointment.includesTime)).foregroundStyle(Palette.muted)
                if !appointment.location.isEmpty { Text(appointment.location).foregroundStyle(Palette.muted) }
            }
            Spacer(minLength: 8)
            if showsDisclosure { Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted) }
        }.padding(.vertical, 12).accessibilityIdentifier("appointment-row-\(appointment.id)")
    }
}

struct AppointmentEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var appointment: Appointment
    @State private var dateConfirmed: Bool
    @FocusState private var editing: Bool
    init(initial: Appointment, saved: Bool = false) {
        _appointment = State(initialValue: initial); _dateConfirmed = State(initialValue: saved)
    }
    var body: some View {
        Form {
            Section {
                TextField("Appointment title", text: $appointment.title).focused($editing).accessibilityIdentifier("appointmentTitle")
                TextField("Location", text: $appointment.location).focused($editing).accessibilityIdentifier("appointmentLocation")
                DatePicker("Date", selection: $appointment.date, displayedComponents: appointment.includesTime ? [.date, .hourAndMinute] : [.date])
                    .accessibilityIdentifier("appointmentDate")
                Toggle("Include time", isOn: $appointment.includesTime).accessibilityIdentifier("appointmentIncludesTime")
                Toggle("Date confirmed", isOn: $dateConfirmed).accessibilityIdentifier("confirmAppointmentDate")
            }
            Section("Notes") { TextField("Notes", text: $appointment.notes, axis: .vertical).lineLimit(3...8).focused($editing).accessibilityIdentifier("appointmentNotes") }
            if let quote = appointment.quote { Section("From your recording") { Text(quote).foregroundStyle(Palette.muted) } }
        }.scrollContentBackground(.hidden).background(Palette.canvas).foregroundStyle(Palette.ink)
            .navigationTitle("Appointment").navigationBarTitleDisplayMode(.inline).drawerHeight(620)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editing = false } }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if store.saveAppointment(appointment) { dismiss() }
                }.disabled(!dateConfirmed || appointment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveAppointment") }
            }
    }
}
