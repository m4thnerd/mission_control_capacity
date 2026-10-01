import AppKit
import CapacityCore
import SwiftUI

// Instrument Panel: the manual's paper and rules with rounded instrument cards.
// Each account gets a dark dual-ring headroom gauge; tasks sit in NOW/NEXT/LATER
// columns beside objectives and the mission manifest.

// MARK: - Dashboard

struct InstrumentPanelDashboardView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    /// Draws without scroll views, for the preview renderer.
    var staticLayout = false

    @State private var editor: MissionEditor?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 20) {
                InstrumentPanelHeader(capacity: capacity, missions: missions, readout: readout, now: context.date)
                InstrumentPanelCapacity(readout: readout, now: context.date)
                GeometryReader { proxy in
                    // Three task columns and a 1.25× objectives column, 18 pt gutters.
                    let unit = max(0, (proxy.size.width - 54) / 4.25)
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(TaskBucket.allCases) { bucket in
                            InstrumentPanelTaskColumn(
                                bucket: bucket,
                                missions: missions,
                                editor: $editor,
                                now: context.date,
                                staticLayout: staticLayout
                            )
                            .frame(width: unit)
                        }
                        InstrumentPanelSideColumn(missions: missions, editor: $editor, staticLayout: staticLayout)
                            .frame(width: unit * 1.25)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(InstrumentPanelPalette.paper)
        .foregroundStyle(InstrumentPanelPalette.ink)
        .missionEditorSheet($editor, missions: missions)
    }
}

// MARK: - Menu

struct InstrumentPanelMenuView: View {
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
        .background(InstrumentPanelPalette.paper)
        .foregroundStyle(InstrumentPanelPalette.ink)
        .missionEditorSheet($editor, missions: missions)
    }

    private func masthead(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline) {
                (Text("Mission Control") + Text(".").foregroundColor(InstrumentPanelPalette.accentInk))
                    .font(.system(size: 30, weight: .black))
                    .kerning(-0.8)
                    .lineLimit(1)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(ThemeText.plateDate(now))
                        .fontWeight(.semibold)
                    Text("\(missions.board.openTaskCount) OPEN · \(missions.board.dueTodayCount(now: now)) DUE")
                        .foregroundStyle(InstrumentPanelPalette.muted)
                }
                .font(InstrumentPanelType.mono(10))
                .fixedSize()
            }
            HStack(spacing: 8) {
                InstrumentPanelRoutePill(best: readout.bestClaude, compact: true)
                Spacer(minLength: 0)
                InstrumentPanelCautionPill(readout: readout, compact: true)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(InstrumentPanelPalette.ink).frame(height: 5) }
        .overlay(alignment: .bottom) { Rectangle().fill(InstrumentPanelPalette.ink).frame(height: 2) }
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            InstrumentPanelHeading(title: "§1 CAPACITY")
            if readout.accounts.isEmpty {
                InstrumentPanelEmpty(text: "No accounts configured.")
            }
            ForEach(readout.accounts, id: \.snapshot.id) { account in
                InstrumentPanelAccountCard(account: account, now: now, scale: 0.66, compact: true)
            }
            let tasks = missions.board.tasks(in: .now, now: now)
            InstrumentPanelColumnHeader(title: "§2 NOW", count: tasks.count, addHelp: "Add a task") {
                editor = .task(MissionTask(title: ""))
            }
            .padding(.top, 4)
            if tasks.isEmpty {
                InstrumentPanelEmpty(text: "Nothing in NOW. Open the dashboard to plan the day.")
            }
            ForEach(tasks) { task in
                InstrumentPanelTaskCard(task: task, missions: missions, editor: $editor, now: now)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Text("THEME ▾").font(InstrumentPanelType.mono(11, .semibold))
            }
            Spacer(minLength: 8)
            Button("QUIT") { NSApp.terminate(nil) }
        }
        .font(InstrumentPanelType.mono(11, .semibold))
        .buttonStyle(.plain)
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(InstrumentPanelPalette.ink).frame(height: 1) }
    }
}

