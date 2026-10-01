import AppKit
import CapacityCore
import SwiftUI

// Blueprint: the dashboard drawn as an engineering sheet — white ink on
// drafting blue, a zoned border, dimensioned capacity dials and a title block.

// MARK: - Dashboard

struct BlueprintDashboardView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    var staticLayout = false

    @State private var editor: MissionEditor?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        GeometryReader { proxy in
            // Sheet margin 18, double border 1.5 + 4 + 0.75, inner padding 16.
            let contentWidth = max(proxy.size.width - 36 - 3 - 8 - 1.5 - 32, 600)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 12) {
                    header(now: context.date)
                    capacitySection(width: contentWidth, now: context.date)
                    detailColumns(width: contentWidth, now: context.date)
                        .frame(minHeight: 220, maxHeight: .infinity, alignment: .top)
                }
                .modifier(BlueprintSheetFrame())
                .padding(18)
            }
        }
        .background(BlueprintSheetBackground(zones: true))
        .background(BlueprintPalette.paper)
        .foregroundStyle(BlueprintPalette.ink)
        .missionEditorSheet($editor, missions: missions)
    }

    // MARK: Header

    private func header(now: Date) -> some View {
        HStack(alignment: .center, spacing: 24) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text("MISSION CONTROL")
                    .font(BlueprintPalette.sans(30, .semibold))
                    .kerning(7)
                    .lineLimit(1)
                    .fixedSize()
                ViewThatFits(in: .horizontal) {
                    subtitle("GENERAL ARRANGEMENT · AI CAPACITY & OPERATIONS · DWG \(BlueprintPalette.drawingNumber)")
                    subtitle("AI CAPACITY & OPERATIONS · DWG \(BlueprintPalette.drawingNumber)")
                    subtitle("DWG \(BlueprintPalette.drawingNumber)")
                    Color.clear.frame(width: 0, height: 0)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 16) {
                BlueprintRouteBox(best: readout.bestClaude, compact: false)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ThemeText.plateDate(now))
                        .font(BlueprintPalette.mono(12, .medium))
                        .kerning(1)
                    Text("\(missions.board.openTaskCount) OPEN · \(missions.board.dueTodayCount(now: now)) DUE · \(ThemeText.probedLabel(capacity.lastRefresh, now: now))")
                        .font(BlueprintPalette.mono(9))
                        .foregroundStyle(BlueprintPalette.dim)
                }
                .lineLimit(1)
                .fixedSize()
                BlueprintRefreshButton(capacity: capacity)
                ThemePicker { BlueprintOutlineLabel(text: "SHEET ▾") }
            }
            .layoutPriority(1)
        }
        .frame(height: 42)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(BlueprintPalette.ink).frame(height: 1.5) }
    }

    private func subtitle(_ text: String) -> some View {
        Text(text)
            .font(BlueprintPalette.mono(11))
            .kerning(1)
            .foregroundStyle(BlueprintPalette.dim)
            .lineLimit(1)
            .fixedSize()
    }

    // MARK: Detail A — capacity

    private func capacitySection(width: CGFloat, now: Date) -> some View {
        let accounts = readout.accounts
        let columns = max(1, min(accounts.count, 4))
        let cardWidth = (width - 14 * CGFloat(columns - 1)) / CGFloat(columns)
        let dialWidth = min(285, cardWidth - 24)
        let rows = stride(from: 0, to: accounts.count, by: columns).map {
            Array(accounts.enumerated())[$0..<min($0 + columns, accounts.count)]
        }
        let bestID = readout.bestClaude?.snapshot.id
        return VStack(alignment: .leading, spacing: 8) {
            BlueprintSectionHeader(letter: "A", title: "DETAIL A — CAPACITY") {
                BlueprintCautionChip(caution: readout.masterCaution)
                Spacer(minLength: 8)
                Text("OUTER ARC 5H WINDOW · INNER ARC WEEKLY · HEADROOM = 100 − MAX(5H, WK) · REDLINE ≥ \(Int(BlueprintPalette.warnAt))% USED")
                    .font(BlueprintPalette.mono(10))
                    .kerning(0.5)
                    .foregroundStyle(BlueprintPalette.dim)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            if accounts.isEmpty {
                BlueprintEmptyNote(text: "NO ACCOUNTS REPORTING YET — PROBE PENDING.")
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 14) {
                    ForEach(row, id: \.element.snapshot.id) { index, account in
                        BlueprintAccountCard(
                            account: account,
                            number: index + 1,
                            isRoute: account.snapshot.id == bestID,
                            dialWidth: dialWidth,
                            now: now
                        )
                        .frame(width: cardWidth)
                        .frame(maxHeight: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Details B, C, D

    private func detailColumns(width: CGFloat, now: Date) -> some View {
        let columnWidth = (width - 44) / 3
        return HStack(alignment: .top, spacing: 22) {
            projectsColumn
                .frame(width: columnWidth)
            tasksColumn(now: now)
                .frame(width: columnWidth)
            objectivesColumn(width: columnWidth, now: now)
                .frame(width: columnWidth)
        }
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
    }

    private var projectsColumn: some View {
        let projects = missions.board.projects
        return VStack(alignment: .leading, spacing: 8) {
            BlueprintSectionHeader(letter: "B", title: "DETAIL B — PROJECT SCHEDULE") {
                Spacer(minLength: 8)
                Text("\(projects.count) \(projects.count == 1 ? "ITEM" : "ITEMS")")
                    .font(BlueprintPalette.mono(10))
                    .foregroundStyle(BlueprintPalette.dim)
                BlueprintAddButton(help: "Add a project") { editor = .project(MissionProject(name: "")) }
            }
            BlueprintScroll(staticLayout: staticLayout) {
                VStack(alignment: .leading, spacing: 7) {
                    if projects.isEmpty {
                        BlueprintEmptyNote(text: "NO PROJECTS ON THIS SHEET. USE + TO ADD ONE.")
                    }
                    ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                        BlueprintProjectRow(project: project, number: index + 1)
                            .projectActions(project, missions: missions, editor: $editor)
                    }
                }
            }
        }
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private func tasksColumn(now: Date) -> some View {
        let board = missions.board
        let total = TaskBucket.allCases.reduce(0) { $0 + board.tasks(in: $1, now: now).count }
        return VStack(alignment: .leading, spacing: 8) {
            BlueprintSectionHeader(letter: "C", title: "DETAIL C — TASK SEQUENCE") {
                Spacer(minLength: 8)
                Text("\(total) TASKS · \(board.dueTodayCount(now: now)) DUE")
                    .font(BlueprintPalette.mono(10))
                    .foregroundStyle(BlueprintPalette.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                BlueprintAddButton(help: "Add a task") { editor = .task(MissionTask(title: "")) }
            }
            BlueprintScroll(staticLayout: staticLayout) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(TaskBucket.allCases.enumerated()), id: \.element) { index, bucket in
                        BlueprintTaskGroup(
                            number: index + 1,
                            bucket: bucket,
                            tasks: board.tasks(in: bucket, now: now),
                            missions: missions,
                            editor: $editor,
                            now: now
                        )
                    }
                }
            }
        }
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private func objectivesColumn(width: CGFloat, now: Date) -> some View {
        let objectives = missions.board.objectives
        return VStack(alignment: .leading, spacing: 10) {
            BlueprintSectionHeader(letter: "D", title: "DETAIL D — OBJECTIVES \(missions.board.periodTitle.uppercased())") {
                Spacer(minLength: 8)
                BlueprintAddButton(help: "Add an objective") { editor = .objective(MissionObjective(title: "")) }
            }
            BlueprintScroll(staticLayout: staticLayout) {
                VStack(alignment: .leading, spacing: 10) {
                    if objectives.isEmpty {
                        BlueprintEmptyNote(text: "NO OBJECTIVES FOR \(missions.board.periodTitle.uppercased()). USE + TO ADD ONE.")
                    }
                    ForEach(Array(objectives.enumerated()), id: \.element.id) { index, objective in
                        BlueprintObjectiveRow(objective: objective, number: index + 1)
                            .objectiveActions(objective, missions: missions, editor: $editor)
                    }
                    notes
                }
            }
            BlueprintTitleBlock(cells: titleCells(now: now), width: width)
        }
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private var notes: some View {
        let lines = ThemeText.briefing(readout)
        let hasCaution = readout.masterCaution != nil
        return VStack(alignment: .leading, spacing: 4) {
            Text("NOTES")
                .font(BlueprintPalette.sans(12, .semibold))
                .kerning(2)
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                BlueprintNote(
                    number: index + 1,
                    text: line,
                    highlighted: (index == 0 && hasCaution) || line.hasSuffix("needs sign-in.")
                )
            }
            if let error = missions.saveError {
                BlueprintNote(number: lines.count + 1, text: error, highlighted: true)
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            BlueprintHDash().stroke(BlueprintPalette.faint, style: StrokeStyle(lineWidth: 0.75, dash: [4, 3]))
                .frame(height: 1)
        }
    }

    private func titleCells(now: Date) -> [(String, String)] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let accounts = readout.accounts
        let live = accounts.filter(\.isLive).count
        return [
            ("SHEET", "01 OF 01"),
            ("ACCOUNTS", "\(accounts.count) · \(live) LIVE"),
            ("DATE", formatter.string(from: now)),
            ("OPEN TASKS", "\(missions.board.openTaskCount) · \(missions.board.dueTodayCount(now: now)) DUE"),
            ("CHECKED", ThemeText.probedLabel(capacity.lastRefresh, now: now)),
            ("SCALE", "1:1 · UNITS %"),
        ]
    }
}

// MARK: - Menu

struct BlueprintMenuView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    var staticLayout = false

    @Environment(\.openWindow) private var openWindow
    @State private var editor: MissionEditor?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 10) {
                header(now: context.date)
                BlueprintRouteBox(best: readout.bestClaude, compact: true)
                BlueprintCautionChip(caution: readout.masterCaution)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if staticLayout {
                    panelContent(now: context.date)
                } else {
                    ScrollView { panelContent(now: context.date) }
                        .scrollIndicators(.never)
                }
                footer
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .modifier(BlueprintSheetFrame(innerPadding: false))
            .padding(8)
        }
        .background(BlueprintSheetBackground(zones: false))
        .background(BlueprintPalette.paper)
        .foregroundStyle(BlueprintPalette.ink)
        .missionEditorSheet($editor, missions: missions)
    }

    private func header(now: Date) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("MISSION CONTROL")
                    .font(BlueprintPalette.sans(19, .semibold))
                    .kerning(4)
                Text("DAILY SHEET · \(ThemeText.plateDate(now))")
                    .font(BlueprintPalette.mono(9))
                    .kerning(0.5)
                    .foregroundStyle(BlueprintPalette.dim)
            }
            Spacer(minLength: 8)
            Text(ThemeText.probedLabel(capacity.lastRefresh, now: now))
                .font(BlueprintPalette.mono(9))
                .foregroundStyle(BlueprintPalette.dim)
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(BlueprintPalette.ink).frame(height: 1.5) }
    }

    private func panelContent(now: Date) -> some View {
        let bestID = readout.bestClaude?.snapshot.id
        let tasks = missions.board.tasks(in: .now, now: now)
        return VStack(alignment: .leading, spacing: 8) {
            BlueprintSectionHeader(letter: "A", title: "CAPACITY") {
                Spacer(minLength: 8)
                Text("\(readout.accounts.count) ACCOUNTS")
                    .font(BlueprintPalette.mono(10))
                    .foregroundStyle(BlueprintPalette.dim)
            }
            if readout.accounts.isEmpty {
                BlueprintEmptyNote(text: "NO ACCOUNTS REPORTING YET.")
            }
            ForEach(Array(readout.accounts.enumerated()), id: \.element.snapshot.id) { index, account in
                BlueprintCompactAccount(
                    account: account,
                    number: index + 1,
                    isRoute: account.snapshot.id == bestID,
                    now: now
                )
            }
            BlueprintSectionHeader(letter: "C", title: "NOW · IN WORK") {
                Spacer(minLength: 8)
                Text("\(tasks.count) \(tasks.count == 1 ? "TASK" : "TASKS")")
                    .font(BlueprintPalette.mono(10))
                    .foregroundStyle(BlueprintPalette.dim)
                BlueprintAddButton(help: "Add a task") { editor = .task(MissionTask(title: "")) }
            }
            .padding(.top, 4)
            if tasks.isEmpty {
                BlueprintEmptyNote(text: "NOTHING IN NOW. OPEN THE DASHBOARD TO PLAN.")
            }
            ForEach(tasks) { task in
                BlueprintTaskRow(task: task, missions: missions, editor: $editor, now: now)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button { OpenDashboardAction(openWindow: openWindow)() } label: {
                BlueprintOutlineLabel(text: "OPEN DASHBOARD", size: 10)
            }
            .buttonStyle(.plain)
            BlueprintRefreshButton(capacity: capacity, size: 10)
            Spacer(minLength: 0)
            ThemePicker { BlueprintOutlineLabel(text: "SHEET ▾", size: 10) }
            Button { NSApp.terminate(nil) } label: {
                BlueprintOutlineLabel(text: "QUIT", size: 10)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(BlueprintPalette.ink).frame(height: 1) }
    }
}

// MARK: - Palette & type

private enum BlueprintPalette {
    static let paper = Color(hex: 0x143A63)
    static let gridMinor = Color(hex: 0x2A5281)
    static let gridMajor = Color(hex: 0x33608F)
    static let ink = Color(hex: 0xF1F6FB)
    static let dim = Color(hex: 0xA9C3DE)
    static let faint = Color(hex: 0x6F93BA)
    static let accent = Color(hex: 0xFFB547)
    static let warnAt = AccountReadout.cautionThreshold
    static let drawingNumber = "MC-CAP-001"

    /// Condensed sans standing in for IBM Plex Sans Condensed.
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    /// Stand-in for IBM Plex Mono.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func tone(_ percent: Double) -> Color { percent >= warnAt ? accent : ink }

    static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    static func windowName(_ window: CapacityWindow?) -> String {
        switch window?.durationMinutes {
        case 300: "5H"
        case 10_080: "WEEKLY"
        default: window?.label.uppercased() ?? "—"
        }
    }

    static func isStale(_ account: AccountReadout) -> Bool {
        account.snapshot.state == .error && account.hasMeasurements
    }

    /// Short drawing-status stamp for an account and its colour.
    static func status(_ account: AccountReadout, isRoute: Bool) -> (String, Color) {
        if account.isNearLimit { return ("HOLD", accent) }
        if isStale(account) { return ("STALE", accent) }
        switch account.snapshot.state {
        case .connected:
            if !account.hasMeasurements { return ("NO DATA", dim) }
            return isRoute ? ("ROUTE", ink) : ("NOMINAL", dim)
        case .unauthenticated: return ("SIGN-IN", accent)
        case .loading: return ("LOADING", dim)
        case .unavailable: return ("N/A", dim)
        case .error: return ("FAULT", accent)
        }
    }
}

// MARK: - Sheet chrome

/// Drafting grid plus the zone letters and numbers around the sheet edge.
private struct BlueprintSheetBackground: View {
    let zones: Bool

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = zones ? 18 : 0
            let rect = CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
            var minor = Path()
            var major = Path()
            var index = 0
            var x = rect.minX
            while x <= rect.maxX + 0.1 {
                if index % 5 == 0 {
                    major.move(to: CGPoint(x: x, y: rect.minY))
                    major.addLine(to: CGPoint(x: x, y: rect.maxY))
                } else {
                    minor.move(to: CGPoint(x: x, y: rect.minY))
                    minor.addLine(to: CGPoint(x: x, y: rect.maxY))
                }
                x += 12
                index += 1
            }
            index = 0
            var y = rect.minY
            while y <= rect.maxY + 0.1 {
                if index % 5 == 0 {
                    major.move(to: CGPoint(x: rect.minX, y: y))
                    major.addLine(to: CGPoint(x: rect.maxX, y: y))
                } else {
                    minor.move(to: CGPoint(x: rect.minX, y: y))
                    minor.addLine(to: CGPoint(x: rect.maxX, y: y))
                }
                y += 12
                index += 1
            }
            context.stroke(minor, with: .color(BlueprintPalette.gridMinor), lineWidth: 0.5)
            context.stroke(major, with: .color(BlueprintPalette.gridMajor), lineWidth: 0.6)
            guard zones else { return }

            var marks = Path()
            let zoneWidth = rect.width / 8
            for i in 0..<8 {
                let label = Text("\(8 - i)").font(BlueprintPalette.mono(9)).foregroundColor(BlueprintPalette.dim)
                let cx = rect.minX + zoneWidth * (CGFloat(i) + 0.5)
                context.draw(label, at: CGPoint(x: cx, y: 9))
                context.draw(label, at: CGPoint(x: cx, y: size.height - 8))
                let bx = rect.minX + zoneWidth * CGFloat(i + 1)
                if i < 7 {
                    marks.move(to: CGPoint(x: bx, y: 10)); marks.addLine(to: CGPoint(x: bx, y: 18))
                    marks.move(to: CGPoint(x: bx, y: size.height - 18)); marks.addLine(to: CGPoint(x: bx, y: size.height - 10))
                }
            }
            let zoneHeight = rect.height / 5
            for (i, letter) in ["A", "B", "C", "D", "E"].enumerated() {
                let label = Text(letter).font(BlueprintPalette.mono(9)).foregroundColor(BlueprintPalette.dim)
                let cy = rect.minY + zoneHeight * (CGFloat(i) + 0.5)
                context.draw(label, at: CGPoint(x: 9, y: cy))
                context.draw(label, at: CGPoint(x: size.width - 9, y: cy))
                let by = rect.minY + zoneHeight * CGFloat(i + 1)
                if i < 4 {
                    marks.move(to: CGPoint(x: 10, y: by)); marks.addLine(to: CGPoint(x: 18, y: by))
                    marks.move(to: CGPoint(x: size.width - 18, y: by)); marks.addLine(to: CGPoint(x: size.width - 10, y: by))
                }
            }
            context.stroke(marks, with: .color(BlueprintPalette.faint), lineWidth: 0.75)
        }
        .accessibilityHidden(true)
    }
}

