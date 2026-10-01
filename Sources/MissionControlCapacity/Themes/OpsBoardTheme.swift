import AppKit
import CapacityCore
import SwiftUI

// Ops Board: a white Swiss-style operations board. Heavy black grotesque
// headlines, monospaced metadata, hairline rules and one red accent.

// MARK: - Palette & type

private enum OpsBoardPalette {
    static let paper = Color.white
    static let ink = Color(hex: 0x111111)
    static let secondary = Color(hex: 0x5E5E5E)
    static let hairline = Color(hex: 0xDDDDDD)
    static let track = Color(hex: 0xEEEEEE)
    static let accent = Color(hex: 0xD90429)
    static let hot = Color(hex: 0xFFF1F2)
    static let dashed = Color(hex: 0xB5B5B5)
}

private enum OpsBoardFont {
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

private enum OpsBoardText {
    /// "Thu 01.10.26".
    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE dd.MM.yy"
        return formatter.string(from: date)
    }

    /// "21m", "1h 02m", "5d 14h".
    static func reset(_ account: AccountReadout, now: Date) -> String {
        ThemeText.resetText(account, now: now).lowercased()
    }

    /// "Probed 4m ago".
    static func probed(_ lastRefresh: Date?, now: Date) -> String {
        let label = ThemeText.probedLabel(lastRefresh, now: now).lowercased()
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    static func windowName(_ window: CapacityWindow) -> String {
        switch window.durationMinutes {
        case 300: "5h window"
        case 10_080: "weekly window"
        default: window.label
        }
    }

    static func keyResults(_ objective: MissionObjective) -> String {
        guard objective.keyResultsTotal > 0 else { return objective.note }
        let unit = objective.keyResultsTotal == 1 ? "KR" : "KRs"
        return "\(objective.keyResultsOnTrack)/\(objective.keyResultsTotal) \(unit)"
    }

    static func due(_ task: MissionTask, now: Date) -> String {
        guard let label = ThemeText.dueLabel(task, now: now) else { return "" }
        return label.capitalized
    }
}

// MARK: - Dashboard

struct OpsBoardDashboardView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    var staticLayout = false

    @State private var editor: MissionEditor?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        let readout = readout
        VStack(alignment: .leading, spacing: 20) {
            OpsBoardHeader(capacity: capacity, missions: missions, readout: readout)
            if let caution = readout.masterCaution {
                OpsBoardCautionBanner(caution: caution)
            }
            OpsBoardAccountGrid(readout: readout)
            GeometryReader { proxy in
                // Three task columns and a 1.2-wide side column, 20 pt apart.
                let unit = (proxy.size.width - 60) / 4.2
                HStack(alignment: .top, spacing: 20) {
                    ForEach(TaskBucket.allCases) { bucket in
                        OpsBoardTaskColumn(bucket: bucket, missions: missions, editor: $editor, staticLayout: staticLayout)
                            .frame(width: unit)
                    }
                    OpsBoardSideColumn(missions: missions, editor: $editor, staticLayout: staticLayout)
                        .frame(width: unit * 1.2)
                }
                .padding(.top, 16)
                .frame(maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .top) { Rectangle().fill(OpsBoardPalette.ink).frame(height: 1) }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OpsBoardPalette.paper)
        .foregroundStyle(OpsBoardPalette.ink)
        .missionEditorSheet($editor, missions: missions)
    }
}

// MARK: - Header

