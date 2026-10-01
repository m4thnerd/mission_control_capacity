import AppKit
import CapacityCore
import SwiftUI

/// Full instrument panel: account gauges above projects, objectives and tasks.
struct CockpitDashboardView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    /// Draws without scroll views, for the preview renderer.
    var staticLayout = false

    @State private var editor: MissionEditor?
    @State private var acknowledgedCaution: String?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        VStack(spacing: 14) {
            header.frame(height: 66)
            accountRow
            GeometryReader { proxy in
                // Columns share the width 1.25 : 1 : 1.1, as on the approved design.
                let unit = (proxy.size.width - 32) / 3.35
                HStack(alignment: .top, spacing: 16) {
                    ProjectsPanel(missions: missions, editor: $editor, staticLayout: staticLayout)
                        .frame(width: unit * 1.25)
                    ObjectivesPanel(missions: missions, readout: readout, editor: $editor, staticLayout: staticLayout)
                        .frame(width: unit)
                    TaskSwitchPanel(missions: missions, editor: $editor, staticLayout: staticLayout)
                        .frame(width: unit * 1.1)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Cockpit.panel)
        .foregroundStyle(Cockpit.text)
        .missionEditorSheet($editor, missions: missions)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            titlePlate
            RouteAnnunciator(best: readout.bestClaude)
                .frame(width: 380)
            MasterCautionButton(
                caution: readout.masterCaution,
                acknowledged: readout.masterCaution.map { cautionKey($0) == acknowledgedCaution } ?? false
            ) {
                acknowledgedCaution = readout.masterCaution.map(cautionKey)
            }
            .frame(width: 250)
        }
    }

    private func cautionKey(_ account: AccountReadout) -> String {
        "\(account.snapshot.id)-\(Int(account.peakUsed ?? 0))"
    }

    private var titlePlate: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("MISSION CONTROL")
                    .font(Cockpit.label(28, .semibold))
                    .kerning(4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                ThemePicker {
                    Text("CAPACITY & OPERATIONS · MODEL MC-1  ▾")
                        .font(Cockpit.label(11))
                        .kerning(2)
                        .foregroundStyle(Cockpit.secondary)
                }
            }
            Spacer(minLength: 16)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(spacing: 20) {
                    headerReading("DATE", ThemeText.plateDate(context.date))
                    headerReading(
                        "TASKS OPEN",
                        "\(missions.board.openTaskCount) · \(missions.board.dueTodayCount(now: context.date)) DUE TODAY"
                    )
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(ThemeText.probedLabel(capacity.lastRefresh, now: context.date))
                            .font(Cockpit.label(10))
                            .kerning(2)
                            .foregroundStyle(Cockpit.secondary)
                        Button {
                            Task { await capacity.refresh() }
                        } label: {
                            Text(capacity.isRefreshing ? "PROBING…" : "RE-PROBE")
                                .font(Cockpit.label(12, .semibold))
                                .kerning(2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(Cockpit.subpanel, in: RoundedRectangle(cornerRadius: 3))
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Cockpit.plateBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(capacity.isRefreshing)
                        .help("Check every account's usage now")
                    }
                    .fixedSize()
                }
            }
        }
        .padding(.leading, 34)
        .padding(.trailing, 32)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Cockpit.plate, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Cockpit.plateBorder, lineWidth: 1))
        .overlay(alignment: .leading) { Screw(rotation: 35).padding(.leading, 14) }
        .overlay(alignment: .trailing) { Screw(rotation: -15).padding(.trailing, 14) }
    }

    private func headerReading(_ title: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(title).font(Cockpit.label(10)).kerning(2).foregroundStyle(Cockpit.secondary)
            Text(value).font(Cockpit.label(17)).kerning(1.5)
        }
        .fixedSize()
    }


    // MARK: Accounts

    private var accountRow: some View {
        let accounts = readout.accounts
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: max(1, min(accounts.count, 4)))
        let bestID = readout.bestClaude?.snapshot.id
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(accounts, id: \.snapshot.id) { account in
                AccountInstrumentCard(account: account, isRoute: account.snapshot.id == bestID)
            }
        }
    }
}

