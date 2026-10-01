import AppKit
import CapacityCore
import SwiftUI

// Flight Deck: a dark mission-control console on a faint 32 pt grid, with
// condensed headings, monospaced readouts and amber accents.

// MARK: - Palette & type

private enum FlightDeckPalette {
    static let background = Color(hex: 0x0B0F14)
    static let card = Color(hex: 0x111821)
    static let rule = Color(hex: 0x1E2A36)
    static let control = Color(hex: 0x2A3846)
    static let controlStrong = Color(hex: 0x4A5D70)
    static let track = Color(hex: 0x1A2430)
    static let text = Color(hex: 0xD7E2EA)
    static let secondary = Color(hex: 0x8595A3)
    static let accent = Color(hex: 0xFFB347)
    static let green = Color(hex: 0x5BD68A)
    static let greenBorder = Color(hex: 0x2B5C3E)
    static let orange = Color(hex: 0xFF8A4C)
    static let orangeBorder = Color(hex: 0x6B3A1E)
    static let red = Color(hex: 0xFF5A5F)
    static let cyan = Color(hex: 0x4CC9F0)
    static let violet = Color(hex: 0xB49CFF)
    static let idle = Color(hex: 0x4A5866)
    static let neutralPhase = Color(hex: 0x9FB3C4)

    /// Green below 65 %, orange to 85 %, red beyond.
    static func tone(_ used: Double) -> Color {
        used >= AccountReadout.cautionThreshold ? red : used >= 65 ? orange : green
    }

    static func phase(_ phase: String) -> Color {
        switch phase.lowercased() {
        case "build", "building": cyan
        case "launch", "live", "ship", "shipped": green
        case "beta", "test", "testing": accent
        case "design", "discovery", "plan", "planning": violet
        default: neutralPhase
        }
    }
}

private enum FlightDeckFont {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func condensed(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
}

private enum FlightDeckText {
    /// "5H" / "WK" for the window that is binding.
    static func windowCode(_ window: CapacityWindow) -> String {
        switch window.durationMinutes {
        case 300: "5H"
        case 10_080: "WK"
        default: window.label.uppercased()
        }
    }

    /// A short project tag: initials for multi-word names, else the first three letters.
    static func tag(_ project: MissionProject) -> String {
        let words = project.name.split(whereSeparator: { $0 == " " || $0 == "-" }).filter { !$0.isEmpty }
        if words.count > 1 {
            return String(words.prefix(4).compactMap(\.first)).uppercased()
        }
        return String(project.name.prefix(3)).uppercased()
    }

    static func weekLabel(_ periodTitle: String, now: Date) -> String {
        let week = Calendar.current.component(.weekOfYear, from: now)
        return "\(periodTitle.uppercased()) · WK \(week)"
    }

    static func logTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Dashboard

struct FlightDeckDashboardView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    var staticLayout = false

    @State private var editor: MissionEditor?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        let readout = readout
        VStack(spacing: 0) {
            FlightDeckHeader(capacity: capacity, missions: missions, readout: readout)
                .frame(height: 64)
            FlightDeckRule()
            GeometryReader { proxy in
                // Columns share the width 1.3 : 1 : 1, as on the approved design.
                let unit = (proxy.size.width - 2) / 3.3
                HStack(spacing: 1) {
                    FlightDeckCapacityColumn(readout: readout, staticLayout: staticLayout)
                        .frame(width: unit * 1.3)
                    FlightDeckMissionsColumn(missions: missions, editor: $editor, staticLayout: staticLayout)
                        .frame(width: unit)
                    FlightDeckObjectivesColumn(missions: missions, editor: $editor, staticLayout: staticLayout)
                        .frame(maxWidth: .infinity)
                }
                .background(FlightDeckPalette.rule)
            }
            FlightDeckRule()
            FlightDeckEventLog(readout: readout, missions: missions)
                .frame(height: 44)
        }
        .background(FlightDeckGridBackground())
        .background(FlightDeckPalette.background)
        .foregroundStyle(FlightDeckPalette.text)
        .missionEditorSheet($editor, missions: missions)
    }
}

// MARK: - Header

