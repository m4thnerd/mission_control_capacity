import Foundation

public protocol CapacityProvider: Sendable {
    var id: ProviderID { get }
    func fetch() async -> ProviderSnapshot
}

public struct CapacityService: Sendable {
    private let providers: [any CapacityProvider]

    public init(providers: [any CapacityProvider]) {
        self.providers = providers
    }

    public static let live = CapacityService(providers: [
        OpenAIProvider(),
        AnthropicProvider(),
        GoogleProvider(),
        CursorProvider(),
        XAIProvider()
    ])

    public func refreshAll() async -> [ProviderSnapshot] {
        let results = await withTaskGroup(of: ProviderSnapshot.self) { group in
            for provider in providers {
                group.addTask { await provider.fetch() }
            }

            var snapshots: [ProviderSnapshot] = []
            for await snapshot in group {
                snapshots.append(snapshot)
            }
            return snapshots
        }
        let order = Dictionary(uniqueKeysWithValues: ProviderID.allCases.enumerated().map { ($1, $0) })
        return results.sorted { order[$0.id, default: .max] < order[$1.id, default: .max] }
    }
}