// MARK: - Palette & type

private enum InstrumentPanelPalette {
    static let paper = Color(hex: 0xF2EEE3)
    static let card = Color(hex: 0xFBF9F3)
    static let ink = Color(hex: 0x1C1B19)
    static let muted = Color(hex: 0x5C574D)
    /// Borders and fills; text uses the darker `accentInk` for contrast.
    static let accent = Color(hex: 0xC2410C)
    static let accentInk = Color(hex: 0xB23A0E)
    static let rule = Color(hex: 0xCFC8B6)
    static let track = Color(hex: 0xDDD6C4)
    // Gauge face.
    static let dialTrack = Color(hex: 0x3A3833)
    static let dialLabel = Color(hex: 0xB8B2A3)
    static let hot = Color(hex: 0xF26B3A)
    static let warm = Color(hex: 0xF2C14E)
    static let cool = Color(hex: 0x8ED1A5)

    static func tone(_ percent: Double) -> Color {
        percent >= 85 ? hot : percent >= 65 ? warm : cool
    }
}

private enum InstrumentPanelType {
    /// Stands in for Barlow Condensed section labels.
    static func label(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    /// Stands in for JetBrains Mono.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Header

private struct InstrumentPanelHeader: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    let readout: CockpitReadout
    let now: Date

    var body: some View {
        HStack(alignment: .bottom, spacing: 24) {
            (Text("Mission Control") + Text(".").foregroundColor(InstrumentPanelPalette.accentInk))
                .font(.system(size: 54, weight: .black))
                .kerning(-1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 30) {
                reading("DATE", ThemeText.plateDate(now))
                reading("OPEN TASKS", "\(missions.board.openTaskCount) · \(missions.board.dueTodayCount(now: now)) DUE TODAY")
                VStack(alignment: .leading, spacing: 1) {
                    Text("ROUTE CLAUDE TO").foregroundStyle(InstrumentPanelPalette.muted)
                    if let best = readout.bestClaude {
                        Text("\(best.snapshot.account.label.uppercased()) · \(Int((best.headroom ?? 0).rounded()))%")
                            .fontWeight(.semibold)
                            .foregroundStyle(InstrumentPanelPalette.accentInk)
                    } else {
                        Text("NO ACCOUNT AVAILABLE")
                            .fontWeight(.semibold)
                            .foregroundStyle(InstrumentPanelPalette.muted)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(ThemeText.probedLabel(capacity.lastRefresh, now: now))
                        .foregroundStyle(InstrumentPanelPalette.muted)
                    HStack(spacing: 6) {
                        Button {
                            Task { await capacity.refresh() }
                        } label: {
                            Text(capacity.isRefreshing ? "PROBING…" : "RE-PROBE")
                                .font(InstrumentPanelType.mono(11, .semibold))
                                .foregroundStyle(InstrumentPanelPalette.paper)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 2)
                                .background(
                                    capacity.isRefreshing ? InstrumentPanelPalette.muted : InstrumentPanelPalette.ink,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(capacity.isRefreshing)
                        .help("Check every account's usage now")
                        ThemePicker {
                            Text("THEME ▾")
                                .font(InstrumentPanelType.mono(11, .semibold))
                                .foregroundStyle(InstrumentPanelPalette.ink)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 1)
                                .overlay(Capsule().stroke(InstrumentPanelPalette.ink, lineWidth: 1))
                        }
                    }
                }
            }
            .font(InstrumentPanelType.mono(12))
            .fixedSize()
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(InstrumentPanelPalette.ink).frame(height: 6) }
        .overlay(alignment: .bottom) { Rectangle().fill(InstrumentPanelPalette.ink).frame(height: 2) }
        .padding(.top, 6)
    }

    private func reading(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).foregroundStyle(InstrumentPanelPalette.muted)
            Text(value).fontWeight(.semibold)
        }
    }
}