private struct FlightDeckHeader: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    let readout: CockpitReadout

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 24) {
                HStack(spacing: 12) {
                    FlightDeckBeacon(size: 22)
                    Text("MISSION CONTROL")
                        .font(FlightDeckFont.condensed(18, .bold))
                        .kerning(3)
                        .fixedSize()
                }
                ViewThatFits(in: .horizontal) {
                    readings(now: context.date, includeWeek: true)
                    readings(now: context.date, includeWeek: false)
                    EmptyView()
                }
                Spacer(minLength: 0)
                statusChips
                Text(ThemeText.probedLabel(capacity.lastRefresh, now: context.date))
                    .font(FlightDeckFont.mono(11))
                    .kerning(1)
                    .foregroundStyle(FlightDeckPalette.secondary)
                    .fixedSize()
                Button {
                    Task { await capacity.refresh() }
                } label: {
                    Text(capacity.isRefreshing ? "PROBING…" : "RE-PROBE")
                }
                .buttonStyle(FlightDeckButtonStyle())
                .disabled(capacity.isRefreshing)
                .help("Check every account's usage now")
                ThemePicker {
                    FlightDeckButtonLabel(text: "THEME ▾")
                }
            }
            .padding(.horizontal, 28)
        }
    }

    private func readings(now: Date, includeWeek: Bool) -> some View {
        HStack(spacing: 24) {
            reading(ThemeText.plateDate(now))
            if includeWeek {
                reading(FlightDeckText.weekLabel(missions.board.periodTitle, now: now))
            }
            reading("TASKS \(missions.board.openTaskCount) OPEN · \(missions.board.dueTodayCount(now: now)) DUE")
        }
        .fixedSize()
    }

    private func reading(_ text: String) -> some View {
        Text(text)
            .font(FlightDeckFont.mono(12))
            .kerning(1)
            .foregroundStyle(FlightDeckPalette.secondary)
    }

    private var statusChips: some View {
        let accounts = readout.accounts
        let caution = accounts.filter(\.isNearLimit).count
        let offline = accounts.filter { !$0.hasMeasurements }.count
        let nominal = accounts.count - caution - offline
        return HStack(spacing: 8) {
            if nominal > 0 {
                FlightDeckChip(text: "\(nominal) NOMINAL", ink: FlightDeckPalette.green, border: FlightDeckPalette.greenBorder)
            }
            if caution > 0 {
                FlightDeckChip(text: "\(caution) CAUTION", ink: FlightDeckPalette.orange, border: FlightDeckPalette.orangeBorder)
            }
            if offline > 0 {
                FlightDeckChip(text: "\(offline) NO SIGNAL", ink: FlightDeckPalette.secondary, border: FlightDeckPalette.control)
            }
        }
        .fixedSize()
    }
}

// MARK: - 01 Capacity

private struct FlightDeckCapacityColumn: View {
    let readout: CockpitReadout
    let staticLayout: Bool

    var body: some View {
        let accounts = readout.accounts
        let bestID = readout.bestClaude?.snapshot.id
        VStack(alignment: .leading, spacing: 14) {
            FlightDeckSectionHeader(title: "01 · PROPELLANT / AI CAPACITY", trailing: "5H · WEEK")
            FlightDeckScroll(staticLayout: staticLayout) {
                if accounts.isEmpty {
                    FlightDeckEmpty(text: "No accounts configured. Add one to accounts.json to start probing.")
                } else if accounts.count <= 4 {
                    VStack(spacing: 14) {
                        ForEach(accounts, id: \.snapshot.id) { account in
                            FlightDeckAccountCard(account: account, isRoute: account.snapshot.id == bestID)
                        }
                    }
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10, alignment: .top), GridItem(.flexible(), spacing: 10, alignment: .top)],
                        spacing: 10
                    ) {
                        ForEach(accounts, id: \.snapshot.id) { account in
                            FlightDeckAccountCard(account: account, isRoute: account.snapshot.id == bestID, compact: true)
                        }
                    }
                }
            }
            FlightDeckGoNoGo(best: readout.bestClaude)
        }
        .flightDeckColumn()
    }
}

