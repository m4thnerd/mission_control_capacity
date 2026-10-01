import AppKit
import CapacityCore
import SwiftUI

// Daily Briefing: the dashboard as the front page of a morning newspaper.
// The lead story is written from the live readout.

// MARK: - Dashboard

struct DailyBriefingDashboardView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    var staticLayout = false

    @State private var editor: MissionEditor?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - 88, 900)
            let mainWidth = width * 1.55 / 3.45
            let middleWidth = width / 3.45
            let asideWidth = width * 0.9 / 3.45
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(spacing: 0) {
                    masthead(now: context.date)
                    HStack(alignment: .top, spacing: 0) {
                        leadColumn(width: mainWidth - 26, now: context.date)
                            .padding(.trailing, 26)
                            .frame(width: mainWidth)
                        featureColumn
                            .padding(.horizontal, 24)
                            .frame(width: middleWidth)
                            .overlay(alignment: .leading) { DailyBriefingRule(vertical: true) }
                        agendaColumn(now: context.date)
                            .padding(.leading, 24)
                            .frame(width: asideWidth)
                            .overlay(alignment: .leading) { DailyBriefingRule(vertical: true) }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                    .clipped()
                    footer(now: context.date)
                }
                .padding(.horizontal, 44)
                .padding(.top, 22)
                .padding(.bottom, 18)
            }
        }
        .background(DailyBriefingPalette.paper)
        .foregroundStyle(DailyBriefingPalette.ink)
        .missionEditorSheet($editor, missions: missions)
    }

    // MARK: Masthead

    private func masthead(now: Date) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(DailyBriefingPalette.editionLine(now))
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text("\(readout.accounts.count) ACCOUNTS REPORTING · \(missions.board.projects.count) PROJECTS · \(missions.board.openTaskCount) OPEN TASKS · \(ThemeText.probedLabel(capacity.lastRefresh, now: now))")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                DailyBriefingRefreshButton(capacity: capacity)
                ThemePicker { DailyBriefingPillLabel(text: "EDITION ▾") }
            }
            .font(DailyBriefingPalette.mono(11))
            .kerning(0.6)
            .foregroundStyle(DailyBriefingPalette.grey)
            .padding(.bottom, 6)

            Text("The Mission Control Daily")
                .font(DailyBriefingPalette.serif(62, .semibold))
                .kerning(-1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .overlay(alignment: .top) { DailyBriefingRule() }
                .overlay(alignment: .bottom) { DailyBriefingRule() }
                .accessibilityAddTraits(.isHeader)

            HStack {
                Text(DailyBriefingPalette.longDate(now))
                    .font(DailyBriefingPalette.serif(15).italic())
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("ALL THE CAPACITY THAT'S FIT TO SPEND")
                    .font(DailyBriefingPalette.mono(11))
                    .kerning(1.4)
                    .lineLimit(1)
                    .fixedSize()
                routingLine
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 6)
            DailyBriefingDoubleRule()
        }
    }

    private var routingLine: some View {
        let routing: Text
        if let best = readout.bestClaude {
            routing = Text("\(best.snapshot.account.label.uppercased()) · \(DailyBriefingPalette.percent(best.headroom ?? 0)) ROOM")
                .foregroundColor(DailyBriefingPalette.accent)
                .fontWeight(.semibold)
        } else {
            routing = Text("NO CLAUDE ACCOUNT AVAILABLE").foregroundColor(DailyBriefingPalette.grey)
        }
        return (Text("ROUTING: ").foregroundColor(DailyBriefingPalette.grey) + routing)
            .font(DailyBriefingPalette.mono(11))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    // MARK: Lead column

    private func leadColumn(width: CGFloat, now: Date) -> some View {
        let story = DailyBriefingStory(readout: readout, now: now)
        return VStack(alignment: .leading, spacing: 14) {
            Text(story.kicker)
                .font(DailyBriefingPalette.mono(11, .semibold))
                .kerning(1.6)
                .foregroundStyle(story.isAlert ? DailyBriefingPalette.accent : DailyBriefingPalette.grey)
            Text(story.headline)
                .font(DailyBriefingPalette.serif(41, .medium))
                .kerning(-0.8)
                .lineSpacing(-2)
                .lineLimit(3)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(story.deck)
                .font(DailyBriefingPalette.serif(16))
                .lineSpacing(4)
                .foregroundStyle(DailyBriefingPalette.body)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            DailyBriefingRecommendation(best: readout.bestClaude, now: now)
            markets(width: width, now: now)
        }
    }

    private func markets(width: CGFloat, now: Date) -> some View {
        let columns = DailyBriefingMarketColumns(width: width)
        let bestID = readout.bestClaude?.snapshot.id
        return VStack(alignment: .leading, spacing: 0) {
            DailyBriefingSectionTitle(title: "The Markets", size: 20) {
                Text("USED % · TICK = \(Int(AccountReadout.cautionThreshold))% CAUTION · ROOM = 100 − MAX")
                    .font(DailyBriefingPalette.mono(10))
                    .kerning(0.6)
                    .foregroundStyle(DailyBriefingPalette.grey)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(spacing: 14) {
                Text("ACCOUNT").frame(width: columns.account, alignment: .leading)
                Text("5-HOUR").frame(width: columns.bar, alignment: .leading)
                Text("WEEKLY").frame(width: columns.bar, alignment: .leading)
                Text("ROOM").frame(width: 72, alignment: .leading)
                Text("RESETS").frame(width: 62, alignment: .trailing)
            }
            .font(DailyBriefingPalette.mono(10))
            .kerning(1)
            .foregroundStyle(DailyBriefingPalette.grey)
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) { DailyBriefingRule(color: DailyBriefingPalette.rule) }

            if readout.accounts.isEmpty {
                Text("No accounts have reported yet. Figures will appear after the first probe.")
                    .font(DailyBriefingPalette.serif(14).italic())
                    .foregroundStyle(DailyBriefingPalette.grey)
                    .padding(.vertical, 10)
            }
            DailyBriefingScroll(staticLayout: staticLayout) {
                VStack(spacing: 0) {
                    ForEach(readout.accounts, id: \.snapshot.id) { account in
                        DailyBriefingMarketRow(
                            account: account,
                            isBest: account.snapshot.id == bestID,
                            columns: columns,
                            now: now
                        )
                    }
                }
            }
        }
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Feature column

    private var featureColumn: some View {
        let board = missions.board
        let average = board.projects.isEmpty ? 0 : board.projects.map(\.progress).reduce(0, +) / Double(board.projects.count)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FEATURE · \(board.periodTitle.uppercased()) OBJECTIVES")
                    .font(DailyBriefingPalette.mono(11, .semibold))
                    .kerning(1.6)
                    .foregroundStyle(DailyBriefingPalette.grey)
                    .lineLimit(1)
                Spacer(minLength: 6)
                DailyBriefingAddButton(help: "Add an objective") { editor = .objective(MissionObjective(title: "")) }
            }
            Text(DailyBriefingPalette.objectivesHeadline(count: board.objectives.count, period: board.periodTitle))
                .font(DailyBriefingPalette.serif(26, .medium))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            DailyBriefingScroll(staticLayout: staticLayout) {
                VStack(alignment: .leading, spacing: 10) {
                    if board.objectives.isEmpty {
                        DailyBriefingEmpty(text: "No objectives filed yet. Use + to set one for \(board.periodTitle).")
                    }
                    ForEach(board.objectives) { objective in
                        DailyBriefingObjectiveRow(objective: objective)
                            .objectiveActions(objective, missions: missions, editor: $editor)
                    }
                    DailyBriefingSectionTitle(title: "In Production", size: 20) {
                        Text(board.projects.isEmpty ? "NO PROJECTS" : "AVG \(DailyBriefingPalette.percent(average))")
                            .font(DailyBriefingPalette.mono(10))
                            .kerning(0.6)
                            .foregroundStyle(DailyBriefingPalette.grey)
                        DailyBriefingAddButton(help: "Add a project") { editor = .project(MissionProject(name: "")) }
                    }
                    .padding(.top, 8)
                    if board.projects.isEmpty {
                        DailyBriefingEmpty(text: "Nothing in production. Use + to add a project.")
                    }
                    ForEach(board.projects) { project in
                        DailyBriefingProjectRow(project: project)
                            .projectActions(project, missions: missions, editor: $editor)
                    }
                }
            }
        }
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Agenda column

    private func agendaColumn(now: Date) -> some View {
        let board = missions.board
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AGENDA · \(board.dueTodayCount(now: now)) DUE TODAY")
                    .font(DailyBriefingPalette.mono(11, .semibold))
                    .kerning(1.6)
                    .foregroundStyle(DailyBriefingPalette.grey)
                    .lineLimit(1)
                Spacer(minLength: 6)
                DailyBriefingAddButton(help: "Add a task") { editor = .task(MissionTask(title: "")) }
            }
            Text("Today's Agenda")
                .font(DailyBriefingPalette.serif(26, .medium))
            DailyBriefingScroll(staticLayout: staticLayout) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(TaskBucket.allCases) { bucket in
                        DailyBriefingLane(
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
    }

    // MARK: Footer

    private func footer(now: Date) -> some View {
        HStack {
            Text("HEADROOM = 100 − MAX(5H, WEEKLY) · FIGURES AS OF \(capacity.lastRefresh.map(DailyBriefingPalette.clock) ?? "—")")
            Spacer(minLength: 12)
            Text(nextResetLine(now: now))
            Spacer(minLength: 12)
            Text("PAGE A1")
        }
        .font(DailyBriefingPalette.mono(10))
        .kerning(0.6)
        .foregroundStyle(DailyBriefingPalette.grey)
        .lineLimit(1)
        .padding(.top, 6)
        .overlay(alignment: .top) { DailyBriefingRule() }
    }

    private func nextResetLine(now: Date) -> String {
        let next = readout.accounts
            .filter { $0.bindingWindow?.resetsAt != nil }
            .min { ($0.bindingWindow?.resetsAt ?? .distantFuture) < ($1.bindingWindow?.resetsAt ?? .distantFuture) }
        guard let next else { return "NEXT RESET: —" }
        return "NEXT RESET: \(next.snapshot.account.label.uppercased()) IN \(ThemeText.resetText(next, now: now))"
    }
}

// MARK: - Menu

struct DailyBriefingMenuView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    var staticLayout = false

    @Environment(\.openWindow) private var openWindow
    @State private var editor: MissionEditor?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 10) {
                masthead(now: context.date)
                if staticLayout {
                    content(now: context.date)
                } else {
                    ScrollView { content(now: context.date) }
                        .scrollIndicators(.never)
                }
                footer
            }
            .padding(14)
        }
        .background(DailyBriefingPalette.paper)
        .foregroundStyle(DailyBriefingPalette.ink)
        .missionEditorSheet($editor, missions: missions)
    }

    private func masthead(now: Date) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(DailyBriefingPalette.editionLine(now, short: true))
                Spacer(minLength: 6)
                Text(ThemeText.probedLabel(capacity.lastRefresh, now: now))
            }
            .font(DailyBriefingPalette.mono(9))
            .kerning(0.4)
            .foregroundStyle(DailyBriefingPalette.grey)
            .lineLimit(1)
            .padding(.bottom, 4)
            Text("The Mission Control Daily")
                .font(DailyBriefingPalette.serif(30, .semibold))
                .kerning(-0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .overlay(alignment: .top) { DailyBriefingRule() }
                .overlay(alignment: .bottom) { DailyBriefingRule() }
            HStack {
                Text(DailyBriefingPalette.longDate(now))
                    .font(DailyBriefingPalette.serif(12).italic())
                Spacer(minLength: 6)
                Text("\(missions.board.openTaskCount) OPEN · \(missions.board.dueTodayCount(now: now)) DUE TODAY")
                    .font(DailyBriefingPalette.mono(9))
                    .foregroundStyle(DailyBriefingPalette.grey)
            }
            .lineLimit(1)
            .padding(.vertical, 4)
            DailyBriefingDoubleRule()
        }
    }

    private func content(now: Date) -> some View {
        let story = DailyBriefingStory(readout: readout, now: now)
        let bestID = readout.bestClaude?.snapshot.id
        let tasks = missions.board.tasks(in: .now, now: now)
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(story.kicker)
                    .font(DailyBriefingPalette.mono(10, .semibold))
                    .kerning(1.4)
                    .foregroundStyle(story.isAlert ? DailyBriefingPalette.accent : DailyBriefingPalette.grey)
                Text(story.headline)
                    .font(DailyBriefingPalette.serif(21, .medium))
                    .kerning(-0.3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DailyBriefingRecommendation(best: readout.bestClaude, now: now, compact: true)

            VStack(alignment: .leading, spacing: 0) {
                DailyBriefingSectionTitle(title: "The Markets", size: 17) {
                    Text("USED % · ROOM")
                        .font(DailyBriefingPalette.mono(9))
                        .foregroundStyle(DailyBriefingPalette.grey)
                }
                if readout.accounts.isEmpty {
                    DailyBriefingEmpty(text: "No accounts have reported yet.")
                        .padding(.top, 6)
                }
                ForEach(readout.accounts, id: \.snapshot.id) { account in
                    DailyBriefingCompactMarketRow(account: account, isBest: account.snapshot.id == bestID, now: now)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                DailyBriefingSectionTitle(title: "Today's Agenda", size: 17) {
                    Text("NOW · \(tasks.count) \(tasks.count == 1 ? "ITEM" : "ITEMS")")
                        .font(DailyBriefingPalette.mono(9, .semibold))
                        .kerning(1)
                        .foregroundStyle(DailyBriefingPalette.accent)
                    DailyBriefingAddButton(help: "Add a task") { editor = .task(MissionTask(title: "")) }
                }
                if tasks.isEmpty {
                    DailyBriefingEmpty(text: "Nothing on today's agenda. Open the dashboard to plan.")
                        .padding(.top, 6)
                }
                ForEach(tasks) { task in
                    DailyBriefingTaskRow(task: task, missions: missions, editor: $editor, now: now)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button { OpenDashboardAction(openWindow: openWindow)() } label: {
                DailyBriefingPillLabel(text: "OPEN DASHBOARD", filled: true)
            }
            .buttonStyle(.plain)
            DailyBriefingRefreshButton(capacity: capacity)
            Spacer(minLength: 0)
            ThemePicker { DailyBriefingPillLabel(text: "EDITION ▾") }
            Button { NSApp.terminate(nil) } label: {
                DailyBriefingPillLabel(text: "QUIT")
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { DailyBriefingRule() }
    }
}

// MARK: - Palette & type

private enum DailyBriefingPalette {
    static let paper = Color(hex: 0xF4F4F0)
    static let ink = Color(hex: 0x14171F)
    static let body = Color(hex: 0x2A2E36)
    static let grey = Color(hex: 0x555A63)
    static let rule = Color(hex: 0xC9CBC4)
    static let track = Color(hex: 0xDCDDD7)
    static let accent = Color(hex: 0xB0213B)

    /// Serif standing in for Newsreader.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Sans standing in for Instrument Sans.
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Stand-in for IBM Plex Mono.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func hot(_ percent: Double) -> Color { percent >= AccountReadout.cautionThreshold ? accent : ink }

    static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    static func formatted(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    static func longDate(_ date: Date) -> String { formatted(date, "EEEE d MMMM yyyy") }

    static func clock(_ date: Date) -> String { formatted(date, "HH:mm") }

    static func editionLine(_ date: Date, short: Bool = false) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let edition = hour < 12 ? "MORNING" : (hour < 17 ? "AFTERNOON" : "EVENING")
        let issue = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        let base = "VOL. I · NO. \(issue) · \(edition) EDITION"
        return short ? base : "\(base) · \(clock(date))"
    }

    /// "Claude · work" → "work", for headlines.
    static func shortName(_ account: AccountReadout) -> String {
        let label = account.snapshot.account.label
        return label.components(separatedBy: "·").last?.trimmingCharacters(in: .whitespaces).dailyBriefingNilIfEmpty ?? label
    }

    static func objectivesHeadline(count: Int, period: String) -> String {
        let words = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"]
        let number = count < words.count ? words[count] : "\(count)"
        switch count {
        case 0: return "No promises yet for \(period)"
        case 1: return "One promise for \(period), and how it stands"
        default: return "\(number) promises for \(period), and how they stand"
        }
    }
}

private extension String {
    var dailyBriefingNilIfEmpty: String? { isEmpty ? nil : self }
}

/// The lead story, written from the live readout.
private struct DailyBriefingStory {
    let kicker: String
    let headline: String
    let deck: String
    let isAlert: Bool

    init(readout: CockpitReadout, now: Date) {
        let best = readout.bestClaude
        var lines = ThemeText.briefing(readout)
        if let worst = readout.masterCaution, let peak = worst.peakUsed {
            isAlert = true
            kicker = "LEAD · CAPACITY ALERT"
            let name = DailyBriefingPalette.shortName(worst)
            let hits = "\(name) hits \(DailyBriefingPalette.percent(peak))"
            if let best, best.snapshot.id != worst.snapshot.id {
                headline = "\(hits); route the next Claude session to \(DailyBriefingPalette.shortName(best))"
            } else if best != nil {
                headline = "\(hits), yet it remains the roomiest Claude account"
            } else {
                headline = "\(hits); no Claude account has room to spare"
            }
            let window = worst.bindingWindow?.durationMinutes == 300 ? "five-hour" : "weekly"
            let reset = ThemeText.resetText(worst, now: now).lowercased()
            if reset != "—" {
                lines.insert("Its \(window) window resets in \(reset).", at: min(1, lines.count))
            }
        } else if let best, let headroom = best.headroom {
            isAlert = false
            kicker = "LEAD · CAPACITY REPORT"
            headline = "All clear: route the next Claude session to \(DailyBriefingPalette.shortName(best)), with \(DailyBriefingPalette.percent(headroom)) headroom"
        } else if readout.accounts.isEmpty {
            isAlert = false
            kicker = "LEAD · AWAITING FIGURES"
            headline = "No accounts have reported yet this morning"
        } else if !readout.needsSignIn.isEmpty {
            isAlert = true
            kicker = "LEAD · SIGN-IN NEEDED"
            let count = readout.needsSignIn.count
            headline = "No Claude account is ready; \(count) \(count == 1 ? "awaits" : "await") sign-in"
        } else {
            isAlert = false
            kicker = "LEAD · CAPACITY REPORT"
            headline = "No Claude account is reporting usage this morning"
        }
        deck = lines.joined(separator: " ")
    }
}

// MARK: - Chrome

private struct DailyBriefingRule: View {
    var vertical = false
    var color: Color = DailyBriefingPalette.ink
    var weight: CGFloat = 1

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: vertical ? weight : nil, height: vertical ? nil : weight)
            .accessibilityHidden(true)
    }
}

private struct DailyBriefingDoubleRule: View {
    var body: some View {
        VStack(spacing: 1) {
            DailyBriefingRule()
            DailyBriefingRule()
        }
    }
}

private struct DailyBriefingSectionTitle<Trailing: View>: View {
    let title: String
    var size: CGFloat = 20
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(DailyBriefingPalette.serif(size, .semibold))
                .lineLimit(1)
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 6)
            trailing
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { DailyBriefingRule(weight: 2) }
    }
}

