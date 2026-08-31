import Foundation

public struct GoogleProvider: CapacityProvider {
    public let id: ProviderID = .google
    private let locator = ExecutableLocator()
    private let probe = PTYUsageProbe()

    public init() {}

    public func fetch() async -> ProviderSnapshot {
        guard let executable = locator.locate("agy") else {
            return ProviderSnapshot(id: id, state: .unavailable, message: "Antigravity CLI (agy) is not installed.")
        }
        do {
            return try UsageParsers.google(try await probe.run(kind: .google, executable: executable))
        } catch {
            let state: ConnectionState = error.localizedDescription.localizedCaseInsensitiveContains("authenticate")
                ? .unauthenticated
                : .error
            return ProviderSnapshot(id: id, state: state, message: error.localizedDescription)
        }
    }
}