private struct FlightDeckAccountCard: View {
    let account: AccountReadout
    let isRoute: Bool
    var compact = false

    private var snapshot: ProviderSnapshot { account.snapshot }
    private var isStale: Bool { snapshot.state == .error && account.hasMeasurements }

    private var dotColor: Color {
        account.peakUsed.map(FlightDeckPalette.tone) ?? FlightDeckPalette.idle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            titleRow
            if compact {
                Text(ThemeText.identityLine(account))
                    .font(FlightDeckFont.mono(10.5))
                    .foregroundStyle(isStale ? FlightDeckPalette.orange : FlightDeckPalette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if account.hasMeasurements {
                VStack(spacing: 6) {
                    FlightDeckWindowRow(code: "5H", name: "5 hour", window: account.fiveHour)
                    FlightDeckWindowRow(code: "WK", name: "Weekly", window: account.weekly)
                }
                if !account.otherWindows.isEmpty {
                    Text(account.otherWindows.prefix(2).map { "\($0.label.uppercased()) \(Int($0.usedPercent.rounded()))%" }.joined(separator: " · "))
                        .font(FlightDeckFont.mono(10))
                        .foregroundStyle(FlightDeckPalette.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("▲ \(snapshot.state.label.uppercased())")
                        .font(FlightDeckFont.mono(11, .semibold))
                        .kerning(1)
                        .foregroundStyle(snapshot.state == .loading ? FlightDeckPalette.secondary : FlightDeckPalette.orange)
                    Text(snapshot.message ?? "No usage reported yet.")
                        .font(FlightDeckFont.mono(11))
                        .foregroundStyle(FlightDeckPalette.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FlightDeckPalette.card)
        .overlay(
            Rectangle().strokeBorder(account.isNearLimit ? FlightDeckPalette.orangeBorder : FlightDeckPalette.rule, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            if account.isNearLimit {
                Rectangle().fill(FlightDeckPalette.orange).frame(width: 2)
            }
        }
    }

    private var titleRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .shadow(color: dotColor.opacity(account.hasMeasurements ? 0.9 : 0), radius: 4)
                .accessibilityHidden(true)
            Text(snapshot.account.label)
                .font(FlightDeckFont.condensed(compact ? 15 : 16, .semibold))
                .kerning(0.5)
                .lineLimit(1)
                .layoutPriority(2)
                .help(ThemeText.guide(snapshot.provider))
            if !compact {
                Text(ThemeText.identityLine(account))
                    .font(FlightDeckFont.mono(11))
                    .foregroundStyle(isStale ? FlightDeckPalette.orange : FlightDeckPalette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if isRoute {
                Text("ROUTE")
                    .font(FlightDeckFont.mono(9.5, .semibold))
                    .kerning(1)
                    .foregroundStyle(FlightDeckPalette.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(Rectangle().strokeBorder(FlightDeckPalette.accent.opacity(0.6), lineWidth: 1))
                    .fixedSize()
            }
            if account.hasMeasurements {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("T−\(ThemeText.resetText(account, now: context.date))")
                        .font(FlightDeckFont.mono(11))
                        .foregroundStyle(FlightDeckPalette.secondary)
                        .fixedSize()
                        .accessibilityLabel("Resets in \(ThemeText.resetText(account, now: context.date))")
                }
            }
        }
    }
}

private struct FlightDeckWindowRow: View {
    let code: String
    let name: String
    let window: CapacityWindow?

    var body: some View {
        HStack(spacing: 10) {
            Text(code)
                .foregroundStyle(FlightDeckPalette.secondary)
                .frame(width: 26, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(FlightDeckPalette.track)
                    if let window {
                        Rectangle()
                            .fill(FlightDeckPalette.tone(window.usedPercent))
                            .frame(width: proxy.size.width * min(max(window.usedPercent, 0), 100) / 100)
                    } else {
                        FlightDeckHatch().foregroundStyle(FlightDeckPalette.control)
                    }
                }
            }
            .frame(height: 8)
            Text(window.map { "\(Int($0.usedPercent.rounded()))%" } ?? "NO DATA")
                .foregroundStyle(window == nil ? FlightDeckPalette.secondary : FlightDeckPalette.text)
                .frame(width: 58, alignment: .trailing)
        }
        .font(FlightDeckFont.mono(11))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) window")
        .accessibilityValue(window.map { "\(Int($0.usedPercent.rounded())) percent used" } ?? "No data")
    }
}

/// Diagonal hatching for a window that reported nothing.
private struct FlightDeckHatch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 6
        }
        return path.strokedPath(StrokeStyle(lineWidth: 1))
    }
}

private struct FlightDeckGoNoGo: View {
    let best: AccountReadout?
    var compact = false

