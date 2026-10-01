import AppKit
import CapacityCore
import SwiftUI

// Flight Manual: a printed operations handbook. Cream paper, black rules,
// numbered sections, tick-strip consumables and a burnt-orange accent.

// MARK: - Dashboard

struct FlightManualDashboardView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    /// Draws without scroll views, for the preview renderer.
    var staticLayout = false

    @State private var editor: MissionEditor?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 22) {
                FlightManualHeader(capacity: capacity, missions: missions, readout: readout, now: context.date)
                GeometryReader { proxy in
                    // Columns share the width 1.45 : 1 with a 40 pt gutter, as on the approved design.
                    let leftWidth = max(0, (proxy.size.width - 40) * 1.45 / 2.45)
                    HStack(alignment: .top, spacing: 40) {
                        FlightManualScroll(staticLayout: staticLayout) {
                            VStack(alignment: .leading, spacing: 22) {
                                FlightManualConsumables(readout: readout, now: context.date)
                                FlightManualManifest(missions: missions, editor: $editor)
                            }
                        }
                        .frame(width: leftWidth)
                        .frame(maxHeight: .infinity, alignment: .top)

                        VStack(alignment: .leading, spacing: 12) {
                            FlightManualScroll(staticLayout: staticLayout) {
                                VStack(alignment: .leading, spacing: 22) {
                                    FlightManualObjectives(missions: missions, editor: $editor)
                                    FlightManualProcedure(missions: missions, editor: $editor, now: context.date)
                                }
                            }
                            FlightManualPageFooter(saveError: missions.saveError)
                        }
                        .padding(.leading, 32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(FlightManualPalette.ink).frame(width: 2)
                        }
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FlightManualPalette.paper)
        .foregroundStyle(FlightManualPalette.ink)
        .missionEditorSheet($editor, missions: missions)
    }
}

// MARK: - Menu

struct FlightManualMenuView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    var staticLayout = false

    @Environment(\.openWindow) private var openWindow
    @State private var editor: MissionEditor?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 12) {
                masthead(now: context.date)
                if staticLayout {
                    content(now: context.date)
                } else {
                    ScrollView { content(now: context.date) }.scrollIndicators(.automatic)
                }
                footer
            }
            .padding(16)
        }
        .background(FlightManualPalette.paper)
        .foregroundStyle(FlightManualPalette.ink)
        .missionEditorSheet($editor, missions: missions)
    }

    private func masthead(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                (Text("MISSION CONTROL ")
                    + Text("/").foregroundColor(FlightManualPalette.accentInk)
                    + Text(" FLIGHT PLAN"))
                    .font(FlightManualType.display(26, .heavy))
                    .kerning(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text(FlightManualStatus.text(readout))
                    .font(FlightManualType.mono(11, .semibold))
                    .foregroundStyle(FlightManualStatus.isAlert(readout) ? FlightManualPalette.accentInk : FlightManualPalette.muted)
            }
            Text("\(ThemeText.plateDate(now)) · \(missions.board.openTaskCount) OPEN · \(missions.board.dueTodayCount(now: now)) DUE TODAY · \(ThemeText.probedLabel(capacity.lastRefresh, now: now))")
                .font(FlightManualType.mono(10))
                .foregroundStyle(FlightManualPalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(FlightManualPalette.ink).frame(height: 5) }
        .overlay(alignment: .bottom) { Rectangle().fill(FlightManualPalette.ink).frame(height: 2) }
        .padding(.top, 0)
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            FlightManualNote(readout: readout, size: 11)
            VStack(alignment: .leading, spacing: 0) {
                FlightManualHeading(title: "§1 CONSUMABLES", size: 17)
                    .padding(.bottom, 4)
                if readout.accounts.isEmpty {
                    FlightManualEmpty(text: "No accounts configured.")
                }
                ForEach(readout.accounts, id: \.snapshot.id) { account in
                    FlightManualCompactAccount(account: account, now: now)
                }
            }
            nowTasks(now: now)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nowTasks(now: Date) -> some View {
        let tasks = missions.board.tasks(in: .now, now: now)
        return VStack(alignment: .leading, spacing: 0) {
            FlightManualHeading(
                title: "§4 PROCEDURE — NOW",
                size: 17,
                addHelp: "Add a task"
            ) {
                editor = .task(MissionTask(title: ""))
            }
            .padding(.bottom, 2)
            if tasks.isEmpty {
                FlightManualEmpty(text: "Nothing in NOW. Open the dashboard to plan the day.")
                    .padding(.top, 6)
            }
            ForEach(tasks) { task in
                FlightManualTaskRow(task: task, missions: missions, editor: $editor, now: now)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Button("OPEN DASHBOARD") { OpenDashboardAction(openWindow: openWindow)() }
            Spacer(minLength: 8)
            Button(capacity.isRefreshing ? "PROBING…" : "RE-PROBE") {
                Task { await capacity.refresh() }
            }
            .disabled(capacity.isRefreshing)
            .help("Check every account's usage now")
            Spacer(minLength: 8)
            ThemePicker {
                Text("EDITION ▾").font(FlightManualType.mono(11, .semibold))
            }
            Spacer(minLength: 8)
            Button("QUIT") { NSApp.terminate(nil) }
        }
        .font(FlightManualType.mono(11, .semibold))
        .buttonStyle(.plain)
        .foregroundStyle(FlightManualPalette.ink)
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(FlightManualPalette.ink).frame(height: 1) }
    }
}

