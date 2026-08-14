import SwiftUI
import NetworkExtension
import UIKit

struct RootView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @State private var showSettings = false
    @State private var showPlaces = false
    @State private var favoriteRenameSuggestion: SavedPlace?
    @State private var favoriteToRename: SavedPlace?
    @State private var favoriteRenameText = ""
    @State private var favoriteRenameTask: Task<Void, Never>?

    var body: some View {
        // Bottom chrome is a sibling overlay aligned to the bottom — no full-screen
        // Spacer layer that can steal / pass map taps through the tray.
        ZStack(alignment: .bottom) {
            MapHomeView(
                showPlaces: $showPlaces,
                favoriteRenameSuggestion: $favoriteRenameSuggestion
            )

            VStack(spacing: 10) {
                if let favoriteRenameSuggestion {
                    renameSuggestionButton(favoriteRenameSuggestion)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 70)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                BottomControlsView(showSettings: $showSettings)
            }
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
        .alert("重命名收藏", isPresented: Binding(
            get: { favoriteToRename != nil },
            set: { if !$0 { favoriteToRename = nil } }
        )) {
            TextField("名称", text: $favoriteRenameText)
            Button("取消", role: .cancel) { favoriteToRename = nil }
            Button("保存") {
                if let favoriteToRename {
                    session.renameFavorite(favoriteToRename, to: favoriteRenameText)
                }
                favoriteToRename = nil
            }
            .disabled(favoriteRenameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("输入一个方便识别的地点名称。")
        }
        .onChange(of: favoriteRenameSuggestion?.id) { _, favoriteID in
            favoriteRenameTask?.cancel()
            guard let favoriteID else { return }
            favoriteRenameTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled,
                      favoriteRenameSuggestion?.id == favoriteID else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    favoriteRenameSuggestion = nil
                }
            }
        }
        .onDisappear {
            favoriteRenameTask?.cancel()
        }
    }

    private func renameSuggestionButton(_ favorite: SavedPlace) -> some View {
        Button {
            favoriteRenameTask?.cancel()
            let current = session.favorites.first(where: { $0.id == favorite.id }) ?? favorite
            favoriteRenameText = session.favoriteDisplayName(current)
            favoriteToRename = current
            withAnimation(.easeOut(duration: 0.15)) {
                favoriteRenameSuggestion = nil
            }
        } label: {
            Label("重命名“\(session.favoriteDisplayName(favorite))”", systemImage: "pencil")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .locusGlass(.interactive, in: Capsule())
        .accessibilityHint("两秒内轻点即可自定义收藏名称")
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.7), radius: 4)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if case .connectVPN = display {
                    Image(systemName: "lock.shield.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LocusTheme.accent)
                }
            }

            if case .active = session.status, let sim = session.simulated {
                Text(String(format: "%.4f, %.4f", sim.latitude, sim.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
    @State private var showTravelModes = false

    private let trayShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if session.joystickActive {
                JoystickPad { vector in
                    session.updateJoystick(vector: vector)
                }
                .frame(width: 148, height: 148)
                .frame(maxWidth: .infinity, alignment: .leading)
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

                if showTravelModes {
                    travelModePicker
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    HStack(spacing: 10) {
                        trayIcon("gearshape.fill") { showSettings = true }
                        travelModeButton
                        joystickButton
                        sessionControl
                    }
                    .transition(.opacity)
                }
            }
            .padding(14)
            .locusGlass(.regular, in: trayShape)
            // Only the fixed controls participate in the glass tray's layout.
            .contentShape(trayShape)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(.easeOut(duration: 0.18), value: session.joystickActive)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: showTravelModes)
    }

    private var travelModePicker: some View {
        HStack(spacing: 6) {
            ForEach(TravelMode.allCases) { mode in
                let selected = session.travelMode == mode
                Button {
                    session.travelMode = mode
                    withAnimation { showTravelModes = false }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Image(systemName: mode.icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(selected ? .black : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Capsule().fill(selected ? LocusTheme.accent : Color.primary.opacity(0.08)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
            }
        }
    }

    private var travelModeButton: some View {
        Button {
            withAnimation { showTravelModes.toggle() }
        } label: {
            Image(systemName: session.travelMode.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(showTravelModes ? .black : .primary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(showTravelModes ? LocusTheme.accent : Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("交通方式：\(session.travelMode.title)")
        .accessibilityHint("轻点选择步行、跑步、骑行或驾车")
    }

    private var joystickButton: some View {
        Button {
            if session.joystickActive {
                session.stopJoystick()
            } else {
                session.startJoystick(pairing: pairing)
            }
        } label: {
            Image(systemName: "dot.circle.and.hand.point.up.left.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(session.joystickActive ? .black : .primary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(session.joystickActive ? LocusTheme.accentSecondary : Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.joystickActive ? "关闭摇杆" : "开启摇杆")
    }

    private var sessionControl: some View {
        Button(action: performSessionAction) {
            HStack(spacing: 6) {
                if session.canResumeRoute {
                    Image(systemName: "play.fill")
                }
                Text(sessionControlTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(session.isSpoofing && !session.canResumeRoute ? .white : .black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(Capsule().fill(sessionControlColor))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!session.isSpoofing && session.isBusy)
        .contextMenu {
            if session.canResumeRoute {
                Button(role: .destructive) {
                    session.stop(pairing: pairing)
                } label: {
                    Label("停止定位", systemImage: "stop.fill")
                }
            }
        }
        .accessibilityHint(session.canResumeRoute ? "轻点继续轨迹；长按可停止定位" : "")
    }

    private var sessionControlTitle: String {
        if session.canResumeRoute { return "继续轨迹" }
        if session.isSpoofing { return session.isMoving ? "暂停" : "停止定位" }
        return "开始定位"
    }

    private var sessionControlColor: Color {
        session.isSpoofing && !session.canResumeRoute ? LocusTheme.danger : LocusTheme.accent
    }

    private func performSessionAction() {
        if session.canResumeRoute {
            session.resumeRoute(pairing: pairing)
        } else if session.isSpoofing {
            session.stop(pairing: pairing)
        } else {
            guard let pin = session.pin else {
                session.lastError = "请先点击地图放置图钉。"
                return
            }
            session.teleport(to: pin, pairing: pairing)
        }
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