private struct DailyBriefingPillLabel: View {
    let text: String
    var filled = false
    var color: Color = DailyBriefingPalette.ink

    var body: some View {
        Text(text)
            .font(DailyBriefingPalette.mono(10, .semibold))
            .kerning(0.8)
            .foregroundStyle(filled ? DailyBriefingPalette.paper : color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(filled ? DailyBriefingPalette.accent : Color.clear))
            .overlay(Capsule().strokeBorder(filled ? DailyBriefingPalette.accent : color, lineWidth: 1))
            .contentShape(Capsule())
    }
}

private struct DailyBriefingRefreshButton: View {
    @ObservedObject var capacity: CapacityStore

    var body: some View {
        Button {
            Task { await capacity.refresh() }
        } label: {
            DailyBriefingPillLabel(
                text: capacity.isRefreshing ? "PROBING…" : "RE-PROBE",
                color: capacity.isRefreshing ? DailyBriefingPalette.grey : DailyBriefingPalette.ink
            )
        }
        .buttonStyle(.plain)
        .disabled(capacity.isRefreshing)
        .help("Check every account's usage now")
    }
}

private struct DailyBriefingAddButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DailyBriefingPalette.ink)
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(DailyBriefingPalette.ink, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct DailyBriefingScroll<Content: View>: View {
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

private struct DailyBriefingEmpty: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DailyBriefingPalette.serif(14).italic())
            .foregroundStyle(DailyBriefingPalette.grey)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Progress ring; `value` 0…100.
private struct DailyBriefingRing: View {
    let value: Double?
    let size: CGFloat
    let lineWidth: CGFloat
    var color: Color = DailyBriefingPalette.ink
    var label: String? = nil
    var labelSize: CGFloat = 12
    var round = false

    var body: some View {
        ZStack {
            Circle().stroke(DailyBriefingPalette.track, lineWidth: lineWidth)
            if let value, value > 0 {
                Circle()
                    .trim(from: 0, to: min(value, 100) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: round ? .round : .butt))
                    .rotationEffect(.degrees(-90))
            }
            if let label {
                Text(label)
                    .font(DailyBriefingPalette.mono(labelSize, .semibold))
                    .foregroundStyle(DailyBriefingPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
    }
}

// MARK: - Capacity

private struct DailyBriefingRecommendation: View {
    let best: AccountReadout?
    let now: Date
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 12 : 16) {
            DailyBriefingRing(
                value: best?.headroom,
                size: compact ? 44 : 56,
                lineWidth: compact ? 4 : 5,
                color: DailyBriefingPalette.accent,
                label: best?.headroom.map { "\(Int($0.rounded()))" } ?? "—",
                labelSize: compact ? 12 : 14,
                round: true
            )
            .accessibilityElement()
            .accessibilityLabel("Claude headroom")
            .accessibilityValue(best?.headroom.map { DailyBriefingPalette.percent($0) } ?? "No account available")
            VStack(alignment: .leading, spacing: 2) {
                Text("RECOMMENDATION · MOST CLAUDE HEADROOM")
                    .font(DailyBriefingPalette.mono(compact ? 9 : 10))
                    .kerning(1.2)
                    .foregroundStyle(DailyBriefingPalette.grey)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let best {
                    Text("Route next Claude session to \(best.snapshot.account.label)")
                        .font(DailyBriefingPalette.serif(compact ? 15 : 18, .medium))
                        .lineLimit(2)
                    Text(detail(best))
                        .font(DailyBriefingPalette.sans(compact ? 11 : 12))
                        .foregroundStyle(DailyBriefingPalette.grey)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No Claude account is available")
                        .font(DailyBriefingPalette.serif(compact ? 15 : 18, .medium))
                    Text("Sign in a Claude account to get a routing recommendation.")
                        .font(DailyBriefingPalette.sans(compact ? 11 : 12))
                        .foregroundStyle(DailyBriefingPalette.grey)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let best, !compact {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("RESETS IN")
                        .font(DailyBriefingPalette.mono(9))
                        .kerning(1)
                        .foregroundStyle(DailyBriefingPalette.grey)
                    Text(ThemeText.resetText(best, now: now))
                        .font(DailyBriefingPalette.mono(15, .semibold))
                        .foregroundStyle(DailyBriefingPalette.accent)
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 9 : 12)
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 12 : 16)
                .strokeBorder(best == nil ? DailyBriefingPalette.rule : DailyBriefingPalette.ink, lineWidth: 1)
        )
    }

    private func detail(_ best: AccountReadout) -> String {
        let five = best.fiveHour.map { "5h \(DailyBriefingPalette.percent($0.usedPercent))" } ?? "5h n/a"
        let week = best.weekly.map { "weekly \(DailyBriefingPalette.percent($0.usedPercent))" } ?? "weekly n/a"
        var parts = compact ? [five, week] : [ThemeText.identityLine(best), five, week]
        if compact { parts.append("resets \(ThemeText.resetText(best, now: now))") }
        return parts.joined(separator: " · ")
    }
}

private struct DailyBriefingMarketColumns {
    let account: CGFloat
    let bar: CGFloat

    init(width: CGFloat) {
        let flexible = max(width - 72 - 62 - 14 * 4, 200)
        account = flexible * 1.5 / 3.5
        bar = flexible / 3.5
    }
}

/// Used-percent bar with the caution tick.
private struct DailyBriefingUsageBar: View {
    let window: CapacityWindow?
    var valueWidth: CGFloat = 30
    var height: CGFloat = 6

    var body: some View {
        HStack(spacing: 8) {
            Canvas { context, size in
                let y = (size.height - height) / 2
                if window == nil {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: size.height / 2))
                    line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    context.stroke(line, with: .color(DailyBriefingPalette.rule), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                } else {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: height)), with: .color(DailyBriefingPalette.track))
                }
                if let window {
                    let used = CGFloat(window.usedPercent) / 100 * size.width
                    context.fill(Path(CGRect(x: 0, y: y, width: used, height: height)), with: .color(DailyBriefingPalette.hot(window.usedPercent)))
                }
                let tickX = CGFloat(AccountReadout.cautionThreshold) / 100 * size.width
                context.fill(Path(CGRect(x: tickX, y: y - 3, width: 1, height: height + 6)), with: .color(DailyBriefingPalette.ink))
            }
            .frame(height: height + 6)
            Text(window.map { "\(Int($0.usedPercent.rounded()))" } ?? "n/a")
                .font(DailyBriefingPalette.mono(window == nil ? 10 : 12, .semibold))
                .foregroundStyle(window.map { DailyBriefingPalette.hot($0.usedPercent) } ?? DailyBriefingPalette.grey)
                .frame(width: valueWidth, alignment: .trailing)
        }
        .accessibilityElement()
        .accessibilityLabel(window?.label ?? "Window")
        .accessibilityValue(window.map { "\(DailyBriefingPalette.percent($0.usedPercent)) used" } ?? "No data")
    }
}

