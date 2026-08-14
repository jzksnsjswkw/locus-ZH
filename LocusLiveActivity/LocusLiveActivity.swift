import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

@main
struct LocusLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        LocusLiveActivityWidget()
    }
}

struct LocusLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LocusActivityAttributes.self) { context in
            statusCard(context.state)
                .activityBackgroundTint(.black.opacity(0.86))
                .activitySystemActionForegroundColor(.cyan)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.status, systemImage: "location.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.coordinate)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(.cyan)
                            Text(locationText(context.state))
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }

                        Link(destination: URL(string: "locus://stop")!) {
                            Label("停止模拟定位", systemImage: "stop.fill")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(Capsule().fill(.red))
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "location.fill")
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.city)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            } minimal: {
                Image(systemName: "location.fill")
                    .foregroundStyle(.green)
            }
            .widgetURL(URL(string: "locus://"))
            .keylineTint(.cyan)
        }
    }

    private func statusCard(_ state: LocusActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text(state.status)
                    .font(.headline)
                Spacer(minLength: 0)
                Text(state.coordinate)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Label(locationText(state), systemImage: "mappin.and.ellipse")
                .font(.subheadline)
                .foregroundStyle(.cyan)
        }
        .padding()
    }

    private func locationText(_ state: LocusActivityAttributes.ContentState) -> String {
        [state.city, state.country]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