private struct OpsBoardHeader: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    let readout: CockpitReadout

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: -22) {
                    Text("Mission")
                    Text("Control") + Text(".").foregroundColor(OpsBoardPalette.accent)
                }
                .font(OpsBoardFont.sans(64, .black))
                .kerning(-2)
                .fixedSize()
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 36) {
                    stat("Today", OpsBoardText.shortDate(context.date))
                    stat(
                        "Open tasks",
                        "\(missions.board.openTaskCount) open · \(missions.board.dueTodayCount(now: context.date)) due"
                    )
                    stat(
                        "Best Claude now",
                        readout.bestClaude.map { "\($0.snapshot.account.label) · \(Int(($0.headroom ?? 0).rounded()))%" } ?? "None available",
                        color: readout.bestClaude == nil ? OpsBoardPalette.secondary : OpsBoardPalette.accent
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(OpsBoardText.probed(capacity.lastRefresh, now: context.date))
                            .foregroundStyle(OpsBoardPalette.secondary)
                        HStack(spacing: 8) {
                            Button {
                                Task { await capacity.refresh() }
                            } label: {
                                Text(capacity.isRefreshing ? "Probing…" : "↻ Re-probe")
                            }
                            .buttonStyle(OpsBoardButtonStyle())
                            .disabled(capacity.isRefreshing)
                            .help("Check every account's usage now")
                            ThemePicker { OpsBoardButtonLabel(text: "Theme ▾") }
                        }
                    }
                    .font(OpsBoardFont.mono(12))
                    .fixedSize()
                }
            }
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(OpsBoardPalette.ink).frame(height: 4) }
        }
    }

    private func stat(_ title: String, _ value: String, color: Color = OpsBoardPalette.ink) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).foregroundStyle(OpsBoardPalette.secondary)
            Text(value).fontWeight(.semibold).foregroundStyle(color)
        }
        .font(OpsBoardFont.mono(12))
        .fixedSize()
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct OpsBoardCautionBanner: View {
    let caution: AccountReadout
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            Text("Limit")
                .font(OpsBoardFont.sans(compact ? 12 : 13, .heavy))
                .textCase(.uppercase)
                .kerning(1)
            Text(detail)
                .font(OpsBoardFont.sans(compact ? 13 : 15, .semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 14)
        .padding(.vertical, compact ? 8 : 9)
        .background(OpsBoardPalette.accent)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        guard let window = caution.bindingWindow else { return caution.snapshot.account.label }
        return "\(caution.snapshot.account.label) is at \(Int(window.usedPercent.rounded()))% of its \(OpsBoardText.windowName(window)). Route work elsewhere."
    }
}

// MARK: - Accounts

private struct OpsBoardAccountGrid: View {
    let readout: CockpitReadout

    var body: some View {
        let accounts = readout.accounts
        let bestID = readout.bestClaude?.snapshot.id
        let rows = stride(from: 0, to: accounts.count, by: 4).map { Array(accounts[$0..<min($0 + 4, accounts.count)]) }
        VStack(alignment: .leading, spacing: 18) {
            if accounts.isEmpty {
                Text("No accounts configured yet. Add one to accounts.json and it appears here.")
                    .font(OpsBoardFont.mono(12))
                    .foregroundStyle(OpsBoardPalette.secondary)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<4, id: \.self) { index in
                        Group {
                            if index < row.count {
                                OpsBoardAccountCell(account: row[index], isRoute: row[index].snapshot.id == bestID)
                            } else {
                                Color.clear.frame(height: 1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.trailing, 20)
                        .overlay(alignment: .trailing) {
                            if index < row.count {
                                Rectangle().fill(OpsBoardPalette.hairline).frame(width: 1)
                            }
                        }
                        .padding(.trailing, 20)
                    }
                }
            }
        }
    }
}

private struct OpsBoardAccountCell: View {
    let account: AccountReadout
    let isRoute: Bool