// MARK: - Palette & type

private enum FlightManualPalette {
    static let paper = Color(hex: 0xF2EEE3)
    static let ink = Color(hex: 0x1C1B19)
    static let muted = Color(hex: 0x5C574D)
    /// Fills (ticks, bars). Text uses the darker `accentInk` for contrast.
    static let accent = Color(hex: 0xC2410C)
    static let accentInk = Color(hex: 0xB23A0E)
    static let rule = Color(hex: 0xCFC8B6)
    static let tickOff = Color(hex: 0xD8D1BF)
    static let track = Color(hex: 0xDDD6C4)
    static let dotted = Color(hex: 0xA9A291)
}

private enum FlightManualType {
    /// Stands in for Barlow Condensed.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    /// Stands in for IBM Plex Mono.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

private enum FlightManualStatus {
    static func cautionCount(_ readout: CockpitReadout) -> Int {
        readout.accounts.filter(\.isNearLimit).count
    }

    static func isAlert(_ readout: CockpitReadout) -> Bool {
        cautionCount(readout) > 0 || !readout.needsSignIn.isEmpty
    }

    static func text(_ readout: CockpitReadout) -> String {
        let cautions = cautionCount(readout)
        if cautions > 0 { return "\(cautions) CAUTION\(cautions == 1 ? "" : "S")" }
        let signIn = readout.needsSignIn.count
        if signIn > 0 { return "\(signIn) SIGN-IN" }
        return "NOMINAL"
    }

    static func windowName(_ window: CapacityWindow) -> String {
        switch window.durationMinutes {
        case 300: "5-hour"
        case 10_080: "weekly"
        default: window.label
        }
    }

    /// Project number on the manifest: "M-3".
    static func code(for projectID: UUID?, in board: MissionBoard) -> String? {
        guard let projectID, let index = board.projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        return "M-\(index + 1)"
    }
}

// MARK: - Header

private struct FlightManualHeader: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    let readout: CockpitReadout
    let now: Date

    var body: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                (Text("MISSION CONTROL ")
                    + Text("/").foregroundColor(FlightManualPalette.accentInk)
                    + Text(" FLIGHT PLAN"))
                    .font(FlightManualType.display(46, .heavy))
                    .kerning(1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: 12) {
                    Text("OPERATIONS HANDBOOK · VOLUME IV · CAPACITY, MISSIONS & OBJECTIVES")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(FlightManualPalette.muted)
                    ThemePicker {
                        Text("EDITION ▾")
                            .font(FlightManualType.mono(11, .semibold))
                            .foregroundStyle(FlightManualPalette.ink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .overlay(Rectangle().stroke(FlightManualPalette.ink, lineWidth: 1))
                    }
                }
                .font(FlightManualType.mono(12))
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 28) {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                    GridRow { key("DATE"); Text(ThemeText.plateDate(now)) }
                    GridRow { key("REV"); Text("WK \(Calendar.current.component(.weekOfYear, from: now))") }
                    GridRow {
                        key("TASKS")
                        Text("\(missions.board.openTaskCount) OPEN · \(missions.board.dueTodayCount(now: now)) DUE TODAY")
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                    GridRow {
                        key("STATUS")
                        Text(FlightManualStatus.text(readout))
                            .fontWeight(.semibold)
                            .foregroundStyle(FlightManualStatus.isAlert(readout) ? FlightManualPalette.accentInk : FlightManualPalette.ink)
                    }
                    GridRow {
                        key("PROBE")
                        Text(ThemeText.probedLabel(capacity.lastRefresh, now: now).replacingOccurrences(of: "PROBED ", with: ""))
                    }
                    GridRow {
                        key("ACTION")
                        Button {
                            Task { await capacity.refresh() }
                        } label: {
                            Text(capacity.isRefreshing ? "PROBING…" : "RE-PROBE")
                                .font(FlightManualType.mono(11, .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .foregroundStyle(FlightManualPalette.paper)
                                .background(capacity.isRefreshing ? FlightManualPalette.muted : FlightManualPalette.ink)
                        }
                        .buttonStyle(.plain)
                        .disabled(capacity.isRefreshing)
                        .help("Check every account's usage now")
                    }
                }
            }
            .font(FlightManualType.mono(12))
            .fixedSize()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(FlightManualPalette.ink).frame(height: 6) }
        .overlay(alignment: .bottom) { Rectangle().fill(FlightManualPalette.ink).frame(height: 2) }
        .padding(.top, 6)
    }

