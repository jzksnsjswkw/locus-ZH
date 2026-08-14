import SwiftUI
import NetworkExtension
import CoreLocation
import Contacts
import UIKit

enum MapChromeLayout {
    static let horizontalPadding: CGFloat = 16
    static let spacing: CGFloat = 10
    static let primaryHeight: CGFloat = 80
    static let rightColumnWidth: CGFloat = 56
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
    @State private var generatedRouteReady = false

    var body: some View {
        // Bottom chrome is a sibling overlay aligned to the bottom — no full-screen
        // Spacer layer that can steal / pass map taps through the tray.
        ZStack(alignment: .bottom) {
            MapHomeView(
                showPlaces: $showPlaces,
                favoriteRenameSuggestion: $favoriteRenameSuggestion,
                searchPresented: $searchPresented,
                showRouteSheet: $showRouteSheet,
                generatedRouteReady: $generatedRouteReady
            )

            VStack(spacing: 10) {
                if let favoriteRenameSuggestion, !searchPresented {
                    renameSuggestionButton(favoriteRenameSuggestion)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if !searchPresented {
                    if generatedRouteReady {
                        generatedRouteControls
                            .frame(maxWidth: .infinity, alignment: .center)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    BottomControlsView(
                        showSettings: $showSettings,
                        showRouteSheet: $showRouteSheet
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, MapChromeLayout.horizontalPadding)
            .padding(.bottom, MapChromeLayout.bottomPadding)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showPlaces) {
            PlacesView()
                .presentationDetents([.medium, .large])
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
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: generatedRouteReady)
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

    private var generatedRouteControls: some View {
        HStack(spacing: 0) {
            Button {
                NotificationCenter.default.post(name: .locusDeleteRoute, object: nil)
            } label: {
                Label("删除", systemImage: "trash.fill")
                    .foregroundStyle(LocusTheme.danger)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .contentShape(Rectangle())
            }

            Divider()
                .overlay(Color.white.opacity(0.25))
                .frame(height: 28)

            Button {
                NotificationCenter.default.post(name: .locusRunRoute, object: nil)
            } label: {
                Label("运行", systemImage: "play.fill")
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .contentShape(Rectangle())
            }
        }
        .font(.subheadline.weight(.bold))
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .frame(width: 224, height: 50)
        .locusGlass(.regular, in: Capsule())
        .contentShape(Capsule())
    }
}

struct StatusBarView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var locationSummary = MapLocationSummary()
    @State private var tunnelConnected = LocalDevVPN.isConnected
    @State private var showLocationDetails = false

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
        VStack(alignment: .leading, spacing: 8) {
            statusContent
                .onTapGesture {
                    if case .connectVPN = display {
                        LocalDevVPN.openOrInstall()
                    }
                }
                .onLongPressGesture(minimumDuration: 0.45) {
                    guard locationSummaryCoordinate != nil else { return }
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        showLocationDetails.toggle()
                    }
                }

            if showLocationDetails, locationSummaryCoordinate != nil {
                locationDetailsCard
                    .transition(
                        .scale(scale: 0.88, anchor: .topLeading)
                            .combined(with: .opacity)
                    )
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
                Text(locationSummary.shortText)
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

    private var locationDetailsCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label("位置信息", systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 6)
                Button {
                    UIPasteboard.general.string = locationCopyText
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(LocusTheme.accent)
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showLocationDetails = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭位置信息")
            }

            Text(locationSummary.formattedAddress)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)

            HStack(spacing: 12) {
                locationDetailValue("国家", locationSummary.country)
                locationDetailValue("城市", locationSummary.city)
                locationDetailValue("邮编", locationSummary.postalCode)
            }

            if let coordinate = locationSummaryCoordinate {
                Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 270, alignment: .leading)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func locationDetailValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
    }

    private var locationCopyText: String {
        let coordinate = locationSummaryCoordinate.map {
            String(format: "%.5f, %.5f", $0.latitude, $0.longitude)
        } ?? ""
        return [
            locationSummary.formattedAddress,
            "国家：\(locationSummary.country)",
            "城市：\(locationSummary.city)",
            "邮编：\(locationSummary.postalCode)",
            coordinate
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
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
    @Published private(set) var country = "正在获取"
    @Published private(set) var city = "地区"
    @Published private(set) var postalCode = "—"
    @Published private(set) var formattedAddress = "正在获取 Apple 地图地址"

    var shortText: String {
        [country, city]
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, value in
                if result.last != value { result.append(value) }
            }
            .joined(separator: " ")
    }

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
                let placemark = try await self.geocoder.reverseGeocodeLocation(
                    location,
                    preferredLocale: Locale(identifier: "zh_Hans_CN")
                ).first
                guard !Task.isCancelled else { return }
                self.country = placemark?.country?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .flatMap { $0.isEmpty ? nil : $0 } ?? "未知国家"
                self.city = (placemark?.locality ?? placemark?.administrativeArea)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .flatMap { $0.isEmpty ? nil : $0 } ?? "未知城市"
                self.postalCode = placemark?.postalCode?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .flatMap { $0.isEmpty ? nil : $0 } ?? "—"
                if let postalAddress = placemark?.postalAddress {
                    self.formattedAddress = CNPostalAddressFormatter
                        .string(from: postalAddress, style: .mailingAddress)
                        .split(whereSeparator: \.isNewline)
                        .joined(separator: "，")
                } else {
                    self.formattedAddress = [
                        placemark?.name,
                        placemark?.subLocality,
                        placemark?.locality,
                        placemark?.administrativeArea,
                        placemark?.country
                    ]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "，")
                }
            } catch {
                guard !Task.isCancelled, self.country == "正在获取" else { return }
                self.country = "未知国家"
                self.city = "未知城市"
                self.postalCode = "—"
                self.formattedAddress = "无法获取地址"
            }
        }
    }
}

struct BottomControlsView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Binding var showSettings: Bool
    @Binding var showRouteSheet: Bool

    private let trayShape = RoundedRectangle(cornerRadius: 30, style: .continuous)

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

                HStack(spacing: 0) {
                    trayIcon("slider.horizontal.3") { showSettings = true }
                    controlDivider
                    routeButton
                    controlDivider
                    joystickButton
                    controlDivider
                    if session.canResumeRoute {
                        pausedRouteControls
                    } else {
                        sessionControl
                    }
                }
        }
        .padding(10)
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
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 60, height: 60)
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
            Image(systemName: "circle.grid.cross.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(session.joystickActive ? LocusTheme.accentSecondary : .primary)
                .frame(width: 60, height: 60)
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
            .frame(height: 56)
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
                    .frame(height: 56)
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
                    .frame(height: 56)
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
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 60, height: 60)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var controlDivider: some View {
        Divider()
            .overlay(Color.white.opacity(0.22))
            .frame(height: 38)
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