/// Heavy outer border line, thin inner border line.
private struct BlueprintSheetFrame: ViewModifier {
    var innerPadding = true

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, innerPadding ? 16 : 0)
            .padding(.vertical, innerPadding ? 12 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(Rectangle().strokeBorder(BlueprintPalette.faint, lineWidth: 0.75))
            .padding(4)
            .overlay(Rectangle().strokeBorder(BlueprintPalette.ink, lineWidth: 1.5))
    }
}

private struct BlueprintHDash: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct BlueprintVDash: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// Circled reference tag ("A", "B3", "D1").
private struct BlueprintBadge: View {
    let text: String
    var size: CGFloat = 24
    var fontSize: CGFloat = 9
    var color: Color = BlueprintPalette.dim
    var weight: Font.Weight = .regular
    var lineWidth: CGFloat = 1

    var body: some View {
        Text(text)
            .font(BlueprintPalette.mono(fontSize, weight))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(color, lineWidth: lineWidth))
            .accessibilityHidden(true)
    }
}

private struct BlueprintSectionHeader<Trailing: View>: View {
    let letter: String
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            BlueprintBadge(text: letter, size: 20, fontSize: 11, color: BlueprintPalette.ink, weight: .semibold)
            Text(title)
                .font(BlueprintPalette.sans(15, .semibold))
                .kerning(2.5)
                .lineLimit(1)
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
            trailing
        }
        .frame(minHeight: 22)
        .padding(.bottom, 5)
        .overlay(alignment: .bottom) { Rectangle().fill(BlueprintPalette.faint).frame(height: 1) }
    }
}