    private func key(_ text: String) -> some View {
        Text(text).foregroundStyle(FlightManualPalette.muted)
    }
}

// MARK: - Shared chrome

private struct FlightManualHeading: View {
    let title: String
    var size: CGFloat = 22
    var addHelp: String?
    var add: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(FlightManualType.display(size, .bold))
                .kerning(1)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 0)
            if let add, let addHelp {
                FlightManualAddButton(help: addHelp, action: add)
            }
        }
    }
}

private struct FlightManualAddButton: View {
    let help: String
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(compact ? "+" : "+ ADD")
                .font(FlightManualType.mono(compact ? 11 : 10, .semibold))
                .padding(.horizontal, compact ? 5 : 6)
                .padding(.vertical, 1)
                .overlay(Rectangle().stroke(FlightManualPalette.ink, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct FlightManualEmpty: View {
    let text: String

    var body: some View {
        Text(text)
            .font(FlightManualType.mono(11))
            .foregroundStyle(FlightManualPalette.muted)
            .italic()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

private struct FlightManualRule: View {
    var color = FlightManualPalette.rule
    var dotted = false

    var body: some View {
        if dotted {
            FlightManualLine()
                .stroke(FlightManualPalette.dotted, style: StrokeStyle(lineWidth: 1, dash: [1.5, 2]))
                .frame(height: 1)
        } else {
            Rectangle().fill(color).frame(height: 1)
        }
    }
}

private struct FlightManualLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// Scrolls in the live window; clips instead when drawn by ImageRenderer.
private struct FlightManualScroll<Content: View>: View {
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
            .scrollIndicators(.automatic)
        }
    }
}

private struct FlightManualProgressBar: View {
    let value: Double
    var tint = FlightManualPalette.accent

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(FlightManualPalette.track)
                Rectangle().fill(tint).frame(width: proxy.size.width * min(max(value, 0), 100) / 100)
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(value.rounded())) percent")
    }
}

/// A checkbox printed in the margin of the procedure.
private struct FlightManualCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Rectangle().fill(configuration.isOn ? FlightManualPalette.ink : FlightManualPalette.paper)
                    Rectangle().strokeBorder(FlightManualPalette.ink, lineWidth: 1.5)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(FlightManualPalette.paper)
                    }
                }
                .frame(width: 16, height: 16)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Done" : "Open")
    }
}

// MARK: - §1 Consumables

private struct FlightManualConsumables: View {
    let readout: CockpitReadout
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlightManualHeading(title: "§1 CONSUMABLES — AI CAPACITY BY ACCOUNT")
                .padding(.bottom, 10)
            HStack(spacing: 0) {
                Text("ACCOUNT").frame(width: FlightManualAccountRow.nameWidth, alignment: .leading)
                Text("IDENTITY").frame(width: FlightManualAccountRow.identityWidth, alignment: .leading)
                Text("5-HOUR · WEEKLY (USED)").frame(maxWidth: .infinity, alignment: .leading)
                Text("RESET").frame(width: FlightManualAccountRow.resetWidth, alignment: .trailing)
            }
            .font(FlightManualType.mono(11))
            .foregroundStyle(FlightManualPalette.muted)
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(FlightManualPalette.ink).frame(height: 1) }

            if readout.accounts.isEmpty {
                FlightManualEmpty(text: "No accounts configured. Add one in the app's account settings.")
            }
            ForEach(readout.accounts, id: \.snapshot.id) { account in
                FlightManualAccountRow(account: account, now: now)
            }
            FlightManualNote(readout: readout, size: 12)
                .padding(.top, 10)
        }
    }
}

