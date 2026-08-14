import ActivityKit
import CoreLocation
import Foundation

actor LocusLiveActivityController {
    static let shared = LocusLiveActivityController()
    static let statusKey = "locus.liveActivityLastStatus"
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
        guard isEnabled else {
            await end()
            recordStatus("已关闭")
            return
        }
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
            recordStatus("启动失败：\(error.localizedDescription)")
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

    private func recordStatus(_ status: String) {
        guard UserDefaults.standard.string(forKey: Self.statusKey) != status else { return }
        UserDefaults.standard.set(status, forKey: Self.statusKey)
    }
}
