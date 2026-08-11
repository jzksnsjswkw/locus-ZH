import CoreLocation
import Foundation

final class BackgroundKeepAlive: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var lastKnownLocation: CLLocation?

    var lastKnownCoordinate: CLLocationCoordinate2D? {
        lastKnownLocation?.coordinate
    }

    override init() {
        super.init()
        manager.delegate = self
        // The previous 3 km setting made “locate me” start from a very coarse fix.
        // Navigation-grade updates let the map converge to the device's real position.
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = false
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        case .restricted, .denied:
            return
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            return
        }
        manager.startUpdatingLocation()
        manager.requestLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            manager.startUpdatingLocation()
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let now = Date()
        let candidates = locations.filter { location in
            location.horizontalAccuracy >= 0 &&
            location.horizontalAccuracy <= 200 &&
            abs(location.timestamp.timeIntervalSince(now)) <= 15
        }
        guard let best = candidates.min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) else { return }

        if let current = lastKnownLocation,
           current.timestamp > best.timestamp,
           current.horizontalAccuracy <= best.horizontalAccuracy {
            return
        }
        lastKnownLocation = best
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient location failures are expected while permissions or GPS settle.
    }
}