private struct FlightManualAccountRow: View {
    static let nameWidth: CGFloat = 150
    static let identityWidth: CGFloat = 200
    static let resetWidth: CGFloat = 64

    let account: AccountReadout
    let now: Date

    private var snapshot: ProviderSnapshot { account.snapshot }
    private var isStale: Bool { snapshot.state == .error && account.hasMeasurements }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(snapshot.account.label)
                .font(FlightManualType.display(20, .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Self.nameWidth, alignment: .leading)
                .help(ThemeText.guide(snapshot.provider))
            VStack(alignment: .leading, spacing: 2) {
                Text(ThemeText.identityLine(account))
                    .font(FlightManualType.mono(12, isStale ? .semibold : .regular))
                    .foregroundStyle(isStale ? FlightManualPalette.accentInk : FlightManualPalette.muted)
                    .lineLimit(2)
                    .truncationMode(.middle)
                ForEach(account.otherWindows.prefix(2)) { window in
                    Text("+ \(window.label) \(Int(window.usedPercent.rounded()))%")
                        .font(FlightManualType.mono(10))
                        .foregroundStyle(FlightManualPalette.muted)
                        .lineLimit(1)
                }
            }
            .frame(width: Self.identityWidth - 12, alignment: .leading)
            .padding(.trailing, 12)

            if account.hasMeasurements {
                VStack(alignment: .leading, spacing: 5) {
                    FlightManualTickStrip(name: "5H", spoken: "5-hour window", value: account.fiveHour?.usedPercent, height: 12, emphasized: true)
                    FlightManualTickStrip(name: "WK", spoken: "Weekly window", value: account.weekly?.usedPercent, height: 6, emphasized: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(ThemeText.resetText(account, now: now))
                    .font(FlightManualType.mono(12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: Self.resetWidth, alignment: .trailing)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.state.label.uppercased())
                        .font(FlightManualType.mono(12, .semibold))
                        .foregroundStyle(FlightManualPalette.accentInk)
                    Text(snapshot.message ?? "No usage reported yet.")
                        .font(FlightManualType.mono(11))
                        .foregroundStyle(FlightManualPalette.muted)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { FlightManualRule() }
    }
}

/// 40 printed ticks; each is 2.5 % of the window.
private struct FlightManualTickStrip: View {
    let name: String
    let spoken: String
    let value: Double?
    let height: CGFloat
    let emphasized: Bool
    var labelWidth: CGFloat = 56

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(FlightManualType.mono(9, .semibold))
                .foregroundStyle(FlightManualPalette.muted)
                .frame(width: 16, alignment: .leading)
            Canvas { context, size in
                let count = 40
                let gap: CGFloat = 2
                let width = max(1, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
                let filled = value.map { Int(($0 / 2.5).rounded()) } ?? 0
                let hot = (value ?? 0) >= AccountReadout.cautionThreshold
                for index in 0..<count {
                    let rect = CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: size.height)
                    let color = index < filled
                        ? (hot ? FlightManualPalette.accent : FlightManualPalette.ink)
                        : FlightManualPalette.tickOff
                    context.fill(Path(rect), with: .color(color))
                }
            }
            .frame(maxWidth: 320)
            .frame(height: height)
            Text(value.map { "\(Int($0.rounded()))%" } ?? "NO DATA")
                .font(FlightManualType.mono(value == nil ? 10 : 12, emphasized && value != nil ? .medium : .regular))
                .foregroundStyle(emphasized && value != nil ? FlightManualPalette.ink : FlightManualPalette.muted)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)
        }
        .accessibilityElement()
        .accessibilityLabel("\(spoken) used")
        .accessibilityValue(value.map { "\(Int($0.rounded())) percent" } ?? "No data")
    }
}

