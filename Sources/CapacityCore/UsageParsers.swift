import Foundation

public enum UsageParsers {
    public static func cursor(_ raw: String, now: Date = Date()) throws -> ProviderSnapshot {
        let text = ANSIText.clean(raw)
        guard let included = percent(#"Included\s+(\d+(?:\.\d+)?)%\s+used"#, in: text) else {
            throw ParserError.missingUsage("Cursor")
        }

        let plan = RegexCapture.last(#"Usage\s*[•·]\s*([A-Za-z0-9 +_-]+?)\s+(?:Resets|Monthly)"#, in: text)?[1]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let reset = RegexCapture.last(#"Resets\s+([A-Za-z]{3}\s+\d{1,2})"#, in: text)?[1]
        var metrics: [CapacityMetric] = []
        if let onDemand = RegexCapture.last(#"On-Demand\s+(Disabled|Enabled|\$[^\s]+)"#, in: text)?[1] {
            metrics.append(CapacityMetric(label: "On-demand", value: onDemand == "Disabled" ? "Off" : onDemand))
        }

        return ProviderSnapshot(
            id: .cursor,
            state: .connected,
            plan: plan,
            windows: [
                CapacityWindow(
                    id: "cursor-monthly",
                    label: "Monthly",
                    usedPercent: included,
                    resetDescription: reset.map { "Resets \($0)" }
                )
            ],
            metrics: metrics,
            updatedAt: now
        )
    }

    public static func google(_ raw: String, now: Date = Date()) throws -> ProviderSnapshot {
        let text = ANSIText.clean(raw)
        let weeklyMatches = RegexCapture.all(
            #"Weekly\s+Limit\s+Remaining[\s\S]{0,700}?(\d+(?:\.\d+)?)%"#,
            in: text
        ).compactMap { Double($0[1]) }
        let fiveHourMatches = RegexCapture.all(
            #"Five\s+Hour\s+Limit\s+Remaining[\s\S]{0,700}?(\d+(?:\.\d+)?)%"#,
            in: text
        ).compactMap { Double($0[1]) }

        guard let geminiWeekly = weeklyMatches.first,
              let geminiFive = fiveHourMatches.first else {
            throw ParserError.missingUsage("Google Antigravity")
        }

        let plan = RegexCapture.last(#"\((Google AI [^)]+)\)"#, in: text)?[1]
        let windows = [
            CapacityWindow(
                id: "google-gemini-5h",
                label: "5 hours",
                usedPercent: 100 - geminiFive,
                durationMinutes: 300,
                resetDescription: geminiFive == 100 ? "Available — window not started" : nil
            ),
            CapacityWindow(
                id: "google-gemini-weekly",
                label: "Weekly",
                usedPercent: 100 - geminiWeekly,
                durationMinutes: 10_080,
                resetDescription: geminiWeekly == 100 ? "Available — window not started" : nil
            )
        ]
        return ProviderSnapshot(
            id: .google,
            state: .connected,
            plan: plan,
            windows: windows,
            updatedAt: now
        )
    }

    public static func anthropic(_ raw: String, plan: String?, now: Date = Date()) throws -> ProviderSnapshot {
        let text = ANSIText.clean(raw)
        var windows: [CapacityWindow] = []

        if let usage = percent(#"Current\s+session[\s\S]{0,650}?(\d+(?:\.\d+)?)%\s+used"#, in: text) {
            let reset = resetDescription(after: #"Current\s+session"#, in: text)
            windows.append(CapacityWindow(
                id: "anthropic-session",
                label: "5 hours",
                usedPercent: usage,
                durationMinutes: 300,
                resetsAt: reset.flatMap { HumanResetParser.date(from: $0, now: now) },
                resetDescription: reset
            ))
        }
        if let usage = percent(#"Current\s+week\s+\(all\s+models\)[\s\S]{0,650}?(\d+(?:\.\d+)?)%\s+used"#, in: text) {
            let reset = resetDescription(after: #"Current\s+week\s+\(all\s+models\)"#, in: text)
            windows.append(CapacityWindow(
                id: "anthropic-weekly",
                label: "Weekly",
                usedPercent: usage,
                durationMinutes: 10_080,
                resetsAt: reset.flatMap { HumanResetParser.date(from: $0, now: now) },
                resetDescription: reset
            ))
        }
        guard !windows.isEmpty else { throw ParserError.missingUsage("Claude") }
        return ProviderSnapshot(
            id: .anthropic,
            state: .connected,
            plan: plan,
            windows: windows,
            updatedAt: now
        )
    }

    public static func openAI(_ raw: String, now: Date = Date()) throws -> ProviderSnapshot {
        let cleaned = ANSIText.clean(raw)
        let jsonObjects: [[String: Any]] = cleaned
            .split(separator: "\n")
            .compactMap { line in
                guard let data = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return nil
                }
                return object
            }

        guard let response = jsonObjects.last(where: { ($0["id"] as? Int) == 2 }),
              let result = response["result"] as? [String: Any] else {
            throw ParserError.missingUsage("OpenAI")
        }

        let rateLimitsByID = result["rateLimitsByLimitId"] as? [String: [String: Any]]
        let fallback = (result["rateLimits"] as? [String: Any]).map { ["codex": $0] }
        let limits = rateLimitsByID ?? fallback ?? [:]
        var windows: [CapacityWindow] = []
        var detectedPlan: String?

        // Direct Codex capacity is the `codex` limit. Model-specific pools such as
        // Bengalfox/Spark are intentionally excluded from the human dashboard.
        for (limitID, snapshot) in limits.sorted(by: { $0.key < $1.key }) where limitID == "codex" {
            detectedPlan = detectedPlan ?? (snapshot["planType"] as? String).map(titleCase)
            let limitName = snapshot["limitName"] as? String
            for (slot, key) in [("primary", "primary"), ("secondary", "secondary")] {
                guard let window = snapshot[key] as? [String: Any],
                      let used = number(window["usedPercent"]) else { continue }
                let duration = integer(window["windowDurationMins"])
                let resetEpoch = integer(window["resetsAt"])
                let baseLabel = durationLabel(duration)
                let label = limitName.map { "\($0) · \(baseLabel)" } ?? baseLabel
                windows.append(CapacityWindow(
                    id: "\(limitID)-\(slot)",
                    label: label,
                    usedPercent: used,
                    durationMinutes: duration,
                    resetsAt: resetEpoch.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                ))
            }
        }

        guard !windows.isEmpty else { throw ParserError.missingUsage("OpenAI") }
        var metrics: [CapacityMetric] = []
        if !windows.contains(where: { $0.durationMinutes == 300 }) {
            metrics.append(CapacityMetric(label: "5-hour", value: "Not reported"))
        }
        if let resetCredits = result["rateLimitResetCredits"] as? [String: Any],
           let count = integer(resetCredits["availableCount"]), count > 0 {
            metrics.append(CapacityMetric(label: "Full resets", value: "\(count) available"))
        }

        return ProviderSnapshot(
            id: .openAI,
            state: .connected,
            plan: detectedPlan,
            windows: windows,
            metrics: metrics,
            updatedAt: now
        )
    }

    private static func percent(_ pattern: String, in text: String) -> Double? {
        RegexCapture.last(pattern, in: text).flatMap { Double($0[1]) }
    }

    private static func resetDescription(after header: String, in text: String) -> String? {
        RegexCapture.first(
            "\(header)[\\s\\S]{0,900}?Resets\\s+([^\\n]+)",
            in: text
        )?[1]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func formatPercent(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))% used" : String(format: "%.1f%% used", value)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func durationLabel(_ minutes: Int?) -> String {
        switch minutes {
        case 300: "5 hours"
        case 10_080: "Weekly"
        case .some(let value): "\(value) minutes"
        case nil: "Usage"
        }
    }

    private static func titleCase(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

public enum ParserError: LocalizedError {
    case missingUsage(String)

    public var errorDescription: String? {
        switch self {
        case .missingUsage(let provider): "Could not recognize \(provider)'s current usage display."
        }
    }
}

enum HumanResetParser {
    static func date(from value: String, now: Date, calendar baseCalendar: Calendar = .current) -> Date? {
        let cleaned = value
            .replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var calendar = baseCalendar
        calendar.locale = Locale(identifier: "en_US_POSIX")

        if let captures = RegexCapture.first(
            #"^([A-Za-z]{3,9})\s+(\d{1,2})\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)$"#,
            in: cleaned
        ) {
            guard let month = monthNumber(captures[1]),
                  let day = Int(captures[2]),
                  var hour = Int(captures[3]) else { return nil }
            let minute = Int(captures[4]) ?? 0
            hour = hour24(hour, meridiem: captures[5])
            var components = calendar.dateComponents([.year], from: now)
            components.month = month
            components.day = day
            components.hour = hour
            components.minute = minute
            guard var date = calendar.date(from: components) else { return nil }
            if date <= now, let next = calendar.date(byAdding: .year, value: 1, to: date) { date = next }
            return date
        }

        if let captures = RegexCapture.first(
            #"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)$"#,
            in: cleaned
        ) {
            guard var hour = Int(captures[1]) else { return nil }
            hour = hour24(hour, meridiem: captures[3])
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = hour
            components.minute = Int(captures[2]) ?? 0
            guard var date = calendar.date(from: components) else { return nil }
            if date <= now, let next = calendar.date(byAdding: .day, value: 1, to: date) { date = next }
            return date
        }
        return nil
    }

    private static func monthNumber(_ name: String) -> Int? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let names = formatter.monthSymbols + formatter.shortMonthSymbols
        guard let index = names.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
        return (index % 12) + 1
    }

    private static func hour24(_ hour: Int, meridiem: String) -> Int {
        let base = hour % 12
        return meridiem.lowercased() == "pm" ? base + 12 : base
    }
}