    var body: some View {
        message
            .font(FlightDeckFont.mono(compact ? 11.5 : 12))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                Rectangle().strokeBorder(
                    best == nil ? FlightDeckPalette.controlStrong : FlightDeckPalette.accent,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
            )
            .accessibilityElement(children: .combine)
    }

    private var message: Text {
        guard let best else {
            return Text("NO-GO ▸ ").foregroundColor(FlightDeckPalette.secondary).bold()
                + Text("No Claude account available — sign in or wait for a reset.")
                .foregroundColor(FlightDeckPalette.secondary)
        }
        return Text("GO/NO-GO ▸ ").foregroundColor(FlightDeckPalette.accent).bold()
            + Text("Route next Claude session to ")
            + Text(best.snapshot.account.label).bold()
            + Text(" · \(Int((best.headroom ?? 0).rounded()))% headroom")
    }
}

// MARK: - 02 Missions

private struct FlightDeckMissionsColumn: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let staticLayout: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FlightDeckSectionHeader(title: "02 · ACTIVE MISSIONS", addHelp: "Add a project") {
                editor = .project(MissionProject(name: ""))
            }
            FlightDeckScroll(staticLayout: staticLayout) {
                if missions.board.projects.isEmpty {
                    FlightDeckEmpty(text: "No missions on the board yet. Use + to add your first project.")
                }
                ForEach(missions.board.projects) { project in
                    FlightDeckProjectRow(project: project)
                        .projectActions(project, missions: missions, editor: $editor)
                }
            }
        }
        .flightDeckColumn()
    }
}

private struct FlightDeckProjectRow: View {
    let project: MissionProject

    var body: some View {
        let color = FlightDeckPalette.phase(project.phase)
        let lit = Int((min(max(project.progress, 0), 100) / 5).rounded())
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(project.name)
                    .font(FlightDeckFont.condensed(16, .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(project.phase.uppercased()) · \(Int(project.progress.rounded()))%")
                    .font(FlightDeckFont.mono(10))
                    .kerning(1.5)
                    .foregroundStyle(color)
                    .fixedSize()
            }
            HStack(spacing: 3) {
                ForEach(0..<20, id: \.self) { index in
                    Rectangle()
                        .fill(index < lit ? color : FlightDeckPalette.track)
                        .frame(height: 10)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("\(project.name) progress")
            .accessibilityValue("\(Int(project.progress.rounded())) percent")
            (Text("NEXT ▸ ").foregroundColor(FlightDeckPalette.secondary)
                + Text(project.nextAction.isEmpty ? "—" : project.nextAction).foregroundColor(FlightDeckPalette.text))
                .font(FlightDeckFont.mono(11))
                .lineLimit(2)
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(FlightDeckPalette.rule).frame(height: 1) }
    }
}

// MARK: - 03 Objectives & 04 Checklist

private struct FlightDeckObjectivesColumn: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let staticLayout: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FlightDeckSectionHeader(
                title: "03 · PRIMARY OBJECTIVES · \(missions.board.periodTitle.uppercased())",
                addHelp: "Add an objective"
            ) {
                editor = .objective(MissionObjective(title: ""))
            }
            if missions.board.objectives.isEmpty {
                FlightDeckEmpty(text: "No objectives for \(missions.board.periodTitle). Use + to set one.")
            }
            ForEach(missions.board.objectives) { objective in
                HStack(alignment: .center, spacing: 12) {
                    Text("\(Int(objective.progress.rounded()))")
                        .font(FlightDeckFont.condensed(26, .bold))
                        .foregroundStyle(FlightDeckPalette.accent)
                        .frame(width: 52, alignment: .leading)
                        .accessibilityLabel("\(Int(objective.progress.rounded())) percent")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(objective.title)
                            .font(FlightDeckFont.mono(12))
                            .lineLimit(2)
                        if !objective.summary.isEmpty {
                            Text(objective.summary)
                                .font(FlightDeckFont.mono(11))
                                .foregroundStyle(FlightDeckPalette.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .objectiveActions(objective, missions: missions, editor: $editor)
            }

            FlightDeckSectionHeader(title: "04 · TODAY'S CHECKLIST", addHelp: "Add a task") {
                editor = .task(MissionTask(title: ""))
            }
            .padding(.top, 12)
            FlightDeckScroll(staticLayout: staticLayout) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    FlightDeckChecklist(missions: missions, editor: $editor, now: context.date)
                }
            }
        }
        .flightDeckColumn()
    }
}

