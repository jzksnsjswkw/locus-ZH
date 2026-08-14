import SwiftUI
import NetworkExtension

struct RootView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @State private var showSettings = false
    @State private var showPlaces = false

    var body: some View {
        // Bottom chrome is a sibling overlay aligned to the bottom — no full-screen
        // Spacer layer that can steal / pass map taps through the tray.
        ZStack(alignment: .bottom) {
            MapHomeView()

            BottomControlsView(
                showSettings: $showSettings,
                showPlaces: $showPlaces
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showPlaces) {
            PlacesView()
        }
        .alert("Locus", isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.lastError = nil } }
        )) {
            Button("确定", role: .cancel) { session.lastError = nil }
        } message: {
            Text(session.lastError ?? "")
        }
    }
}

struct StatusBarView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.scenePhase) private var scenePhase

    @State private var tunnelConnected = LocalDevVPN.isConnected

    private enum Display {
        case notSpoofing
        case connectVPN
        case status(String)
    }

    private var display: Display {
        switch session.status {
        case .idle:
            return tunnelConnected ? .notSpoofing : .connectVPN
        case .connecting:
            return .status("正在连接…")
        case .active:
            return .status("正在模拟定位")
        case .reconnecting:
            return .status("正在重新连接…")
        case .dropped(let reason):
            return .status(reason.isEmpty ? "连接已断开" : "连接已断开 — \(reason)")
        }
    }

    private var color: Color {
        switch display {
        case .notSpoofing:
            return Color.primary.opacity(0.55)
        case .connectVPN:
            return LocusTheme.statusWarn
        case .status:
            switch session.status {
            case .active: return LocusTheme.statusGood
            case .connecting, .reconnecting: return LocusTheme.statusWarn
            case .dropped: return LocusTheme.statusBad
            case .idle: return Color.primary.opacity(0.55)
            }
        }
    }

    private var title: String {
        switch display {
        case .notSpoofing: return "未模拟定位"
        case .connectVPN: return "连接 LocalDevVPN"
        case .status(let text): return text
        }
    }

    var body: some View {
        Group {
            if case .connectVPN = display {
                Button(action: LocalDevVPN.openOrInstall) {
                    statusContent
                }
                .buttonStyle(.plain)
            } else {
                statusContent
            }
        }
        .onAppear { refreshTunnel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshTunnel() }
        }
        .onChange(of: session.status) { _, _ in
            refreshTunnel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)) { _ in
            // LocalDevVPN connection changes show up here even though we don’t own the VPN.
            refreshTunnel()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                refreshTunnel()
            }
        }
    }

    private var statusContent: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.7), radius: 4)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if case .connectVPN = display {
                Image(systemName: "lock.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LocusTheme.accent)
            } else if case .active = session.status, let sim = session.simulated {
                Text(String(format: "%.4f, %.4f", sim.latitude, sim.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .locusGlass(.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func refreshTunnel() {
        tunnelConnected = LocalDevVPN.isConnected
    }
}

struct BottomControlsView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Binding var showSettings: Bool
    @Binding var showPlaces: Bool

    private let trayShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if session.joystickActive {
                JoystickPad { vector in
                    session.updateJoystick(vector: vector)
                }
                .frame(width: 148, height: 148)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            VStack(spacing: 12) {
                if session.routeActive || session.routePaused {
                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            Button { session.adjustSpeed(by: -0.25) } label: {
                                Label("减速", systemImage: "minus.circle.fill")
                            }
                            .disabled(session.speedMultiplier <= 0.25)

                            Spacer()
                            VStack(spacing: 2) {
                                Text(String(format: "%.2fx · %.1f km/h", session.speedMultiplier, session.travelMode.baseSpeed * session.speedMultiplier * 3.6))
                                    .font(.subheadline.bold())
                                    .monospacedDigit()
                                Text("第 \(max(1, session.routeLap)) 圈 · \(Int(session.routeProgress * 100))%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            Button { session.adjustSpeed(by: 0.25) } label: {
                                Label("加速", systemImage: "plus.circle.fill")
                            }
                            .disabled(session.speedMultiplier >= 4.0)
                        }
                        .buttonStyle(.borderless)

                        ProgressView(value: session.routeProgress)
                            .tint(LocusTheme.accent)
                    }
                    .padding(.horizontal, 4)
                }

                HStack(spacing: 8) {
                    ForEach(TravelMode.allCases) { mode in
                        let selected = session.travelMode == mode
                        Button {
                            session.travelMode = mode
                        } label: {
                            Image(systemName: mode.icon)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(selected ? .black : .primary)
                                .frame(width: 44, height: 40)
                                .background(
                                    Capsule().fill(selected ? LocusTheme.accent : Color.primary.opacity(0.08))
                                )
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    trayIcon("gearshape.fill") { showSettings = true }
                    trayIcon("star.fill") { showPlaces = true }

                    Button {
                        if session.joystickActive {
                            session.stopJoystick()
                        } else {
                            session.startJoystick(pairing: pairing)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "dot.circle.and.hand.point.up.left.fill")
                            Text(session.joystickActive ? "摇杆开启" : "摇杆")
                                .lineLimit(1)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(session.joystickActive ? .black : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(session.joystickActive ? LocusTheme.accentSecondary : Color.primary.opacity(0.08))
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    if session.isSpoofing {
                        if session.canResumeRoute {
                            Button {
                                session.resumeRoute(pairing: pairing)
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.body.bold())
                                    .foregroundStyle(.black)
                                    .frame(width: 46, height: 46)
                                    .background(Circle().fill(LocusTheme.accent))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("继续轨迹")
                        }
                        Button {
                            session.stop(pairing: pairing)
                        } label: {
                            Text(session.isMoving ? "暂停" : "停止定位")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 72)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 8)
                                .background(Capsule().fill(LocusTheme.danger))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            guard let pin = session.pin else {
                                session.lastError = "请先点击地图放置图钉。"
                                return
                            }
                            session.teleport(to: pin, pairing: pairing)
                        } label: {
                            Text("开始定位")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.black)
                                .frame(minWidth: 96)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 10)
                                .background(Capsule().fill(LocusTheme.accent))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(session.isBusy)
                    }
                }
            }
            .padding(14)
            .locusGlass(.regular, in: trayShape)
            // Only the fixed controls participate in the glass tray's layout.
            .contentShape(trayShape)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(.easeOut(duration: 0.18), value: session.joystickActive)
    }

    private func trayIcon(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct IconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .locusGlass(.interactive, in: Circle())
        .foregroundStyle(.primary)
    }
}
