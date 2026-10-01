import AppKit
import CapacityCore
import SwiftUI

// Orbital: deep-space navy cards, concentric usage rings per account, projects
// as planets travelling from launch to landing, and objectives as orbit gauges.

// MARK: - Palette and type

private enum OrbitalPalette {
    static let space = Color(hex: 0x070B1A)
    static let card = Color(hex: 0x0E1530)
    static let track = Color(hex: 0x1B2448)
    static let dash = Color(hex: 0x2A3563)
    static let text = Color(hex: 0xE8ECF8)
    static let secondary = Color(hex: 0x8F9BBF)
    static let accent = Color(hex: 0x4CC9F0)
    static let warm = Color(hex: 0xF4A261)
    static let hot = Color(hex: 0xF28482)
    static let green = Color(hex: 0x7BE0AD)
    static let violet = Color(hex: 0xB49CFF)
    static let hotBorder = Color(hex: 0x5A2A3A)
    static let planets: [Color] = [accent, warm, green, violet]

    /// Ring colour for a window's used percentage, as on the design.
    static func tone(_ used: Double) -> Color {
        used >= 85 ? hot : used >= 65 ? warm : accent
    }

    /// Space Grotesk stand-in.
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Space Mono stand-in.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

private enum OrbitalFormat {
    static func percent(_ window: CapacityWindow?) -> String {
        window.map { "\(Int($0.usedPercent.rounded()))%" } ?? "no data"
    }

    static func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    static func probed(_ lastRefresh: Date?, now: Date) -> String {
        ThemeText.probedLabel(lastRefresh, now: now).lowercased()
    }

    static func windowName(_ window: CapacityWindow?) -> String {
        switch window?.durationMinutes {
        case 300: "5-hour"
        case 10_080: "weekly"
        default: "usage"
        }
    }
}

// MARK: - Dashboard

struct OrbitalDashboardView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    var staticLayout = false

    @State private var editor: MissionEditor?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OrbitalHeader(capacity: capacity, missions: missions)
            OrbitalStatusStrip(readout: readout)
            accountGrid
            GeometryReader { proxy in
                let unit = (proxy.size.width - 16) / 2.6
                HStack(alignment: .top, spacing: 16) {
                    OrbitalProjectsPanel(missions: missions, editor: $editor, staticLayout: staticLayout)
                        .frame(width: unit * 1.6)
                    VStack(spacing: 16) {
                        OrbitalObjectivesPanel(missions: missions, editor: $editor)
                        OrbitalTasksPanel(missions: missions, editor: $editor, staticLayout: staticLayout)
                    }
                    .frame(width: unit)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OrbitalPalette.space)
        .foregroundStyle(OrbitalPalette.text)
        .missionEditorSheet($editor, missions: missions)
    }

    private var accountGrid: some View {
        let accounts = readout.accounts
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 16, alignment: .top),
            count: max(1, min(accounts.count, 4))
        )
        let bestID = readout.bestClaude?.snapshot.id
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(accounts, id: \.snapshot.id) { account in
                OrbitalAccountCard(account: account, isRoute: account.snapshot.id == bestID)
            }
            if accounts.isEmpty {
                Text("No accounts configured yet.")
                    .font(OrbitalPalette.sans(13))
                    .foregroundStyle(OrbitalPalette.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .orbitalCard()
            }
        }
    }
}

// MARK: - Header