private struct FlightDeckChecklist: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let now: Date
    var buckets: [TaskBucket] = TaskBucket.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if buckets.allSatisfy({ missions.board.tasks(in: $0, now: now).isEmpty }) {
                FlightDeckEmpty(text: buckets == [.now]
                    ? "Nothing in NOW. Open the dashboard to plan."
                    : "Checklist clear. Use + to add a task.")
            } else {
                ForEach(buckets) { bucket in
                    let tasks = missions.board.tasks(in: bucket, now: now)
                    if buckets.count > 1 {
                        HStack(spacing: 8) {
                            Text(bucket.title)
                                .font(FlightDeckFont.mono(10, .semibold))
                                .kerning(2)
                                .foregroundStyle(bucket == .now ? FlightDeckPalette.accent : FlightDeckPalette.secondary)
                            Rectangle().fill(FlightDeckPalette.rule).frame(height: 1)
                            Text("\(tasks.count)")
                                .font(FlightDeckFont.mono(10))
                                .foregroundStyle(FlightDeckPalette.secondary)
                        }
                    }
                    ForEach(tasks) { task in
                        FlightDeckTaskRow(task: task, missions: missions, editor: $editor, now: now)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FlightDeckTaskRow: View {
    let task: MissionTask
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let now: Date

    var body: some View {
        Toggle(isOn: doneBinding(task, missions: missions)) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(task.title)
                    .font(FlightDeckFont.mono(12))
                    .strikethrough(task.isDone, color: FlightDeckPalette.secondary)
                    .foregroundStyle(task.isDone ? FlightDeckPalette.secondary : FlightDeckPalette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !tag.isEmpty {
                    Text(tag)
                        .font(FlightDeckFont.mono(10))
                        .kerning(1)
                        .foregroundStyle(task.isDue(on: now) ? FlightDeckPalette.accent : FlightDeckPalette.secondary)
                        .fixedSize()
                }
            }
        }
        .toggleStyle(FlightDeckCheckboxStyle())
        .frame(minHeight: 22)
        .taskActions(task, missions: missions, editor: $editor)
    }

    private var tag: String {
        [missions.board.project(for: task).map(FlightDeckText.tag), ThemeText.dueLabel(task, now: now)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private struct FlightDeckCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(configuration.isOn ? FlightDeckPalette.accent : FlightDeckPalette.card)
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(configuration.isOn ? FlightDeckPalette.accent : FlightDeckPalette.controlStrong, lineWidth: 1.2)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8.5, weight: .heavy))
                            .foregroundStyle(FlightDeckPalette.background)
                    }
                }
                .frame(width: 14, height: 14)
                .padding(.top, 1)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Done" : "Open")
    }
}

// MARK: - Event log footer

private struct FlightDeckEventLog: View {
    let readout: CockpitReadout
    @ObservedObject var missions: MissionStore

    private struct Entry: Hashable {
        let text: String
        let color: Color
    }

