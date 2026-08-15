import CoreLocation
import Foundation
import MapKit

struct PlannedRoute: Identifiable {
    let id = UUID()
    let coordinates: [CLLocationCoordinate2D]
    let distance: CLLocationDistance
    let expectedTravelTime: TimeInterval
}

enum RouteBuilder {
    static func roadRoute(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        mode: TravelMode
    ) async throws -> [CLLocationCoordinate2D] {
        let routes = try await roadRoutes(
            from: start,
            to: end,
            via: [],
            mode: mode,
            requestsAlternatives: false
        )
        return routes.first?.coordinates ?? sample(coordinates: [start, end], every: 10)
    }

    static func roadRoutes(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        via waypoints: [CLLocationCoordinate2D],
        mode: TravelMode,
        requestsAlternatives: Bool
    ) async throws -> [PlannedRoute] {
        let mapPoints = [start] + waypoints + [end]
        var candidates: [([CLLocationCoordinate2D], Bool)] = [(mapPoints, false)]
        if ChinaCoordinateTransform.usesMainlandChinaOffset(start) {
            candidates.append((
                mapPoints.map(ChinaCoordinateTransform.mapCoordinateToSystemCoordinate),
                true
            ))
        }

        for (candidatePoints, convertsBackToMapCoordinates) in candidates {
            var segmentOptions: [[PlannedRoute]] = []
            for (segmentStart, segmentEnd) in zip(candidatePoints, candidatePoints.dropFirst()) {
                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: segmentStart))
                request.destination = MKMapItem(placemark: MKPlacemark(coordinate: segmentEnd))
                request.transportType = mode.mkTransportType
                request.requestsAlternateRoutes = requestsAlternatives

                guard let response = try? await MKDirections(request: request).calculate(),
                      !response.routes.isEmpty else {
                    segmentOptions.removeAll()
                    break
                }

                let options = response.routes.prefix(requestsAlternatives ? 3 : 1).map { route in
                    var coordinates = sample(polyline: route.polyline, every: 12)
                    if convertsBackToMapCoordinates {
                        coordinates = coordinates.map(ChinaCoordinateTransform.systemCoordinateToMapCoordinate)
                    }
                    return PlannedRoute(
                        coordinates: coordinates,
                        distance: route.distance,
                        expectedTravelTime: route.expectedTravelTime
                    )
                }
                segmentOptions.append(options)
            }

            guard segmentOptions.count == mapPoints.count - 1 else { continue }
            let optionCount = min(3, segmentOptions.map(\.count).max() ?? 1)
            var combinedRoutes: [PlannedRoute] = []
            var signatures = Set<String>()

            for optionIndex in 0..<optionCount {
                var coordinates: [CLLocationCoordinate2D] = []
                var distance: CLLocationDistance = 0
                var expectedTravelTime: TimeInterval = 0
                for options in segmentOptions {
                    let segment = options[optionIndex < options.count ? optionIndex : 0]
                    coordinates.append(contentsOf: coordinates.isEmpty ? segment.coordinates[...] : segment.coordinates.dropFirst())
                    distance += segment.distance
                    expectedTravelTime += segment.expectedTravelTime
                }
                guard coordinates.count > 1 else { continue }
                let middle = coordinates[coordinates.count / 2]
                let signature = String(
                    format: "%.4f,%.4f-%d-%d",
                    middle.latitude,
                    middle.longitude,
                    Int(distance / 50),
                    Int(expectedTravelTime / 30)
                )
                guard signatures.insert(signature).inserted else { continue }
                combinedRoutes.append(PlannedRoute(
                    coordinates: coordinates,
                    distance: distance,
                    expectedTravelTime: expectedTravelTime
                ))
            }
            if !combinedRoutes.isEmpty { return combinedRoutes }
        }

        let fallback = sample(coordinates: mapPoints, every: 10)
        let distance = zip(mapPoints, mapPoints.dropFirst()).reduce(0.0) { result, pair in
            result + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        }
        return [PlannedRoute(
            coordinates: fallback,
            distance: distance,
            expectedTravelTime: distance / max(0.1, mode.baseSpeed)
        )]
    }

    static func sample(polyline: MKPolyline, every meters: CLLocationDistance) -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return sample(coordinates: coords, every: meters)
    }

    static func sample(coordinates: [CLLocationCoordinate2D], every meters: CLLocationDistance) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 1 else { return coordinates }
        var sampled = [coordinates[0]]
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            let dist = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            let steps = max(1, Int(ceil(dist / meters)))
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                sampled.append(CLLocationCoordinate2D(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t
                ))
            }
        }
        return sampled
    }
}

enum GPXCodec {
    static func parse(_ url: URL) throws -> [CLLocationCoordinate2D] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        var coords: [CLLocationCoordinate2D] = []
        let pattern = #"lat="([^"]+)"[^>]*lon="([^"]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match,
                  let latR = Range(match.range(at: 1), in: text),
                  let lonR = Range(match.range(at: 2), in: text),
                  let lat = Double(text[latR]),
                  let lon = Double(text[lonR]) else { return }
            coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        // Also support lon before lat
        if coords.isEmpty {
            let alt = #"lon="([^"]+)"[^>]*lat="([^"]+)""#
            let altRegex = try NSRegularExpression(pattern: alt)
            altRegex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match,
                      let lonR = Range(match.range(at: 1), in: text),
                      let latR = Range(match.range(at: 2), in: text),
                      let lon = Double(text[lonR]),
                      let lat = Double(text[latR]) else { return }
                coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }
        guard !coords.isEmpty else {
            throw NSError(domain: "Locus", code: 2, userInfo: [NSLocalizedDescriptionKey: "GPX 中未找到轨迹点"])
        }
        return coords
    }

    static func export(_ coordinates: [CLLocationCoordinate2D], name: String = "Locus Route") -> String {
        var body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Locus" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>\(name)</name>
            <trkseg>

        """
        for c in coordinates {
            body += String(format: "      <trkpt lat=\"%.6f\" lon=\"%.6f\"></trkpt>\n", c.latitude, c.longitude)
        }
        body += """
            </trkseg>
          </trk>
        </gpx>
        """
        return body
    }
}
