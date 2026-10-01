import Foundation

extension ProviderID {
    /// The environment variable that points this provider's CLI at a separate
    /// config folder, which is how one Mac keeps several signed-in accounts.
    /// Providers without one support only their default login.
    public var configDirectoryVariable: String? {
        switch self {
        case .anthropic: "CLAUDE_CONFIG_DIR"
        case .openAI: "CODEX_HOME"
        case .google, .cursor, .xAI: nil
        }
    }
}

/// Identifies which signed-in account a snapshot describes.
public struct AccountRef: Codable, Hashable, Sendable {
    public let id: String
    public let label: String
    /// What the provider reports about the login, such as its email address.
    public let identity: String?

    public init(id: String, label: String, identity: String? = nil) {
        self.id = id
        self.label = label
        self.identity = identity
    }

    public static func primary(_ provider: ProviderID) -> AccountRef {
        AccountRef(id: provider.rawValue, label: provider.shortName)
    }
}

/// One account to poll, read from `accounts.json`.
public struct AccountConfig: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let provider: ProviderID
    public let label: String
    /// Config folder for this login; `~` is expanded. Omit it to use the CLI's
    /// default folder (`~/.claude`, `~/.codex`).
    public let configDirectory: String?

    public init(id: String, provider: ProviderID, label: String, configDirectory: String? = nil) {
        self.id = id
        self.provider = provider
        self.label = label
        self.configDirectory = configDirectory
    }

    public var ref: AccountRef { AccountRef(id: id, label: label) }

    public var expandedConfigDirectory: String? {
        guard let configDirectory, !configDirectory.isEmpty else { return nil }
        return NSString(string: configDirectory).expandingTildeInPath
    }

    /// Variables that make the provider CLI use this account's login.
    public var environment: [String: String] {
        guard let path = expandedConfigDirectory,
              let variable = provider.configDirectoryVariable else { return [:] }
        return [variable: path]
    }

    public static func primary(_ provider: ProviderID) -> AccountConfig {
        AccountConfig(id: provider.rawValue, provider: provider, label: provider.shortName)
    }
}

/// Loads the accounts to poll. Without an `accounts.json`, every provider is
/// polled once with its CLI's default login, as before multi-account support.
public enum AccountRegistry {
    private struct File: Codable {
        let accounts: [AccountConfig]
    }

    public static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mission Control Capacity", isDirectory: true)
            .appendingPathComponent("accounts.json", isDirectory: false)
    }

    public static let defaultAccounts = ProviderID.allCases.map(AccountConfig.primary)

    public static func load() -> [AccountConfig] {
        guard let data = try? Data(contentsOf: fileURL),
              let accounts = try? decode(data) else {
            return defaultAccounts
        }
        return accounts
    }

    /// Parses `{"accounts": [...]}`, keeping the first entry for any repeated id.
    public static func decode(_ data: Data) throws -> [AccountConfig] {
        let accounts = try JSONDecoder().decode(File.self, from: data).accounts
        var seen = Set<String>()
        let unique = accounts.filter { seen.insert($0.id).inserted }
        return unique.isEmpty ? defaultAccounts : unique
    }
}
