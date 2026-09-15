import AppKit
import CapacityCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: CapacityStore
    let compact: Bool
    /// Renders the card grid without a ScrollView. Used by the preview renderer,
    /// which cannot draw scroll views or lazy containers.
    var staticLayout = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if staticLayout {
                cardGrid
            } else {
                ScrollView { cardGrid }
            }
            Divider()
            footer
        }
        .background(.regularMaterial)
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
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mission Control: Capacity")
                    .font(.headline)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(refreshLabel(now: context.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
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
                Button("Open Dashboard") {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            Spacer()
            Text("10m polling")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if compact {
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func refreshLabel(now: Date) -> String {
        guard let date = store.lastRefresh else { return "Preparing first snapshot…" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "Last checked just now" }
        if seconds < 3_600 { return "Last checked \(seconds / 60)m ago" }
        if seconds < 86_400 { return "Last checked \(seconds / 3_600)h ago" }
        return "Last checked \(seconds / 86_400)d ago"
    }

    private var visibleSnapshots: [ProviderSnapshot] {
        store.snapshots.filter { $0.id != .xAI }
    }
}

private struct ProviderCard: View {
    let snapshot: ProviderSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(snapshot.id.shortName)
                    .font(.callout.weight(.bold))
                    .lineLimit(1)
                if let plan = snapshot.plan, !plan.isEmpty {
                    Text(displayPlan(plan))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                if snapshot.state != .connected {
                    Text(snapshot.state.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if snapshot.state == .error, !snapshot.windows.isEmpty {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Label(staleLabel(now: context.date), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
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
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 8) {
                        if let unreportedFiveHour {
                            UnreportedWindowRow(label: unreportedFiveHour.label)
                        }
                        ForEach(snapshot.windows) { window in
                            CapacityWindowRow(window: window, now: context.date, tint: providerColor)
                        }
                    }
                }

                if !displayMetrics.isEmpty {
                    Divider()
                    VStack(spacing: 3) {
                        ForEach(displayMetrics) { metric in
                            HStack(spacing: 6) {
                                Text(metric.label)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 4)
                                Text(metric.value)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .font(.caption2)
                }
            }
            Spacer(minLength: 0)
            BestForSection(guide: ProviderGuide.forProvider(snapshot.id), tint: providerColor)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(providerColor.opacity(0.6), lineWidth: 1.5)
        }
    }

    private var statusColor: Color {
        switch snapshot.state {
        case .connected: .green
        case .loading: .blue
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
        if seconds < 60 { return "Stale · last good update just now" }
        if seconds < 3_600 { return "Stale · last good update \(seconds / 60)m ago" }
        if seconds < 86_400 { return "Stale · last good update \(seconds / 3_600)h ago" }
        return "Stale · last good update \(seconds / 86_400)d ago"
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
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(tint)
            Text(guide.headline)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            ForEach(guide.bestFor, id: \.self) { item in
                HStack(alignment: .top, spacing: 4) {
                    Text("•")
                    Text(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("What this provider's models are generally known to be strongest at. Use it to pick where the next project goes, or where to shift when a limit runs out.")
    }
}

private struct UnreportedWindowRow: View {
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                Spacer()
                Text("Not reported")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Capsule()
                .fill(.quaternary)
                .frame(height: 4)
            Text("Not returned by the provider")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
                Text(window.label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                Spacer()
                Text(percentLabel)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(usageColor)
            }
            ProgressView(value: window.usedPercent, total: 100)
                .tint(usageColor)
                .controlSize(.mini)
            HStack {
                Text("\(format(window.remainingPercent))% left")
                Spacer()
                Text(resetLabel)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
    }

    private var percentLabel: String { "\(format(window.usedPercent))% used" }

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
