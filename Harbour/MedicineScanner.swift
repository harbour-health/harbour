import SwiftUI
import PhotosUI
import Vision
import ImageIO
import HarbourCore

@MainActor final class MedicineScanner: ObservableObject {
    @Published var busy = false
    @Published var text = ""
    @Published var error: String?
    func recognize(_ data: Data) async {
        busy = true; error = nil; text = ""; defer { busy = false }
        do {
            text = try await Task.detached(priority: .userInitiated) {
                let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = true; request.recognitionLanguages = ["en-CA", "fr-CA"]
                let handler = VNImageRequestHandler(data: data, options: [:]); try handler.perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }.value
            if text.isEmpty { error = "No text found. Try a closer, sharper photo of the label." }
        } catch { self.error = "Couldn’t read this photo. " + error.localizedDescription }
    }
}
struct MedicineScanButtons: View {
    @ObservedObject var scanner: MedicineScanner
    @State private var photo: PhotosPickerItem?
    @State private var camera = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { camera = true } label: { Label("Camera", systemImage: "camera").frame(maxWidth: .infinity, minHeight: AppLayout.controlSize, alignment: .leading).contentShape(Rectangle()) }.accessibilityLabel("Scan medicine label")
            }
            PhotosPicker(selection: $photo, matching: .images) { Label("Label photo", systemImage: "photo").frame(maxWidth: .infinity, minHeight: AppLayout.controlSize, alignment: .leading).contentShape(Rectangle()) }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--qa-label-fixture") {
                Button {
                    let image = UIGraphicsImageRenderer(size: CGSize(width: 1100, height: 700)).image { context in
                        UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1100, height: 700))
                        ("METFORMIN\n500 mg\nTake one tablet with food" as NSString).draw(in: CGRect(x: 70, y: 90, width: 970, height: 520), withAttributes: [.font: UIFont.systemFont(ofSize: 58), .foregroundColor: UIColor.black])
                    }
                    if let data = image.pngData() { Task { await scanner.recognize(data) } }
                } label: { Text("Read test label").frame(maxWidth: .infinity, minHeight: AppLayout.controlSize, alignment: .leading).contentShape(Rectangle()) }.accessibilityIdentifier("qaReadLabel")
            }
            #endif
        }.buttonStyle(.borderless).disabled(scanner.busy)
            .onChange(of: photo) { Task { do { if let data = try await photo?.loadTransferable(type: Data.self) { await scanner.recognize(data) } } catch { scanner.error = "Couldn’t open the photo." }; photo = nil } }
            .fullScreenCover(isPresented: $camera) { LabelCamera { data in camera = false; if let data { Task { await scanner.recognize(data) } } }.ignoresSafeArea() }
    }
}
private struct LabelCamera: UIViewControllerRepresentable {
    var finished: (Data?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController(); controller.sourceType = .camera; controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let finished: (Data?) -> Void
        init(finished: @escaping (Data?) -> Void) { self.finished = finished }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { finished(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { finished((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.9)) }
    }
}
struct ScheduleFields: View {
    @Binding var times: [DoseTime]
    @Binding var notify: Bool
    @Binding var refillEnabled: Bool
    @Binding var refill: Date
    var body: some View {
        Section("Schedule") {
            ForEach(times.indices, id: \.self) { index in
                HStack {
                    DatePicker("Time \(index + 1)", selection: Binding(get: { Calendar.current.date(bySettingHour: times[index].hour, minute: times[index].minute, second: 0, of: .now) ?? .now }, set: { let p = Calendar.current.dateComponents([.hour, .minute], from: $0); times[index] = DoseTime(hour: p.hour ?? 0, minute: p.minute ?? 0) }), displayedComponents: .hourAndMinute).accessibilityIdentifier("doseTime-\(index)")
                    Button { times.remove(at: index) } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }.accessibilityLabel("Remove time \(index + 1)")
                }
            }.buttonStyle(.borderless)
            Button {
                #if DEBUG
                if times.isEmpty && ProcessInfo.processInfo.arguments.contains("--qa-label-fixture") {
                    let p = Calendar.current.dateComponents([.hour, .minute], from: max(Calendar.current.startOfDay(for: .now), Date.now.addingTimeInterval(-600))); times.append(DoseTime(hour: p.hour!, minute: p.minute!))
                } else { times.append(DoseTime(hour: times.isEmpty ? 8 : min(23, (times.last?.hour ?? 8) + 4), minute: 0)) }
                #else
                times.append(DoseTime(hour: times.isEmpty ? 8 : min(23, (times.last?.hour ?? 8) + 4), minute: 0))
                #endif
            } label: { Label("Add time", systemImage: "plus") }.disabled(times.count >= 8).accessibilityIdentifier("addDoseTime")
            Toggle("Refill reminder", isOn: $refillEnabled)
            if refillEnabled { DatePicker("Refill", selection: $refill, displayedComponents: [.date, .hourAndMinute]) }
            if !times.isEmpty || refillEnabled { Toggle("Notify me", isOn: $notify) }
        }
    }
}
