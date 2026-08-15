import SwiftUI
import NetworkExtension
import CoreLocation
import MapKit
import UIKit

enum MapChromeLayout {
    static let horizontalPadding: CGFloat = 16
    static let spacing: CGFloat = 10
    static let primaryHeight: CGFloat = 56
    static let rightColumnWidth: CGFloat = 56
    // Leave MapKit's system-owned attribution unobscured. Its position is not
    // publicly configurable, so the app chrome must yield this space instead.
    static let bottomPadding: CGFloat = 24
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
    @State private var routeOptions: [PlannedRoute] = []
    @State private var selectedRouteOptionID: UUID?
    @State private var drawingRouteActive = false
    @State private var drawingRoutePointCount = 0

    var body: some View {
        // Bottom chrome is a sibling overlay aligned to the bottom — no full-screen
        // Spacer layer that can steal / pass map taps through the tray.
        ZStack(alignment: .bottom) {
            MapHomeView(
                showPlaces: $showPlaces,
                favoriteRenameSuggestion: $favoriteRenameSuggestion,
                searchPresented: $searchPresented,
                showRouteSheet: $showRouteSheet,
                generatedRouteReady: $generatedRouteReady,
                routeOptions: $routeOptions,
                selectedRouteOptionID: $selectedRouteOptionID,
                drawingRouteActive: $drawingRouteActive,
                drawingRoutePointCount: $drawingRoutePointCount
            )

            VStack(spacing: 10) {
                if let favoriteRenameSuggestion, !searchPresented {
                    renameSuggestionButton(favoriteRenameSuggestion)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if !searchPresented {
                    HStack(alignment: .bottom, spacing: MapChromeLayout.spacing) {
                        VStack(spacing: MapChromeLayout.spacing) {
                            if drawingRouteActive {
                                drawingRouteControls
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            } else if generatedRouteReady {
                                generatedRouteControls
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                if routeOptions.count > 1 {
                                    routeChoiceControls
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }

                            BottomControlsView(
                                showSettings: $showSettings,
                                showRouteSheet: $showRouteSheet
                            )
                        }
                        .frame(maxWidth: .infinity)

                        bottomSearchButton
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, MapChromeLayout.horizontalPadding)
            .padding(.bottom, MapChromeLayout.bottomPadding)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
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
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: drawingRouteActive)
    }

    private var bottomSearchButton: some View {
        Button {
            dismissStatusDetails()
            UISelectionFeedbackGenerator().selectionChanged()
            searchPresented = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.title3.weight(.semibold))
                .frame(
                    width: MapChromeLayout.rightColumnWidth,
                    height: MapChromeLayout.rightColumnWidth
                )
                .aspectRatio(1, contentMode: .fit)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .locusGlass(.interactive, in: Circle())
        .frame(
            width: MapChromeLayout.rightColumnWidth,
            height: MapChromeLayout.rightColumnWidth
        )
        .clipShape(Circle())
        .accessibilityLabel("搜索地点")
    }

    private func dismissStatusDetails() {
        NotificationCenter.default.post(name: .locusDismissStatusDetails, object: nil)
    }

    private func renameSuggestionButton(_ favorite: SavedPlace) -> some View {
        Button {
            dismissStatusDetails()
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
                dismissStatusDetails()
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
                dismissStatusDetails()
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

    private var routeChoiceControls: some View {
        HStack(spacing: 6) {
            ForEach(routeOptions) { option in
                let index = routeOptions.firstIndex(where: { $0.id == option.id }) ?? 0
                Button {
                    dismissStatusDetails()
                    selectedRouteOptionID = option.id
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: 1) {
                        Text("路线 \(index + 1)")
                            .font(.caption.weight(.bold))
                        Text(routeOptionDetail(option))
                            .font(.caption2.monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(selectedRouteOptionID == option.id ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        Capsule().fill(
                            selectedRouteOptionID == option.id
                                ? Color(red: 0.0, green: 0.42, blue: 0.24)
                                : Color.primary.opacity(0.06)
                        )
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(maxWidth: 320)
        .locusGlass(.regular, in: Capsule())
        .contentShape(Capsule())
    }

    private func routeOptionDetail(_ option: PlannedRoute) -> String {
        let minutes = max(1, Int((option.expectedTravelTime / 60).rounded()))
        let distance = option.distance >= 1_000
            ? String(format: "%.1f km", option.distance / 1_000)
            : "\(Int(option.distance.rounded())) m"
        return "\(minutes) 分 · \(distance)"
    }

    private var drawingRouteControls: some View {
        HStack(spacing: 0) {
            drawingActionButton("取消", systemImage: "xmark", color: LocusTheme.danger) {
                NotificationCenter.default.post(name: .locusCancelDrawingRoute, object: nil)
            }

            Divider()
                .overlay(Color.white.opacity(0.25))
                .frame(height: 28)

            drawingActionButton("撤回", systemImage: "arrow.uturn.backward", color: .orange) {
                NotificationCenter.default.post(name: .locusUndoDrawingPoint, object: nil)
            }
            .disabled(drawingRoutePointCount == 0)

            Divider()
                .overlay(Color.white.opacity(0.25))
                .frame(height: 28)

            drawingActionButton("保存", systemImage: "checkmark", color: .blue) {
                NotificationCenter.default.post(name: .locusSaveDrawingRoute, object: nil)
            }
            .disabled(drawingRoutePointCount < 2)
        }
        .font(.caption.weight(.bold))
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .frame(maxWidth: 320)
        .frame(height: 50)
        .locusGlass(.regular, in: Capsule())
        .contentShape(Capsule())
    }

    private func drawingActionButton(
        _ title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            dismissStatusDetails()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 42)
                .contentShape(Rectangle())
        }
    }
}

struct StatusBarView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var mapDataSourceDetector: MapDataSourceDetector

    @StateObject private var locationSummary = MapLocationSummary()
    @State private var tunnelConnected = LocalDevVPN.isConnected
    @State private var showLocationDetails = false

    private enum Display {
        case notSpoofing
        case connectVPN
        case status(String)
    }

    private var display: Display {
        guard tunnelConnected else { return .connectVPN }
        switch session.status {
        case .idle:
            return .notSpoofing
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
        case .connectVPN: return "点击连接 LocalDevVPN"
        case .status(let text): return text
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusContent

            if showLocationDetails, locationSummary.coordinate != nil {
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
            }
            syncLiveActivity()
        }
        .onChange(of: session.routePaused) { _, paused in
            if paused {
                locationSummary.suspend()
            }
            syncLiveActivity()
        }
        .onChange(of: session.simulated?.latitude) { _, _ in
            syncLiveActivity()
        }
        .onChange(of: session.simulated?.longitude) { _, _ in
            syncLiveActivity()
        }
        .onChange(of: session.locationSummaryRevision) { _, _ in
            updateLocationSummary(force: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)) { _ in
            // LocalDevVPN connection changes show up here even though we don’t own the VPN.
            refreshTunnel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .locusDismissStatusDetails)) { _ in
            guard showLocationDetails else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                showLocationDetails = false
            }
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
        Button(action: handleStatusTap) {
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

                    if !tunnelConnected {
                        Image(systemName: "lock.shield.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LocusTheme.accent)
                    }
                }

                if tunnelConnected, locationSummary.coordinate != nil {
                    Text(locationSummary.shortText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .fixedSize(horizontal: true, vertical: false)
            .locusGlass(.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tunnelConnected ? title : "点击连接 LocalDevVPN")
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
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .locusGlass(.interactive, tint: Color.blue.opacity(0.45), in: Capsule())

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

            HStack(spacing: 8) {
                Label("地图数据源", systemImage: "map.fill")
                Spacer(minLength: 4)
                HStack(spacing: 5) {
                    mapDataSourceBadge("Apple", isActive: mapDataSourceDetector.source == .apple)
                    mapDataSourceBadge("高德", isActive: mapDataSourceDetector.source == .amap)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                Label("当地时间：\(locationSummary.localTimeString(at: context.date))", systemImage: "clock")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let coordinate = locationSummary.coordinate {
                Text("纬度：\(latitudeText(coordinate.latitude))  经度：\(longitudeText(coordinate.longitude))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
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
        let coordinate = locationSummary.coordinate.map {
            "纬度：\(latitudeText($0.latitude))\n经度：\(longitudeText($0.longitude))"
        } ?? ""
        return [
            locationSummary.formattedAddress,
            "国家：\(locationSummary.country)",
            "城市：\(locationSummary.city)",
            "邮编：\(locationSummary.postalCode)",
            mapDataSourceCopyLine,
            coordinate
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private func latitudeText(_ latitude: Double) -> String {
        String(format: "%.5f° %@", abs(latitude), latitude >= 0 ? "N" : "S")
    }

    private func longitudeText(_ longitude: Double) -> String {
        String(format: "%.5f° %@", abs(longitude), longitude >= 0 ? "E" : "W")
    }

    private var mapDataSourceName: String {
        mapDataSourceDetector.source.displayName ?? ""
    }

    private var mapDataSourceCopyLine: String {
        guard !mapDataSourceName.isEmpty else { return "地图数据源：Apple / 高德" }
        return "地图数据源：Apple / 高德（当前：\(mapDataSourceName)）"
    }

    @ViewBuilder
    private func mapDataSourceBadge(_ name: String, isActive: Bool) -> some View {
        let badge = HStack(spacing: 4) {
            Image(systemName: isActive ? "circle.fill" : "circle")
                .font(.system(size: 7, weight: .semibold))
            Text(name)
                .fontWeight(isActive ? .bold : .regular)
        }
        .font(.caption2)
        .foregroundStyle(isActive ? Color.primary : Color.secondary)
        .padding(.horizontal, 7)
        .frame(height: 24)

        if isActive {
            badge
                .locusGlass(.regular, tint: Color.orange.opacity(0.45), in: Capsule())
                .allowsHitTesting(false)
        } else {
            badge
                .allowsHitTesting(false)
        }
    }

    private func handleStatusTap() {
        if !tunnelConnected {
            showLocationDetails = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            LocalDevVPN.openOrInstall()
            return
        }

        guard locationSummary.coordinate != nil else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            showLocationDetails.toggle()
        }
    }

    private func refreshTunnel() {
        let connected = LocalDevVPN.isConnected
        if !connected, showLocationDetails {
            showLocationDetails = false
        }
        tunnelConnected = connected
    }

    private func updateLocationSummary(force: Bool = false) {
        guard !session.routeActive, !session.routePaused else { return }
        guard let coordinate = session.simulated ?? session.realMapCoordinate else { return }
        locationSummary.requestUpdate(to: coordinate, force: force)
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
    @Published private(set) var timeZone: TimeZone?
    @Published private(set) var coordinate: CLLocationCoordinate2D?

    var shortText: String {
        [country, city]
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, value in
                if result.last != value { result.append(value) }
            }
            .joined(separator: " ")
    }

    func localTimeString(at date: Date) -> String {
        guard let timeZone else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy年 M月 d日 HH:mm"
        return formatter.string(from: date)
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

    func requestUpdate(to coordinate: CLLocationCoordinate2D, force: Bool = false) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if !force,
           let lastAttemptLocation,
           let lastAttemptAt,
           location.distance(from: lastAttemptLocation) < 2_000,
           Date().timeIntervalSince(lastAttemptAt) < 300 {
            return
        }

        lastAttemptLocation = location
        lastAttemptAt = Date()
        self.coordinate = coordinate
        lookupTask?.cancel()
        geocoder.cancelGeocode()

        lookupTask = Task { [weak self] in
            guard let self else { return }
            do {
                let isMainlandCoordinate = ChinaCoordinateTransform.usesMainlandChinaOffset(coordinate)
                let lookupCoordinate = isMainlandCoordinate
                    ? ChinaCoordinateTransform.mapCoordinateToSystemCoordinate(coordinate)
                    : coordinate
                let lookupLocation = CLLocation(
                    latitude: lookupCoordinate.latitude,
                    longitude: lookupCoordinate.longitude
                )
                let chinesePlacemarks = try await self.geocoder.reverseGeocodeLocation(
                    lookupLocation,
                    preferredLocale: Locale(identifier: "zh_Hans_CN")
                )
                let chinesePlacemark = self.bestPlacemark(in: chinesePlacemarks)
                guard !Task.isCancelled else { return }
                let countryCode = isMainlandCoordinate
                    ? "CN"
                    : chinesePlacemark?.isoCountryCode?.uppercased()
                if countryCode == "CN" {
                    self.applyChinesePlacemark(chinesePlacemark, countryCode: "CN")
                } else if countryCode == "TW" {
                    self.applyChinesePlacemark(chinesePlacemark, countryCode: "TW")
                } else {
                    let englishPlacemark: CLPlacemark?
                    do {
                        englishPlacemark = try await self.geocoder.reverseGeocodeLocation(
                            lookupLocation,
                            preferredLocale: Locale(identifier: "en_GB")
                        ).max(by: { self.placemarkScore($0) < self.placemarkScore($1) }) ?? chinesePlacemark
                    } catch {
                        englishPlacemark = chinesePlacemark
                    }
                    guard !Task.isCancelled else { return }
                    self.applyForeignPlacemarks(
                        chinese: chinesePlacemark,
                        english: englishPlacemark,
                        countryCode: countryCode
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.country = "未知国家"
                self.city = "未知城市"
                self.postalCode = "—"
                self.formattedAddress = "无法获取地址"
                self.timeZone = nil
            }
        }
    }

    private func applyChinesePlacemark(_ placemark: CLPlacemark?, countryCode: String) {
        let isTaiwan = countryCode == "TW"
        country = "中国"
        city = nonEmpty(
            placemark?.locality ?? placemark?.subAdministrativeArea ?? placemark?.administrativeArea
        ) ?? "未知城市"
        postalCode = nonEmpty(placemark?.postalCode) ?? "—"
        timeZone = placemark?.timeZone

        let street = [placemark?.thoroughfare, placemark?.subThoroughfare]
            .compactMap { nonEmpty($0) }
            .joined()
        let pointOfInterest = placemark?.areasOfInterest?
            .compactMap { nonEmpty($0) }
            .first
        let prefix = isTaiwan ? "中华人民共和国台湾省" : "中国"
        let components = [
            prefix,
            nonEmpty(placemark?.administrativeArea),
            nonEmpty(placemark?.locality),
            nonEmpty(placemark?.subAdministrativeArea),
            nonEmpty(placemark?.subLocality),
            street.isEmpty ? nil : street,
            pointOfInterest,
            nonEmpty(placemark?.name),
            nonEmpty(placemark?.postalCode)
        ]
        .compactMap { $0 }
        .reduce(into: [String]()) { result, value in
            guard !result.contains(where: { existing in
                existing == value || existing.contains(value)
            }) else { return }
            result.append(value)
        }
        formattedAddress = components.isEmpty ? "无法获取地址" : components.joined()
    }

    private func bestPlacemark(in placemarks: [CLPlacemark]) -> CLPlacemark? {
        placemarks.max { placemarkScore($0) < placemarkScore($1) }
    }

    private func placemarkScore(_ placemark: CLPlacemark) -> Int {
        [
            (placemark.subThoroughfare, 4),
            (placemark.thoroughfare, 5),
            (placemark.subLocality, 4),
            (placemark.locality, 4),
            (placemark.subAdministrativeArea, 3),
            (placemark.administrativeArea, 2),
            (placemark.postalCode, 2),
            (placemark.name, 2)
        ].reduce(0) { score, field in
            score + (nonEmpty(field.0) == nil ? 0 : field.1)
        }
    }

    private func applyForeignPlacemarks(
        chinese: CLPlacemark?,
        english: CLPlacemark?,
        countryCode: String?
    ) {
        country = countryCode.flatMap {
            Locale(identifier: "zh_Hans_CN").localizedString(forRegionCode: $0)
        } ?? nonEmpty(chinese?.country) ?? "未知国家"
        city = nonEmpty(
            chinese?.locality ?? chinese?.subAdministrativeArea ?? chinese?.administrativeArea
        ) ?? "未知城市"
        postalCode = nonEmpty(english?.postalCode ?? chinese?.postalCode) ?? "—"
        timeZone = english?.timeZone ?? chinese?.timeZone

        let street = [english?.subThoroughfare, english?.thoroughfare]
            .compactMap { englishText($0) }
            .joined(separator: " ")
        let englishCountry = countryCode.flatMap {
            Locale(identifier: "en_GB").localizedString(forRegionCode: $0)
        } ?? englishText(english?.country)
        let components = [
            street.isEmpty ? englishText(english?.name) : street,
            englishText(english?.subLocality),
            englishText(english?.locality),
            englishText(english?.subAdministrativeArea),
            englishText(english?.administrativeArea),
            nonEmpty(english?.postalCode),
            englishCountry
        ]
        .compactMap { $0 }
        .reduce(into: [String]()) { result, value in
            guard !result.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return }
            result.append(value)
        }
        formattedAddress = components.isEmpty ? "Address unavailable" : components.joined(separator: ", ")
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func englishText(_ value: String?) -> String? {
        guard let value = nonEmpty(value) else { return nil }
        return value.applyingTransform(.toLatin, reverse: false) ?? value
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
                                Text(routeProgressText)
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

                        routeRuntimeOptions
                    }
                    .padding(.horizontal, 4)
                }

                HStack(spacing: 0) {
                    trayIcon("slider.horizontal.3") { showSettings = true }
                    routeButton
                    joystickButton
                    if session.canResumeRoute {
                        pausedRouteControls
                    } else if showsCrosshairSessionControls {
                        crosshairSessionControls
                            .padding(.leading, 6)
                    } else {
                        sessionControl
                            .padding(.leading, 6)
                    }
                }
        }
        .padding(4)
        .locusGlass(.regular, in: trayShape)
        .contentShape(trayShape)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(minHeight: MapChromeLayout.primaryHeight)
        .simultaneousGesture(TapGesture().onEnded {
            NotificationCenter.default.post(name: .locusDismissStatusDetails, object: nil)
        })
        .animation(.easeOut(duration: 0.18), value: session.joystickActive)
    }

    private var routeRuntimeOptions: some View {
        VStack(spacing: 8) {
            TravelModeSelector(compact: true)

            HStack(spacing: 10) {
                Toggle(isOn: $session.routeLoopEnabled) {
                    Label("循环", systemImage: "repeat")
                        .font(.caption.weight(.semibold))
                }
                .toggleStyle(.switch)

                Spacer(minLength: 0)
                loopCountControl
            }
        }
    }

    private var routeProgressText: String {
        let lap = max(1, session.routeLap)
        let progress = Int(session.routeProgress * 100)
        if session.routeLoopEnabled {
            return "第 \(lap)/\(session.routeLoopCount) 圈 · \(progress)%"
        }
        return "第 \(lap) 圈 · \(progress)%"
    }

    private var loopCountControl: some View {
        HStack(spacing: 0) {
            Button {
                session.routeLoopCount = max(minimumLoopCount, session.routeLoopCount - 1)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 32, height: 30)
            }
            .disabled(!session.routeLoopEnabled || session.routeLoopCount <= minimumLoopCount)

            Text("共 \(session.routeLoopCount) 圈")
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(minWidth: 58)

            Button {
                session.routeLoopCount = min(99, session.routeLoopCount + 1)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 32, height: 30)
            }
            .disabled(!session.routeLoopEnabled || session.routeLoopCount >= 99)
        }
        .buttonStyle(.plain)
        .foregroundStyle(session.routeLoopEnabled ? Color.primary : Color.secondary)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .contentShape(Capsule())
        .opacity(session.routeLoopEnabled ? 1 : 0.55)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("循环次数，共 \(session.routeLoopCount) 圈")
    }

    private var minimumLoopCount: Int {
        max(2, session.routeLap)
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
            Image(systemName: "circle.grid.cross.fill")
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
            .frame(height: 48)
            .padding(.horizontal, 8)
            .locusGlass(.interactive, tint: sessionControlColor, in: Capsule())
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

    private var showsCrosshairSessionControls: Bool {
        session.targetSelectionMode == .crosshair &&
            !session.routeActive &&
            !session.routePaused
    }

    @ViewBuilder
    private var crosshairSessionControls: some View {
        if session.isSpoofing {
            HStack(spacing: 6) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    session.stop(pairing: pairing)
                } label: {
                    Text("停止")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .locusGlass(.interactive, tint: LocusTheme.danger, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    guard let target = session.crosshairCoordinate else {
                        session.lastError = "尚未取得准星位置，请先移动地图。"
                        return
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    session.teleport(to: target, pairing: pairing)
                } label: {
                    Text("应用当前位置")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .locusGlass(.interactive, tint: LocusTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(session.crosshairCoordinate == nil || session.isBusy)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 6) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    performSessionAction()
                } label: {
                    Text("开始定位")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .locusGlass(.interactive, tint: LocusTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(session.crosshairCoordinate == nil || session.isBusy)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    NotificationCenter.default.post(name: .locusBuildRouteToTarget, object: nil)
                } label: {
                    Text("生成轨迹")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .locusGlass(.interactive, tint: Color.blue, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(session.crosshairCoordinate == nil || session.isBusy)
            }
            .frame(maxWidth: .infinity)
        }
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
                    .frame(height: 48)
                    .locusGlass(.interactive, tint: LocusTheme.danger, in: Capsule())
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
                    .frame(height: 48)
                    .locusGlass(.interactive, tint: LocusTheme.accent, in: Capsule())
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
            guard let target = session.selectedTargetCoordinate else {
                session.lastError = session.targetSelectionMode == .crosshair
                    ? "尚未取得准星位置，请先移动地图。"
                    : "请先点击地图放置图钉。"
                return
            }
            session.teleport(to: target, pairing: pairing)
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