private struct DailyBriefingRouteTag: View {
    var body: some View {
        Text("ROUTE")
            .font(DailyBriefingPalette.mono(9, .semibold))
            .kerning(1)
            .foregroundStyle(DailyBriefingPalette.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(DailyBriefingPalette.accent, lineWidth: 1))
            .fixedSize()
    }
}

private struct DailyBriefingMarketRow: View {
    let account: AccountReadout
    let isBest: Bool
    let columns: DailyBriefingMarketColumns
    let now: Date

    private var isStale: Bool { account.snapshot.state == .error && account.hasMeasurements }

    var body: some View {
        HStack(alignment: account.hasMeasurements ? .center : .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text(account.snapshot.account.label)
                        .font(DailyBriefingPalette.sans(14, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if isBest { DailyBriefingRouteTag() }
                }
                Text(ThemeText.identityLine(account))
                    .font(DailyBriefingPalette.sans(11))
                    .foregroundStyle(isStale ? DailyBriefingPalette.accent : DailyBriefingPalette.grey)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: columns.account, alignment: .leading)
            .help(ThemeText.guide(account.snapshot.provider))

            if account.hasMeasurements {
                DailyBriefingUsageBar(window: account.fiveHour).frame(width: columns.bar)
                DailyBriefingUsageBar(window: account.weekly).frame(width: columns.bar)
                HStack(spacing: 6) {
                    DailyBriefingRing(
                        value: account.headroom,
                        size: 26,
                        lineWidth: 3,
                        color: account.isNearLimit ? DailyBriefingPalette.accent : DailyBriefingPalette.ink
                    )
                    Text(account.headroom.map(DailyBriefingPalette.percent) ?? "—")
                        .font(DailyBriefingPalette.mono(13, .semibold))
                        .foregroundStyle(account.isNearLimit ? DailyBriefingPalette.accent : DailyBriefingPalette.ink)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(width: 72, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Headroom")
                .accessibilityValue(account.headroom.map(DailyBriefingPalette.percent) ?? "No data")
                Text(ThemeText.resetText(account, now: now))
                    .font(DailyBriefingPalette.mono(12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 62, alignment: .trailing)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.snapshot.state.label.uppercased())
                        .font(DailyBriefingPalette.mono(10, .semibold))
                        .kerning(1)
                        .foregroundStyle(account.snapshot.state == .unauthenticated ? DailyBriefingPalette.accent : DailyBriefingPalette.grey)
                    Text(account.snapshot.message ?? "No usage reported yet.")
                        .font(DailyBriefingPalette.mono(10.5))
                        .foregroundStyle(DailyBriefingPalette.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { DailyBriefingRule(color: DailyBriefingPalette.rule) }
    }
}

private struct DailyBriefingCompactMarketRow: View {
    let account: AccountReadout
    let isBest: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(account.snapshot.account.label)
                    .font(DailyBriefingPalette.sans(13, .semibold))
                    .lineLimit(1)
                if isBest { DailyBriefingRouteTag() }
                Spacer(minLength: 4)
                if account.hasMeasurements {
                    Text("ROOM \(account.headroom.map(DailyBriefingPalette.percent) ?? "—") · \(ThemeText.resetText(account, now: now))")
                        .font(DailyBriefingPalette.mono(10, .semibold))
                        .foregroundStyle(account.isNearLimit ? DailyBriefingPalette.accent : DailyBriefingPalette.ink)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Text(ThemeText.identityLine(account))
                .font(DailyBriefingPalette.sans(10.5))
                .foregroundStyle(DailyBriefingPalette.grey)
                .lineLimit(1)
                .truncationMode(.middle)
            if account.hasMeasurements {
                HStack(spacing: 14) {
                    labeled("5H", account.fiveHour)
                    labeled("WK", account.weekly)
                }
            } else {
                Text(account.snapshot.state.label.uppercased())
                    .font(DailyBriefingPalette.mono(9, .semibold))
                    .kerning(1)
                    .foregroundStyle(account.snapshot.state == .unauthenticated ? DailyBriefingPalette.accent : DailyBriefingPalette.grey)
                Text(account.snapshot.message ?? "No usage reported yet.")
                    .font(DailyBriefingPalette.mono(9.5))
                    .foregroundStyle(DailyBriefingPalette.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { DailyBriefingRule(color: DailyBriefingPalette.rule) }
        .help(ThemeText.guide(account.snapshot.provider))
    }

    private func labeled(_ label: String, _ window: CapacityWindow?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(DailyBriefingPalette.mono(9))
                .foregroundStyle(DailyBriefingPalette.grey)
            DailyBriefingUsageBar(window: window, valueWidth: 26, height: 5)
        }
    }
}

// MARK: - Missions

private struct DailyBriefingObjectiveRow: View {
    let objective: MissionObjective

    var body: some View {
        HStack(spacing: 12) {
            DailyBriefingRing(
                value: objective.progress,
                size: 52,
                lineWidth: 4,
                label: DailyBriefingPalette.percent(objective.progress)
            )
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue(DailyBriefingPalette.percent(objective.progress))
            VStack(alignment: .leading, spacing: 2) {
                Text(objective.title)
                    .font(DailyBriefingPalette.serif(17, .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !objective.summary.isEmpty {
                    Text(objective.summary)
                        .font(DailyBriefingPalette.sans(12))
                        .foregroundStyle(DailyBriefingPalette.grey)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 9)
        .overlay(alignment: .top) { DailyBriefingRule(color: DailyBriefingPalette.rule) }
    }
}

private struct DailyBriefingProjectRow: View {
    let project: MissionProject

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(project.name)
                    .font(DailyBriefingPalette.sans(14, .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(project.phase.uppercased())
                    .font(DailyBriefingPalette.mono(9))
                    .kerning(1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 58)
                    .padding(.vertical, 1)
                    .overlay(Capsule().strokeBorder(DailyBriefingPalette.ink, lineWidth: 1))
                Text(DailyBriefingPalette.percent(project.progress))
                    .font(DailyBriefingPalette.mono(12))
                    .frame(width: 38, alignment: .trailing)
            }
            HStack(spacing: 10) {
                Text("Next: \(project.nextAction.isEmpty ? "—" : project.nextAction)")
                    .font(DailyBriefingPalette.sans(12))
                    .foregroundStyle(DailyBriefingPalette.grey)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: .leading) {
                    Rectangle().fill(DailyBriefingPalette.track)
                    Rectangle()
                        .fill(DailyBriefingPalette.ink)
                        .frame(width: 100 * min(max(project.progress, 0), 100) / 100)
                }
                .frame(width: 100, height: 3)
                .accessibilityElement()
                .accessibilityLabel("Progress")
                .accessibilityValue(DailyBriefingPalette.percent(project.progress))
            }
        }
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) { DailyBriefingRule(color: DailyBriefingPalette.rule) }
    }
}

private struct DailyBriefingLane: View {
    let bucket: TaskBucket
    let tasks: [MissionTask]
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(bucket.title)
                    .foregroundStyle(bucket == .now ? DailyBriefingPalette.accent : DailyBriefingPalette.ink)
                Spacer()
                Text("\(tasks.count) \(tasks.count == 1 ? "ITEM" : "ITEMS")")
                    .foregroundStyle(DailyBriefingPalette.grey)
            }
            .font(DailyBriefingPalette.mono(11, .semibold))
            .kerning(1.4)
            .padding(.bottom, 3)
            .overlay(alignment: .bottom) { DailyBriefingRule(weight: 2) }
            if tasks.isEmpty {
                Text(bucket == .now ? "Nothing scheduled. Use + to add a task." : "Nothing filed.")
                    .font(DailyBriefingPalette.serif(13).italic())
                    .foregroundStyle(DailyBriefingPalette.grey)
                    .padding(.vertical, 7)
            }
            ForEach(tasks) { task in
                DailyBriefingTaskRow(task: task, missions: missions, editor: $editor, now: now)
            }
        }
        .padding(.top, 4)
    }
}

private struct DailyBriefingTaskRow: View {
    let task: MissionTask
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let now: Date

    var body: some View {
        Toggle(isOn: doneBinding(task, missions: missions)) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(DailyBriefingPalette.sans(14, .medium))
                    .strikethrough(task.isDone, color: DailyBriefingPalette.grey)
                    .foregroundStyle(task.isDone ? DailyBriefingPalette.grey : DailyBriefingPalette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack {
                    Text(missions.board.project(for: task)?.name.uppercased() ?? "")
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if let due = ThemeText.dueLabel(task, now: now) {
                        Text(due)
                            .fontWeight(.semibold)
                            .foregroundStyle(task.isDue(on: now) ? DailyBriefingPalette.accent : DailyBriefingPalette.grey)
                    }
                }
                .font(DailyBriefingPalette.mono(10))
                .kerning(0.6)
                .foregroundStyle(DailyBriefingPalette.grey)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(DailyBriefingCheckStyle())
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { DailyBriefingRule(color: DailyBriefingPalette.rule) }
        .contentShape(Rectangle())
        .taskActions(task, missions: missions, editor: $editor)
    }
}

/// Printed tick box.
private struct DailyBriefingCheckStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(configuration.isOn ? DailyBriefingPalette.ink : DailyBriefingPalette.paper)
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(DailyBriefingPalette.ink, lineWidth: 1.2)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(DailyBriefingPalette.paper)
                    }
                }
                .frame(width: 15, height: 15)
                .padding(.top, 2)
                .frame(width: 18)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Done" : "Open")
    }
}
