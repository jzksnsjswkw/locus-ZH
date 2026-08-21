import ActivityKit
import CoreLocation
import Foundation

@available(iOS 16.2, *)
actor LocusLiveActivityController {
    static let shared = LocusLiveActivityController()
    static let statusKey = "locus.liveActivityLastStatus"

    private var currentActivity: Activity<LocusActivityAttributes>?
    private let geocoder = CLGeocoder()
    private var geocodedLocation: CLLocation?
    private var lastGeocodeAttempt: Date?
    private var lastPublishedAt: Date?
    private var lastPublishedStatus: String?
    private var registrationBlocked = false
    private var regionLookupTask: Task<Void, Never>?
    private var city = "正在获取位置"
    private var country = ""

    func sync(
        isActive: Bool,
        status: String,
        coordinate: CLLocationCoordinate2D?,
        distanceTraveled: CLLocationDistance,
        elapsedTime: TimeInterval,
        allowRegionLookup: Bool
    ) async {
        guard isActive, let coordinate else {
            await end()
            recordStatus("等待模拟定位")
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await end()
            recordStatus("系统未允许实时活动")
            return
        }
        guard !registrationBlocked else {
            recordStatus("LiveContainer 未向系统注册实时活动扩展")
            return
        }
        if !allowRegionLookup {
            regionLookupTask?.cancel()
            regionLookupTask = nil
            geocoder.cancelGeocode()
        }

        if currentActivity == nil {
            currentActivity = Activity<LocusActivityAttributes>.activities.first
        }

        let now = Date()
        if currentActivity != nil,
           lastPublishedStatus == status,
           let lastPublishedAt,
           now.timeIntervalSince(lastPublishedAt) < 5 {
            return
        }

        let lookupCoordinate = ChinaCoordinateTransform.mapCoordinateToSystemCoordinate(coordinate)
        let location = CLLocation(latitude: lookupCoordinate.latitude, longitude: lookupCoordinate.longitude)
        if allowRegionLookup, shouldReverseGeocode(location) {
            // Region text is secondary: never delay creation or metric updates while
            // Apple reverse geocoding is slow, offline, or rate-limited.
            regionLookupTask?.cancel()
            regionLookupTask = Task { await reverseGeocode(location) }
        }

        let state = LocusActivityAttributes.ContentState(
            status: status,
            coordinate: String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude),
            distance: Self.formatDistance(distanceTraveled),
            elapsed: Self.formatElapsedTime(elapsedTime),
            city: city,
            country: country
        )
        let content = ActivityContent(state: state, staleDate: nil, relevanceScore: 80)

        if let currentActivity {
            await currentActivity.update(content)
            lastPublishedAt = now
            lastPublishedStatus = status
            recordStatus("运行中")
            return
        }

        do {
            currentActivity = try Activity.request(
                attributes: LocusActivityAttributes(title: "Locus"),
                content: content,
                pushType: nil
            )
            lastPublishedAt = now
            lastPublishedStatus = status
            recordStatus("运行中")
        } catch {
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("NSSupportsLiveActivities") {
                registrationBlocked = true
                recordStatus("LiveContainer 未向系统注册实时活动扩展")
            } else {
                recordStatus("启动失败：\(message)")
            }
            NSLog("[Locus] Live Activity start failed: %@", message)
        }
    }

    private func shouldReverseGeocode(_ location: CLLocation) -> Bool {
        guard let geocodedLocation else { return true }
        if location.distance(from: geocodedLocation) >= 5_000 { return true }
        guard city == "未知城市",
              let lastGeocodeAttempt else { return false }
        return Date().timeIntervalSince(lastGeocodeAttempt) >= 300
    }

    private func reverseGeocode(_ location: CLLocation) async {
        geocodedLocation = location
        lastGeocodeAttempt = Date()
        do {
            let placemark = try await geocoder.reverseGeocodeLocation(location).first
            guard !Task.isCancelled else { return }
            city = placemark?.locality ?? placemark?.administrativeArea ?? "未知城市"
            country = placemark?.country ?? "未知国家"
        } catch {
            guard !Task.isCancelled else { return }
            city = "未知城市"
            country = "未知国家"
        }
    }

    private static func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1_000 {
            return "\(Int(max(0, meters).rounded())) 米"
        }
        return String(format: "%.2f km", meters / 1_000)
    }

    private static func formatElapsedTime(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func end() async {
        let activities = Activity<LocusActivityAttributes>.activities
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
        regionLookupTask?.cancel()
        regionLookupTask = nil
        geocoder.cancelGeocode()
        lastPublishedAt = nil
        lastPublishedStatus = nil
    }

    private func recordStatus(_ status: String) {
        guard UserDefaults.standard.string(forKey: Self.statusKey) != status else { return }
        UserDefaults.standard.set(status, forKey: Self.statusKey)
    }
}