private struct InstrumentPanelRoutePill: View {
    let best: AccountReadout?
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            Text("ROUTE CLAUDE →").foregroundStyle(InstrumentPanelPalette.muted)
            if let best {
                Text("\(best.snapshot.account.label.uppercased()) · \(Int((best.headroom ?? 0).rounded()))%")
                    .fontWeight(.semibold)
                    .foregroundStyle(InstrumentPanelPalette.accentInk)
            } else {
                Text("NO ACCOUNT AVAILABLE").fontWeight(.semibold).foregroundStyle(InstrumentPanelPalette.muted)
            }
        }
        .font(InstrumentPanelType.mono(compact ? 10 : 11))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }
}

/// Master caution: a filled accent capsule when an account is near its limit.
private struct InstrumentPanelCautionPill: View {
    let readout: CockpitReadout
    var compact = false

    var body: some View {
        Group {
            if let caution = readout.masterCaution, let window = caution.bindingWindow {
                Text("MASTER CAUTION · \(caution.snapshot.account.label.uppercased()) \(Int(window.usedPercent.rounded()))% \(window.durationMinutes == 300 ? "5H" : "WK")\(compact ? "" : " · HOLD UNTIL RESET \(ThemeText.resetText(caution, now: Date()))")")
                    .fontWeight(.bold)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(InstrumentPanelPalette.accentInk, in: Capsule())
            } else {
                HStack(spacing: 6) {
                    Circle().stroke(InstrumentPanelPalette.ink, lineWidth: 1.2).frame(width: 7, height: 7)
                    Text(statusText)
                }
                .foregroundStyle(InstrumentPanelPalette.muted)
            }
        }
        .font(InstrumentPanelType.mono(compact ? 10 : 11))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        let signIn = readout.needsSignIn.count
        let normal = "ALL ACCOUNTS BELOW \(Int(AccountReadout.cautionThreshold))%"
        return signIn > 0 ? "\(normal) · \(signIn) NEED\(signIn == 1 ? "S" : "") SIGN-IN" : normal
    }
}

// MARK: - Shared chrome

private struct InstrumentPanelHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(InstrumentPanelType.label(18))
            .kerning(1.5)
            .lineLimit(1)
    }
}

private struct InstrumentPanelAddButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(InstrumentPanelPalette.ink, lineWidth: 1.2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct InstrumentPanelEmpty: View {
    let text: String

    var body: some View {
        Text(text)
            .font(InstrumentPanelType.mono(11))
            .foregroundStyle(InstrumentPanelPalette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(InstrumentPanelPalette.rule, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
    }
}

/// Scrolls in the live window; clips instead when drawn by ImageRenderer.
private struct InstrumentPanelScroll<Content: View>: View {
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

private struct InstrumentPanelCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(configuration.isOn ? InstrumentPanelPalette.ink : InstrumentPanelPalette.card)
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(InstrumentPanelPalette.ink, lineWidth: 1.5)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(InstrumentPanelPalette.paper)
                    }
                }
                .frame(width: 16, height: 16)
                .padding(.top, 2)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Done" : "Open")
    }
}

// MARK: - §1 Capacity

