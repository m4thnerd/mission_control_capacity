import Foundation

public enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI
    case anthropic
    case google
    case cursor
    case xAI

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .google: "Google Antigravity"
        case .cursor: "Cursor"
        case .xAI: "xAI / SuperGrok"
        }
    }

    public var shortName: String {
        switch self {
        case .google: "Google"
        case .xAI: "xAI"
        default: displayName
        }
    }
}

public enum ConnectionState: String, Codable, Sendable {
    case loading
    case connected
    case unauthenticated
    case unavailable
    case error

    public var label: String {
        switch self {
        case .loading: "Loading"
        case .connected: "Connected"
        case .unauthenticated: "Sign-in required"
        case .unavailable: "Unavailable"
        case .error: "Needs attention"
        }
    }
}

public struct CapacityWindow: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let usedPercent: Double
    public let durationMinutes: Int?
    public let resetsAt: Date?
    public let resetDescription: String?

    public init(
        id: String,
        label: String,
        usedPercent: Double,
        durationMinutes: Int? = nil,
        resetsAt: Date? = nil,
        resetDescription: String? = nil
    ) {
        self.id = id
        self.label = label
        self.usedPercent = min(max(usedPercent, 0), 100)
        self.durationMinutes = durationMinutes
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
    }

    public var remainingPercent: Double { max(0, 100 - usedPercent) }
}

public struct CapacityMetric: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let value: String

    public init(id: String? = nil, label: String, value: String) {
        self.id = id ?? label
        self.label = label
        self.value = value
    }
}

public struct ProviderSnapshot: Codable, Identifiable, Sendable {
    public let id: ProviderID
    public let state: ConnectionState
    public let plan: String?
    public let windows: [CapacityWindow]
    public let metrics: [CapacityMetric]
    public let message: String?
    public let updatedAt: Date

    public init(
        id: ProviderID,
        state: ConnectionState,
        plan: String? = nil,
        windows: [CapacityWindow] = [],
        metrics: [CapacityMetric] = [],
        message: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.state = state
        self.plan = plan
        self.windows = windows
        self.metrics = metrics
        self.message = message
        self.updatedAt = updatedAt
    }

    public static func loading(_ id: ProviderID) -> ProviderSnapshot {
        ProviderSnapshot(id: id, state: .loading)
    }

    /// Keeps the last successful measurements when a transient refresh fails,
    /// while making the failure (and the age of the data) explicit to callers.
    public func retainingMeasurements(after failure: ProviderSnapshot) -> ProviderSnapshot {
        precondition(id == failure.id)
        let detail = failure.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = if let detail, !detail.isEmpty {
            "Latest refresh failed: \(detail)"
        } else {
            "Latest refresh failed."
        }
        return ProviderSnapshot(
            id: id,
            state: .error,
            plan: plan,
            windows: windows,
            metrics: metrics,
            message: message,
            updatedAt: updatedAt
        )
    }
}