// MARK: - Header instruments

private struct RouteAnnunciator: View {
    let best: AccountReadout?

    var body: some View {
        VStack(spacing: 1) {
            Text("ROUTE NEXT CLAUDE SESSION")
                .font(Cockpit.label(11, .semibold))
                .kerning(3)
            Text(routeText)
                .font(Cockpit.label(19, .bold))
                .kerning(1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(best == nil ? Cockpit.dim : Cockpit.routeInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(best == nil ? Cockpit.lampOff : Cockpit.routeGreen, in: RoundedRectangle(cornerRadius: 4))
        .shadow(color: best == nil ? .clear : Cockpit.routeGreen.opacity(0.45), radius: 8)
        .padding(7)
        .background(Cockpit.plate, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Cockpit.plateBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var routeText: String {
        guard let best else { return "NO CLAUDE ACCOUNT AVAILABLE" }
        return "→ \(best.snapshot.account.label.uppercased()) · \(Int(best.headroom ?? 0))% HEADROOM"
    }
}

private struct MasterCautionButton: View {
    let caution: AccountReadout?
    let acknowledged: Bool
    let acknowledge: () -> Void

    private var lit: Bool { caution != nil && !acknowledged }

    var body: some View {
        Button(action: acknowledge) {
            VStack(spacing: 0) {
                Text("MASTER CAUTION")
                    .font(Cockpit.label(18, .bold))
                    .kerning(3)
                Text(detail)
                    .font(Cockpit.label(11, .semibold))
                    .kerning(1.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(lit ? Cockpit.amberInk : Cockpit.dim)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(lit ? Cockpit.amber : Cockpit.lampOff, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Cockpit.bezel, lineWidth: 2))
            .shadow(color: lit ? Cockpit.amber.opacity(0.6) : .clear, radius: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(caution == nil)
        .padding(7)
        .background(Cockpit.plate, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Cockpit.plateBorder, lineWidth: 1))
        .help(caution == nil ? "No account is near its limit." : "Push to acknowledge. It lights again if usage climbs.")
    }

    private var detail: String {
        guard let caution, let window = caution.bindingWindow else { return "ALL ACCOUNTS NORMAL" }
        let name = window.durationMinutes == 300 ? "5H" : "WK"
        return "\(caution.snapshot.account.label.uppercased()) · \(name) \(Int(window.usedPercent.rounded()))%"
    }
}

// MARK: - Account card

struct AccountInstrumentCard: View {
    let account: AccountReadout
    let isRoute: Bool
    var dialSize: CGFloat = 132

    private var snapshot: ProviderSnapshot { account.snapshot }

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 3) {
                Placard(text: snapshot.account.label.uppercased())
                    .help(guideText)
                Text(identityLine)
                    .font(Cockpit.typewriter(11))
                    .foregroundStyle(isStale ? Cockpit.amber : Cockpit.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 14)

            HStack(spacing: 10) {
                DialGauge(value: account.fiveHour?.usedPercent, label: "5 HOUR", size: dialSize)
                DialGauge(value: account.weekly?.usedPercent, label: "WEEKLY", size: dialSize)
            }

            if account.hasMeasurements {
                readings
                ForEach(account.otherWindows.prefix(2)) { window in
                    Text("\(window.label.uppercased()) · \(Int(window.usedPercent.rounded()))%")
                        .font(Cockpit.typewriter(10.5))
                        .foregroundStyle(Cockpit.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                LogStrip {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.state.label.uppercased()).bold()
                        Text(snapshot.message ?? "No usage reported yet.")
                            .font(Cockpit.typewriter(11))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .panelPlate(border: account.isNearLimit ? Cockpit.amber : Cockpit.subpanelBorder, width: account.isNearLimit ? 2 : 1)
    }

    private var readings: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("HEADROOM %").font(Cockpit.label(9)).kerning(2).foregroundStyle(Cockpit.secondary)
                    Odometer(value: account.headroom.map { Int($0.rounded()) })
                }
                HStack(spacing: 6) {
                    ResetClock(fraction: clockFraction(now: context.date), hand: Cockpit.amber)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("RESETS IN").font(Cockpit.label(9)).kerning(2).foregroundStyle(Cockpit.secondary)
                        Text(resetText(now: context.date))
                            .font(Cockpit.label(16, .semibold))
                            .kerning(1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Lamp(text: "LIMIT", isOn: account.isNearLimit, color: Cockpit.amber, ink: Cockpit.amberInk)
                    Lamp(text: "ROUTE", isOn: isRoute, color: Cockpit.routeGreen, ink: Cockpit.routeInk)
                }
            }
        }
    }

    private var isStale: Bool { snapshot.state == .error && account.hasMeasurements }

    private var identityLine: String { ThemeText.identityLine(account) }

    private var guideText: String { ThemeText.guide(snapshot.provider) }

    private func clockFraction(now: Date) -> Double? { ThemeText.resetFraction(account, now: now) }

    private func resetText(now: Date) -> String { ThemeText.resetText(account, now: now) }
}

// MARK: - Projects

private struct ProjectsPanel: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let staticLayout: Bool

    var body: some View {
        PanelSection(title: "PROJECTS · PROGRESS GAUGES", addHelp: "Add a project", staticLayout: staticLayout) {
            editor = .project(MissionProject(name: ""))
        } content: {
            if missions.board.projects.isEmpty {
                EmptyPlate(text: "No projects yet. Use + to add one.")
            }
            ForEach(missions.board.projects) { project in
                HStack(spacing: 12) {
                    ProgressGauge(value: project.progress, tint: Cockpit.amber)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name).font(Cockpit.label(16)).lineLimit(2)
                        HStack(spacing: 6) {
                            Text(project.phase.uppercased())
                                .font(Cockpit.label(10, .semibold))
                                .kerning(2)
                                .padding(.horizontal, 7)
                                .background(Cockpit.plate, in: RoundedRectangle(cornerRadius: 2))
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Cockpit.plateBorder, lineWidth: 1))
                            Text("\(Int(project.progress.rounded()))%")
                                .font(Cockpit.label(12))
                                .foregroundStyle(Cockpit.secondary)
                        }
                    }
                    .frame(width: 132, alignment: .leading)
                    LogStrip {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("NEXT").font(Cockpit.typewriter(12.5, bold: true))
                            Text(project.nextAction.isEmpty ? "—" : project.nextAction).lineLimit(2)
                        }
                    }
                }
                .projectActions(project, missions: missions, editor: $editor)
            }
        }
    }
}

