import Foundation

public struct CursorProvider: CapacityProvider {
    public let account: AccountConfig
    private let locator = ExecutableLocator()
    private let runner = CommandRunner()
    private let probe = PTYUsageProbe()

    public init(account: AccountConfig = .primary(.cursor)) {
        self.account = account
    }

    public func fetch() async -> ProviderSnapshot {
        guard let executable = locator.locate("agent") ?? locator.locate("cursor-agent") else {
            return ProviderSnapshot(provider: .cursor, state: .unavailable, message: "Cursor Agent is not installed.")
        }
        do {
            let auth = try await runner.run(executable: executable, arguments: ["status", "--format", "json"])
            guard let data = auth.stdout.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["isAuthenticated"] as? Bool) == true else {
                return ProviderSnapshot(provider: .cursor, state: .unauthenticated, message: "Run agent login.")
            }
            return try UsageParsers.cursor(try await probe.run(kind: .cursor, executable: executable))
        } catch {
            return ProviderSnapshot(provider: .cursor, state: .error, message: error.localizedDescription)
        }
    }
}
