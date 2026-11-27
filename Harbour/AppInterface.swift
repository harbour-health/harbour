import SwiftUI

enum AppInterface: String, CaseIterable, Identifiable {
    case simple, caregiver
    var id: String {
        rawValue
    }

    var title: String {
        L10n.string(self == .simple ? "Simple" : "Caregiver")
    }

    var detail: String {
        L10n.string(self == .simple ? "Chat and voice" : "Records and tools")
    }
}

struct InterfaceSettingsView: View {
    @AppStorage("interfaceMode") private var choice = AppInterface.simple.rawValue
    var body: some View {
        List {
            ForEach(AppInterface.allCases) { option in
                Button { choice = option.rawValue } label: {
                    HStack(spacing: 18) {
                        Image(systemName: option == .simple ? "bubble.left.and.bubble.right" : "person.2")
                            .font(.title2).foregroundStyle(Palette.blue).frame(width: 32)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(option.title).font(.title3.weight(.semibold))
                            Text(option.detail).font(.body).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        if choice == option.rawValue {
                            Image(systemName: "checkmark").font(.title3.weight(.semibold))
                        }
                    }.foregroundStyle(Palette.ink).frame(minHeight: 64).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("interface-" + option.rawValue)
                    .accessibilityAddTraits(choice == option.rawValue ? .isSelected : [])
            }
        }.scrollContentBackground(.hidden).background(Palette.canvas)
            .navigationTitle("Interface").navigationBarTitleDisplayMode(.inline).drawerHeight(350)
    }
}
