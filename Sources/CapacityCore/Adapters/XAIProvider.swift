import Foundation

public struct XAIProvider: CapacityProvider {
    public let account: AccountConfig

    public init(account: AccountConfig = .primary(.xAI)) {
        self.account = account
    }

    public func fetch() async -> ProviderSnapshot {
        ProviderSnapshot(
            provider: .xAI,
            state: .unavailable,
            message: "Not configured. Cursor-hosted Grok usage appears under Cursor."
        )
    }
}
