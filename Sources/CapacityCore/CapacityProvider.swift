import Foundation

public protocol CapacityProvider: Sendable {
    var account: AccountConfig { get }
    func fetch() async -> ProviderSnapshot
}

public struct CapacityService: Sendable {
    private let providers: [any CapacityProvider]

    public var accounts: [AccountConfig] { providers.map(\.account) }

    public init(providers: [any CapacityProvider]) {
        self.providers = providers
    }

    public init(accounts: [AccountConfig]) {
        self.init(providers: accounts.map(Self.provider(for:)))
    }

    /// Polls the accounts in `accounts.json`, or each provider's default login.
    public static var live: CapacityService {
        CapacityService(accounts: AccountRegistry.load())
    }

    private static func provider(for account: AccountConfig) -> any CapacityProvider {
        switch account.provider {
        case .openAI: OpenAIProvider(account: account)
        case .anthropic: AnthropicProvider(account: account)
        case .google: GoogleProvider(account: account)
        case .cursor: CursorProvider(account: account)
        case .xAI: XAIProvider(account: account)
        }
    }

    /// Returns one snapshot per account, in the order the accounts are listed.
    public func refreshAll() async -> [ProviderSnapshot] {
        let results = await withTaskGroup(of: (Int, ProviderSnapshot).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask { (index, await provider.fetch().assigned(to: provider.account)) }
            }

            var snapshots: [(Int, ProviderSnapshot)] = []
            for await result in group {
                snapshots.append(result)
            }
            return snapshots
        }
        return results.sorted { $0.0 < $1.0 }.map(\.1)
    }
}
