import Foundation
import CoreLocation

enum LocationEngineError: LocalizedError {
    case locationSet
    case locationClear
    case notActive

    var errorDescription: String? {
        switch self {
        case .locationSet: return "Failed to set simulated coordinates."
        case .locationClear: return "Failed to clear simulated location."
        case .notActive: return "No active simulation session."
        }
    }
}

/// Thin Swift wrapper around CLSimulationManager — the same private API Geranium,
/// Andromeda and udevs' locsim use to inject coordinates into locationd system-wide.
/// Requires the com.apple.locationd.simulation entitlement (TrollStore preserves it).
/// No pairing file, no developer tunnel, no Developer Mode needed.
enum LocationEngine {
    private static let queue = DispatchQueue(label: "com.chrismack.locus.location", qos: .userInitiated)

    private static let simManager = CLSimulationManager()
    private static var active = false

    static var isSessionActive: Bool { active }

    static func set(latitude: Double, longitude: Double) -> Result<Void, LocationEngineError> {
        var result: Result<Void, LocationEngineError> = .failure(.locationSet)
        queue.sync {
            let location = CLLocation(latitude: latitude, longitude: longitude)
            simManager.stopLocationSimulation()
            simManager.clearSimulatedLocations()
            simManager.appendSimulatedLocation(location)
            simManager.flush()
            simManager.startLocationSimulation()
            postTimezoneUpdate()
            active = true
            result = .success(())
        }
        return result
    }

    static func clear() -> Result<Void, LocationEngineError> {
        var result: Result<Void, LocationEngineError> = .failure(.notActive)
        queue.sync {
            simManager.stopLocationSimulation()
            simManager.clearSimulatedLocations()
            simManager.flush()
            postTimezoneUpdate()
            active = false
            result = .success(())
        }
        return result
    }

    private static func postTimezoneUpdate() {
        CFNotificationCenterPostNotificationWithOptions(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("AutomaticTimeZoneUpdateNeeded" as CFString),
            nil,
            nil,
            kCFNotificationDeliverImmediately
        )
    }
}