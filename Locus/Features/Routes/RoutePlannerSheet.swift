import SwiftUI
import UIKit

struct RoutePlannerSheet: View {
    var onPlay: () -> Void
    var onImportGPX: () -> Void
    var onExportGPX: () -> Void
    var drawMode: Bool
    var hasDrawnPath: Bool
    var onToggleDrawing: () -> Void
    var onUseDrawn: () -> Void

    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("交通方式与速度") {
                    HStack(spacing: 6) {
                        ForEach(TravelMode.allCases) { mode in
                            let selected = session.travelMode == mode
                            Button {
                                session.travelMode = mode
                                session.speedMultiplier = 1.0
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: mode.icon)
                                        .font(.body.weight(.semibold))
                                    Text(mode.title)
                                        .font(.caption2.weight(.semibold))
                                }
                                .foregroundStyle(selected ? .black : .primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Capsule().fill(selected ? LocusTheme.accent : Color.primary.opacity(0.08)))
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        Label("速度", systemImage: "speedometer")
                        Spacer()
                        Text(String(format: "%.2fx · %.1f km/h", session.speedMultiplier, session.travelMode.baseSpeed * session.speedMultiplier * 3.6))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $session.speedMultiplier, in: 0.25...4.0, step: 0.25)
                    Text("选择交通方式会恢复该方式的默认速度，再使用滑块微调。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle(isOn: $session.routeLoopEnabled) {
                        Label("循环运行轨迹", systemImage: "repeat")
                    }
                }

                Section("地图手绘") {
                    Button {
                        onToggleDrawing()
                        dismiss()
                    } label: {
                        Label(
                            drawMode ? "结束地图手绘" : "开始地图手绘",
                            systemImage: drawMode ? "pencil.tip.crop.circle.badge.minus" : "pencil.tip.crop.circle"
                        )
                    }

                    Button {
                        onUseDrawn()
                    } label: {
                        Label("将手绘线设为当前轨迹", systemImage: "pencil.tip")
                    }
                    .disabled(!hasDrawnPath)
                }

                Section("运行与 GPX") {
                    Button(action: onPlay) {
                        Label("开始运行轨迹", systemImage: "play.fill")
                    }
                    Button(action: onImportGPX) {
                        Label("导入 GPX", systemImage: "square.and.arrow.down")
                    }
                    Button(action: onExportGPX) {
                        Label("导出 GPX", systemImage: "square.and.arrow.up")
                    }
                }

                Section("生成轨迹") {
                    Label("长按地图上的红色图钉，然后选择“生成轨迹”", systemImage: "hand.tap.fill")
                    Text("当前定位点始终作为起点，红图钉作为终点。速度设置同时作用于轨迹和摇杆。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("轨迹")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

}
