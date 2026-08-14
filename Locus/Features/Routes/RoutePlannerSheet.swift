import SwiftUI

struct RoutePlannerSheet: View {
    var onPlay: () -> Void
    var onImportGPX: () -> Void
    var onExportGPX: () -> Void
    var onUseDrawn: () -> Void

    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("轨迹运行") {
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
                }

                Section("运行、手绘与 GPX") {
                    Button {
                        onUseDrawn()
                    } label: {
                        Label("使用地图上手绘的轨迹", systemImage: "pencil.tip")
                    }
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
