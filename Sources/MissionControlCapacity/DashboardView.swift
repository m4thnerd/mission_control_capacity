import AppKit
import CapacityCore
import SwiftUI

/// Dark instrument-panel palette shared by the dashboard views.
enum ConsoleTheme {
    static let background = Color(red: 0.055, green: 0.075, blue: 0.105)
    static let panel = Color.white.opacity(0.045)
    static let grid = Color.white.opacity(0.035)
    static let hairline = Color.white.opacity(0.10)
    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.60)
    static let tertiary = Color.white.opacity(0.40)
    static let track = Color.white.opacity(0.09)

    static func mono(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }
}

struct DashboardView: View {
    @ObservedObject var store: CapacityStore
    let compact: Bool
    /// Renders the card grid without a ScrollView. Used by the preview renderer,
    /// which cannot draw scroll views or lazy containers.
    var staticLayout = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            ConsoleTheme.background
            GridBackdrop()
            VStack(spacing: 0) {
                header
                Rectangle().fill(ConsoleTheme.hairline).frame(height: 1)
                if staticLayout {
                    cardGrid
                } else {
                    ScrollView { cardGrid }
                }
                Rectangle().fill(ConsoleTheme.hairline).frame(height: 1)
                footer
            }
        }
        .foregroundStyle(ConsoleTheme.primary)
        .preferredColorScheme(.dark)
    }

    private var cardGrid: some View {
        let rows = stride(from: 0, to: visibleSnapshots.count, by: 2).map {
            Array(visibleSnapshots[$0..<min($0 + 2, visibleSnapshots.count)])
        }
        return VStack(spacing: 10) {
            ForEach(rows, id: \.first!.id) { row in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(row) { snapshot in
                        ProviderCard(snapshot: snapshot)
                            .frame(maxWidth: .infinity, minHeight: 250)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(.cyan)
                .shadow(color: .cyan.opacity(0.7), radius: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text("MISSION CONTROL")
                    .font(ConsoleTheme.mono(.subheadline, weight: .bold))
                    .tracking(2)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("CAPACITY · \(refreshLabel(now: context.date))")
                        .font(ConsoleTheme.mono(.caption2))
                        .tracking(0.8)
                        .foregroundStyle(ConsoleTheme.secondary)
                }
            }
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            }
            StatusPill(status: systemStatus)
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(ConsoleTheme.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh all providers")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            if compact {
                Button("OPEN DASHBOARD") {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            Spacer()
            Text("POLL 10M")
                .foregroundStyle(ConsoleTheme.tertiary)
            if compact {
                Button("QUIT") { NSApp.terminate(nil) }
            }
        }
        .font(ConsoleTheme.mono(.caption2, weight: .semibold))
        .tracking(0.8)
        .buttonStyle(.borderless)
        .tint(ConsoleTheme.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var systemStatus: SystemStatus {
        if store.snapshots.contains(where: { $0.state == .error || $0.state == .unauthenticated }) {
            return .attention
        }
        if store.snapshots.contains(where: { $0.state == .loading }) {
            return .syncing
        }
        return .nominal
    }

    private func refreshLabel(now: Date) -> String {
        guard let date = store.lastRefresh else { return "FIRST SNAPSHOT PENDING" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "CHECKED JUST NOW" }
        if seconds < 3_600 { return "CHECKED \(seconds / 60)M AGO" }
        if seconds < 86_400 { return "CHECKED \(seconds / 3_600)H AGO" }
        return "CHECKED \(seconds / 86_400)D AGO"
    }

    private var visibleSnapshots: [ProviderSnapshot] {
        store.snapshots.filter { $0.id != .xAI }
    }
}

private enum SystemStatus {
    case nominal, syncing, attention

    var label: String {
        switch self {
        case .nominal: "NOMINAL"
        case .syncing: "SYNCING"
        case .attention: "ATTENTION"
        }
    }

    var color: Color {
        switch self {
        case .nominal: .green
        case .syncing: .cyan
        case .attention: .orange
        }
    }
}

private struct StatusPill: View {
    let status: SystemStatus

    var body: some View {
        HStack(spacing: 5) {
            GlowDot(color: status.color)
            Text(status.label)
                .font(ConsoleTheme.mono(.caption2, weight: .bold))
                .tracking(1)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(status.color.opacity(0.45), lineWidth: 1))
    }
}

private struct GlowDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.9), radius: 4)
    }
}

