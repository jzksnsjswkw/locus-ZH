import CoreLocation
import Foundation

/// Converts coordinates selected on Apple's mainland-China map tiles (GCJ-02)
/// into the WGS-84 coordinates expected by the developer location service.
enum ChinaCoordinateTransform {
    private static let semiMajorAxis = 6_378_245.0
    private static let eccentricitySquared = 0.00669342162296594323

    static func mapCoordinateToSystemCoordinate(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard usesMainlandChinaOffset(coordinate) else { return coordinate }

        // Iteratively invert WGS-84 -> GCJ-02. A few iterations converge to
        // sub-centimetre error and avoid the visible 400-700 m displacement.
        var estimate = coordinate
        for _ in 0..<8 {
            let projected = wgs84ToGCJ02(estimate)
            estimate.latitude -= projected.latitude - coordinate.latitude
            estimate.longitude -= projected.longitude - coordinate.longitude
        }
        return estimate
    }

    static func usesMainlandChinaOffset(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.longitude >= 72.004 && coordinate.longitude <= 137.8347 &&
        coordinate.latitude >= 0.8293 && coordinate.latitude <= 55.8271
    }

    private static func wgs84ToGCJ02(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard usesMainlandChinaOffset(coordinate) else { return coordinate }

        var latitudeDelta = transformLatitude(
            longitude: coordinate.longitude - 105.0,
            latitude: coordinate.latitude - 35.0
        )
        var longitudeDelta = transformLongitude(
            longitude: coordinate.longitude - 105.0,
            latitude: coordinate.latitude - 35.0
        )
        let radians = coordinate.latitude / 180.0 * .pi
        let sine = sin(radians)
        var magic = 1.0 - eccentricitySquared * sine * sine
        let squareRootMagic = sqrt(magic)
        latitudeDelta = latitudeDelta * 180.0 /
            ((semiMajorAxis * (1.0 - eccentricitySquared)) / (magic * squareRootMagic) * .pi)
        longitudeDelta = longitudeDelta * 180.0 /
            (semiMajorAxis / squareRootMagic * cos(radians) * .pi)

        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + latitudeDelta,
            longitude: coordinate.longitude + longitudeDelta
        )
    }

    private static func transformLatitude(longitude x: Double, latitude y: Double) -> Double {
        var result = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y +
            0.1 * x * y + 0.2 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        result += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        result += (160.0 * sin(y / 12.0 * .pi) + 320.0 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return result
    }

    private static func transformLongitude(longitude x: Double, latitude y: Double) -> Double {
        var result = 300.0 + x + 2.0 * y + 0.1 * x * x +
            0.1 * x * y + 0.1 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        result += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        result += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return result
    }
}
