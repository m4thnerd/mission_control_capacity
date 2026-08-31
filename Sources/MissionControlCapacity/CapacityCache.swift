import CapacityCore
import Foundation

struct CapacityCacheEnvelope: Codable {
    let snapshots: [ProviderSnapshot]
    let lastPolledAt: Date
}

enum CapacityCache {
    static let pollInterval: TimeInterval = 10 * 60
    static let failureRetryInterval: TimeInterval = 60

    static func load() -> CapacityCacheEnvelope? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CapacityCacheEnvelope.self, from: data)
    }

    static func save(snapshots: [ProviderSnapshot], lastPolledAt: Date) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(
            CapacityCacheEnvelope(snapshots: snapshots, lastPolledAt: lastPolledAt)
        ) else { return }

        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Mission Control Capacity", isDirectory: true)
            .appendingPathComponent("capacity-snapshot.json", isDirectory: false)
    }
}
