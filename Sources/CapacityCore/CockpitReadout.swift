import Foundation

/// The two dials an account shows, plus any extra pools the provider reports.
public struct AccountReadout: Sendable {
    public static let cautionThreshold: Double = 85

    public let snapshot: ProviderSnapshot
    public let fiveHour: CapacityWindow?
    public let weekly: CapacityWindow?
    public let otherWindows: [CapacityWindow]

    public init(_ snapshot: ProviderSnapshot) {
        self.snapshot = snapshot
        // OpenAI lists model-specific pools beside the account-wide windows
        // (ids "codex-…"). The dials show the account-wide ones.
        let primary = snapshot.provider == .openAI
            ? snapshot.windows.filter { $0.id.hasPrefix("codex-") }
            : snapshot.windows
        let fiveHour = primary.first { $0.durationMinutes == 300 }
        let weekly = primary.first { $0.durationMinutes == 10_080 }
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.otherWindows = snapshot.windows.filter { $0.id != fiveHour?.id && $0.id != weekly?.id }
    }

    public var hasMeasurements: Bool { fiveHour != nil || weekly != nil }

    /// The window closest to its limit; it decides headroom and the reset clock.
    public var bindingWindow: CapacityWindow? {
        [fiveHour, weekly].compactMap { $0 }.max { $0.usedPercent < $1.usedPercent }
    }

    public var peakUsed: Double? { bindingWindow?.usedPercent }

    public var headroom: Double? { peakUsed.map { max(0, 100 - $0) } }

    public var isNearLimit: Bool { (peakUsed ?? 0) >= Self.cautionThreshold }

    /// Usable for routing: connected now, or stale but still measured.
    public var isLive: Bool { snapshot.state == .connected && hasMeasurements }
}

public struct CockpitReadout: Sendable {
    public let accounts: [AccountReadout]

    public init(snapshots: [ProviderSnapshot]) {
        accounts = snapshots.filter { $0.provider != .xAI }.map(AccountReadout.init)
    }

    /// The Claude account with the most headroom, for the ROUTE annunciator.
    public var bestClaude: AccountReadout? {
        accounts
            .filter { $0.snapshot.provider == .anthropic && $0.isLive }
            .max { ($0.headroom ?? 0) < ($1.headroom ?? 0) }
    }

    /// The measured account closest to a limit, when it is past the caution line.
    public var masterCaution: AccountReadout? {
        accounts
            .filter { $0.isNearLimit }
            .max { ($0.peakUsed ?? 0) < ($1.peakUsed ?? 0) }
    }

    public var needsSignIn: [AccountReadout] {
        accounts.filter { $0.snapshot.state == .unauthenticated }
    }
}