// MARK: - Objectives

private struct ObjectivesPanel: View {
    @ObservedObject var missions: MissionStore
    let readout: CockpitReadout
    @Binding var editor: MissionEditor?
    let staticLayout: Bool

    var body: some View {
        PanelSection(
            title: "OBJECTIVES · \(missions.board.periodTitle.uppercased())",
            addHelp: "Add an objective",
            staticLayout: staticLayout
        ) {
            editor = .objective(MissionObjective(title: ""))
        } content: {
            if missions.board.objectives.isEmpty {
                EmptyPlate(text: "No objectives yet. Use + to add one.")
            }
            ForEach(missions.board.objectives) { objective in
                HStack(spacing: 12) {
                    SemicircleGauge(value: objective.progress)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(objective.title).font(Cockpit.label(15)).lineLimit(2)
                        HStack(spacing: 10) {
                            Text("\(Int(objective.progress.rounded()))%").font(Cockpit.label(22, .semibold))
                            HStack(spacing: 3) {
                                ForEach(0..<objective.keyResultsTotal, id: \.self) { index in
                                    Circle()
                                        .fill(index < objective.keyResultsOnTrack ? Cockpit.routeGreen : Cockpit.lampOff)
                                        .overlay(Circle().stroke(Cockpit.bezel, lineWidth: 1))
                                        .frame(width: 12, height: 12)
                                }
                            }
                        }
                        if !objective.summary.isEmpty {
                            Text(objective.summary).font(Cockpit.typewriter(11.5)).foregroundStyle(Cockpit.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .objectiveActions(objective, missions: missions, editor: $editor)
            }
        } footer: {
            LogStrip {
                VStack(alignment: .leading, spacing: 1) {
                    Text("LOGBOOK · \(ThemeText.plateDate(Date()))")
                        .font(Cockpit.typewriter(12, bold: true))
                    ForEach(logEntries, id: \.self) { Text($0).font(Cockpit.typewriter(12)) }
                    if let error = missions.saveError {
                        Text(error).font(Cockpit.typewriter(12, bold: true))
                    }
                }
            }
        }
    }

    private var logEntries: [String] { ThemeText.briefing(readout) }
}

// MARK: - Tasks

private struct TaskSwitchPanel: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let staticLayout: Bool

    var body: some View {
        PanelSection(title: "TASK SWITCH PANEL", addHelp: "Add a task", staticLayout: staticLayout) {
            editor = .task(MissionTask(title: ""))
        } content: {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(TaskBucket.allCases) { bucket in
                        let tasks = missions.board.tasks(in: bucket, now: context.date)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text(bucket.title)
                                    .font(Cockpit.label(12, .semibold))
                                    .kerning(3)
                                    .foregroundStyle(bucket == .now ? Cockpit.amber : Cockpit.text)
                                Rectangle().fill(Cockpit.plateBorder).frame(height: 1)
                                Text("\(tasks.count) \(tasks.count == 1 ? "SWITCH" : "SWITCHES")")
                                    .font(Cockpit.label(11))
                                    .foregroundStyle(Cockpit.secondary)
                            }
                            ForEach(tasks) { task in
                                TaskSwitchRow(task: task, missions: missions, editor: $editor, now: context.date)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct TaskSwitchRow: View {
    let task: MissionTask
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let now: Date

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: doneBinding(task, missions: missions)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(Cockpit.label(14.5))
                        .strikethrough(task.isDone, color: Cockpit.secondary)
                        .foregroundStyle(task.isDone ? Cockpit.secondary : Cockpit.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let project = missions.board.project(for: task) {
                        Text(project.name).font(Cockpit.typewriter(11)).foregroundStyle(Cockpit.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(LeverSwitchStyle(tint: Cockpit.amber))
            if let label = dueLabel {
                Text(label)
                    .font(Cockpit.label(10, .semibold))
                    .kerning(1.5)
                    .foregroundStyle(isDue ? Cockpit.amberInk : Cockpit.text)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(isDue ? Cockpit.amber : Cockpit.plate, in: RoundedRectangle(cornerRadius: 2))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Cockpit.bezel, lineWidth: 1))
            }
        }
        .taskActions(task, missions: missions, editor: $editor)
    }

    private var isDue: Bool { task.isDue(on: now) }

    private var dueLabel: String? { ThemeText.dueLabel(task, now: now) }
}

// MARK: - Shared panel chrome

private struct PanelSection<Content: View, Footer: View>: View {
    let title: String
    let addHelp: String
    let staticLayout: Bool
    let add: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    init(
        title: String,
        addHelp: String,
        staticLayout: Bool,
        add: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) {
        self.title = title
        self.addHelp = addHelp
        self.staticLayout = staticLayout
        self.add = add
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Placard(text: title)
                HStack {
                    Spacer()
                    Button(action: add) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 24, height: 22)
                            .background(Cockpit.plate, in: RoundedRectangle(cornerRadius: 3))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Cockpit.plateBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(addHelp)
                    .accessibilityLabel(addHelp)
                }
            }
            if staticLayout {
                VStack(alignment: .leading, spacing: 9) { content }
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) { content }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
            }
            footer
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .panelPlate()
    }
}

private struct EmptyPlate: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Cockpit.typewriter(12))
            .foregroundStyle(Cockpit.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
