import Foundation
import Testing
@testable import CapacityCore

@Suite("Accounts")
struct AccountsTests {
    @Test("decodes accounts and keeps the first of a repeated id")
    func decodesAccounts() throws {
        let json = #"""
        {"accounts":[
          {"id":"openai","provider":"openAI","label":"OpenAI"},
          {"id":"claude-org","provider":"anthropic","label":"Claude · Org","configDirectory":"~/.claude-accounts/org"},
          {"id":"claude-org","provider":"anthropic","label":"Duplicate"}
        ]}
        """#

        let accounts = try AccountRegistry.decode(Data(json.utf8))

        #expect(accounts.map(\.id) == ["openai", "claude-org"])
        #expect(accounts[1].label == "Claude · Org")
        #expect(accounts[0].configDirectory == nil)
    }

    @Test("an empty list falls back to one default login per provider")
    func emptyListFallsBack() throws {
        let accounts = try AccountRegistry.decode(Data(#"{"accounts":[]}"#.utf8))
        #expect(accounts.map(\.provider) == ProviderID.allCases)
    }

    @Test("points each CLI at its own config folder")
    func environmentPerProvider() {
        let home = NSString(string: "~").expandingTildeInPath
        let claude = AccountConfig(id: "c", provider: .anthropic, label: "C", configDirectory: "~/.claude-accounts/org")
        let codex = AccountConfig(id: "o", provider: .openAI, label: "O", configDirectory: "/tmp/codex-two")
        let cursor = AccountConfig(id: "cu", provider: .cursor, label: "Cu", configDirectory: "/tmp/ignored")

        #expect(claude.environment == ["CLAUDE_CONFIG_DIR": "\(home)/.claude-accounts/org"])
        #expect(codex.environment == ["CODEX_HOME": "/tmp/codex-two"])
        #expect(cursor.environment.isEmpty)
        #expect(AccountConfig.primary(.anthropic).environment.isEmpty)
    }

    @Test("labels snapshots with the account while keeping reported identity")
    func assignsAccount() {
        let account = AccountConfig(id: "claude-org", provider: .anthropic, label: "Claude · Org")
        let snapshot = ProviderSnapshot(provider: .anthropic, state: .connected)
            .identified(as: "me@example.com")
            .assigned(to: account)

        #expect(snapshot.id == "claude-org")
        #expect(snapshot.account.label == "Claude · Org")
        #expect(snapshot.account.identity == "me@example.com")
    }

    @Test("shows a team organization but hides a personal one")
    func identityLabel() {
        #expect(AnthropicProvider.identity(email: "a@b.com", organization: "a@b.com's Organization") == "a@b.com")
        #expect(AnthropicProvider.identity(email: "a@b.com", organization: "Acme") == "a@b.com · Acme")
        #expect(AnthropicProvider.identity(email: nil, organization: "Acme") == nil)
    }
}
