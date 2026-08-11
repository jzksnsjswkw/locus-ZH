import CoreLocation
import SwiftUI

struct RoutePlannerSheet: View {
    @Binding var start: CLLocationCoordinate2D?
    @Binding var end: CLLocationCoordinate2D?
    @Binding var isRouting: Bool
    var onBuild: () -> Void
    var onPlay: () -> Void
    var onImportGPX: () -> Void
    var onExportGPX: () -> Void
    var onUseDrawn: () -> Void

    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("道路路线") {
                    Button("使用当前图钉或模拟位置作为起点") {
                        start = session.simulated ?? session.pin
                    }
                    Button("使用当前图钉作为终点") {
                        end = session.pin
                    }
                    LabeledContent("起点") {
                        Text(coordText(start)).font(.caption.monospaced())
                    }
                    LabeledContent("终点") {
                        Text(coordText(end)).font(.caption.monospaced())
                    }
                    Button {
                        onBuild()
                    } label: {
                        if isRouting {
                            ProgressView()
                        } else {
                            Label("沿道路规划步行或驾车路线", systemImage: "road.lanes")
                        }
                    }
                    .disabled(isRouting)
                }

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

                Section {
                    Text("优先使用 Apple 地图规划道路路线；路线服务器不可用时自动生成直线备用路线。速度设置同时作用于轨迹和摇杆。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("轨迹")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func coordText(_ c: CLLocationCoordinate2D?) -> String {
        guard let c else { return "—" }
        return String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }
}
