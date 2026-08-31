import Foundation

public struct OpenAIProvider: CapacityProvider {
    public let id: ProviderID = .openAI
    private let locator = ExecutableLocator()
    private let probe = PTYUsageProbe()

    public init() {}

    public func fetch() async -> ProviderSnapshot {
        guard let executable = locator.locate("codex") else {
            return ProviderSnapshot(id: id, state: .unavailable, message: "Codex CLI is not installed.")
        }
        do {
            return try UsageParsers.openAI(try await probe.run(kind: .openAI, executable: executable))
        } catch {
            return ProviderSnapshot(id: id, state: .error, message: error.localizedDescription)
        }
    }
}
