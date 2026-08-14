import CoreLocation
import Foundation
import MapKit
import UIKit
import UserNotifications

enum TravelMode: String, CaseIterable, Identifiable {
    case walk, run, cycle, drive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walk: return "步行"
        case .run: return "跑步"
        case .cycle: return "骑行"
        case .drive: return "驾车"
        }
    }

    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .run: return "figure.run"
        case .cycle: return "bicycle"
        case .drive: return "car.fill"
        }
    }

    /// Base meters per second before natural variation.
    var baseSpeed: CLLocationSpeed {
        switch self {
        case .walk: return 1.4
        case .run: return 3.3
        case .cycle: return 6.5
        case .drive: return 13.4
        }
    }

    var mkTransportType: MKDirectionsTransportType {
        switch self {
        case .walk, .run: return .walking
        case .cycle, .drive: return .automobile
        }
    }
}

enum SpoofStatus: Equatable {
    case idle
    case connecting
    case active
    case reconnecting
    case dropped(String)

    var label: String {
        switch self {
        case .idle: return "未模拟定位"
        case .connecting: return "正在启动…"
        case .active: return "正在模拟定位"
        case .reconnecting: return "正在重新连接…"
        case .dropped: return "连接中断"
        }
    }

    var isDropped: Bool {
        if case .dropped = self { return true }
        return false
    }
}

@MainActor
final class SpoofSession: ObservableObject {
    @Published var status: SpoofStatus = .idle
    @Published var pin: CLLocationCoordinate2D?
    @Published var simulated: CLLocationCoordinate2D?
    @Published var travelMode: TravelMode = .walk
    @Published var mapStyleIndex: Int = 0
    @Published var lastError: String?
    @Published var isBusy = false
    @Published var joystickActive = false
    @Published private(set) var routeActive = false
    @Published private(set) var routePaused = false
    @Published private(set) var routeProgress = 0.0
    @Published private(set) var routeLap = 0
    @Published var speedMultiplier: Double = 1.0 {
        didSet { UserDefaults.standard.set(speedMultiplier, forKey: "locus.speedMultiplier") }
    }
    @Published var routeLoopEnabled = false {
        didSet { UserDefaults.standard.set(routeLoopEnabled, forKey: "locus.routeLoopEnabled") }
    }

    @Published var favorites: [SavedPlace] = []
    @Published var recents: [SavedPlace] = []

    private var resendTimer: Timer?
    private var healthTimer: Timer?
    private var joystickTimer: Timer?
    private var routeTask: Task<Void, Never>?
    private var activeRoute: [CLLocationCoordinate2D] = []
    private var routeGeneration = UUID()
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var joystickVector: CGVector = .zero
    private let locationKeeper = BackgroundKeepAlive()

    private let favoritesKey = "locus.favorites"
    private let recentsKey = "locus.recents"
    private let favoriteMatchTolerance: CLLocationDistance = 8
    private let countryLookupRetryDelay: TimeInterval = 15 * 60
    private var countryLookupRunning = false

    init() {
        favorites = SavedPlace.load(key: favoritesKey)
        recents = SavedPlace.load(key: recentsKey)
        let storedSpeed = UserDefaults.standard.double(forKey: "locus.speedMultiplier")
        speedMultiplier = storedSpeed > 0 ? min(4.0, max(0.25, storedSpeed)) : 1.0
        routeLoopEnabled = UserDefaults.standard.bool(forKey: "locus.routeLoopEnabled")
    }

    var isSpoofing: Bool {
        if case .active = status { return true }
        if case .reconnecting = status { return true }
        return false
    }