private struct OrbitalHeader: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 16) {
                OrbitalLogo().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mission Control")
                        .font(OrbitalPalette.sans(22, .bold))
                        .kerning(0.5)
                    Text("\(OrbitalFormat.longDate(context.date)) · \(OrbitalFormat.probed(capacity.lastRefresh, now: context.date))")
                        .font(OrbitalPalette.mono(11))
                        .foregroundStyle(OrbitalPalette.secondary)
                }
                Spacer(minLength: 16)
                HStack(spacing: 6) {
                    segment("\(missions.board.openTaskCount) open tasks")
                    segment("\(missions.board.dueTodayCount(now: context.date)) due today")
                    ThemePicker {
                        Text("Theme ▾")
                            .font(OrbitalPalette.sans(13))
                            .foregroundStyle(OrbitalPalette.secondary)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                    }
                    Button {
                        Task { await capacity.refresh() }
                    } label: {
                        Text(capacity.isRefreshing ? "Probing…" : "Re-probe")
                            .font(OrbitalPalette.sans(13, .semibold))
                            .foregroundStyle(OrbitalPalette.space)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(
                                capacity.isRefreshing ? OrbitalPalette.secondary : OrbitalPalette.accent,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(capacity.isRefreshing)
                    .help("Check every account's usage now")
                }
                .padding(4)
                .background(OrbitalPalette.card, in: Capsule())
                .fixedSize()
            }
        }
    }

    private func segment(_ text: String) -> some View {
        Text(text)
            .font(OrbitalPalette.sans(13))
            .foregroundStyle(OrbitalPalette.secondary)
            .padding(.horizontal, 14)
            .frame(height: 36)
    }
}

private struct OrbitalLogo: View {
    var color: Color = OrbitalPalette.accent

