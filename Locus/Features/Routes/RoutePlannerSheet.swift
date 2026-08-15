import SwiftUI

struct RoutePlannerSheet: View {
    var onPlay: () -> Void
    var onImportGPX: () -> Void
    var onExportGPX: () -> Void
    var onBuildRouteToTarget: () -> Void
    var drawMode: Bool
    var onToggleDrawing: () -> Void

    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("速度与循环") {
                    TravelModeSelector()
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    HStack {
                        Label("速度", systemImage: "speedometer")
                        Spacer()
                        Text(String(format: "%.2fx · %.1f km/h", session.speedMultiplier, session.travelMode.baseSpeed * session.speedMultiplier * 3.6))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $session.speedMultiplier, in: 0.25...4.0, step: 0.25)
                    Toggle(isOn: $session.routeLoopEnabled) {
                        Label("循环运行轨迹", systemImage: "repeat")
                    }
                    Stepper(value: $session.routeLoopCount, in: max(2, session.routeLap)...99) {
                        Label("共运行 \(session.routeLoopCount) 圈", systemImage: "number")
                    }
                    .disabled(!session.routeLoopEnabled)
                }

                Section("地图手绘") {
                    Button {
                        onToggleDrawing()
                        dismiss()
                    } label: {
                        Label(
                            drawMode ? "返回地图继续手绘" : "开始地图手绘",
                            systemImage: "pencil.tip.crop.circle"
                        )
                    }
                    Text("开始后可直接在地图底部撤回、保存或取消，无需返回此页面。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                    if session.targetSelectionMode == .crosshair {
                        Button(action: onBuildRouteToTarget) {
                            Label("从当前位置生成至准星的轨迹", systemImage: "scope")
                        }
                    } else {
                        Label("长按地图上的红色图钉，然后选择“生成轨迹”", systemImage: "hand.tap.fill")
                    }
                    Text(session.targetSelectionMode == .crosshair
                         ? "当前模拟位置或真实位置作为起点，屏幕中央准星作为终点。"
                         : "当前模拟位置或真实位置作为起点，红图钉作为终点。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(.regularMaterial)
            .navigationTitle("轨迹")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

}