    func teleport(to coordinate: CLLocationCoordinate2D, pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = "请先在设置中导入 RPPairing 文件。"
            return
        }
        pin = coordinate
        apply(coordinate, pairing: pairing, markRecent: true)
    }

    var isMoving: Bool { routeActive || joystickActive }
    var canResumeRoute: Bool { routePaused && activeRoute.count >= 2 && simulated != nil }

    func adjustSpeed(by delta: Double) {
        speedMultiplier = min(4.0, max(0.25, speedMultiplier + delta))
    }

    /// First press while moving freezes at the current simulated coordinate.
    /// A later press clears the developer-location override and returns to GPS.
    func stop(pairing: PairingStore) {
        if isMoving {
            stopMovement()
            return
        }
        stopResend()
        stopHealth()
        isBusy = true
        let result = LocationEngine.clear()
        isBusy = false
        switch result {
        case .success:
            simulated = nil
            status = .idle
            endBackground()
            // Keep location updates running so the map puck / locate button
            // can return to the real GPS fix (not the leftover pin).
            locationKeeper.start()
        case .failure(let error):
            lastError = error.localizedDescription
            status = .dropped(error.localizedDescription)
            postDropNotification(error.localizedDescription)
        }
    }

    /// Best-known real device coordinate (not the teleport pin).
    var realCoordinate: CLLocationCoordinate2D? {
        locationKeeper.lastKnownCoordinate
    }

    /// Real GPS fix converted for display on Apple map tiles.
    var realMapCoordinate: CLLocationCoordinate2D? {
        realCoordinate.map(ChinaCoordinateTransform.systemCoordinateToMapCoordinate)
    }

    /// Start lightweight GPS updates for the map puck / locate button.
    func startLocationUpdates() {
        locationKeeper.start()
    }

    func startJoystick(pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = "请先在设置中导入 RPPairing 文件。"
            return
        }
        routeTask?.cancel()
        routeTask = nil
        routeActive = false
        routePaused = false
        activeRoute.removeAll()
        let start = simulated ?? pin ?? realMapCoordinate
        guard let start else {
            lastError = "使用摇杆前请先放置图钉或开始模拟定位。"
            return
        }
        if simulated == nil {
            apply(start, pairing: pairing, markRecent: false)
        }
        joystickActive = true
        joystickTimer?.invalidate()
        joystickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickJoystick(pairing: pairing)
            }
        }
    }

    func updateJoystick(vector: CGVector) {
        joystickVector = vector
    }

    func stopMovement() {
        let wasRouting = routeActive
        routeGeneration = UUID()
        routeTask?.cancel()
        routeTask = nil
        routeActive = false
        routePaused = wasRouting && activeRoute.count >= 2
        stopJoystick()
    }

    func resumeRoute(pairing: PairingStore) {
        guard canResumeRoute, let current = simulated else { return }
        let nearest = activeRoute.indices.min { lhs, rhs in
            Self.distance(from: current, to: activeRoute[lhs]) < Self.distance(from: current, to: activeRoute[rhs])
        } ?? activeRoute.startIndex
        var remaining = [current]
        remaining.append(contentsOf: activeRoute[nearest...])
        guard remaining.count >= 2 else { return }
        startRoute(remaining, pairing: pairing, preserveOriginalRoute: true)
    }

    func stopJoystick() {
        joystickActive = false
        joystickVector = .zero
        joystickTimer?.invalidate()
        joystickTimer = nil
    }

    func followRoute(_ coordinates: [CLLocationCoordinate2D], pairing: PairingStore) {
        guard pairing.hasPairingFile, coordinates.count >= 2 else { return }
        activeRoute = coordinates
        routeProgress = 0
        routeLap = 0
        startRoute(coordinates, pairing: pairing, preserveOriginalRoute: true)
    }

    private func startRoute(
        _ coordinates: [CLLocationCoordinate2D],
        pairing: PairingStore,
        preserveOriginalRoute: Bool
    ) {
        routeGeneration = UUID()
        let generation = routeGeneration
        routeTask?.cancel()
        stopJoystick()
        routeActive = true
        routePaused = false
        if !preserveOriginalRoute { activeRoute = coordinates }
        let mode = travelMode
        routeTask = Task { [weak self] in
            guard let self else { return }
            var firstPass = true
            var lap = 0
            repeat {
                if Task.isCancelled { break }
                lap += 1
                self.routeLap = lap
                var previous = coordinates[0]
                self.apply(previous, pairing: pairing, markRecent: firstPass)
                firstPass = false

                for (segmentIndex, next) in coordinates.dropFirst().enumerated() {
                    if Task.isCancelled { break }
                    let distance = Self.distance(from: previous, to: next)
                    var speed = mode.baseSpeed * self.speedMultiplier * Double.random(in: 0.88...1.12)
                    speed = max(0.2, speed)
                    let stepMeters: CLLocationDistance = min(12, max(1, speed * 0.5))
                    let steps = max(1, Int(ceil(distance / stepMeters)))
                    for i in 1...steps {
                        if Task.isCancelled { break }
                        let t = Double(i) / Double(steps)
                        let coord = CLLocationCoordinate2D(
                            latitude: previous.latitude + (next.latitude - previous.latitude) * t,
                            longitude: previous.longitude + (next.longitude - previous.longitude) * t
                        )
                        speed = max(0.2, mode.baseSpeed * self.speedMultiplier * Double.random(in: 0.94...1.06))
                        let delay = max(0.05, stepMeters / speed)
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        if Task.isCancelled { break }
                        self.apply(coord, pairing: pairing, markRecent: false)
                        self.routeProgress = min(1, (Double(segmentIndex) + t) / Double(max(1, coordinates.count - 1)))
                    }
                    previous = next
                }
                if self.routeLoopEnabled { self.routeProgress = 0 }
            } while self.routeLoopEnabled && !Task.isCancelled
            guard self.routeGeneration == generation else { return }
            self.routeTask = nil
            self.routeActive = false
            self.routePaused = false
        }
    }

    private static func distance(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
    }

    func favorite(at coordinate: CLLocationCoordinate2D) -> SavedPlace? {
        favorites.first {
            Self.distance(from: $0.coordinate, to: coordinate) <= favoriteMatchTolerance
        }
    }

    func favoriteDisplayName(_ place: SavedPlace) -> String {
        if place.nameIsUserEdited == true { return place.name }
        Self.isGenericFavoriteName(place.name) ? "收藏地点" : place.name
    }

    @discardableResult
    func toggleFavorite(name: String, coordinate: CLLocationCoordinate2D) -> (added: Bool, name: String) {
        if let existing = favorite(at: coordinate) {
            let displayName = favoriteDisplayName(existing)
            removeFavorite(existing)
            return (false, displayName)
        }
        addFavorite(name: name, coordinate: coordinate)
        return (true, favorite(at: coordinate).map(favoriteDisplayName) ?? "收藏地点")
    }

    func addFavorite(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: Self.isGenericFavoriteName(trimmed) ? "收藏地点" : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            nameIsUserEdited: false
        )
        // Don't let a generic star overwrite a named favorite for the same spot.
        if let existing = favorite(at: coordinate),
           Self.isGenericFavoriteName(place.name),
           !Self.isGenericFavoriteName(existing.name) {
            return
        }
        favorites.removeAll {
            Self.distance(from: $0.coordinate, to: coordinate) <= favoriteMatchTolerance
        }
        favorites.insert(place, at: 0)
        SavedPlace.save(favorites, key: favoritesKey)
        Task { await backfillFavoriteCountries() }
    }

    func renameFavorite(_ place: SavedPlace, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = favorites.firstIndex(where: { $0.id == place.id }) else { return }
        favorites[index].name = trimmed
        favorites[index].nameIsUserEdited = true
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeFavorite(_ place: SavedPlace) {
        favorites.removeAll { $0.id == place.id }
        SavedPlace.save(favorites, key: favoritesKey)
    }

    func removeRecent(_ place: SavedPlace) {
        recents.removeAll { $0.id == place.id }
        SavedPlace.save(recents, key: recentsKey)
    }

    func backfillFavoriteCountries() async {
        guard !countryLookupRunning else { return }
        countryLookupRunning = true
        defer { countryLookupRunning = false }

        while !Task.isCancelled,
              let favorite = favorites.first(where: { shouldLookupCountry(for: $0) }) {
            let canContinue = await resolveFavoriteMetadata(for: favorite.id)
            guard canContinue, !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func shouldLookupCountry(for favorite: SavedPlace) -> Bool {
        guard favorite.countryName == nil else { return false }
        guard let lastAttempt = favorite.countryLookupLastAttempt else { return true }
        return Date().timeIntervalSince(lastAttempt) >= countryLookupRetryDelay
    }

    /// Returns false after a transient failure so the queue does not hammer the service.
    private func resolveFavoriteMetadata(for favoriteID: String) async -> Bool {
        guard let index = favorites.firstIndex(where: { $0.id == favoriteID }),
              shouldLookupCountry(for: favorites[index]) else { return true }

        favorites[index].countryLookupLastAttempt = Date()
        favorites[index].countryLookupAttempted = false
        SavedPlace.save(favorites, key: favoritesKey)

        let favorite = favorites[index]
        let mapCoordinate = favorite.coordinate
        let systemCoordinate = ChinaCoordinateTransform.mapCoordinateToSystemCoordinate(mapCoordinate)
        let location = CLLocation(latitude: systemCoordinate.latitude, longitude: systemCoordinate.longitude)

        do {
            let geocoder = CLGeocoder()
            let placemarks = try await geocoder.reverseGeocodeLocation(
                location,
                preferredLocale: Locale(identifier: "zh_Hans_CN")
            )
            guard let placemark = placemarks.first else {
                markCountryLookupFailed(for: favoriteID)
                return true
            }
            guard let index = favorites.firstIndex(where: { $0.id == favoriteID }) else { return true }
            let countryCode = placemark.isoCountryCode
            let localizedCountry = countryCode.flatMap {
                Locale(identifier: "zh_Hans_CN").localizedString(forRegionCode: $0)
            }
            favorites[index].countryCode = countryCode
            favorites[index].countryName = localizedCountry ?? placemark.country
            favorites[index].countryLookupAttempted = true

            if favorites[index].nameIsUserEdited != true,
               Self.isGenericFavoriteName(favorites[index].name) {
                let resolvedName = [placemark.name, placemark.subLocality, placemark.locality]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty }
                favorites[index].name = resolvedName ?? "收藏地点"
            }
            SavedPlace.save(favorites, key: favoritesKey)
            return true
        } catch {
            if Task.isCancelled {
                clearCancelledCountryLookup(for: favoriteID)
                return false
            }
            markCountryLookupFailed(for: favoriteID)
            return false
        }
    }

    private func clearCancelledCountryLookup(for favoriteID: String) {
        guard let index = favorites.firstIndex(where: { $0.id == favoriteID }) else { return }
        favorites[index].countryLookupLastAttempt = nil
        favorites[index].countryLookupAttempted = nil
        SavedPlace.save(favorites, key: favoritesKey)
    }

    private func markCountryLookupFailed(for favoriteID: String) {
        guard let index = favorites.firstIndex(where: { $0.id == favoriteID }) else { return }
        favorites[index].countryLookupAttempted = false
        SavedPlace.save(favorites, key: favoritesKey)
    }

    /// Best display name for starring the current pin (search title, matching recent, etc.).
    func suggestedFavoriteName(for coordinate: CLLocationCoordinate2D, fallback: String? = nil) -> String {
        if let fallback, !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let favorite = favorite(at: coordinate),
           !Self.isGenericFavoriteName(favorite.name) {
            return favorite.name
        }
        if let recent = recents.first(where: {
            abs($0.latitude - coordinate.latitude) < 0.00015 && abs($0.longitude - coordinate.longitude) < 0.00015
        }), !Self.isGenericFavoriteName(recent.name) {
            return recent.name
        }
        return "收藏地点"
    }

    private static func coordinateLabel(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private static func isGenericFavoriteName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Favorite" || trimmed == "收藏地点" { return true }
        // Coordinate-looking labels from older teleports.
        let parts = trimmed.split(separator: ",")
        if parts.count == 2,
           Double(parts[0].trimmingCharacters(in: .whitespaces)) != nil,
           Double(parts[1].trimmingCharacters(in: .whitespaces)) != nil {
            return true
        }
        return false
    }

    private func apply(_ coordinate: CLLocationCoordinate2D, pairing: PairingStore, markRecent: Bool) {
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude.isFinite, coordinate.longitude.isFinite else {
            lastError = "所选地图坐标无效，请重新放置图钉。"
            return
        }
        if status == .idle || status.isDropped {
            status = .connecting
        }
        isBusy = true
        let systemCoordinate = ChinaCoordinateTransform.mapCoordinateToSystemCoordinate(coordinate)
        let result = LocationEngine.set(
            latitude: systemCoordinate.latitude,
            longitude: systemCoordinate.longitude,
            pairingPath: pairing.pairingPath,
            deviceIP: TunnelConfig.targetIP
        )
        isBusy = false
        switch result {
        case .success:
            simulated = coordinate
            pin = coordinate
            status = .active
            lastError = nil
            beginBackground()
            locationKeeper.start()
            startResend(pairing: pairing)
            startHealth(pairing: pairing)
            if markRecent {
                pushRecent(coordinate)
            }
        case .failure(let error):
            lastError = error.localizedDescription
            if simulated != nil {
                status = .dropped(error.localizedDescription)
                postDropNotification(error.localizedDescription)
            } else {
                status = .idle
            }
        }
    }

    private func tickJoystick(pairing: PairingStore) {
        guard joystickActive, let current = simulated else { return }
        let magnitude = hypot(joystickVector.dx, joystickVector.dy)
        guard magnitude > 0.08 else { return }
        let nx = joystickVector.dx / magnitude
        let ny = -joystickVector.dy / magnitude
        let speed = travelMode.baseSpeed * speedMultiplier * min(1.0, magnitude) * Double.random(in: 0.9...1.1)
        let dt = 0.25
        let meters = speed * dt
        let next = offset(coordinate: current, eastMeters: nx * meters, northMeters: ny * meters)
        apply(next, pairing: pairing, markRecent: false)
    }

    private func startResend(pairing: PairingStore) {
        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let sim = self.simulated else { return }
                let systemCoordinate = ChinaCoordinateTransform.mapCoordinateToSystemCoordinate(sim)
                _ = LocationEngine.set(
                    latitude: systemCoordinate.latitude,
                    longitude: systemCoordinate.longitude,
                    pairingPath: pairing.pairingPath,
                    deviceIP: TunnelConfig.targetIP
                )
            }
        }
    }

    private func stopResend() {
        resendTimer?.invalidate()
        resendTimer = nil
    }

    private func startHealth(pairing: PairingStore) {
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let sim = self.simulated else { return }
                if case .dropped = self.status {
                    self.status = .reconnecting
                    self.apply(sim, pairing: pairing, markRecent: false)
                } else if !LocationEngine.isSessionActive, self.isSpoofing {
                    self.status = .reconnecting
                    self.apply(sim, pairing: pairing, markRecent: false)
                }
            }
        }
    }

    private func stopHealth() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    private func pushRecent(_ coordinate: CLLocationCoordinate2D) {
        pushNamedRecent(
            name: Self.coordinateLabel(coordinate),
            coordinate: coordinate
        )
    }

    func pushNamedRecent(name: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = SavedPlace(
            name: trimmed.isEmpty ? Self.coordinateLabel(coordinate) : trimmed,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        recents.removeAll {
            abs($0.latitude - place.latitude) < 0.00015 && abs($0.longitude - place.longitude) < 0.00015
        }
        recents.insert(place, at: 0)
        if recents.count > 20 { recents = Array(recents.prefix(20)) }
        SavedPlace.save(recents, key: recentsKey)
    }

    private func beginBackground() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackground()
        }
    }

    private func endBackground() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func postDropNotification(_ message: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "Locus 模拟定位已断开"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func offset(coordinate: CLLocationCoordinate2D, eastMeters: Double, northMeters: Double) -> CLLocationCoordinate2D {
        let earth = 6378137.0
        let dLat = northMeters / earth * (180 / .pi)
        let dLon = eastMeters / (earth * cos(coordinate.latitude * .pi / 180)) * (180 / .pi)
        return CLLocationCoordinate2D(latitude: coordinate.latitude + dLat, longitude: coordinate.longitude + dLon)
    }
}
