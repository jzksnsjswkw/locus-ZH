import CoreLocation
import Foundation

enum TargetSelectionMode: String, CaseIterable, Codable, Identifiable {
    case pin
    case crosshair

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pin: return "红色图钉"
        case .crosshair: return "屏幕准星"
        }
    }

    var icon: String {
        switch self {
        case .pin: return "mappin"
        case .crosshair: return "scope"
        }
    }
}

struct SearchHistoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
    var visitedAt = Date()

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func load(key: String) -> [SearchHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SearchHistoryEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ entries: [SearchHistoryEntry], key: String) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