    private var snapshot: ProviderSnapshot { account.snapshot }
    private var isStale: Bool { snapshot.state == .error && account.hasMeasurements }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(snapshot.account.label)
                    .font(OpsBoardFont.sans(13, .bold))
                    .lineLimit(1)
                    .help(ThemeText.guide(snapshot.provider))
                Spacer(minLength: 4)
                if account.hasMeasurements {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text("↻ \(OpsBoardText.reset(account, now: context.date))")
                            .font(OpsBoardFont.mono(13))
                            .foregroundStyle(OpsBoardPalette.secondary)
                            .fixedSize()
                            .accessibilityLabel("Resets in \(OpsBoardText.reset(account, now: context.date))")
                    }
                }
            }
            Text(ThemeText.identityLine(account))
                .font(OpsBoardFont.sans(12))
                .foregroundStyle(isStale ? OpsBoardPalette.accent : OpsBoardPalette.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if account.hasMeasurements {
                measured
            } else {
                unmeasured
            }
        }
    }

    private var measured: some View {
        let headroom = Int((account.headroom ?? 0).rounded())
        return VStack(alignment: .leading, spacing: 6) {
            (Text("\(headroom)").kerning(-3) + Text("%").font(OpsBoardFont.sans(32, .black)))
                .font(OpsBoardFont.sans(84, .black))
                .foregroundStyle(headroom <= 15 ? OpsBoardPalette.accent : OpsBoardPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: 84, alignment: .leading)
                .accessibilityLabel("Headroom")
                .accessibilityValue("\(headroom) percent")
            HStack(spacing: 6) {
                Text("headroom left")
                    .foregroundStyle(OpsBoardPalette.secondary)
                if isRoute {
                    Text("· best Claude")
                        .fontWeight(.semibold)
                        .foregroundStyle(OpsBoardPalette.accent)
                }
            }
            .font(OpsBoardFont.sans(11))
            .padding(.top, -4)
            VStack(spacing: 4) {
                OpsBoardWindowBar(code: "5h", name: "5 hour", window: account.fiveHour)
                OpsBoardWindowBar(code: "wk", name: "Weekly", window: account.weekly)
            }
            .padding(.top, 6)
            if !account.otherWindows.isEmpty {
                Text(account.otherWindows.prefix(2).map { "\($0.label) \(Int($0.usedPercent.rounded()))%" }.joined(separator: " · "))
                    .font(OpsBoardFont.mono(10))
                    .foregroundStyle(OpsBoardPalette.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var unmeasured: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.state.label)
                .font(OpsBoardFont.sans(26, .black))
                .kerning(-1)
                .foregroundStyle(snapshot.state == .loading ? OpsBoardPalette.secondary : OpsBoardPalette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 8)
            Text(snapshot.message ?? "No usage reported yet.")
                .font(OpsBoardFont.mono(10.5))
                .foregroundStyle(OpsBoardPalette.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OpsBoardPalette.track)
        }
    }
}

private struct OpsBoardWindowBar: View {
    let code: String
    let name: String
    let window: CapacityWindow?

    var body: some View {
        HStack(spacing: 8) {
            Text(code).frame(width: 20, alignment: .leading)
            if let window {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(OpsBoardPalette.track)
                        Rectangle()
                            .fill(OpsBoardPalette.ink)
                            .frame(width: proxy.size.width * min(max(window.usedPercent, 0), 100) / 100)
                    }
                }
                .frame(height: 4)
                Text("\(Int(window.usedPercent.rounded()))%")
                    .frame(width: 34, alignment: .trailing)
            } else {
                Text("no data")
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(OpsBoardFont.mono(10))
        .foregroundStyle(OpsBoardPalette.secondary)
        .frame(height: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) window")
        .accessibilityValue(window.map { "\(Int($0.usedPercent.rounded())) percent used" } ?? "No data")
    }
}

// MARK: - Task columns

private struct OpsBoardTaskColumn: View {
    let bucket: TaskBucket
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let staticLayout: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let tasks = missions.board.tasks(in: bucket, now: context.date)
            VStack(alignment: .leading, spacing: 10) {
                OpsBoardColumnHeader(title: bucket.rawValue, count: "\(tasks.count)", addHelp: "Add a task to \(bucket.rawValue.capitalized)") {
                    editor = .task(MissionTask(title: "", bucket: bucket))
                }
                OpsBoardScroll(staticLayout: staticLayout, spacing: 10) {
                    if tasks.isEmpty {
                        OpsBoardEmpty(text: bucket == .now ? "Nothing on deck. Pull a task forward or press +." : "Empty. Press + to add a task.")
                    }
                    ForEach(tasks) { task in
                        OpsBoardTaskCard(task: task, missions: missions, editor: $editor, now: context.date)
                    }
                }
            }
        }
    }
}

private struct OpsBoardTaskCard: View {
    let task: MissionTask
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let now: Date
    var compact = false

