import SwiftUI

struct SimpleHomeView: View {
    @EnvironmentObject private var recorder: VisitRecorder
    @Environment(\.dynamicTypeSize) private var textSize
    @Binding var sheet: AppSheet?
    let message: () -> Void
    let talk: () -> Void
    let record: () -> Void
    @State private var guide = false
    @ScaledMetric(relativeTo: .body) private var minimumHomeHeight = 620
    var body: some View {
        GeometryReader { geometry in
            if textSize.isAccessibilitySize || geometry.size.height < minimumHomeHeight {
                ScrollView { content.padding(.bottom, 24) }
            } else {
                content
            }
        }
        .padding(.horizontal, 24).frame(maxWidth: AppLayout.contentWidth).frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
        .background(Palette.canvas).foregroundStyle(Palette.ink)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton(sheet: $sheet) } }
        .sheet(isPresented: $guide) {
            NavigationStack { SimpleGuideView { guide = false
                message() } }.floatingDrawer(height: 530)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                HarbourMark(size: 32).foregroundStyle(Palette.blue)
                Text("Harbour").font(.system(.largeTitle, design: .rounded, weight: .bold))
            }.padding(.top, 12).padding(.bottom, 8)
            Button(action: talk) {
                ZStack(alignment: .trailing) {
                    HStack(spacing: 18) {
                        Image(systemName: "waveform").font(.system(size: 32, weight: .medium))
                        Text("Talk").font(.system(.title, design: .rounded, weight: .semibold))
                        Spacer(minLength: textSize.isAccessibilitySize ? 0 : 110)
                    }.padding(26)
                    if !textSize.isAccessibilitySize {
                        HarbourIllustration(kind: .conversation).frame(width: 160, height: 140).offset(x: 38, y: 28)
                    }
                }.frame(maxWidth: .infinity, minHeight: 146).background(
                    Palette.blueWash,
                    in: RoundedRectangle(cornerRadius: 30)
                )
                .clipShape(RoundedRectangle(cornerRadius: 30))
            }.buttonStyle(PressFeedback()).disabled(recorder.active).accessibilityIdentifier("simpleTalk")
                .presentationTarget("home.talk")
            action("Message", symbol: "bubble.left.and.text.bubble.right", id: "simpleMessage", action: message)
                .presentationTarget("home.message")
            action(
                recorder.active ? "Resume visit" : "Record a visit",
                symbol: recorder.active ? "waveform" : "mic",
                id: "simpleRecordVisit",
                action: record
            )
            if
                recorder
                    .active {
                Label("Recording in progress", systemImage: "record.circle.fill").font(.body)
                    .foregroundStyle(Palette.coral) }
            Button { guide = true } label: {
                Label("How to use Harbour", systemImage: "questionmark.circle").font(.title3.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 60).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("simpleGuide")
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 16)
            .presentationTarget("home.overview")
    }

    private func action(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: symbol).font(.title2).foregroundStyle(Palette.blue).frame(width: 34)
                Text(L10n.string(title)).font(.title2.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right").font(.body.weight(.semibold)).foregroundStyle(Palette.muted)
            }.padding(.horizontal, 22).frame(minHeight: 84).background(
                Palette.surface,
                in: RoundedRectangle(cornerRadius: 26)
            )
        }.buttonStyle(PressFeedback()).accessibilityIdentifier(id)
    }
}

struct SimpleGuideView: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.dismiss) private var dismiss
    let tryMessage: () -> Void
    @State private var page = 0
    private let titles = ["Talk naturally", "Type a message", "Review before saving"]
    private let details = [
        "Tap Talk and say what you need.",
        "Ask about a reading, a medicine, or how you feel.",
        "Check the details when Harbour offers to update a record."
    ]
    var body: some View {
        VStack(spacing: 20) {
            TabView(selection: $page) {
                ForEach(titles.indices, id: \.self) { index in
                    ScrollView {
                        VStack(spacing: 20) {
                            if !textSize.isAccessibilitySize {
                                HarbourIllustration(kind: index == 2 ? .medicines : .conversation).frame(height: 160)
                            }
                            Text(L10n.string(titles[index])).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            Text(L10n.string(details[index])).font(.title3).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }.padding(.horizontal, 28).padding(.vertical, 16).frame(maxWidth: .infinity)
                    }.scrollBounceBehavior(.basedOnSize).tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode: .always)).indexViewStyle(.page(backgroundDisplayMode: .always))
            Button("Try a message", action: tryMessage).buttonStyle(ActionButtonStyle()).padding(.horizontal, 24)
        }.padding(.bottom, 20).background(Palette.canvas).navigationTitle("How to use Harbour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
