import AppKit
import CapacityCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: CapacityStore
    let compact: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            GeometryReader { proxy in
                let cardHeight = max(180, (proxy.size.height - 30) / 2)
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(visibleSnapshots) { snapshot in
                        ProviderCard(snapshot: snapshot)
                            .frame(height: cardHeight, alignment: .top)
                    }
                }
                .padding(10)
            }
            Divider()
            footer
        }
        .background(.regularMaterial)
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
                        if hasUnreportedFiveHour {
                            UnreportedWindowRow()
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
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.separator.opacity(0.35), lineWidth: 1)
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

    private var hasUnreportedFiveHour: Bool {
        snapshot.metrics.contains { $0.label == "5-hour" && $0.value == "Not reported" }
    }

    private var displayMetrics: [CapacityMetric] {
        snapshot.metrics.filter { $0.label != "5-hour" }
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

private struct UnreportedWindowRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("5 hours")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("Not reported")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Capsule()
                .fill(.quaternary)
                .frame(height: 4)
            Text("Codex does not expose this window")
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
                    .lineLimit(1)
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
