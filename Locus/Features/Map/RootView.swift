import SwiftUI
import NetworkExtension
import CoreLocation
import UIKit

enum MapChromeLayout {
    static let horizontalPadding: CGFloat = 16
    static let spacing: CGFloat = 10
    static let primaryHeight: CGFloat = 64
    static let rightColumnWidth: CGFloat = 64
    static let bottomPadding: CGFloat = 8
    static let rightRailClearance = bottomPadding + primaryHeight + spacing
}

struct RootView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @State private var showSettings = false
    @State private var showPlaces = false
    @State private var favoriteRenameSuggestion: SavedPlace?
    @State private var favoriteToRename: SavedPlace?
    @State private var favoriteRenameText = ""
    @State private var favoriteRenameTask: Task<Void, Never>?
    @State private var searchPresented = false
    @State private var showRouteSheet = false

    var body: some View {
        // Bottom chrome is a sibling overlay aligned to the bottom — no full-screen
        // Spacer layer that can steal / pass map taps through the tray.
        ZStack(alignment: .bottom) {
            MapHomeView(
                showPlaces: $showPlaces,
                favoriteRenameSuggestion: $favoriteRenameSuggestion,
                searchPresented: $searchPresented,
                showRouteSheet: $showRouteSheet
            )

            VStack(spacing: 10) {
                if let favoriteRenameSuggestion, !searchPresented {
                    renameSuggestionButton(favoriteRenameSuggestion)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if !searchPresented {
                    HStack(alignment: .bottom, spacing: 10) {
                        BottomControlsView(
                            showSettings: $showSettings,
                            showRouteSheet: $showRouteSheet
                        )

                        locationButton
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, MapChromeLayout.horizontalPadding)
            .padding(.bottom, MapChromeLayout.bottomPadding)
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
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: searchPresented)
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
                .foregroundStyle(LocusTheme.danger)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .locusGlass(.interactive, in: Capsule())
        .accessibilityHint("两秒内轻点即可自定义收藏名称")
    }

    private var locationButton: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            NotificationCenter.default.post(name: .locusLocateCurrent, object: nil)
        } label: {
            Image(systemName: "location.fill")
                .font(.title2.weight(.semibold))
                .frame(
                    width: MapChromeLayout.rightColumnWidth,
                    height: MapChromeLayout.primaryHeight
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .locusGlass(.interactive, in: Circle())
        .foregroundStyle(.primary)
        .opacity(session.joystickActive ? 0 : 1)
        .allowsHitTesting(!session.joystickActive)
        .accessibilityLabel("回到当前位置")
    }
}

struct StatusBarView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var locationSummary = MapLocationSummary()
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
        .onAppear {
            refreshTunnel()
            syncLiveActivity()
            updateLocationSummary()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshTunnel() }
        }
        .onChange(of: session.status) { _, _ in
            refreshTunnel()
            syncLiveActivity()
        }
        .onChange(of: session.routeActive) { _, active in
            if active {
                locationSummary.suspend()
            } else if !session.routePaused {
                updateLocationSummary()
            }
            syncLiveActivity()
        }
        .onChange(of: session.routePaused) { _, paused in
            if paused {
                locationSummary.suspend()
            } else if !session.routeActive {
                updateLocationSummary()
            }
            syncLiveActivity()
        }
        .onChange(of: session.simulated?.latitude) { _, _ in
            syncLiveActivity()
            updateLocationSummary()
        }
        .onChange(of: session.simulated?.longitude) { _, _ in
            syncLiveActivity()
            updateLocationSummary()
        }
        .onChange(of: session.pin?.latitude) { _, _ in
            updateLocationSummary()
        }
        .onChange(of: session.pin?.longitude) { _, _ in
            updateLocationSummary()
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

            if locationSummaryCoordinate != nil {
                Text(locationSummary.text)
                    .font(.caption)
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

    private var locationSummaryCoordinate: CLLocationCoordinate2D? {
        session.simulated ?? session.pin ?? session.realMapCoordinate
    }

    private func updateLocationSummary() {
        guard !session.routeActive, !session.routePaused else { return }
        guard let coordinate = locationSummaryCoordinate else { return }
        locationSummary.requestUpdate(to: coordinate)
    }

    private func syncLiveActivity() {
        let isActive = session.isSpoofing
        let status = title
        let coordinate = session.simulated
        Task {
            await LocusLiveActivityController.shared.sync(
                isActive: isActive,
                status: status,
                coordinate: coordinate,
                distanceTraveled: session.routeDistanceTraveled,
                elapsedTime: session.routeElapsedTime,
                allowRegionLookup: !session.routeActive && !session.routePaused
            )
        }
    }
}

@MainActor
private final class MapLocationSummary: ObservableObject {
    @Published private(set) var text = "正在获取地区"

    private let geocoder = CLGeocoder()
    private var lastAttemptLocation: CLLocation?
    private var lastAttemptAt: Date?
    private var lookupTask: Task<Void, Never>?

    func suspend() {
        lookupTask?.cancel()
        lookupTask = nil
        geocoder.cancelGeocode()
    }

    func requestUpdate(to coordinate: CLLocationCoordinate2D) {
        let lookupCoordinate = ChinaCoordinateTransform.mapCoordinateToSystemCoordinate(coordinate)
        let location = CLLocation(latitude: lookupCoordinate.latitude, longitude: lookupCoordinate.longitude)
        if let lastAttemptLocation,
           let lastAttemptAt,
           location.distance(from: lastAttemptLocation) < 2_000,
           Date().timeIntervalSince(lastAttemptAt) < 300 {
            return
        }

        lastAttemptLocation = location
        lastAttemptAt = Date()
        lookupTask?.cancel()
        geocoder.cancelGeocode()

        lookupTask = Task { [weak self] in
            guard let self else { return }
            do {
                let placemark = try await self.geocoder.reverseGeocodeLocation(location).first
                guard !Task.isCancelled else { return }
                let country = placemark?.country?.trimmingCharacters(in: .whitespacesAndNewlines)
                let city = (placemark?.locality ?? placemark?.administrativeArea)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = [country, city]
                    .compactMap { value -> String? in
                        guard let value, !value.isEmpty else { return nil }
                        return value
                    }
                    .reduce(into: [String]()) { result, value in
                        if result.last != value { result.append(value) }
                    }
                self.text = parts.isEmpty ? "未知地区" : parts.joined(separator: " ")
            } catch {
                guard !Task.isCancelled, self.text == "正在获取地区" else { return }
                self.text = "未知地区"
            }
        }
    }
}

struct BottomControlsView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Binding var showSettings: Bool
    @Binding var showRouteSheet: Bool

    private let trayShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        VStack(spacing: 12) {
                if session.routeActive || session.routePaused {
                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            Button {
                                session.adjustSpeed(by: -0.25)
                            } label: {
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

                            Button {
                                session.adjustSpeed(by: 0.25)
                            } label: {
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

                HStack(spacing: 10) {
                    trayIcon("gearshape.fill") { showSettings = true }
                    routeButton
                    joystickButton
                    if session.canResumeRoute {
                        pausedRouteControls
                    } else {
                        sessionControl
                    }
                }
        }
        .padding(6)
        .locusGlass(.regular, in: trayShape)
        .contentShape(trayShape)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(minHeight: MapChromeLayout.primaryHeight)
        .animation(.easeOut(duration: 0.18), value: session.joystickActive)
    }

    private var routeButton: some View {
        Button {
            showRouteSheet = true
        } label: {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开轨迹")
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
                .foregroundStyle(session.joystickActive ? LocusTheme.accentSecondary : .primary)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.joystickActive ? "关闭摇杆" : "开启摇杆")
    }

    private var sessionControl: some View {
        Button {
            performSessionAction()
        } label: {
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

    private var pausedRouteControls: some View {
        HStack(spacing: 6) {
            Button {
                NotificationCenter.default.post(name: .locusDeleteRoute, object: nil)
            } label: {
                Text("结束")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Capsule().fill(LocusTheme.danger))
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                session.resumeRoute(pairing: pairing)
            } label: {
                Text("继续")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Capsule().fill(LocusTheme.accent))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
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
        Button {
            action()
        } label: {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
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