/// Faint engineering grid behind the panels.
private struct GridBackdrop: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 28
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(ConsoleTheme.grid), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

private struct ProviderCard: View {
    let snapshot: ProviderSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                GlowDot(color: statusColor)
                Text(snapshot.id.shortName.uppercased())
                    .font(ConsoleTheme.mono(.callout, weight: .bold))
                    .tracking(1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let plan = snapshot.plan, !plan.isEmpty {
                    Text(displayPlan(plan).uppercased())
                        .font(ConsoleTheme.mono(.caption2, weight: .semibold))
                        .foregroundStyle(providerColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(providerColor.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(providerColor.opacity(0.4), lineWidth: 1))
                }
                Spacer()
                if snapshot.state != .connected {
                    Text(snapshot.state.label.uppercased())
                        .font(ConsoleTheme.mono(.caption2))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            if snapshot.state == .error, !snapshot.windows.isEmpty {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Label(staleLabel(now: context.date), systemImage: "exclamationmark.triangle.fill")
                        .font(ConsoleTheme.mono(.caption2, weight: .semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .help(snapshot.message ?? "The latest refresh failed.")
                }
            }

            if snapshot.state == .loading {
                Spacer()
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                Spacer()
            } else if snapshot.windows.isEmpty {
                Text(snapshot.message ?? "No quota windows were returned.")
                    .font(.caption)
                    .foregroundStyle(ConsoleTheme.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 9) {
                        if let unreportedFiveHour {
                            UnreportedWindowRow(label: unreportedFiveHour.label)
                        }
                        ForEach(snapshot.windows) { window in
                            CapacityWindowRow(window: window, now: context.date, tint: providerColor)
                        }
                    }
                }

                if !displayMetrics.isEmpty {
                    Rectangle().fill(ConsoleTheme.hairline).frame(height: 1)
                    VStack(spacing: 3) {
                        ForEach(displayMetrics) { metric in
                            HStack(spacing: 6) {
                                Text(metric.label.uppercased())
                                    .foregroundStyle(ConsoleTheme.secondary)
                                Spacer(minLength: 4)
                                Text(metric.value.uppercased())
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .font(ConsoleTheme.mono(.caption2))
                }
            }
            Spacer(minLength: 0)
            BestForSection(guide: ProviderGuide.forProvider(snapshot.id), tint: providerColor)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ConsoleTheme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(providerColor.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: providerColor.opacity(0.22), radius: 10)
    }

    private var statusColor: Color {
        switch snapshot.state {
        case .connected: .green
        case .loading: .cyan
        case .unauthenticated: .orange
        case .unavailable: .gray
        case .error: .red
        }
    }

    private var providerColor: Color {
        switch snapshot.id {
        case .openAI: .mint
        case .anthropic: .orange
        case .google: .blue
        case .cursor: .cyan
        case .xAI: .purple
        }
    }

    private var unreportedFiveHour: CapacityMetric? {
        snapshot.metrics.first {
            $0.id == "openai-account-wide-5-hour-unreported" && $0.value == "Not reported"
        }
    }

    private var displayMetrics: [CapacityMetric] {
        snapshot.metrics.filter { $0.id != "openai-account-wide-5-hour-unreported" }
    }

    private func displayPlan(_ plan: String) -> String {
        snapshot.id == .google ? plan.replacingOccurrences(of: "Google ", with: "") : plan
    }

    private func staleLabel(now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(snapshot.updatedAt)))
        if seconds < 60 { return "STALE · LAST GOOD JUST NOW" }
        if seconds < 3_600 { return "STALE · LAST GOOD \(seconds / 60)M AGO" }
        if seconds < 86_400 { return "STALE · LAST GOOD \(seconds / 3_600)H AGO" }
        return "STALE · LAST GOOD \(seconds / 86_400)D AGO"
    }
}

private struct BestForSection: View {
    let guide: ProviderGuide
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "scope")
                    .font(.system(size: 9, weight: .bold))
                Text("BEST FOR")
                    .font(ConsoleTheme.mono(.caption2, weight: .bold))
                    .tracking(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(tint)
            Text(guide.headline)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            ForEach(guide.bestFor, id: \.self) { item in
                HStack(alignment: .top, spacing: 4) {
                    Text("›").foregroundStyle(tint)
                    Text(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption2)
                .foregroundStyle(ConsoleTheme.secondary)
                .lineLimit(2)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
        .help("What this provider's models are generally known to be strongest at. Use it to pick where the next project goes, or where to shift when a limit runs out.")
    }
}

/// Thin gauge with quarter tick marks and a glowing fill.
private struct GaugeBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(ConsoleTheme.track)
                if value > 0 {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(5, proxy.size.width * value / 100))
                        .shadow(color: tint.opacity(0.7), radius: 3)
                }
                ForEach([0.25, 0.5, 0.75], id: \.self) { fraction in
                    Rectangle()
                        .fill(ConsoleTheme.background.opacity(0.9))
                        .frame(width: 1)
                        .offset(x: proxy.size.width * fraction)
                }
            }
        }
        .frame(height: 5)
    }
}

