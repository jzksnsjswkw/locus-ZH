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
                Section("Road route") {
                    Button("Use current pin / spoof as start") {
                        start = session.simulated ?? session.pin
                    }
                    Button("Use current pin as end") {
                        end = session.pin
                    }
                    LabeledContent("Start") {
                        Text(coordText(start)).font(.caption.monospaced())
                    }
                    LabeledContent("End") {
                        Text(coordText(end)).font(.caption.monospaced())
                    }
                    Button {
                        onBuild()
                    } label: {
                        if isRouting {
                            ProgressView()
                        } else {
                            Label("Build walk/drive route on roads", systemImage: "road.lanes")
                        }
                    }
                    .disabled(isRouting)
                }

                Section("Playback") {
                    HStack {
                        Label("Speed", systemImage: "speedometer")
                        Spacer()
                        Text(String(format: "%.2fx · %.1f km/h", session.speedMultiplier, session.travelMode.baseSpeed * session.speedMultiplier * 3.6))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $session.speedMultiplier, in: 0.25...4.0, step: 0.25)
                    Toggle(isOn: $session.routeLoopEnabled) {
                        Label("Loop route", systemImage: "repeat")
                    }
                }

                Section("Play / draw / GPX") {
                    Button {
                        onUseDrawn()
                    } label: {
                        Label("Use drawn path from map", systemImage: "pencil.tip")
                    }
                    Button(action: onPlay) {
                        Label("Follow route", systemImage: "play.fill")
                    }
                    Button(action: onImportGPX) {
                        Label("Import GPX", systemImage: "square.and.arrow.down")
                    }
                    Button(action: onExportGPX) {
                        Label("Export GPX", systemImage: "square.and.arrow.up")
                    }
                }

                Section {
                    Text("Road routing uses Apple Maps when available and falls back to a direct route when the route server is unreachable. Speed applies to route playback and the joystick.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Routes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func coordText(_ c: CLLocationCoordinate2D?) -> String {
        guard let c else { return "—" }
        return String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }
}
