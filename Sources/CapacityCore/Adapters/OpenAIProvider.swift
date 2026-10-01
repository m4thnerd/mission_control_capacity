import Foundation

public struct OpenAIProvider: CapacityProvider {
    public let account: AccountConfig
    private let locator = ExecutableLocator()
    private let probe = PTYUsageProbe()

    public init(account: AccountConfig = .primary(.openAI)) {
        self.account = account
    }

    public func fetch() async -> ProviderSnapshot {
        guard let executable = locator.locate("codex") else {
            return ProviderSnapshot(provider: .openAI, state: .unavailable, message: "Codex CLI is not installed.")
        }
        do {
            return try UsageParsers.openAI(
                try await probe.run(kind: .openAI, executable: executable, environment: account.environment)
            )
        } catch {
            return ProviderSnapshot(provider: .openAI, state: .error, message: error.localizedDescription)
        }
    }
}
