import Foundation

public struct CursorProvider: CapacityProvider {
    public let id: ProviderID = .cursor
    private let locator = ExecutableLocator()
    private let runner = CommandRunner()
    private let probe = PTYUsageProbe()

    public init() {}

    public func fetch() async -> ProviderSnapshot {
        guard let executable = locator.locate("agent") ?? locator.locate("cursor-agent") else {
            return ProviderSnapshot(id: id, state: .unavailable, message: "Cursor Agent is not installed.")
        }
        do {
            let auth = try await runner.run(executable: executable, arguments: ["status", "--format", "json"])
            guard let data = auth.stdout.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["isAuthenticated"] as? Bool) == true else {
                return ProviderSnapshot(id: id, state: .unauthenticated, message: "Run agent login.")
            }
            return try UsageParsers.cursor(try await probe.run(kind: .cursor, executable: executable))
        } catch {
            return ProviderSnapshot(id: id, state: .error, message: error.localizedDescription)
        }
    }
}