private struct BlueprintAddButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BlueprintPalette.ink)
                .frame(width: 22, height: 20)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(BlueprintPalette.ink, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct BlueprintOutlineLabel: View {
    let text: String
    var size: CGFloat = 11
    var color: Color = BlueprintPalette.ink

    var body: some View {
        Text(text)
            .font(BlueprintPalette.mono(size))
            .kerning(1)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, size + 1)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

private struct BlueprintRefreshButton: View {
    @ObservedObject var capacity: CapacityStore
    var size: CGFloat = 11

    var body: some View {
        Button {
            Task { await capacity.refresh() }
        } label: {
            BlueprintOutlineLabel(
                text: capacity.isRefreshing ? "PROBING…" : "RE-PROBE",
                size: size,
                color: capacity.isRefreshing ? BlueprintPalette.dim : BlueprintPalette.ink
            )
        }
        .buttonStyle(.plain)
        .disabled(capacity.isRefreshing)
        .help("Check every account's usage now")
    }
}

private struct BlueprintScroll<Content: View>: View {
    let staticLayout: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if staticLayout {
            content
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        } else {
            ScrollView {
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
    }
}

private struct BlueprintEmptyNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(BlueprintPalette.mono(10))
            .kerning(0.5)
            .foregroundStyle(BlueprintPalette.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(BlueprintPalette.faint, style: StrokeStyle(lineWidth: 0.75, dash: [4, 3]))
            )
    }
}

// MARK: - Route & caution

private struct BlueprintRouteBox: View {
    let best: AccountReadout?
    let compact: Bool

    var body: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 2) {
                    caption
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        name
                        Spacer(minLength: 4)
                        headroom
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    caption
                    name
                    headroom
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(best == nil ? BlueprintPalette.faint : BlueprintPalette.ink, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var caption: some View {
        Text("ROUTE NEXT CLAUDE SESSION TO")
            .font(BlueprintPalette.mono(compact ? 9 : 10))
            .kerning(1)
            .foregroundStyle(BlueprintPalette.dim)
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder private var name: some View {
        if let best {
            Text(best.snapshot.account.label)
                .font(BlueprintPalette.sans(16, .bold))
                .kerning(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        } else {
            Text("NO CLAUDE ACCOUNT AVAILABLE")
                .font(BlueprintPalette.sans(15, .semibold))
                .kerning(0.5)
                .foregroundStyle(BlueprintPalette.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    @ViewBuilder private var headroom: some View {
        if let best {
            Text("\(Int((best.headroom ?? 0).rounded()))% HEADROOM")
                .font(BlueprintPalette.mono(12, .semibold))
                .lineLimit(1)
                .fixedSize()
        }
    }
}

private struct BlueprintCautionChip: View {
    let caution: AccountReadout?

    var body: some View {
        Group {
            if let caution, let window = caution.bindingWindow {
                Text("⚠ HOLD · \(caution.snapshot.account.label.uppercased()) · \(BlueprintPalette.windowName(window)) \(BlueprintPalette.percent(window.usedPercent)) USED — INSIDE REDLINE")
                    .foregroundStyle(BlueprintPalette.accent)
            } else {
                Text("ALL ACCOUNTS NOMINAL · BELOW \(Int(BlueprintPalette.warnAt))% REDLINE")
                    .foregroundStyle(BlueprintPalette.dim)
            }
        }
        .font(BlueprintPalette.mono(10, .semibold))
        .kerning(0.8)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(caution == nil ? BlueprintPalette.faint : BlueprintPalette.accent, lineWidth: caution == nil ? 0.75 : 1.2)
        )
        .accessibilityLabel(caution == nil ? "Master caution off. All accounts nominal." : "Master caution")
    }
}

// MARK: - Capacity instruments

/// Dimensioned dial: outer arc 5-hour window, inner arc weekly, redline band.
private struct BlueprintDial: View {
    let account: AccountReadout
    let now: Date
    /// Compact draws only the dial face, without callouts or small print.
    var compact = false

    var body: some View {
        Canvas { context, size in
            let box = compact ? CGSize(width: 200, height: 200) : CGSize(width: 300, height: 190)
            let scale = min(size.width / box.width, size.height / box.height)
            context.translateBy(x: (size.width - box.width * scale) / 2, y: (size.height - box.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            draw(in: context)
        }
        .accessibilityElement()
        .accessibilityLabel("\(account.snapshot.account.label) capacity")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard account.hasMeasurements else { return account.snapshot.state.label }
        let five = account.fiveHour.map { "5-hour \(BlueprintPalette.percent($0.usedPercent)) used" } ?? "5-hour no data"
        let week = account.weekly.map { "weekly \(BlueprintPalette.percent($0.usedPercent)) used" } ?? "weekly no data"
        let room = account.headroom.map { "\(BlueprintPalette.percent($0)) headroom" } ?? ""
        return [five, week, room].joined(separator: ", ")
    }

    private static func degrees(_ percent: Double) -> Double { -135 + percent * 2.7 }

    private func text(_ string: String, _ font: Font, _ color: Color) -> Text {
        Text(string).font(font).foregroundColor(color)
    }

    private func draw(in context: GraphicsContext) {
        let center = CGPoint(x: 100, y: 100)
        let deg = Self.degrees
        let weight: CGFloat = compact ? 1.8 : 1

        // Redline band.
        context.stroke(
            DialGeometry.arc(center, 92, from: deg(BlueprintPalette.warnAt), to: deg(100)),
            with: .color(BlueprintPalette.accent),
            lineWidth: 2 * weight
        )
        // Graduations.
        var minor = Path()
        var major = Path()
        for i in 0...50 {
            let p = Double(i * 2)
            let isMajor = i % 5 == 0
            let tick = DialGeometry.tick(center, 88, isMajor ? 79 : 84, deg(p))
            if isMajor { major.addPath(tick) } else { minor.addPath(tick) }
        }
        context.stroke(minor, with: .color(BlueprintPalette.ink), lineWidth: 0.6 * weight)
        context.stroke(major, with: .color(BlueprintPalette.ink), lineWidth: 1.1 * weight)
        if !compact {
            for p in stride(from: 0, through: 100, by: 20) {
                let point = DialGeometry.point(center, 97, deg(Double(p)))
                context.draw(text("\(p)", BlueprintPalette.mono(8), BlueprintPalette.dim), at: CGPoint(x: point.x, y: point.y + 0.5))
            }
        }
        // Tracks and value arcs.
        for (radius, window) in [(CGFloat(74), account.fiveHour), (CGFloat(62), account.weekly)] {
            context.stroke(
                DialGeometry.arc(center, radius, from: deg(0), to: deg(100)),
                with: .color(BlueprintPalette.faint),
                style: StrokeStyle(lineWidth: 0.75 * weight, dash: window == nil ? [3, 3] : [])
            )
            if let window, window.usedPercent > 0 {
                context.stroke(
                    DialGeometry.arc(center, radius, from: deg(0), to: deg(window.usedPercent)),
                    with: .color(BlueprintPalette.tone(window.usedPercent)),
                    lineWidth: 3 * weight
                )
            }
        }
        // Centre mark.
        if account.hasMeasurements {
        var cross = Path()
        cross.move(to: CGPoint(x: 92, y: 100)); cross.addLine(to: CGPoint(x: 108, y: 100))
        cross.move(to: CGPoint(x: 100, y: 92)); cross.addLine(to: CGPoint(x: 100, y: 108))
        context.stroke(cross, with: .color(BlueprintPalette.faint), lineWidth: 0.5)
        }

        // Centre readings.
        if let headroom = account.headroom {
            let color = account.isNearLimit ? BlueprintPalette.accent : BlueprintPalette.ink
            context.draw(text("\(Int(headroom.rounded()))", BlueprintPalette.sans(compact ? 40 : 30, .semibold), color), at: CGPoint(x: 100, y: compact ? 80 : 84))
        } else {
            context.draw(text("—", BlueprintPalette.sans(compact ? 40 : 30, .semibold), BlueprintPalette.dim), at: CGPoint(x: 100, y: compact ? 80 : 84))
        }
        if compact {
            context.draw(text("ROOM %", BlueprintPalette.mono(14), BlueprintPalette.dim), at: CGPoint(x: 100, y: 124))
            return
        }
        context.draw(
            text(account.hasMeasurements ? "HEADROOM %" : "NO READING", BlueprintPalette.mono(7.5), BlueprintPalette.dim),
            at: CGPoint(x: 100, y: 115)
        )
        if account.hasMeasurements {
            context.draw(text("T− \(ThemeText.resetText(account, now: now))", BlueprintPalette.mono(12, .semibold), BlueprintPalette.ink), at: CGPoint(x: 100, y: 156))
            context.draw(text("TO \(BlueprintPalette.windowName(account.bindingWindow)) RESET", BlueprintPalette.mono(7.5), BlueprintPalette.dim), at: CGPoint(x: 100, y: 169))
        } else {
            let (status, color) = BlueprintPalette.status(account, isRoute: false)
            context.draw(text(status, BlueprintPalette.mono(11, .semibold), color), at: CGPoint(x: 100, y: 156))
        }

        // Leader-line callouts.
        let first = account.fiveHour.map { DialGeometry.point(center, 74, deg($0.usedPercent)) }
        let second = account.weekly.map { DialGeometry.point(center, 62, deg($0.usedPercent)) }
        var firstTop = true
        if let first, let second { firstTop = first.y <= second.y }
        drawCallout(context, end: first, lineY: firstTop ? 56 : 132, window: account.fiveHour, label: "5H WINDOW")
        drawCallout(context, end: second, lineY: firstTop ? 132 : 56, window: account.weekly, label: "WEEKLY")
    }

    private func drawCallout(_ context: GraphicsContext, end: CGPoint?, lineY: CGFloat, window: CapacityWindow?, label: String) {
        if let end, let window {
            let color = BlueprintPalette.tone(window.usedPercent)
            var leader = Path()
            leader.move(to: end)
            leader.addLine(to: CGPoint(x: 206, y: lineY))
            leader.addLine(to: CGPoint(x: 296, y: lineY))
            context.stroke(leader, with: .color(BlueprintPalette.dim), lineWidth: 0.75)
            let dot = Path(ellipseIn: CGRect(x: end.x - 2.6, y: end.y - 2.6, width: 5.2, height: 5.2))
            context.fill(dot, with: .color(BlueprintPalette.paper))
            context.stroke(dot, with: .color(color), lineWidth: 1.2)
            context.draw(text(BlueprintPalette.percent(window.usedPercent), BlueprintPalette.sans(19, .semibold), color), at: CGPoint(x: 296, y: lineY - 12), anchor: .trailing)
            context.draw(text("\(label) USED", BlueprintPalette.mono(7.5), BlueprintPalette.dim), at: CGPoint(x: 296, y: lineY + 9), anchor: .trailing)
        } else {
            var leader = Path()
            leader.move(to: CGPoint(x: 216, y: lineY))
            leader.addLine(to: CGPoint(x: 296, y: lineY))
            context.stroke(leader, with: .color(BlueprintPalette.faint), style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
            context.draw(text("—", BlueprintPalette.sans(19, .semibold), BlueprintPalette.dim), at: CGPoint(x: 296, y: lineY - 12), anchor: .trailing)
            context.draw(text("\(label) · NO DATA", BlueprintPalette.mono(7.5), BlueprintPalette.dim), at: CGPoint(x: 296, y: lineY + 9), anchor: .trailing)
        }
    }
}

/// Linear scale with a dimension line measuring the remaining headroom.
private struct BlueprintScaleStrip: View {
    let account: AccountReadout

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let x = { (p: Double) -> CGFloat in 10 + (w - 20) * CGFloat(p) / 100 }
            var base = Path()
            base.move(to: CGPoint(x: 10, y: 12)); base.addLine(to: CGPoint(x: w - 10, y: 12))
            context.stroke(base, with: .color(BlueprintPalette.faint), lineWidth: 0.75)
            var ticks = Path()
            for i in 0...10 {
                ticks.move(to: CGPoint(x: x(Double(i * 10)), y: i % 5 == 0 ? 7 : 10))
                ticks.addLine(to: CGPoint(x: x(Double(i * 10)), y: 15))
            }
            context.stroke(ticks, with: .color(BlueprintPalette.dim), lineWidth: 0.6)
            guard let used = account.peakUsed, let headroom = account.headroom else { return }
            let xm = x(used)
            let end = w - 10
            var bar = Path()
            bar.move(to: CGPoint(x: 10, y: 12)); bar.addLine(to: CGPoint(x: xm, y: 12))
            context.stroke(bar, with: .color(BlueprintPalette.tone(used)), lineWidth: 3)
            var dimension = Path()
            dimension.move(to: CGPoint(x: xm, y: 16)); dimension.addLine(to: CGPoint(x: xm, y: 40))
            dimension.move(to: CGPoint(x: end, y: 16)); dimension.addLine(to: CGPoint(x: end, y: 40))
            context.stroke(dimension, with: .color(BlueprintPalette.ink), lineWidth: 0.6)
            var line = Path()
            line.move(to: CGPoint(x: xm, y: 35)); line.addLine(to: CGPoint(x: end, y: 35))
            context.stroke(line, with: .color(BlueprintPalette.ink), lineWidth: 0.75)
            var slashes = Path()
            slashes.move(to: CGPoint(x: xm - 3, y: 38)); slashes.addLine(to: CGPoint(x: xm + 3, y: 32))
            slashes.move(to: CGPoint(x: end - 3, y: 38)); slashes.addLine(to: CGPoint(x: end + 3, y: 32))
            context.stroke(slashes, with: .color(BlueprintPalette.ink), lineWidth: 1.2)

            let headroomLabel = Text("HEADROOM \(BlueprintPalette.percent(headroom))")
                .font(BlueprintPalette.mono(9, .semibold))
                .foregroundColor(BlueprintPalette.ink)
            if end - xm > 90 {
                context.draw(headroomLabel, at: CGPoint(x: (xm + end) / 2, y: 27))
            } else {
                context.draw(headroomLabel, at: CGPoint(x: xm - 8, y: 27), anchor: .trailing)
            }
            if end - xm > 90 || xm > 190 {
                context.draw(
                    Text("MAX USED \(BlueprintPalette.percent(used))").font(BlueprintPalette.mono(8.5)).foregroundColor(BlueprintPalette.dim),
                    at: CGPoint(x: 10, y: 27),
                    anchor: .leading
                )
            }
        }
        .frame(height: 44)
        .accessibilityHidden(true)
    }
}

private struct BlueprintAccountCard: View {
    let account: AccountReadout
    let number: Int
    let isRoute: Bool
    let dialWidth: CGFloat
    let now: Date

    var body: some View {
        let (status, statusColor) = BlueprintPalette.status(account, isRoute: isRoute)
        let border = account.isNearLimit ? BlueprintPalette.accent : (isRoute ? BlueprintPalette.ink : BlueprintPalette.faint)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                BlueprintBadge(text: "A\(number)", size: 28, fontSize: 10, color: BlueprintPalette.ink, weight: .semibold)
                VStack(alignment: .leading, spacing: 0) {
                    Text(account.snapshot.account.label)
                        .font(BlueprintPalette.sans(16, .semibold))
                        .lineLimit(1)
                    Text(ThemeText.identityLine(account))
                        .font(BlueprintPalette.mono(10))
                        .foregroundStyle(BlueprintPalette.isStale(account) ? BlueprintPalette.accent : BlueprintPalette.dim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Text(status)
                    .font(BlueprintPalette.mono(9))
                    .kerning(1)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(statusColor, lineWidth: 1))
                    .fixedSize()
            }
            .frame(height: 34)
            .help(ThemeText.guide(account.snapshot.provider))

            BlueprintDial(account: account, now: now)
                .frame(width: dialWidth, height: dialWidth * 190 / 300)
                .frame(maxWidth: .infinity)

            if account.hasMeasurements {
                BlueprintScaleStrip(account: account)
                if !account.otherWindows.isEmpty {
                    Text("ALSO · " + account.otherWindows.map { "\($0.label.uppercased()) \(BlueprintPalette.percent($0.usedPercent))" }.joined(separator: " · "))
                        .font(BlueprintPalette.mono(9))
                        .foregroundStyle(BlueprintPalette.dim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                BlueprintSignInNote(account: account)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BlueprintPalette.paper, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(border, lineWidth: account.isNearLimit ? 1.5 : 1))
    }
}

/// State and the provider's message (the sign-in command) for an unmeasured account.
private struct BlueprintSignInNote: View {
    let account: AccountReadout
    var compact = false

    var body: some View {
        let (_, color) = BlueprintPalette.status(account, isRoute: false)
        VStack(alignment: .leading, spacing: 3) {
            Text(account.snapshot.state.label.uppercased())
                .font(BlueprintPalette.mono(compact ? 9 : 10, .semibold))
                .kerning(1)
                .foregroundStyle(color)
            Text(account.snapshot.message ?? "No usage reported yet.")
                .font(BlueprintPalette.mono(compact ? 9 : 10))
                .foregroundStyle(BlueprintPalette.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(BlueprintPalette.faint, style: StrokeStyle(lineWidth: 0.75, dash: [4, 3]))
        )
    }
}

private struct BlueprintCompactAccount: View {
    let account: AccountReadout
    let number: Int
    let isRoute: Bool
    let now: Date

    var body: some View {
        let (status, statusColor) = BlueprintPalette.status(account, isRoute: isRoute)
        HStack(alignment: .top, spacing: 10) {
            BlueprintDial(account: account, now: now, compact: true)
                .frame(width: 86, height: 86)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    BlueprintBadge(text: "A\(number)", size: 22, fontSize: 9, color: BlueprintPalette.ink, weight: .semibold)
                    Text(account.snapshot.account.label)
                        .font(BlueprintPalette.sans(15, .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(status)
                        .font(BlueprintPalette.mono(8.5))
                        .kerning(1)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(statusColor, lineWidth: 1))
                        .fixedSize()
                }
                Text(ThemeText.identityLine(account))
                    .font(BlueprintPalette.mono(9))
                    .foregroundStyle(BlueprintPalette.isStale(account) ? BlueprintPalette.accent : BlueprintPalette.dim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if account.hasMeasurements {
                    HStack(alignment: .top, spacing: 14) {
                        reading(account.fiveHour.map { BlueprintPalette.percent($0.usedPercent) } ?? "—", "5H USED", account.fiveHour?.usedPercent)
                        reading(account.weekly.map { BlueprintPalette.percent($0.usedPercent) } ?? "—", "WK USED", account.weekly?.usedPercent)
                        reading(ThemeText.resetText(account, now: now), "T− \(BlueprintPalette.windowName(account.bindingWindow)) RESET", nil)
                    }
                } else {
                    BlueprintSignInNote(account: account, compact: true)
                }
            }
        }
        .padding(10)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(account.isNearLimit ? BlueprintPalette.accent : BlueprintPalette.faint, lineWidth: 1)
        )
        .help(ThemeText.guide(account.snapshot.provider))
    }

    private func reading(_ value: String, _ label: String, _ percent: Double?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(BlueprintPalette.sans(18, .semibold))
                .foregroundStyle(percent.map(BlueprintPalette.tone) ?? (value == "—" ? BlueprintPalette.dim : BlueprintPalette.ink))
                .lineLimit(1)
            Text(label)
                .font(BlueprintPalette.mono(8))
                .foregroundStyle(BlueprintPalette.dim)
                .lineLimit(1)
        }
        .fixedSize()
    }
}

// MARK: - Projects, objectives, tasks

/// Thin measured bar with a 10% scale above it.
private struct BlueprintMeasureBar: View {
    let value: Double
    var marker = true

    var body: some View {
        Canvas { context, size in
            let baseline: CGFloat = marker ? 9 : 7
            let w = size.width
            var base = Path()
            base.move(to: CGPoint(x: 0, y: baseline)); base.addLine(to: CGPoint(x: w, y: baseline))
            context.stroke(base, with: .color(BlueprintPalette.faint), lineWidth: 0.75)
            var ticks = Path()
            for i in 0...10 {
                let x = min(max(w * CGFloat(i) / 10, 0.3), w - 0.3)
                ticks.move(to: CGPoint(x: x, y: baseline - (i % 5 == 0 ? 7 : 4)))
                ticks.addLine(to: CGPoint(x: x, y: baseline))
            }
            context.stroke(ticks, with: .color(BlueprintPalette.dim), lineWidth: 0.6)
            let end = w * CGFloat(min(max(value, 0), 100)) / 100
            if end > 0 {
                var bar = Path()
                bar.move(to: CGPoint(x: 0, y: baseline)); bar.addLine(to: CGPoint(x: end, y: baseline))
                context.stroke(bar, with: .color(BlueprintPalette.ink), lineWidth: 3)
            }
            if marker {
                var mark = Path()
                mark.move(to: CGPoint(x: end, y: 0)); mark.addLine(to: CGPoint(x: end, y: 12))
                context.stroke(mark, with: .color(BlueprintPalette.ink), lineWidth: 1.2)
            }
        }
        .frame(height: marker ? 12 : 10)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(BlueprintPalette.percent(value))
    }
}

private struct BlueprintProjectRow: View {
    let project: MissionProject
    let number: Int

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            BlueprintBadge(text: "B\(number)")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(project.name)
                        .font(BlueprintPalette.sans(15, .semibold))
                        .lineLimit(1)
                    if !project.phase.isEmpty {
                        Text(project.phase.uppercased())
                            .font(BlueprintPalette.mono(9))
                            .kerning(1)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(BlueprintPalette.ink, lineWidth: 1))
                            .fixedSize()
                    }
                    Spacer(minLength: 0)
                    Text(BlueprintPalette.percent(project.progress))
                        .font(BlueprintPalette.mono(13, .semibold))
                        .fixedSize()
                }
                BlueprintMeasureBar(value: project.progress)
                (Text("NEXT: ").foregroundColor(BlueprintPalette.dim)
                    + Text(project.nextAction.isEmpty ? "—" : project.nextAction).foregroundColor(BlueprintPalette.ink))
                    .font(BlueprintPalette.mono(11))
                    .lineLimit(2)
            }
        }
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) {
            BlueprintHDash().stroke(BlueprintPalette.faint, style: StrokeStyle(lineWidth: 0.75, dash: [4, 3]))
                .frame(height: 1)
        }
    }
}

private struct BlueprintObjectiveRow: View {
    let objective: MissionObjective
    let number: Int

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            BlueprintBadge(text: "D\(number)")
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(objective.title)
                        .font(BlueprintPalette.sans(14, .semibold))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Text(BlueprintPalette.percent(objective.progress))
                        .font(BlueprintPalette.mono(13, .semibold))
                        .fixedSize()
                }
                BlueprintMeasureBar(value: objective.progress, marker: false)
                if !objective.summary.isEmpty {
                    Text(objective.summary)
                        .font(BlueprintPalette.mono(10))
                        .foregroundStyle(BlueprintPalette.dim)
                        .lineLimit(2)
                }
            }
        }
    }
}

