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
                // ActivityKit requires one expanded region even when Locus intentionally
                // presents no expanded content. Keep the region visually empty.
                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }
            } compactLeading: {
                Image(systemName: "location.fill")
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.elapsed)
                    .font(.caption2.monospacedDigit().weight(.semibold))
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
                Text(state.elapsed)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.cyan)
            }

            HStack(spacing: 20) {
                metric(title: "已行驶", value: state.distance, systemImage: "figure.walk.motion")
                metric(title: "运行时间", value: state.elapsed, systemImage: "timer")
            }

            Label(locationText(state), systemImage: "mappin.and.ellipse")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(state.coordinate)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    private func metric(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
            }
        }
    }

    private func locationText(_ state: LocusActivityAttributes.ContentState) -> String {
        [state.city, state.country]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