/// The "NOTE —" / "CAUTION —" paragraph under the consumables table.
private struct FlightManualNote: View {
    let readout: CockpitReadout
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let caution = readout.masterCaution, let window = caution.bindingWindow {
                (Text("CAUTION — ").bold().foregroundColor(FlightManualPalette.accentInk)
                    + Text("\(caution.snapshot.account.label) is in its final reserve (\(Int(window.usedPercent.rounded()))% of the \(FlightManualStatus.windowName(window)) window used). Hold until reset in \(ThemeText.resetText(caution, now: Date()).lowercased())."))
            }
            routeLine
            ForEach(readout.needsSignIn, id: \.snapshot.id) { account in
                (Text("ACTION — ").bold().foregroundColor(FlightManualPalette.accentInk)
                    + Text("\(account.snapshot.account.label) needs sign-in; see §1 for the command."))
            }
        }
        .font(FlightManualType.mono(size))
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var routeLine: Text {
        let note = Text("NOTE — ").bold().foregroundColor(FlightManualPalette.accentInk)
        guard let best = readout.bestClaude else {
            return note + Text("No Claude account is available for routing. Sign in or re-probe before starting a session.")
        }
        let headroom = Int((best.headroom ?? 0).rounded())
        let tail = readout.masterCaution == nil ? " All accounts are inside normal limits." : ""
        return note + Text("Route the next Claude session to \(best.snapshot.account.label) (\(headroom)% headroom).\(tail)")
    }
}

private struct FlightManualCompactAccount: View {
    let account: AccountReadout
    let now: Date

    private var snapshot: ProviderSnapshot { account.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(snapshot.account.label)
                    .font(FlightManualType.display(17, .bold))
                    .lineLimit(1)
                Text(ThemeText.identityLine(account))
                    .font(FlightManualType.mono(10))
                    .foregroundStyle(snapshot.state == .error && account.hasMeasurements ? FlightManualPalette.accentInk : FlightManualPalette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if account.hasMeasurements {
                    Text("RESET \(ThemeText.resetText(account, now: now))")
                        .font(FlightManualType.mono(10))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            if account.hasMeasurements {
                FlightManualTickStrip(name: "5H", spoken: "5-hour window", value: account.fiveHour?.usedPercent, height: 10, emphasized: true, labelWidth: 52)
                FlightManualTickStrip(name: "WK", spoken: "Weekly window", value: account.weekly?.usedPercent, height: 5, emphasized: false, labelWidth: 52)
            } else {
                Text(snapshot.state.label.uppercased())
                    .font(FlightManualType.mono(11, .semibold))
                    .foregroundStyle(FlightManualPalette.accentInk)
                Text(snapshot.message ?? "No usage reported yet.")
                    .font(FlightManualType.mono(10))
                    .foregroundStyle(FlightManualPalette.muted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { FlightManualRule() }
    }
}

// MARK: - §2 Manifest

private struct FlightManualManifest: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlightManualHeading(title: "§2 MISSION MANIFEST", addHelp: "Add a project") {
                editor = .project(MissionProject(name: ""))
            }
            .padding(.bottom, 4)
            if missions.board.projects.isEmpty {
                FlightManualEmpty(text: "No missions on the manifest. Use + ADD to log the first project.")
                    .overlay(alignment: .bottom) { FlightManualRule() }
            }
            ForEach(Array(missions.board.projects.enumerated()), id: \.element.id) { index, project in
                HStack(spacing: 12) {
                    Text("M-\(index + 1)")
                        .foregroundStyle(FlightManualPalette.muted)
                        .frame(width: 40, alignment: .leading)
                    Text(project.name)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .frame(width: 180, alignment: .leading)
                    Text(project.phase.uppercased())
                        .font(FlightManualType.mono(10))
                        .kerning(1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 4)
                        .frame(width: 90)
                        .overlay(Rectangle().stroke(FlightManualPalette.ink, lineWidth: 1))
                    Text("→ \(project.nextAction.isEmpty ? "—" : project.nextAction)")
                        .foregroundStyle(FlightManualPalette.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(Int(project.progress.rounded()))%")
                        .fontWeight(.semibold)
                        .frame(width: 46, alignment: .trailing)
                }
                .font(FlightManualType.mono(12))
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { FlightManualRule() }
                .help(project.nextAction)
                .projectActions(project, missions: missions, editor: $editor)
            }
        }
    }
}

// MARK: - §3 Objectives

private struct FlightManualObjectives: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlightManualHeading(
                title: "§3 PRIMARY OBJECTIVES · \(missions.board.periodTitle.uppercased())",
                addHelp: "Add an objective"
            ) {
                editor = .objective(MissionObjective(title: ""))
            }
            .padding(.bottom, 12)
            if missions.board.objectives.isEmpty {
                FlightManualEmpty(text: "No objectives set for \(missions.board.periodTitle). Use + ADD to set one.")
            }
            ForEach(Array(missions.board.objectives.enumerated()), id: \.element.id) { index, objective in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1). \(objective.title)")
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        Text("\(Int(objective.progress.rounded()))%")
                    }
                    .font(FlightManualType.mono(13, .semibold))
                    FlightManualProgressBar(value: objective.progress)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                    if !objective.summary.isEmpty {
                        Text(objective.summary)
                            .font(FlightManualType.mono(11))
                            .foregroundStyle(FlightManualPalette.muted)
                            .lineLimit(2)
                    }
                }
                .padding(.bottom, 14)
                .objectiveActions(objective, missions: missions, editor: $editor)
            }
        }
    }
}

