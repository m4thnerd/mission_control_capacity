import Foundation

public struct XAIProvider: CapacityProvider {
    public let id: ProviderID = .xAI

    public init() {}

    public func fetch() async -> ProviderSnapshot {
        ProviderSnapshot(
            id: id,
            state: .unavailable,
            message: "Not configured. Cursor-hosted Grok usage appears under Cursor."
        )
    }
}