private struct InstrumentPanelCapacity: View {
    let readout: CockpitReadout
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                InstrumentPanelHeading(title: "§1 CAPACITY — BY ACCOUNT")
                Spacer(minLength: 0)
                InstrumentPanelCautionPill(readout: readout)
            }
            if readout.accounts.isEmpty {
                InstrumentPanelEmpty(text: "No accounts configured. Add one in the app's account settings.")
            } else {
                let columns = max(1, min(readout.accounts.count, 4))
                let rows = stride(from: 0, to: readout.accounts.count, by: columns).map {
                    Array(readout.accounts[$0..<min($0 + columns, readout.accounts.count)])
                }
                Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                    ForEach(rows.indices, id: \.self) { index in
                        GridRow {
                            ForEach(rows[index], id: \.snapshot.id) { account in
                                InstrumentPanelAccountCard(account: account, now: now)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            ForEach(0..<(columns - rows[index].count), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                            }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct InstrumentPanelAccountCard: View {
    let account: AccountReadout
    let now: Date
    var scale: CGFloat = 1
    var compact = false

    private var snapshot: ProviderSnapshot { account.snapshot }
    private var isStale: Bool { snapshot.state == .error && account.hasMeasurements }

    var body: some View {
        HStack(alignment: .center, spacing: 14 * scale) {
            InstrumentPanelGauge(account: account, scale: scale)
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.account.label)
                    .font(.system(size: 18 * max(scale, 0.85), weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .help(ThemeText.guide(snapshot.provider))
                Text(ThemeText.identityLine(account))
                    .font(.system(size: 11, weight: isStale ? .semibold : .regular))
                    .foregroundStyle(isStale ? InstrumentPanelPalette.accentInk : InstrumentPanelPalette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if account.hasMeasurements {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
                        row("5H", account.fiveHour.map { "\(Int($0.usedPercent.rounded()))% used" })
                        row("WK", account.weekly.map { "\(Int($0.usedPercent.rounded()))% used" })
                        row("RESET", ThemeText.resetText(account, now: now).lowercased())
                    }
                    .font(InstrumentPanelType.mono(11))
                    .padding(.top, compact ? 4 : 8)
                    ForEach(account.otherWindows.prefix(compact ? 1 : 2)) { window in
                        Text("+ \(window.label) \(Int(window.usedPercent.rounded()))%")
                            .font(InstrumentPanelType.mono(10))
                            .foregroundStyle(InstrumentPanelPalette.muted)
                            .lineLimit(1)
                    }
                } else {
                    Text(snapshot.state.label.uppercased())
                        .font(InstrumentPanelType.mono(11, .semibold))
                        .foregroundStyle(InstrumentPanelPalette.accentInk)
                        .padding(.top, 6)
                    Text(snapshot.message ?? "No usage reported yet.")
                        .font(InstrumentPanelType.mono(10))
                        .foregroundStyle(InstrumentPanelPalette.muted)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18 * scale)
        .padding(.vertical, 14 * scale)
        .frame(maxHeight: compact ? nil : .infinity)
        .background(InstrumentPanelPalette.card, in: RoundedRectangle(cornerRadius: 22 * scale))
        .overlay(
            RoundedRectangle(cornerRadius: 22 * scale)
                .strokeBorder(account.isNearLimit ? InstrumentPanelPalette.accent : InstrumentPanelPalette.rule, lineWidth: account.isNearLimit ? 2 : 1.5)
        )
    }

    @ViewBuilder
    private func row(_ key: String, _ value: String?) -> some View {
        GridRow {
            Text(key).foregroundStyle(InstrumentPanelPalette.muted)
            Text(value ?? "no data")
                .foregroundStyle(value == nil ? InstrumentPanelPalette.muted : InstrumentPanelPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// Dark dial: outer ring is the 5-hour window, inner ring the weekly one;
/// the centre reads headroom on the tighter of the two.
private struct InstrumentPanelGauge: View {
    let account: AccountReadout
    var scale: CGFloat = 1

    private static func degrees(_ percent: Double) -> Double { -135 + percent * 2.7 }

    var body: some View {
        let s = scale
        Canvas { context, _ in
            let c = CGPoint(x: 64 * s, y: 62 * s)
            context.fill(
                Path(ellipseIn: CGRect(x: c.x - 56 * s, y: c.y - 56 * s, width: 112 * s, height: 112 * s)),
                with: .color(InstrumentPanelPalette.ink)
            )
            for index in 0...10 {
                let major = index % 5 == 0
                context.stroke(
                    DialGeometry.tick(c, 52 * s, (major ? 45 : 48) * s, -135 + Double(index) * 27),
                    with: .color(InstrumentPanelPalette.paper),
                    lineWidth: (major ? 2 : 1) * s
                )
            }
            ring(&context, c, radius: 40 * s, width: 7 * s, value: account.fiveHour?.usedPercent)
            ring(&context, c, radius: 29 * s, width: 4 * s, value: account.weekly?.usedPercent)
            let centre = account.headroom.map { "\(Int($0.rounded()))" } ?? "—"
            context.draw(
                Text(centre).font(.system(size: 20 * s, weight: .black)).foregroundColor(InstrumentPanelPalette.paper),
                at: CGPoint(x: c.x, y: c.y)
            )
            context.draw(
                Text(account.hasMeasurements ? "HEADROOM %" : "NO DATA")
                    .font(InstrumentPanelType.mono(8 * s))
                    .foregroundColor(InstrumentPanelPalette.dialLabel),
                at: CGPoint(x: c.x, y: c.y + 38 * s)
            )
        }
        .frame(width: 128 * s, height: 120 * s)
        .accessibilityElement()
        .accessibilityLabel("\(account.snapshot.account.label) headroom")
        .accessibilityValue(accessibilityValue)
    }

    private func ring(_ context: inout GraphicsContext, _ c: CGPoint, radius: CGFloat, width: CGFloat, value: Double?) {
        context.stroke(
            DialGeometry.arc(c, radius, from: -135, to: 135),
            with: .color(InstrumentPanelPalette.dialTrack),
            lineWidth: width
        )
        if let value, value > 0 {
            context.stroke(
                DialGeometry.arc(c, radius, from: -135, to: Self.degrees(value)),
                with: .color(InstrumentPanelPalette.tone(value)),
                lineWidth: width
            )
        }
    }

    private var accessibilityValue: String {
        guard let headroom = account.headroom else { return account.snapshot.state.label }
        let five = account.fiveHour.map { "5-hour \(Int($0.usedPercent.rounded())) percent used" } ?? "5-hour no data"
        let week = account.weekly.map { "weekly \(Int($0.usedPercent.rounded())) percent used" } ?? "weekly no data"
        return "\(Int(headroom.rounded())) percent headroom; \(five); \(week)"
    }
}

// MARK: - §2 Tasks

private struct InstrumentPanelColumnHeader: View {
    let title: String
    let count: Int
    let addHelp: String
    let add: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            InstrumentPanelHeading(title: title)
            Spacer(minLength: 0)
            Text("\(count)")
                .font(InstrumentPanelType.mono(12))
                .foregroundStyle(InstrumentPanelPalette.muted)
            InstrumentPanelAddButton(help: addHelp, action: add)
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(InstrumentPanelPalette.ink).frame(height: 2) }
    }
}

private struct InstrumentPanelTaskColumn: View {
    let bucket: TaskBucket
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let now: Date
    let staticLayout: Bool

    var body: some View {
        let tasks = missions.board.tasks(in: bucket, now: now)
        VStack(alignment: .leading, spacing: 10) {
            InstrumentPanelColumnHeader(
                title: bucket == .now ? "§2 NOW" : bucket.title,
                count: tasks.count,
                addHelp: "Add a task to \(bucket.title)"
            ) {
                editor = .task(MissionTask(title: "", bucket: bucket))
            }
            InstrumentPanelScroll(staticLayout: staticLayout) {
                VStack(alignment: .leading, spacing: 10) {
                    if tasks.isEmpty {
                        InstrumentPanelEmpty(text: emptyText)
                    }
                    ForEach(tasks) { task in
                        InstrumentPanelTaskCard(task: task, missions: missions, editor: $editor, now: now)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var emptyText: String {
        switch bucket {
        case .now: "Nothing in NOW. Use + to add a task."
        case .next: "Nothing queued next."
        case .later: "Nothing parked for later."
        }
    }
}

private struct InstrumentPanelTaskCard: View {
    let task: MissionTask
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let now: Date

    var body: some View {
        Toggle(isOn: doneBinding(task, missions: missions)) {
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineSpacing(2)
                    .strikethrough(task.isDone, color: InstrumentPanelPalette.muted)
                    .foregroundStyle(task.isDone ? InstrumentPanelPalette.muted : InstrumentPanelPalette.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(missions.board.project(for: task)?.name ?? "No project")
                        .foregroundStyle(InstrumentPanelPalette.muted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let when = ThemeText.dueLabel(task, now: now) {
                        Text(when)
                            .fontWeight(isDue ? .semibold : .regular)
                            .foregroundStyle(isDue ? InstrumentPanelPalette.accentInk : InstrumentPanelPalette.muted)
                            .fixedSize()
                    }
                }
                .font(InstrumentPanelType.mono(10))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(InstrumentPanelCheckboxStyle())
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(InstrumentPanelPalette.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(InstrumentPanelPalette.rule, lineWidth: 1))
        .taskActions(task, missions: missions, editor: $editor)
    }

    private var isDue: Bool { task.isDue(on: now) }
}

// MARK: - §3 Objectives and §4 Manifest

private struct InstrumentPanelSideColumn: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let staticLayout: Bool

    var body: some View {
        InstrumentPanelScroll(staticLayout: staticLayout) {
            VStack(alignment: .leading, spacing: 12) {
                header("§3 OBJECTIVES · \(missions.board.periodTitle.uppercased())", help: "Add an objective") {
                    editor = .objective(MissionObjective(title: ""))
                }
                if missions.board.objectives.isEmpty {
                    InstrumentPanelEmpty(text: "No objectives for \(missions.board.periodTitle) yet. Use + to set one.")
                }
                ForEach(Array(missions.board.objectives.enumerated()), id: \.element.id) { index, objective in
                    objectiveRow(index + 1, objective)
                        .objectiveActions(objective, missions: missions, editor: $editor)
                }
                header("§4 MISSION MANIFEST", help: "Add a project") {
                    editor = .project(MissionProject(name: ""))
                }
                .padding(.top, 6)
                if missions.board.projects.isEmpty {
                    InstrumentPanelEmpty(text: "No missions yet. Use + to add a project.")
                }
                ForEach(missions.board.projects) { project in
                    projectRow(project)
                        .projectActions(project, missions: missions, editor: $editor)
                }
            }
        }
        .padding(.leading, 22)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .leading) { Rectangle().fill(InstrumentPanelPalette.ink).frame(width: 2) }
    }

    private func header(_ title: String, help: String, add: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            InstrumentPanelHeading(title: title)
            Spacer(minLength: 0)
            InstrumentPanelAddButton(help: help, action: add)
        }
    }

    private func objectiveRow(_ number: Int, _ objective: MissionObjective) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(InstrumentPanelPalette.accentInk)
                .frame(width: 30, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(objective.title).lineLimit(2)
                    Spacer(minLength: 0)
                    Text("\(Int(objective.progress.rounded()))%")
                }
                .font(.system(size: 13, weight: .bold))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(InstrumentPanelPalette.track)
                        Rectangle()
                            .fill(InstrumentPanelPalette.ink)
                            .frame(width: proxy.size.width * min(max(objective.progress, 0), 100) / 100)
                    }
                }
                .frame(height: 4)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .accessibilityElement()
                .accessibilityLabel("Progress")
                .accessibilityValue("\(Int(objective.progress.rounded())) percent")
                if !objective.summary.isEmpty {
                    Text(objective.summary)
                        .font(InstrumentPanelType.mono(10))
                        .foregroundStyle(InstrumentPanelPalette.muted)
                        .lineLimit(2)
                }
            }
        }
    }

    private func projectRow(_ project: MissionProject) -> some View {
        HStack(spacing: 8) {
            Text(project.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(project.phase.uppercased())
                .font(InstrumentPanelType.mono(9))
                .kerning(1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .frame(width: 64)
                .overlay(Capsule().stroke(InstrumentPanelPalette.ink, lineWidth: 1))
            Text("\(Int(project.progress.rounded()))%")
                .font(InstrumentPanelType.mono(11))
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(InstrumentPanelPalette.rule).frame(height: 1) }
        .help(project.nextAction.isEmpty ? project.name : "Next: \(project.nextAction)")
    }
}