    var body: some View {
        Toggle(isOn: doneBinding(task, missions: missions)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(task.title)
                    .font(OpsBoardFont.sans(compact ? 13 : 14, .medium))
                    .lineSpacing(2)
                    .strikethrough(task.isDone, color: OpsBoardPalette.secondary)
                    .foregroundStyle(task.isDone ? OpsBoardPalette.secondary : OpsBoardPalette.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(missions.board.project(for: task)?.name ?? "No project")
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(OpsBoardText.due(task, now: now))
                        .foregroundStyle(isHot ? OpsBoardPalette.accent : OpsBoardPalette.secondary)
                        .fixedSize()
                }
                .font(OpsBoardFont.mono(10))
                .foregroundStyle(OpsBoardPalette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(OpsBoardCheckboxStyle())
        .padding(.horizontal, 14)
        .padding(.vertical, compact ? 10 : 12)
        .background(isHot ? OpsBoardPalette.hot : OpsBoardPalette.paper)
        .overlay(Rectangle().strokeBorder(OpsBoardPalette.ink, lineWidth: 1))
        .taskActions(task, missions: missions, editor: $editor)
    }

    private var isHot: Bool { task.isDue(on: now) }
}

private struct OpsBoardCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Rectangle().fill(configuration.isOn ? OpsBoardPalette.ink : OpsBoardPalette.paper)
                    Rectangle().strokeBorder(OpsBoardPalette.ink, lineWidth: 1.5)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(width: 15, height: 15)
                .padding(.top, 1)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Done" : "Open")
    }
}

// MARK: - Objectives & missions

private struct OpsBoardSideColumn: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let staticLayout: Bool

    var body: some View {
        OpsBoardScroll(staticLayout: staticLayout, spacing: 14) {
            OpsBoardColumnHeader(title: "Objectives \(missions.board.periodTitle)", addHelp: "Add an objective") {
                editor = .objective(MissionObjective(title: ""))
            }
            if missions.board.objectives.isEmpty {
                OpsBoardEmpty(text: "No objectives for \(missions.board.periodTitle) yet. Press + to set one.")
            }
            ForEach(Array(missions.board.objectives.enumerated()), id: \.element.id) { index, objective in
                OpsBoardObjectiveRow(number: index + 1, objective: objective)
                    .objectiveActions(objective, missions: missions, editor: $editor)
            }
            OpsBoardColumnHeader(title: "Missions", addHelp: "Add a project") {
                editor = .project(MissionProject(name: ""))
            }
            .padding(.top, 8)
            if missions.board.projects.isEmpty {
                OpsBoardEmpty(text: "No missions yet. Press + to add a project.")
            }
            ForEach(missions.board.projects) { project in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(project.name)
                        .font(OpsBoardFont.sans(13))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(project.phase) · \(Int(project.progress.rounded()))%")
                        .font(OpsBoardFont.mono(13))
                        .foregroundStyle(OpsBoardPalette.secondary)
                        .fixedSize()
                }
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(OpsBoardPalette.track).frame(height: 1) }
                .help(project.nextAction.isEmpty ? project.name : "Next: \(project.nextAction)")
                .projectActions(project, missions: missions, editor: $editor)
            }
            if let error = missions.saveError {
                Text(error)
                    .font(OpsBoardFont.mono(11, .semibold))
                    .foregroundStyle(OpsBoardPalette.accent)
            }
        }
        .padding(.leading, 20)
        .overlay(alignment: .leading) { Rectangle().fill(OpsBoardPalette.ink).frame(width: 4) }
    }
}

private struct OpsBoardObjectiveRow: View {
    let number: Int
    let objective: MissionObjective

