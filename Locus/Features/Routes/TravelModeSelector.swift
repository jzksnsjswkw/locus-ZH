import SwiftUI
import UIKit

struct TravelModeSelector: View {
    @EnvironmentObject private var session: SpoofSession

    var compact = false

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            ForEach(TravelMode.allCases) { mode in
                Button {
                    session.selectTravelMode(mode)
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: mode.icon)
                            .font(.subheadline.weight(.semibold))
                        Text(mode.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(session.travelMode == mode ? .black : .primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 40 : 44)
                    .locusGlass(
                        .interactive,
                        tint: session.travelMode == mode ? LocusTheme.accent : nil,
                        in: Capsule()
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("交通方式：\(mode.title)")
                .accessibilityValue(session.travelMode == mode ? "已选择" : "未选择")
            }
        }
    }
}