private struct BlueprintNote: View {
    let number: Int
    let text: String
    let highlighted: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(number).")
                .font(BlueprintPalette.mono(11))
                .frame(width: 16, alignment: .leading)
            Text(text)
                .font(BlueprintPalette.sans(12.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(highlighted ? BlueprintPalette.accent : BlueprintPalette.ink)
    }
}

private struct BlueprintTitleBlock: View {
    let cells: [(String, String)]
    let width: CGFloat

    var body: some View {
        let cellWidth = max((width - 3) / 3, 60)
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("MISSION CONTROL")
                        .font(BlueprintPalette.sans(15, .bold))
                        .kerning(3)
                    Text("CAPACITY & OPERATIONS — DAILY SHEET")
                        .font(BlueprintPalette.mono(9))
                        .kerning(1)
                        .foregroundStyle(BlueprintPalette.dim)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(BlueprintPalette.drawingNumber)
                    .font(BlueprintPalette.mono(13, .semibold))
                    .kerning(1)
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Rectangle().fill(BlueprintPalette.ink).frame(height: 1)
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { column in
                        let cell = cells[row * 3 + column]
                        VStack(alignment: .leading, spacing: 1) {
                            Text(cell.0)
                                .font(BlueprintPalette.mono(8.5))
                                .kerning(1)
                                .foregroundStyle(BlueprintPalette.dim)
                            Text(cell.1)
                                .font(BlueprintPalette.mono(12, .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .frame(width: cellWidth, alignment: .leading)
                        if column < 2 { Rectangle().fill(BlueprintPalette.ink).frame(width: 1) }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                if row == 0 { Rectangle().fill(BlueprintPalette.ink).frame(height: 1) }
            }
        }
        .overlay(Rectangle().strokeBorder(BlueprintPalette.ink, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }
}

private struct BlueprintTaskGroup: View {
    let number: Int
    let bucket: TaskBucket
    let tasks: [MissionTask]
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let now: Date

    private var note: String {
        switch bucket {
        case .now: "IN WORK"
        case .next: "QUEUED"
        case .later: "PARKED"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            BlueprintBadge(text: "\(number)", size: 24, fontSize: 11, color: BlueprintPalette.ink, weight: .semibold, lineWidth: 1.2)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(bucket.title)
                        .font(BlueprintPalette.sans(14, .semibold))
                        .kerning(2)
                    Text(note)
                        .font(BlueprintPalette.mono(10))
                        .foregroundStyle(BlueprintPalette.dim)
                    Spacer(minLength: 0)
                    Text("\(tasks.count)")
                        .font(BlueprintPalette.mono(10))
                        .foregroundStyle(BlueprintPalette.dim)
                }
                .frame(height: 22)
                if tasks.isEmpty {
                    Text(bucket == .now ? "NOTHING IN WORK. USE + TO ADD A TASK." : "— NO ITEMS —")
                        .font(BlueprintPalette.mono(10))
                        .foregroundStyle(BlueprintPalette.dim)
                        .padding(.bottom, 4)
                }
                ForEach(tasks) { task in
                    BlueprintTaskRow(task: task, missions: missions, editor: $editor, now: now)
                }
            }
        }
        .background(alignment: .topLeading) {
            BlueprintVDash()
                .stroke(BlueprintPalette.faint, style: StrokeStyle(lineWidth: 0.75, dash: [4, 3]))
                .frame(width: 30)
                .padding(.top, 27)
        }
    }
}

private struct BlueprintTaskRow: View {
    let task: MissionTask
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: doneBinding(task, missions: missions)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(BlueprintPalette.sans(14, .medium))
                        .strikethrough(task.isDone, color: BlueprintPalette.dim)
                        .foregroundStyle(task.isDone ? BlueprintPalette.dim : BlueprintPalette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let project = missions.board.project(for: task) {
                        Text(project.name)
                            .font(BlueprintPalette.mono(10))
                            .foregroundStyle(BlueprintPalette.dim)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(BlueprintCheckStyle())
            if let due = ThemeText.dueLabel(task, now: now) {
                Text(due)
                    .font(BlueprintPalette.mono(10, .semibold))
                    .kerning(1)
                    .foregroundStyle(task.isDue(on: now) ? BlueprintPalette.accent : BlueprintPalette.dim)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(BlueprintPalette.faint, lineWidth: 0.75))
        .contentShape(Rectangle())
        .taskActions(task, missions: missions, editor: $editor)
    }
}

/// Square drafting check box.
private struct BlueprintCheckStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(configuration.isOn ? BlueprintPalette.ink : Color.clear)
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(BlueprintPalette.ink, lineWidth: 1)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(BlueprintPalette.paper)
                    }
                }
                .frame(width: 14, height: 14)
                .frame(width: 18)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Done" : "Open")
    }
}