    var body: some View {
        let progress = min(max(objective.progress, 0), 100)
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(OpsBoardFont.sans(28, .black))
                .foregroundStyle(OpsBoardPalette.accent)
                .frame(width: 34, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(objective.title)
                    .font(OpsBoardFont.sans(14, .bold))
                    .lineSpacing(2)
                    .lineLimit(2)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(OpsBoardPalette.track)
                        Rectangle().fill(OpsBoardPalette.ink).frame(width: proxy.size.width * progress / 100)
                    }
                }
                .frame(height: 4)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .accessibilityElement()
                .accessibilityLabel("Progress")
                .accessibilityValue("\(Int(progress.rounded())) percent")
                Text([String(Int(progress.rounded())) + "%", OpsBoardText.keyResults(objective)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(OpsBoardFont.mono(10))
                    .foregroundStyle(OpsBoardPalette.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Menu

struct OpsBoardMenuView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    var staticLayout = false
    @Environment(\.openWindow) private var openWindow
    @State private var editor: MissionEditor?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        let readout = readout
        VStack(alignment: .leading, spacing: 14) {
            header(readout)
            if let caution = readout.masterCaution {
                OpsBoardCautionBanner(caution: caution, compact: true)
            }
            if staticLayout {
                content(readout)
            } else {
                ScrollView { content(readout) }.scrollIndicators(.never)
            }
            footer
        }
        .padding(18)
        .background(OpsBoardPalette.paper)
        .foregroundStyle(OpsBoardPalette.ink)
        .missionEditorSheet($editor, missions: missions)
    }

    private func header(_ readout: CockpitReadout) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .lastTextBaseline) {
                    (Text("Mission Control") + Text(".").foregroundColor(OpsBoardPalette.accent))
                        .font(OpsBoardFont.sans(30, .black))
                        .kerning(-1)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(OpsBoardText.shortDate(context.date)).fontWeight(.semibold)
                        Text(OpsBoardText.probed(capacity.lastRefresh, now: context.date))
                            .foregroundStyle(OpsBoardPalette.secondary)
                    }
                    .font(OpsBoardFont.mono(11))
                    .fixedSize()
                }
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(OpsBoardPalette.ink).frame(height: 3) }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Best Claude now")
                        .font(OpsBoardFont.mono(11))
                        .foregroundStyle(OpsBoardPalette.secondary)
                    Spacer(minLength: 4)
                    if let best = readout.bestClaude {
                        Text("→ \(best.snapshot.account.label) · \(Int((best.headroom ?? 0).rounded()))% headroom")
                            .font(OpsBoardFont.sans(15, .heavy))
                            .foregroundStyle(OpsBoardPalette.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        Text("No Claude account available")
                            .font(OpsBoardFont.sans(14, .bold))
                            .foregroundStyle(OpsBoardPalette.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func content(_ readout: CockpitReadout) -> some View {
        let bestID = readout.bestClaude?.snapshot.id
        let tasks = missions.board.tasks(in: .now)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                ForEach(readout.accounts, id: \.snapshot.id) { account in
                    OpsBoardCompactAccount(account: account, isRoute: account.snapshot.id == bestID)
                        .padding(.vertical, 10)
                        .overlay(alignment: .top) { Rectangle().fill(OpsBoardPalette.hairline).frame(height: 1) }
                }
                if readout.accounts.isEmpty {
                    OpsBoardEmpty(text: "No accounts configured.")
                }
            }
            .overlay(alignment: .bottom) { Rectangle().fill(OpsBoardPalette.ink).frame(height: 1) }
            OpsBoardColumnHeader(title: "Now", count: "\(tasks.count)", addHelp: "Add a task to Now") {
                editor = .task(MissionTask(title: ""))
            }
            if tasks.isEmpty {
                OpsBoardEmpty(text: "Nothing in Now. Open the dashboard to plan.")
            }
            ForEach(tasks) { task in
                OpsBoardTaskCard(task: task, missions: missions, editor: $editor, now: Date(), compact: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Open Dashboard") { OpenDashboardAction(openWindow: openWindow)() }
                .buttonStyle(OpsBoardButtonStyle(filled: true))
            Button(capacity.isRefreshing ? "Probing…" : "↻ Re-probe") {
                Task { await capacity.refresh() }
            }
            .buttonStyle(OpsBoardButtonStyle())
            .disabled(capacity.isRefreshing)
            ThemePicker { OpsBoardButtonLabel(text: "Theme ▾") }
            Spacer(minLength: 0)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(OpsBoardButtonStyle())
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Rectangle().fill(OpsBoardPalette.ink).frame(height: 4) }
    }
}

private struct OpsBoardCompactAccount: View {
    let account: AccountReadout
    let isRoute: Bool

    private var snapshot: ProviderSnapshot { account.snapshot }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(snapshot.account.label)
                        .font(OpsBoardFont.sans(13, .bold))
                        .lineLimit(1)
                    if isRoute {
                        Text("best")
                            .font(OpsBoardFont.mono(10, .semibold))
                            .foregroundStyle(OpsBoardPalette.accent)
                    }
                }
                Text(ThemeText.identityLine(account))
                    .font(OpsBoardFont.sans(11))
                    .foregroundStyle(snapshot.state == .error ? OpsBoardPalette.accent : OpsBoardPalette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if account.hasMeasurements {
                    VStack(spacing: 3) {
                        OpsBoardWindowBar(code: "5h", name: "5 hour", window: account.fiveHour)
                        OpsBoardWindowBar(code: "wk", name: "Weekly", window: account.weekly)
                    }
                    .padding(.top, 4)
                } else {
                    Text(snapshot.state.label)
                        .font(OpsBoardFont.sans(12, .heavy))
                        .foregroundStyle(snapshot.state == .loading ? OpsBoardPalette.secondary : OpsBoardPalette.accent)
                        .padding(.top, 2)
                    Text(snapshot.message ?? "No usage reported yet.")
                        .font(OpsBoardFont.mono(10))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if account.hasMeasurements {
                let headroom = Int((account.headroom ?? 0).rounded())
                VStack(alignment: .trailing, spacing: 0) {
                    (Text("\(headroom)").kerning(-1.5) + Text("%").font(OpsBoardFont.sans(18, .black)))
                        .font(OpsBoardFont.sans(44, .black))
                        .foregroundStyle(headroom <= 15 ? OpsBoardPalette.accent : OpsBoardPalette.ink)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text("↻ \(OpsBoardText.reset(account, now: context.date))")
                            .font(OpsBoardFont.mono(10))
                            .foregroundStyle(OpsBoardPalette.secondary)
                    }
                }
                .fixedSize()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Headroom \(headroom) percent")
            }
        }
    }
}

