import CapacityCore
import Foundation

@main
struct CapacityCLI {
    static func main() async {
        if let rawIndex = CommandLine.arguments.firstIndex(of: "--raw"),
           CommandLine.arguments.indices.contains(rawIndex + 1),
           let kind = PTYProbeKind(rawValue: CommandLine.arguments[rawIndex + 1]) {
            let commandName: String = switch kind {
            case .openAI: "codex"
            case .anthropic: "claude"
            case .google: "agy"
            case .cursor: "agent"
            }
            guard let executable = ExecutableLocator().locate(commandName) else {
                print("Missing executable: \(commandName)")
                return
            }
            do {
                let raw = try await PTYUsageProbe().run(kind: kind, executable: executable)
                print(ANSIText.clean(raw))
            } catch {
                print("Probe failed: \(error.localizedDescription)")
            }
            return
        }

        let snapshots = await CapacityService.live.refreshAll()
        if CommandLine.arguments.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshots) {
                print(String(decoding: data, as: UTF8.self))
            }
            return
        }

        for snapshot in snapshots {
            let plan = snapshot.plan.map { " · \($0)" } ?? ""
            print("\n\(snapshot.id.displayName) — \(snapshot.state.label)\(plan)")
            for window in snapshot.windows {
                let reset = window.resetsAt.map { $0.formatted(date: .abbreviated, time: .shortened) }
                    ?? window.resetDescription
                    ?? "reset unknown"
                print("  \(window.label): \(String(format: "%.1f", window.usedPercent))% used · \(reset)")
            }
            for metric in snapshot.metrics {
                print("  \(metric.label): \(metric.value)")
            }
            if let message = snapshot.message { print("  \(message)") }
        }
    }
}