// MARK: - §4 Procedure

private struct FlightManualProcedure: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlightManualHeading(title: "§4 PROCEDURE — NOW · NEXT · LATER", addHelp: "Add a task") {
                editor = .task(MissionTask(title: ""))
            }
            .padding(.bottom, 8)
            if missions.board.tasks.isEmpty {
                FlightManualEmpty(text: "No procedure written yet. Use + ADD to log the first step.")
            }
            ForEach(Array(TaskBucket.allCases.enumerated()), id: \.element) { index, bucket in
                let tasks = missions.board.tasks(in: bucket, now: now)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("4.\(index + 1) \(bucket.title)")
                            .font(FlightManualType.display(16, .bold))
                            .kerning(1)
                            .foregroundStyle(bucket == .now ? FlightManualPalette.accentInk : FlightManualPalette.ink)
                        Text("\(tasks.count) STEP\(tasks.count == 1 ? "" : "S")")
                            .font(FlightManualType.mono(10))
                            .foregroundStyle(FlightManualPalette.muted)
                        Spacer(minLength: 0)
                        FlightManualAddButton(help: "Add a task to \(bucket.title)", compact: true) {
                            editor = .task(MissionTask(title: "", bucket: bucket))
                        }
                    }
                    .padding(.bottom, 2)
                    if tasks.isEmpty, !missions.board.tasks.isEmpty {
                        Text("— no steps —")
                            .font(FlightManualType.mono(11))
                            .foregroundStyle(FlightManualPalette.muted)
                            .padding(.vertical, 5)
                    }
                    ForEach(tasks) { task in
                        FlightManualTaskRow(task: task, missions: missions, editor: $editor, now: now)
                    }
                }
                .padding(.bottom, 10)
            }
        }
    }
}

private struct FlightManualTaskRow: View {
    let task: MissionTask
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let now: Date

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle(isOn: doneBinding(task, missions: missions)) {
                Text(task.title)
                    .font(FlightManualType.mono(12))
                    .strikethrough(task.isDone, color: FlightManualPalette.muted)
                    .foregroundStyle(task.isDone ? FlightManualPalette.muted : FlightManualPalette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(FlightManualCheckboxStyle())
            if !tag.isEmpty {
                Text(tag)
                    .font(FlightManualType.mono(10, isDue ? .semibold : .regular))
                    .foregroundStyle(isDue ? FlightManualPalette.accentInk : FlightManualPalette.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { FlightManualRule(dotted: true) }
        .taskActions(task, missions: missions, editor: $editor)
    }

    private var isDue: Bool { task.isDue(on: now) }

    private var tag: String {
        [FlightManualStatus.code(for: task.projectID, in: missions.board), ThemeText.dueLabel(task, now: now)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private struct FlightManualPageFooter: View {
    let saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let saveError {
                Text(saveError)
                    .font(FlightManualType.mono(10, .semibold))
                    .foregroundStyle(FlightManualPalette.accentInk)
            }
            Text("PAGE 1 OF 1 · AUTO-POLLED · LOCAL ONLY · RIGHT-CLICK AN ENTRY TO AMEND")
                .font(FlightManualType.mono(10))
                .foregroundStyle(FlightManualPalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(FlightManualPalette.ink).frame(height: 1) }
    }
}