// MARK: - Shared chrome

private struct OpsBoardColumnHeader: View {
    let title: String
    var count: String?
    let addHelp: String
    let add: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(OpsBoardFont.sans(14, .heavy))
                .textCase(.uppercase)
                .kerning(1)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if let count {
                Text(count)
                    .font(OpsBoardFont.mono(14))
                    .foregroundStyle(OpsBoardPalette.secondary)
            }
            Button(action: add) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .heavy))
                    .frame(width: 20, height: 20)
                    .overlay(Rectangle().strokeBorder(OpsBoardPalette.ink, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(addHelp)
            .accessibilityLabel(addHelp)
        }
    }
}

private struct OpsBoardScroll<Content: View>: View {
    let staticLayout: Bool
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if staticLayout {
            VStack(alignment: .leading, spacing: spacing) { content }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
    }
}

private struct OpsBoardEmpty: View {
    let text: String

    var body: some View {
        Text(text)
            .font(OpsBoardFont.mono(11))
            .foregroundStyle(OpsBoardPalette.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(Rectangle().strokeBorder(OpsBoardPalette.dashed, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

private struct OpsBoardButtonLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(OpsBoardFont.mono(12, .semibold))
            .foregroundStyle(OpsBoardPalette.ink)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .overlay(Rectangle().strokeBorder(OpsBoardPalette.ink, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

private struct OpsBoardButtonStyle: ButtonStyle {
    var filled = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let inverted = filled != configuration.isPressed
        configuration.label
            .font(OpsBoardFont.mono(12, .semibold))
            .lineLimit(1)
            .foregroundStyle(inverted ? Color.white : (isEnabled ? OpsBoardPalette.ink : OpsBoardPalette.secondary))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(inverted ? OpsBoardPalette.ink : OpsBoardPalette.paper)
            .overlay(Rectangle().strokeBorder(OpsBoardPalette.ink, lineWidth: 1))
            .contentShape(Rectangle())
            .fixedSize()
    }
}
