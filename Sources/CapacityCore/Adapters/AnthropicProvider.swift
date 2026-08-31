import Foundation

public struct AnthropicProvider: CapacityProvider {
    public let id: ProviderID = .anthropic
    private let locator = ExecutableLocator()
    private let runner = CommandRunner()
    private let probe = PTYUsageProbe()

    public init() {}

    public func fetch() async -> ProviderSnapshot {
        guard let executable = locator.locate("claude") else {
            return ProviderSnapshot(id: id, state: .unavailable, message: "Claude Code is not installed.")
        }
        do {
            let auth = try await runner.run(executable: executable, arguments: ["auth", "status", "--json"])
            guard let data = auth.stdout.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["loggedIn"] as? Bool) == true else {
                return ProviderSnapshot(id: id, state: .unauthenticated, message: "Run claude auth login.")
            }
            let plan = (json["subscriptionType"] as? String)?.capitalized
            let raw = try await probe.run(kind: .anthropic, executable: executable)
            return try UsageParsers.anthropic(raw, plan: plan)
        } catch {
            return ProviderSnapshot(id: id, state: .error, message: error.localizedDescription)
        }
    }
}
