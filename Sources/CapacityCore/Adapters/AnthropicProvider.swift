import Foundation

public struct AnthropicProvider: CapacityProvider {
    public let account: AccountConfig
    private let locator = ExecutableLocator()
    private let runner = CommandRunner()
    private let probe = PTYUsageProbe()

    public init(account: AccountConfig = .primary(.anthropic)) {
        self.account = account
    }

    public func fetch() async -> ProviderSnapshot {
        guard let executable = locator.locate("claude") else {
            return ProviderSnapshot(provider: .anthropic, state: .unavailable, message: "Claude Code is not installed.")
        }
        do {
            let auth = try await runner.run(
                executable: executable,
                arguments: ["auth", "status", "--json"],
                environment: account.environment
            )
            guard let data = auth.stdout.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["loggedIn"] as? Bool) == true else {
                return ProviderSnapshot(provider: .anthropic, state: .unauthenticated, message: loginHint)
            }
            let plan = (json["subscriptionType"] as? String)?.capitalized
            let raw = try await probe.run(kind: .anthropic, executable: executable, environment: account.environment)
            return try UsageParsers.anthropic(raw, plan: plan)
                .identified(as: Self.identity(email: json["email"] as? String, organization: json["orgName"] as? String))
        } catch {
            return ProviderSnapshot(provider: .anthropic, state: .error, message: error.localizedDescription)
        }
    }

    private var loginHint: String {
        guard let directory = account.expandedConfigDirectory else { return "Run claude auth login." }
        return "Run CLAUDE_CONFIG_DIR=\"\(directory)\" claude auth login."
    }

    /// "email · Org" for team logins. Claude names a personal plan's
    /// organization "<email>'s Organization", which adds nothing.
    static func identity(email: String?, organization: String?) -> String? {
        let trimmed = { (value: String?) in
            value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        guard let email = trimmed(email) else { return nil }
        guard let organization = trimmed(organization),
              !organization.hasSuffix("'s Organization") else { return email }
        return "\(email) · \(organization)"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
