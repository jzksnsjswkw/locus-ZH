import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct LocusBackup: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var exportedAt = Date()
    var favorites: [SavedPlace]
    var searchHistory: [SearchHistoryEntry]
    var preferences: BackupPreferences

    func validated() throws -> LocusBackup {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw BackupError.unsupportedVersion(schemaVersion)
        }
        guard favorites.count <= 10_000, searchHistory.count <= 1_000 else {
            throw BackupError.invalidContent
        }
        guard favorites.allSatisfy({ Self.valid(latitude: $0.latitude, longitude: $0.longitude) }),
              searchHistory.allSatisfy({ Self.valid(latitude: $0.latitude, longitude: $0.longitude) }) else {
            throw BackupError.invalidContent
        }
        return self
    }

    private static func valid(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite &&
            (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

struct BackupPreferences: Codable {
    var travelMode: String
    var speedMultiplier: Double
    var routeLoopEnabled: Bool
    var routeLoopCount: Int
    var mapStyleIndex: Int
    var targetSelectionMode: String
    var searchHistoryEnabled: Bool
    var autoFollowRoute: Bool
    var restoreLastMapView: Bool
    var appearanceMode: String?
    var zoomSliderEnabled: Bool?
    var locationJitterEnabled: Bool?
    var locationJitterRadius: Double?
    var locationUpdateInterval: Double?
    var locationUpdateJitter: Double?
}

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidContent

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "不支持版本为 \(version) 的 Locus 备份。"
        case .invalidContent:
            return "备份包含无效或超出范围的数据。"
        }
    }
}

struct LocusBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var backup: LocusBackup

    init(backup: LocusBackup) {
        self.backup = backup
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        backup = try decoder.decode(LocusBackup.self, from: data).validated()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return FileWrapper(regularFileWithContents: try encoder.encode(backup))
    }
}