    var body: some View {
        Canvas { context, size in
            let s = size.width / 40
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            context.stroke(
                Path(ellipseIn: CGRect(x: c.x - 5 * s, y: c.y - 5 * s, width: 10 * s, height: 10 * s)),
                with: .color(color), lineWidth: 1.6 * s
            )
            let orbit = Path(ellipseIn: CGRect(x: -17 * s, y: -7 * s, width: 34 * s, height: 14 * s))
                .applying(CGAffineTransform(rotationAngle: -25 * .pi / 180))
                .applying(CGAffineTransform(translationX: c.x, y: c.y))
            context.stroke(orbit, with: .color(color), lineWidth: 1.6 * s)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Route and caution

private struct OrbitalStatusStrip: View {
    let readout: CockpitReadout
    var compact = false

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 8) {
                route
                HStack(spacing: 8) {
                    caution
                    signIn
                    Spacer(minLength: 0)
                }
            }
        } else {
            HStack(spacing: 12) {
                route
                caution
                signIn
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var signIn: some View {
        if !readout.needsSignIn.isEmpty {
            pill(border: OrbitalPalette.dash) {
                Circle().fill(OrbitalPalette.warm).frame(width: 8, height: 8)
                Text(signInText)
                    .font(OrbitalPalette.sans(compact ? 12 : 13))
                    .foregroundStyle(OrbitalPalette.warm)
                    .lineLimit(1)
            }
        }
    }

    private var signInText: String {
        let count = readout.needsSignIn.count
        return "\(count) account\(count == 1 ? "" : "s") need\(count == 1 ? "s" : "") sign-in"
    }

    private var route: some View {
        pill(border: readout.bestClaude == nil ? OrbitalPalette.dash : OrbitalPalette.accent.opacity(0.45)) {
            OrbitalLogo(color: readout.bestClaude == nil ? OrbitalPalette.secondary : OrbitalPalette.accent)
                .frame(width: 20, height: 20)
            Text(compact ? "Route" : "Route next Claude session")
                .font(OrbitalPalette.sans(compact ? 12 : 13))
                .foregroundStyle(OrbitalPalette.secondary)
                .lineLimit(1)
            if let best = readout.bestClaude {
                Text("→ \(best.snapshot.account.label)")
                    .font(OrbitalPalette.sans(compact ? 13 : 14, .semibold))
                    .lineLimit(1)
                Text("\(Int((best.headroom ?? 0).rounded()))% headroom")
                    .font(OrbitalPalette.mono(compact ? 11 : 12, .bold))
                    .foregroundStyle(OrbitalPalette.accent)
                    .lineLimit(1)
            } else {
                Text("no Claude account available")
                    .font(OrbitalPalette.sans(compact ? 13 : 14, .semibold))
                    .foregroundStyle(OrbitalPalette.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var caution: some View {
        Group {
            if let caution = readout.masterCaution, let window = caution.bindingWindow {
                pill(border: OrbitalPalette.hotBorder, fill: OrbitalPalette.hot.opacity(0.10)) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(OrbitalPalette.hot)
                    Text("\(caution.snapshot.account.label) is at \(Int(window.usedPercent.rounded()))% of its \(OrbitalFormat.windowName(window)) window")
                        .font(OrbitalPalette.sans(compact ? 12 : 13, .medium))
                        .foregroundStyle(OrbitalPalette.hot)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                pill(border: OrbitalPalette.dash) {
                    Circle().fill(OrbitalPalette.green).frame(width: 8, height: 8)
                    Text(compact ? "Within limits" : "All accounts within limits")
                        .font(OrbitalPalette.sans(compact ? 12 : 13))
                        .foregroundStyle(OrbitalPalette.text)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func pill<Content: View>(
        border: Color,
        fill: Color = OrbitalPalette.card,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 16)
            .frame(height: compact ? 34 : 40)
            .background(fill, in: Capsule())
            .overlay(Capsule().stroke(border, lineWidth: 1))
    }
}

// MARK: - Accounts

/// Outer ring: 5-hour window. Inner ring: weekly window. Centre: headroom.
private struct OrbitalRings: View {
    let account: AccountReadout
    var size: CGFloat = 104

    var body: some View {
        let s = size / 104
        ZStack {
            ring(account.fiveHour, diameter: 88 * s, width: 8 * s, opacity: 1)
            ring(account.weekly, diameter: 60 * s, width: 6 * s, opacity: 0.75)
            Text(account.headroom.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(OrbitalPalette.sans(17 * s, .bold))
                .foregroundStyle(account.hasMeasurements ? OrbitalPalette.text : OrbitalPalette.secondary)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(account.snapshot.account.label) usage rings")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard account.hasMeasurements else { return account.snapshot.state.label }
        return "5-hour \(OrbitalFormat.percent(account.fiveHour)) used, weekly \(OrbitalFormat.percent(account.weekly)) used, \(Int((account.headroom ?? 0).rounded()))% headroom"
    }

    @ViewBuilder
    private func ring(_ window: CapacityWindow?, diameter: CGFloat, width: CGFloat, opacity: Double) -> some View {
        ZStack {
            Circle().stroke(OrbitalPalette.track, lineWidth: width)
            if let window, window.usedPercent > 0 {
                Circle()
                    .trim(from: 0, to: window.usedPercent / 100)
                    .stroke(OrbitalPalette.tone(window.usedPercent), style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(opacity)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

private struct OrbitalAccountCard: View {
    let account: AccountReadout
    let isRoute: Bool

    private var snapshot: ProviderSnapshot { account.snapshot }
    private var isStale: Bool { snapshot.state == .error && account.hasMeasurements }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            OrbitalRings(account: account)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(snapshot.account.label)
                        .font(OrbitalPalette.sans(17, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if isRoute {
                        Text("route")
                            .font(OrbitalPalette.mono(10, .bold))
                            .foregroundStyle(OrbitalPalette.space)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(OrbitalPalette.accent, in: Capsule())
                    }
                }
                Text(ThemeText.identityLine(account))
                    .font(OrbitalPalette.sans(12))
                    .foregroundStyle(isStale ? OrbitalPalette.warm : OrbitalPalette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if account.hasMeasurements {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("5h \(OrbitalFormat.percent(account.fiveHour)) · wk \(OrbitalFormat.percent(account.weekly))")
                            Text("resets in \(ThemeText.resetText(account, now: context.date).lowercased())")
                        }
                        .font(OrbitalPalette.mono(11))
                        .foregroundStyle(OrbitalPalette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                    .padding(.top, 6)
                } else {
                    Text(snapshot.state.label.lowercased())
                        .font(OrbitalPalette.mono(11, .bold))
                        .foregroundStyle(OrbitalPalette.warm)
                        .padding(.top, 4)
                    Text(snapshot.message ?? "No usage reported yet.")
                        .font(OrbitalPalette.mono(10))
                        .foregroundStyle(OrbitalPalette.secondary)
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .orbitalCard(border: account.isNearLimit ? OrbitalPalette.hotBorder : OrbitalPalette.card)
        .help(ThemeText.guide(snapshot.provider))
    }
}

// MARK: - Projects

private struct OrbitalProjectsPanel: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let staticLayout: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Missions in orbit").font(OrbitalPalette.sans(18, .semibold))
                Spacer()
                Text("launch → landing")
                    .font(OrbitalPalette.mono(11))
                    .foregroundStyle(OrbitalPalette.secondary)
                OrbitalAddButton(help: "Add a project") {
                    editor = .project(MissionProject(name: ""))
                }
            }
            .padding(.bottom, 8)
            OrbitalScroll(staticLayout: staticLayout) {
                VStack(alignment: .leading, spacing: 0) {
                    if missions.board.projects.isEmpty {
                        OrbitalEmpty(text: "No missions in orbit yet. Use + to launch your first project.")
                    }
                    ForEach(Array(missions.board.projects.enumerated()), id: \.element.id) { index, project in
                        OrbitalProjectRow(project: project, color: OrbitalPalette.planets[index % OrbitalPalette.planets.count])
                            .projectActions(project, missions: missions, editor: $editor)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .orbitalCard()
    }
}

private struct OrbitalProjectRow: View {
    let project: MissionProject
    let color: Color

    private var fraction: Double { min(max(project.progress / 100, 0), 1) }

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(OrbitalPalette.sans(15, .semibold))
                    .lineLimit(1)
                Text(project.nextAction.isEmpty ? project.phase : project.nextAction)
                    .font(OrbitalPalette.sans(12))
                    .foregroundStyle(OrbitalPalette.secondary)
                    .lineLimit(1)
            }
            .frame(width: 190, alignment: .leading)
            GeometryReader { proxy in
                let travel = (proxy.size.width - 44) * fraction
                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 12))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: 12))
                    }
                    .stroke(OrbitalPalette.dash, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    Rectangle()
                        .fill(color.opacity(0.6))
                        .frame(width: travel, height: 2)
                        .offset(y: 11)
                    Circle()
                        .fill(color)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(color.opacity(0.14)).frame(width: 32, height: 32))
                        .offset(x: travel, y: 2)
                    Text("\(Int(project.progress.rounded()))%")
                        .font(OrbitalPalette.mono(11))
                        .foregroundStyle(OrbitalPalette.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .offset(y: -6)
                }
            }
            .frame(height: 24)
        }
        .frame(height: 62)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(project.name), \(project.phase)")
        .accessibilityValue("\(Int(project.progress.rounded()))% complete. Next: \(project.nextAction)")
    }
}

// MARK: - Objectives

private struct OrbitalObjectivesPanel: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Objectives · \(missions.board.periodTitle)").font(OrbitalPalette.sans(18, .semibold))
                Spacer()
                OrbitalAddButton(help: "Add an objective") {
                    editor = .objective(MissionObjective(title: ""))
                }
            }
            if missions.board.objectives.isEmpty {
                OrbitalEmpty(text: "No objectives for \(missions.board.periodTitle) yet. Use + to set one.")
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3),
                    spacing: 12
                ) {
                    ForEach(missions.board.objectives) { objective in
                        VStack(spacing: 8) {
                            OrbitalProgressRing(value: objective.progress, size: 78)
                            Text(objective.title)
                                .font(OrbitalPalette.sans(12))
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .lineSpacing(1)
                        }
                        .frame(maxWidth: .infinity)
                        .help(objective.summary)
                        .objectiveActions(objective, missions: missions, editor: $editor)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .orbitalCard()
    }
}

private struct OrbitalProgressRing: View {
    let value: Double
    var size: CGFloat = 78
    var color: Color = OrbitalPalette.accent

    var body: some View {
        let s = size / 78
        ZStack {
            Circle().stroke(OrbitalPalette.track, lineWidth: 7 * s)
            Circle()
                .trim(from: 0, to: min(max(value / 100, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 7 * s, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(value.rounded()))")
                .font(OrbitalPalette.sans(16 * s, .bold))
        }
        .frame(width: 64 * s, height: 64 * s)
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(value.rounded()))%")
    }
}

// MARK: - Tasks

private struct OrbitalTasksPanel: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let staticLayout: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Flight plan").font(OrbitalPalette.sans(18, .semibold))
                Text("\(missions.board.openTaskCount) open")
                    .font(OrbitalPalette.mono(11))
                    .foregroundStyle(OrbitalPalette.secondary)
                Spacer()
                OrbitalAddButton(help: "Add a task") {
                    editor = .task(MissionTask(title: ""))
                }
            }
            OrbitalScroll(staticLayout: staticLayout) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: 4) {
                        if missions.board.tasks.isEmpty {
                            OrbitalEmpty(text: "No tasks yet. Use + to add your first one.")
                        } else {
                            ForEach(TaskBucket.allCases) { bucket in
                                bucketSection(bucket, now: context.date)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .orbitalCard()
    }

    @ViewBuilder
    private func bucketSection(_ bucket: TaskBucket, now: Date) -> some View {
        let tasks = missions.board.tasks(in: bucket, now: now)
        HStack(spacing: 8) {
            Text(bucket.rawValue.capitalized)
                .font(OrbitalPalette.mono(11, .bold))
                .foregroundStyle(bucket == .now ? OrbitalPalette.accent : OrbitalPalette.secondary)
            Text(tasks.isEmpty ? "· clear skies" : "· \(tasks.count)")
                .font(OrbitalPalette.mono(11))
                .foregroundStyle(OrbitalPalette.secondary)
        }
        .padding(.top, bucket == .now ? 0 : 6)
        ForEach(tasks) { task in
            OrbitalTaskRow(task: task, missions: missions, editor: $editor, now: now)
        }
    }
}

private struct OrbitalTaskRow: View {
    let task: MissionTask
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let now: Date
    var fontSize: CGFloat = 13

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: doneBinding(task, missions: missions)) {
                Text(task.title)
                    .font(OrbitalPalette.sans(fontSize))
                    .strikethrough(task.isDone, color: OrbitalPalette.secondary)
                    .foregroundStyle(task.isDone ? OrbitalPalette.secondary : OrbitalPalette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(OrbitalCheckStyle())
            if let due = ThemeText.dueLabel(task, now: now) {
                Text(due.lowercased())
                    .font(OrbitalPalette.mono(10, .bold))
                    .foregroundStyle(task.isDue(on: now) ? OrbitalPalette.warm : OrbitalPalette.secondary)
                    .fixedSize()
            }
            if let project = missions.board.project(for: task) {
                Text(project.name)
                    .font(OrbitalPalette.sans(11))
                    .foregroundStyle(OrbitalPalette.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(OrbitalPalette.track, in: Capsule())
                    .frame(maxWidth: 110, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: 29)
        .taskActions(task, missions: missions, editor: $editor)
    }
}

private struct OrbitalCheckStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(configuration.isOn ? OrbitalPalette.accent : Color.clear)
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(configuration.isOn ? OrbitalPalette.accent : OrbitalPalette.secondary, lineWidth: 1.5)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(OrbitalPalette.space)
                    }
                }
                .frame(width: 18, height: 18)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Done" : "Open")
    }
}

// MARK: - Shared chrome

private struct OrbitalAddButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(OrbitalPalette.accent)
                .frame(width: 26, height: 26)
                .background(OrbitalPalette.track, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct OrbitalEmpty: View {
    let text: String

    var body: some View {
        Text(text)
            .font(OrbitalPalette.sans(13))
            .foregroundStyle(OrbitalPalette.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

private struct OrbitalScroll<Content: View>: View {
    let staticLayout: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if staticLayout {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        } else {
            ScrollView {
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
    }
}

private extension View {
    func orbitalCard(border: Color = OrbitalPalette.card, radius: CGFloat = 20) -> some View {
        background(OrbitalPalette.card, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(border, lineWidth: 1))
    }
}

// MARK: - Menu

struct OrbitalMenuView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    var staticLayout = false
    @Environment(\.openWindow) private var openWindow
    @State private var editor: MissionEditor?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            OrbitalStatusStrip(readout: readout, compact: true)
            if staticLayout {
                content
            } else {
                ScrollView { content }.scrollIndicators(.never)
            }
            footer
        }
        .padding(16)
        .background(OrbitalPalette.space)
        .foregroundStyle(OrbitalPalette.text)
        .missionEditorSheet($editor, missions: missions)
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 10) {
                OrbitalLogo().frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mission Control").font(OrbitalPalette.sans(16, .bold))
                    Text("\(OrbitalFormat.longDate(context.date)) · \(OrbitalFormat.probed(capacity.lastRefresh, now: context.date))")
                        .font(OrbitalPalette.mono(10))
                        .foregroundStyle(OrbitalPalette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(readout.accounts, id: \.snapshot.id) { account in
                compactAccount(account, isRoute: account.snapshot.id == readout.bestClaude?.snapshot.id)
            }
            nowTasks
        }
    }

    private func compactAccount(_ account: AccountReadout, isRoute: Bool) -> some View {
        HStack(spacing: 14) {
            OrbitalRings(account: account, size: 72)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(account.snapshot.account.label)
                        .font(OrbitalPalette.sans(14, .semibold))
                        .lineLimit(1)
                    if isRoute {
                        Text("route")
                            .font(OrbitalPalette.mono(9, .bold))
                            .foregroundStyle(OrbitalPalette.space)
                            .padding(.horizontal, 5)
                            .background(OrbitalPalette.accent, in: Capsule())
                    }
                }
                if account.hasMeasurements {
                    Text(ThemeText.identityLine(account))
                        .font(OrbitalPalette.sans(11))
                        .foregroundStyle(OrbitalPalette.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("5h \(OrbitalFormat.percent(account.fiveHour)) · wk \(OrbitalFormat.percent(account.weekly)) · resets \(ThemeText.resetText(account, now: Date()).lowercased())")
                        .font(OrbitalPalette.mono(10))
                        .foregroundStyle(OrbitalPalette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text(account.snapshot.state.label.lowercased())
                        .font(OrbitalPalette.mono(10, .bold))
                        .foregroundStyle(OrbitalPalette.warm)
                    Text(account.snapshot.message ?? "No usage reported yet.")
                        .font(OrbitalPalette.mono(9.5))
                        .foregroundStyle(OrbitalPalette.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .orbitalCard(border: account.isNearLimit ? OrbitalPalette.hotBorder : OrbitalPalette.card, radius: 16)
    }

    private var nowTasks: some View {
        let tasks = missions.board.tasks(in: .now)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Now").font(OrbitalPalette.sans(15, .semibold))
                Text(tasks.isEmpty ? "clear skies" : "\(tasks.count) tasks")
                    .font(OrbitalPalette.mono(10))
                    .foregroundStyle(OrbitalPalette.secondary)
                Spacer()
                OrbitalAddButton(help: "Add a task") {
                    editor = .task(MissionTask(title: ""))
                }
            }
            if tasks.isEmpty {
                OrbitalEmpty(text: "Nothing in Now. Open the dashboard to plan.")
            }
            ForEach(tasks) { task in
                OrbitalTaskRow(task: task, missions: missions, editor: $editor, now: Date(), fontSize: 12.5)
            }
        }
        .padding(14)
        .orbitalCard(radius: 16)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                OpenDashboardAction(openWindow: openWindow)()
            } label: {
                Text("Open Dashboard")
                    .font(OrbitalPalette.sans(12, .semibold))
                    .foregroundStyle(OrbitalPalette.space)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(OrbitalPalette.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            Button {
                Task { await capacity.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OrbitalPalette.accent)
                    .frame(width: 30, height: 30)
                    .background(OrbitalPalette.card, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(capacity.isRefreshing)
            .help("Re-probe every account")
            .accessibilityLabel(capacity.isRefreshing ? "Probing" : "Re-probe")
            Spacer(minLength: 0)
            ThemePicker {
                Text("Theme ▾")
                    .font(OrbitalPalette.sans(12))
                    .foregroundStyle(OrbitalPalette.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(OrbitalPalette.card, in: Capsule())
            }
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(OrbitalPalette.sans(12))
                    .foregroundStyle(OrbitalPalette.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(OrbitalPalette.card, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}
