import ActivityKit
import CoreLocation
import Foundation

actor LocusLiveActivityController {
    static let shared = LocusLiveActivityController()
    private static let enabledKey = "locus.liveActivityEnabled"

    private var currentActivity: Activity<LocusActivityAttributes>?
    private let geocoder = CLGeocoder()
    private var geocodedLocation: CLLocation?
    private var lastGeocodeAttempt: Date?
    private var lastPublishedAt: Date?
    private var lastPublishedStatus: String?
    private var city = "正在获取位置"
    private var country = ""

    func sync(isActive: Bool, status: String, coordinate: CLLocationCoordinate2D?) async {
        let storedPreference = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool
        let isEnabled = storedPreference ?? true
        guard isEnabled, isActive, let coordinate else {
            await end()
            return
        }

        if currentActivity == nil {
            currentActivity = Activity<LocusActivityAttributes>.activities.first
        }

        let now = Date()
        if currentActivity != nil,
           lastPublishedStatus == status,
           let lastPublishedAt,
           now.timeIntervalSince(lastPublishedAt) < 10 {
            return
        }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if shouldReverseGeocode(location) {
            await reverseGeocode(location)
        }

        let state = LocusActivityAttributes.ContentState(
            status: status,
            coordinate: String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude),
            city: city,
            country: country
        )
        let content = ActivityContent(state: state, staleDate: nil, relevanceScore: 80)

        if let currentActivity {
            await currentActivity.update(content)
            lastPublishedAt = now
            lastPublishedStatus = status
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            currentActivity = try Activity.request(
                attributes: LocusActivityAttributes(title: "Locus"),
                content: content,
                pushType: nil
            )
            lastPublishedAt = now
            lastPublishedStatus = status
        } catch {
            NSLog("[Locus] Live Activity start failed: %@", error.localizedDescription)
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
            city = placemark?.locality ?? placemark?.administrativeArea ?? "未知城市"
            country = placemark?.country ?? "未知国家"
        } catch {
            city = "未知城市"
            country = "未知国家"
        }
    }

    private func end() async {
        let activities = Activity<LocusActivityAttributes>.activities
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
        lastPublishedAt = nil
        lastPublishedStatus = nil
    }
}