private struct UnreportedWindowRow: View {
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label.uppercased())
                    .font(ConsoleTheme.mono(.caption2, weight: .semibold))
                    .lineLimit(2)
                Spacer()
                Text("NO DATA")
                    .font(ConsoleTheme.mono(.caption2, weight: .bold))
                    .foregroundStyle(ConsoleTheme.tertiary)
            }
            GaugeBar(value: 0, tint: .clear)
            Text("NOT RETURNED BY PROVIDER")
                .font(ConsoleTheme.mono(.caption2))
                .foregroundStyle(ConsoleTheme.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct CapacityWindowRow: View {
    let window: CapacityWindow
    let now: Date
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label.uppercased())
                    .font(ConsoleTheme.mono(.caption2, weight: .semibold))
                    .lineLimit(2)
                Spacer()
                Text(percentLabel)
                    .font(ConsoleTheme.mono(.caption, weight: .bold))
                    .foregroundStyle(usageColor)
            }
            GaugeBar(value: window.usedPercent, tint: usageColor)
            HStack {
                Text("\(format(window.remainingPercent))% LEFT")
                Spacer()
                Text(resetLabel.uppercased())
            }
            .font(ConsoleTheme.mono(.caption2))
            .foregroundStyle(ConsoleTheme.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    private var percentLabel: String { "\(format(window.usedPercent))% USED" }

    private var usageColor: Color {
        switch window.usedPercent {
        case 80...: .red
        case 60..<80: .orange
        default: tint
        }
    }

    private var resetLabel: String {
        if let reset = window.resetsAt {
            let seconds = max(0, Int(reset.timeIntervalSince(now)))
            if seconds < 60 { return "↻ <1m" }
            if seconds < 3_600 { return "↻ \(seconds / 60)m" }
            if seconds < 86_400 { return "↻ \(seconds / 3_600)h \((seconds % 3_600) / 60)m" }
            return "↻ \(seconds / 86_400)d \((seconds % 86_400) / 3_600)h"
        }
        switch window.resetDescription {
        case "Available — window not started": return "Not started"
        case .some(let description): return description.replacingOccurrences(of: "Resets ", with: "↻ ")
        case nil: return "Reset unavailable"
        }
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
