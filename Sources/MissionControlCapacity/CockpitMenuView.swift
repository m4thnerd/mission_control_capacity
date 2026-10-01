import AppKit
import CapacityCore
import SwiftUI

/// Menu-bar popover: routing, caution, each account's dials and the NOW switches.
struct CockpitMenuView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    var staticLayout = false
    @Environment(\.openWindow) private var openWindow
    @State private var editor: MissionEditor?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        VStack(spacing: 10) {
            annunciators
            if staticLayout {
                panelContent
            } else {
                ScrollView { panelContent }.scrollIndicators(.never)
            }
            footer
        }
        .padding(12)
        .background(Cockpit.panel)
        .foregroundStyle(Cockpit.text)
    }

    private var panelContent: some View {
        VStack(spacing: 10) {
            ForEach(readout.accounts, id: \.snapshot.id) { account in
                CompactAccountRow(account: account, isRoute: account.snapshot.id == readout.bestClaude?.snapshot.id)
            }
            nowSwitches
        }
    }

    private var annunciators: some View {
        HStack(spacing: 8) {
            VStack(spacing: 0) {
                Text("ROUTE CLAUDE").font(Cockpit.label(9, .semibold)).kerning(2)
                Text(readout.bestClaude.map { "→ \($0.snapshot.account.label.uppercased()) · \(Int($0.headroom ?? 0))%" } ?? "NO ACCOUNT")
                    .font(Cockpit.label(13, .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(readout.bestClaude == nil ? Cockpit.dim : Cockpit.routeInk)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(readout.bestClaude == nil ? Cockpit.lampOff : Cockpit.routeGreen, in: RoundedRectangle(cornerRadius: 4))

            VStack(spacing: 0) {
                Text("MASTER CAUTION").font(Cockpit.label(11, .bold)).kerning(2)
                if let caution = readout.masterCaution, let peak = caution.peakUsed {
                    Text("\(caution.snapshot.account.label.uppercased()) \(Int(peak.rounded()))%")
                        .font(Cockpit.label(9, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(readout.masterCaution == nil ? Cockpit.dim : Cockpit.amberInk)
            .frame(width: 150, height: 40)
            .background(readout.masterCaution == nil ? Cockpit.lampOff : Cockpit.amber, in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(6)
        .background(Cockpit.plate, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Cockpit.plateBorder, lineWidth: 1))
    }

    private var nowSwitches: some View {
        let tasks = missions.board.tasks(in: .now)
        return VStack(alignment: .leading, spacing: 6) {
            Placard(text: "NOW · \(tasks.count) \(tasks.count == 1 ? "SWITCH" : "SWITCHES")", size: 12)
                .frame(maxWidth: .infinity)
            ForEach(tasks) { task in
                TaskSwitchRow(task: task, missions: missions, editor: $editor, now: Date())
            }
            if tasks.isEmpty {
                Text("Nothing in NOW. Open the dashboard to plan.")
                    .font(Cockpit.typewriter(11))
                    .foregroundStyle(Cockpit.secondary)
            }
        }
        .padding(14)
        .panelPlate()
        .missionEditorSheet($editor, missions: missions)
    }

    private var footer: some View {
        HStack {
            Button("OPEN DASHBOARD") {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            }
            Spacer()
            Button(capacity.isRefreshing ? "PROBING…" : "RE-PROBE") {
                Task { await capacity.refresh() }
            }
            .disabled(capacity.isRefreshing)
            Spacer()
            ThemePicker { Text("THEME ▾") }
            Spacer()
            Button("QUIT") { NSApp.terminate(nil) }
        }
        .font(Cockpit.label(11, .semibold))
        .kerning(1.5)
        .buttonStyle(.plain)
        .foregroundStyle(Cockpit.secondary)
        .padding(.horizontal, 6)
    }
}

private struct CompactAccountRow: View {
    let account: AccountReadout
    let isRoute: Bool

    var body: some View {
        HStack(spacing: 10) {
            DialGauge(value: account.fiveHour?.usedPercent, label: "5 HOUR", size: 92)
            DialGauge(value: account.weekly?.usedPercent, label: "WEEKLY", size: 92)
            VStack(alignment: .leading, spacing: 5) {
                Text(account.snapshot.account.label.uppercased())
                    .font(Cockpit.label(13, .semibold))
                    .kerning(1.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if account.hasMeasurements {
                    Odometer(value: account.headroom.map { Int($0.rounded()) })
                    HStack(spacing: 4) {
                        Lamp(text: "LIMIT", isOn: account.isNearLimit, color: Cockpit.amber, ink: Cockpit.amberInk, width: 50)
                        Lamp(text: "ROUTE", isOn: isRoute, color: Cockpit.routeGreen, ink: Cockpit.routeInk, width: 50)
                    }
                } else {
                    Text(account.snapshot.state.label.uppercased())
                        .font(Cockpit.typewriter(11, bold: true))
                        .foregroundStyle(Cockpit.amber)
                    Text(account.snapshot.message ?? "")
                        .font(Cockpit.typewriter(10))
                        .foregroundStyle(Cockpit.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .panelPlate(border: account.isNearLimit ? Cockpit.amber : Cockpit.subpanelBorder, width: account.isNearLimit ? 2 : 1)
    }
}