    var body: some View {
        HStack(spacing: 28) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                Text("● \(entry.text)")
                    .foregroundStyle(entry.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(Double(entries.count - index))
            }
            Spacer(minLength: 0)
            Text("POLL \(Int(CapacityCache.pollInterval / 60))M")
                .fixedSize()
        }
        .font(FlightDeckFont.mono(11))
        .kerning(0.5)
        .foregroundStyle(FlightDeckPalette.secondary)
        .padding(.horizontal, 28)
        .accessibilityElement(children: .combine)
    }

    private var entries: [Entry] {
        var entries: [Entry] = []
        if let caution = readout.masterCaution, let window = caution.bindingWindow {
            entries.append(Entry(
                text: "\(FlightDeckText.logTime(caution.snapshot.updatedAt)) \(caution.snapshot.account.label.uppercased()) \(FlightDeckText.windowCode(window)) WINDOW AT \(Int(window.usedPercent.rounded()))% · MASTER CAUTION",
                color: FlightDeckPalette.orange
            ))
        } else {
            entries.append(Entry(
                text: "NO ACCOUNT ABOVE \(Int(AccountReadout.cautionThreshold))% · NOMINAL",
                color: FlightDeckPalette.green
            ))
        }
        for account in readout.needsSignIn {
            entries.append(Entry(text: "\(account.snapshot.account.label.uppercased()) NEEDS SIGN-IN", color: FlightDeckPalette.accent))
        }
        if let error = missions.saveError {
            entries.append(Entry(text: error.uppercased(), color: FlightDeckPalette.red))
        }
        return entries
    }
}

// MARK: - Menu

