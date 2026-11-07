import ActivityKit
import SwiftUI
import WidgetKit

@main struct HarbourActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HarbourActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: context.state.phase.symbol).font(.title2).foregroundStyle(accent(context))
                VStack(alignment: .leading, spacing: 5) {
                    Text(context.attributes.title).font(.headline)
                    Text(status(context)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                elapsed(context).font(.title3.monospacedDigit()).frame(maxWidth: 90, alignment: .trailing)
            }.padding(20).activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
                .widgetURL(context.attributes.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: context.state.phase.symbol).font(.title2).foregroundStyle(accent(context)) }
                DynamicIslandExpandedRegion(.trailing) { elapsed(context).monospacedDigit().frame(maxWidth: 80) }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack { VStack(alignment: .leading, spacing: 4) { Text(context.attributes.title).font(.headline); Text(status(context)).font(.subheadline).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.up.forward") }.padding(.top, 8)
                }
            } compactLeading: {
                Image(systemName: context.state.phase.symbol).foregroundStyle(accent(context))
            } compactTrailing: {
                if context.attributes.mode == .recording { elapsed(context).monospacedDigit().frame(width: 45) }
                else { Image(systemName: context.state.phase == .paused ? "pause.fill" : "waveform").foregroundStyle(accent(context)) }
            } minimal: {
                Image(systemName: context.state.phase.symbol).foregroundStyle(accent(context))
            }.widgetURL(context.attributes.url).keylineTint(accent(context))
        }
    }
    private func accent(_ context: ActivityViewContext<HarbourActivityAttributes>) -> Color { context.attributes.mode == .recording ? Color(red: 0.91, green: 0.40, blue: 0.29) : Color(red: 0.63, green: 0.71, blue: 1) }
    private func status(_ context: ActivityViewContext<HarbourActivityAttributes>) -> String {
        context.isStale ? (context.attributes.french ? "Ouvrir Harbour pour vérifier" : "Open Harbour to check") : context.state.phase.title(french: context.attributes.french)
    }
    @ViewBuilder private func elapsed(_ context: ActivityViewContext<HarbourActivityAttributes>) -> some View {
        if context.attributes.mode == .recording {
            if let start = context.state.timerStart, !context.isStale { Text(timerInterval: start...Date.distantFuture, countsDown: false).contentTransition(.numericText()) }
            else { Text(String(format: "%02d:%02d", Int(context.state.elapsed) / 60, Int(context.state.elapsed) % 60)) }
        }
    }
}
