import Foundation

public struct GoogleProvider: CapacityProvider {
    public let account: AccountConfig
    private let locator = ExecutableLocator()
    private let probe = PTYUsageProbe()

    public init(account: AccountConfig = .primary(.google)) {
        self.account = account
    }

    public func fetch() async -> ProviderSnapshot {
        guard let executable = locator.locate("agy") else {
            return ProviderSnapshot(provider: .google, state: .unavailable, message: "Antigravity CLI (agy) is not installed.")
        }
        do {
            return try UsageParsers.google(try await probe.run(kind: .google, executable: executable))
        } catch {
            let state: ConnectionState = error.localizedDescription.localizedCaseInsensitiveContains("authenticate")
                ? .unauthenticated
                : .error
            return ProviderSnapshot(provider: .google, state: state, message: error.localizedDescription)
        }
    }
}