struct FlightDeckMenuView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    var staticLayout = false
    @Environment(\.openWindow) private var openWindow
    @State private var editor: MissionEditor?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        let readout = readout
        VStack(spacing: 0) {
            header
            FlightDeckRule()
            VStack(alignment: .leading, spacing: 12) {
                FlightDeckGoNoGo(best: readout.bestClaude, compact: true)
                caution(readout)
                if staticLayout {
                    content(readout)
                } else {
                    ScrollView { content(readout) }.scrollIndicators(.never)
                }
            }
            .padding(14)
            FlightDeckRule()
            footer
        }
        .background(FlightDeckGridBackground())
        .background(FlightDeckPalette.background)
        .foregroundStyle(FlightDeckPalette.text)
        .missionEditorSheet($editor, missions: missions)
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 10) {
                FlightDeckBeacon(size: 18)
                Text("MISSION CONTROL")
                    .font(FlightDeckFont.condensed(15, .bold))
                    .kerning(2.5)
                Spacer(minLength: 6)
                Text(ThemeText.probedLabel(capacity.lastRefresh, now: context.date))
                    .font(FlightDeckFont.mono(10))
                    .kerning(1)
                    .foregroundStyle(FlightDeckPalette.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
        }
    }

    @ViewBuilder
    private func caution(_ readout: CockpitReadout) -> some View {
        if let caution = readout.masterCaution, let window = caution.bindingWindow {
            Text("● MASTER CAUTION · \(caution.snapshot.account.label.uppercased()) \(FlightDeckText.windowCode(window)) AT \(Int(window.usedPercent.rounded()))%")
                .font(FlightDeckFont.mono(11, .semibold))
                .kerning(0.5)
                .foregroundStyle(FlightDeckPalette.orange)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(Rectangle().strokeBorder(FlightDeckPalette.orangeBorder, lineWidth: 1))
        } else {
            Text("● NO ACCOUNT ABOVE \(Int(AccountReadout.cautionThreshold))% · NOMINAL")
                .font(FlightDeckFont.mono(11))
                .kerning(0.5)
                .foregroundStyle(FlightDeckPalette.green)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func content(_ readout: CockpitReadout) -> some View {
        let bestID = readout.bestClaude?.snapshot.id
        return VStack(alignment: .leading, spacing: 10) {
            FlightDeckSectionHeader(title: "PROPELLANT / AI CAPACITY", trailing: "5H · WEEK")
            if readout.accounts.isEmpty {
                FlightDeckEmpty(text: "No accounts configured.")
            }
            ForEach(readout.accounts, id: \.snapshot.id) { account in
                FlightDeckAccountCard(account: account, isRoute: account.snapshot.id == bestID, compact: true)
            }
            FlightDeckSectionHeader(title: "NOW · CHECKLIST", addHelp: "Add a task") {
                editor = .task(MissionTask(title: ""))
            }
            .padding(.top, 6)
            FlightDeckChecklist(missions: missions, editor: $editor, now: Date(), buckets: [.now])
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("OPEN DASHBOARD") { OpenDashboardAction(openWindow: openWindow)() }
            Button(capacity.isRefreshing ? "PROBING…" : "RE-PROBE") {
                Task { await capacity.refresh() }
            }
            .disabled(capacity.isRefreshing)
            ThemePicker { FlightDeckButtonLabel(text: "THEME ▾") }
            Spacer(minLength: 0)
            Button("QUIT") { NSApp.terminate(nil) }
        }
        .buttonStyle(FlightDeckButtonStyle())
        .padding(.horizontal, 14)
        .frame(height: 52)
    }
}

// MARK: - Shared chrome

private extension View {
    func flightDeckColumn() -> some View {
        padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(FlightDeckPalette.background)
    }
}

private struct FlightDeckRule: View {
    var body: some View {
        Rectangle().fill(FlightDeckPalette.rule).frame(height: 1)
    }
}

private struct FlightDeckGridBackground: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += 32
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += 32
            }
            context.stroke(path, with: .color(.white.opacity(0.03)), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// The radar-style beacon beside the title.
private struct FlightDeckBeacon: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 24
            let center = CGPoint(x: 12 * scale, y: 12 * scale)
            let style = StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round)
            let shading = GraphicsContext.Shading.color(FlightDeckPalette.accent)
            context.stroke(Path(ellipseIn: CGRect(x: center.x - 2.5 * scale, y: center.y - 2.5 * scale, width: 5 * scale, height: 5 * scale)), with: shading, style: style)
            for radius in [6.4, 10.5] as [CGFloat] {
                for start in [135.0, -45.0] {
                    var arc = Path()
                    arc.addArc(center: center, radius: radius * scale, startAngle: .degrees(start), endAngle: .degrees(start + 90), clockwise: false)
                    context.stroke(arc, with: shading, style: style)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct FlightDeckSectionHeader: View {
    let title: String
    var trailing: String?
    var addHelp: String?
    var add: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(FlightDeckFont.condensed(13, .semibold))
                .kerning(2.5)
                .foregroundStyle(FlightDeckPalette.secondary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(FlightDeckFont.mono(11))
                    .foregroundStyle(FlightDeckPalette.secondary)
                    .fixedSize()
            }
            if let add, let addHelp {
                Button(action: add) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 20)
                        .foregroundStyle(FlightDeckPalette.accent)
                        .overlay(Rectangle().strokeBorder(FlightDeckPalette.control, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(addHelp)
                .accessibilityLabel(addHelp)
            }
        }
        .frame(minHeight: 20)
    }
}

private struct FlightDeckScroll<Content: View>: View {
    let staticLayout: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if staticLayout {
            VStack(alignment: .leading, spacing: 14) { content }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
    }
}

private struct FlightDeckEmpty: View {
    let text: String

    var body: some View {
        Text(text)
            .font(FlightDeckFont.mono(11.5))
            .foregroundStyle(FlightDeckPalette.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(Rectangle().strokeBorder(FlightDeckPalette.rule, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }
}

private struct FlightDeckChip: View {
    let text: String
    let ink: Color
    let border: Color

    var body: some View {
        Text(text)
            .font(FlightDeckFont.mono(11, .semibold))
            .kerning(1)
            .foregroundStyle(ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(Rectangle().strokeBorder(border, lineWidth: 1))
    }
}

private struct FlightDeckButtonLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(FlightDeckFont.mono(11))
            .kerning(1)
            .foregroundStyle(FlightDeckPalette.text)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .overlay(Rectangle().strokeBorder(FlightDeckPalette.control, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

private struct FlightDeckButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FlightDeckFont.mono(11))
            .kerning(1)
            .lineLimit(1)
            .foregroundStyle(isEnabled ? FlightDeckPalette.text : FlightDeckPalette.secondary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(configuration.isPressed ? FlightDeckPalette.control : Color.clear)
            .overlay(Rectangle().strokeBorder(FlightDeckPalette.control, lineWidth: 1))
            .contentShape(Rectangle())
            .fixedSize()
    }
}
