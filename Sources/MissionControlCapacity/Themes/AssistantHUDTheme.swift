import AppKit
import CapacityCore
import SwiftUI

// Assistant HUD: a holographic operations console run by "MC". Cyan line work
// on near-black, a central ring that splits its outer band into one arc per
// account, objective rings inside it, and an amber accent for critical items.

// MARK: - Palette and type

private enum AssistantHUDPalette {
    static let void = Color(hex: 0x04080C)
    static let cyan = Color(hex: 0x5CE1FF)
    static let text = Color(hex: 0xD8F3FF)
    static let bright = Color(hex: 0xE9F9FF)
    static let secondary = Color(hex: 0x8FB3C2)
    static let amber = Color(hex: 0xFFA53D)
    static let panel = Color(red: 8 / 255, green: 22 / 255, blue: 30 / 255).opacity(0.78)
    static let track = Color(hex: 0x163340)
    static let deepTrack = Color(hex: 0x12303C)
    static let core = Color(hex: 0x061219)
    static let midTick = Color(hex: 0x3E7F95)
    static let minorTick = Color(hex: 0x24505F)
    static let objectiveColors: [Color] = [cyan, Color(hex: 0x9CC9FF), Color(hex: 0x58F0C8)]

    /// Rajdhani stand-in: condensed system sans.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    /// Share Tech Mono stand-in.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func tone(_ used: Double) -> Color { used >= 85 ? amber : cyan }
}

private enum AssistantHUDText {
    /// "work" from "Claude · work".
    static func short(_ label: String) -> String {
        label.components(separatedBy: " · ").last ?? label
    }

    static func isCritical(_ account: AccountReadout) -> Bool {
        account.hasMeasurements && (account.headroom ?? 100) <= 15
    }

    static func percent(_ window: CapacityWindow?) -> String {
        window.map { "\(Int($0.usedPercent.rounded()))%" } ?? "NO DATA"
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func longDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE · dd MMM yyyy"
        return formatter.string(from: date).uppercased()
    }

    static func week(_ date: Date) -> Int {
        Calendar(identifier: .iso8601).component(.weekOfYear, from: date)
    }

    static func greeting(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? "\(part)." : "\(part), \(first)."
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

struct AssistantHUDDashboardView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    var staticLayout = false

    @State private var editor: MissionEditor?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 14) {
                AssistantHUDHeader(capacity: capacity, missions: missions, readout: readout, now: context.date)
                GeometryReader { proxy in
                    let side = min(380, (proxy.size.width - 48) * 0.27)
                    HStack(alignment: .top, spacing: 24) {
                        VStack(spacing: 14) {
                            AssistantHUDSystemStatus(capacity: capacity, missions: missions, readout: readout, now: context.date)
                            AssistantHUDAccountsPanel(readout: readout, now: context.date, staticLayout: staticLayout)
                        }
                        .frame(width: side)
                        AssistantHUDCenter(
                            missions: missions,
                            readout: readout,
                            now: context.date,
                            editor: $editor,
                            staticLayout: staticLayout
                        )
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 14) {
                            AssistantHUDProjectsPanel(missions: missions, editor: $editor, staticLayout: staticLayout)
                                .frame(maxHeight: projectsHeight(total: proxy.size.height))
                            AssistantHUDTasksPanel(missions: missions, editor: $editor, now: context.date, staticLayout: staticLayout)
                        }
                        .frame(width: side)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { AssistantHUDGrid() }
        .background(AssistantHUDPalette.void)
        .foregroundStyle(AssistantHUDPalette.text)
        .missionEditorSheet($editor, missions: missions)
    }

    /// The project panel keeps its natural height up to ~45% of the column.
    private func projectsHeight(total: CGFloat) -> CGFloat {
        let rows = CGFloat(max(1, missions.board.projects.count))
        return min(total * 0.45, 52 + rows * 56)
    }
}

// MARK: - Header

private struct AssistantHUDHeader: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    let readout: CockpitReadout
    let now: Date

    private var liveCount: Int { readout.accounts.filter(\.isLive).count }

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                AssistantHUDLogo().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("MC · MISSION CONTROL")
                        .font(AssistantHUDPalette.display(22, .bold))
                        .kerning(5)
                        .lineLimit(1)
                    Text("PERSONAL OPERATIONS ASSISTANT · CAPACITY + OBJECTIVES")
                        .font(AssistantHUDPalette.mono(11))
                        .kerning(2)
                        .foregroundStyle(AssistantHUDPalette.secondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                Circle()
                    .fill(capacity.isRefreshing ? AssistantHUDPalette.amber : AssistantHUDPalette.cyan)
                    .frame(width: 8, height: 8)
                    .shadow(color: AssistantHUDPalette.cyan, radius: 3)
                Text(capacity.isRefreshing ? "MC PROBING" : "MC ONLINE")
                    .foregroundStyle(AssistantHUDPalette.cyan)
                AssistantHUDSegmentBar(lit: litSegments)
                    .frame(width: 120, height: 10)
                    .accessibilityElement()
                    .accessibilityLabel("Live accounts")
                    .accessibilityValue("\(liveCount) of \(readout.accounts.count)")
                Text("LINKS \(liveCount)/\(readout.accounts.count)")
            }
            .font(AssistantHUDPalette.mono(12))
            .kerning(2)
            .foregroundStyle(AssistantHUDPalette.secondary)
            .fixedSize()
            Spacer(minLength: 12)
            HStack(spacing: 26) {
                reading("DATE", ThemeText.plateDate(now))
                reading("CYCLE", "\(missions.board.periodTitle.uppercased()) · WK \(AssistantHUDText.week(now))")
                reading(
                    "ROUTE CLAUDE",
                    readout.bestClaude.map {
                        "\(AssistantHUDText.short($0.snapshot.account.label).uppercased()) · \(Int(($0.headroom ?? 0).rounded()))%"
                    } ?? "NONE LIVE",
                    color: readout.bestClaude == nil ? AssistantHUDPalette.secondary : AssistantHUDPalette.cyan
                )
                ThemePicker {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("SKIN").font(AssistantHUDPalette.mono(11)).foregroundStyle(AssistantHUDPalette.secondary)
                        Text("THEME ▾").font(AssistantHUDPalette.mono(12)).foregroundStyle(AssistantHUDPalette.text)
                    }
                    .kerning(1.5)
                }
            }
            .fixedSize()
        }
        .frame(height: 40)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AssistantHUDPalette.cyan.opacity(0.28)).frame(height: 1)
        }
    }

    private var litSegments: Int {
        guard !readout.accounts.isEmpty else { return 0 }
        return Int((20 * Double(liveCount) / Double(readout.accounts.count)).rounded())
    }

    private func reading(_ title: String, _ value: String, color: Color = AssistantHUDPalette.text) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(title).font(AssistantHUDPalette.mono(11)).foregroundStyle(AssistantHUDPalette.secondary)
            Text(value).font(AssistantHUDPalette.mono(12)).foregroundStyle(color)
        }
        .kerning(1.5)
        .accessibilityElement(children: .combine)
    }
}

private struct AssistantHUDLogo: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 34
            func hex(_ points: [(CGFloat, CGFloat)]) -> Path {
                var path = Path()
                path.move(to: CGPoint(x: points[0].0 * s, y: points[0].1 * s))
                for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0 * s, y: point.1 * s)) }
                path.closeSubpath()
                return path
            }
            context.stroke(hex([(17, 2), (30, 9.5), (30, 24.5), (17, 32), (4, 24.5), (4, 9.5)]),
                           with: .color(AssistantHUDPalette.cyan), lineWidth: 1.5 * s)
            context.stroke(hex([(17, 7), (25.5, 12), (25.5, 22), (17, 27), (8.5, 22), (8.5, 12)]),
                           with: .color(AssistantHUDPalette.cyan.opacity(0.45)), lineWidth: s)
            context.draw(
                Text("MC").font(AssistantHUDPalette.display(11 * s, .bold)).foregroundColor(AssistantHUDPalette.bright),
                at: CGPoint(x: 17 * s, y: 17 * s)
            )
        }
        .accessibilityHidden(true)
    }
}

private struct AssistantHUDSegmentBar: View {
    let lit: Int

    var body: some View {
        Canvas { context, size in
            let step = size.width / 20
            for index in 0..<20 {
                let rect = CGRect(x: CGFloat(index) * step, y: 1, width: step * 0.66, height: size.height - 2)
                context.fill(Path(rect), with: .color(AssistantHUDPalette.cyan.opacity(index < lit ? 0.85 : 0.2)))
            }
        }
    }
}

private struct AssistantHUDGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += 40
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += 40
            }
            context.stroke(path, with: .color(AssistantHUDPalette.cyan.opacity(0.045)), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Panel chrome

private struct AssistantHUDPanel<Content: View>: View {
    let index: String
    let title: String
    var trailing: String = ""
    var addHelp: String?
    var add: (() -> Void)?
    var spacing: CGFloat = 8
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(spacing: 8) {
                (Text(index).foregroundColor(AssistantHUDPalette.cyan) + Text(" // \(title)"))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(trailing).lineLimit(1)
                if let add, let addHelp {
                    AssistantHUDAddButton(help: addHelp, action: add)
                }
            }
            .font(AssistantHUDPalette.mono(11))
            .kerning(1.2)
            .foregroundStyle(AssistantHUDPalette.secondary)
            .padding(.bottom, 7)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AssistantHUDPalette.cyan.opacity(0.18)).frame(height: 1)
            }
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .hudPanel()
    }
}

private struct AssistantHUDCorners: Shape {
    var length: CGFloat = 14
    var radius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = radius, l = length
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + l, y: rect.minY), radius: r)
        path.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + l), radius: r)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - l, y: rect.maxY), radius: r)
        path.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - l), radius: r)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return path
    }
}

private extension View {
    func hudPanel() -> some View {
        background(AssistantHUDPalette.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AssistantHUDPalette.cyan.opacity(0.32), lineWidth: 1))
            .overlay(AssistantHUDCorners().stroke(AssistantHUDPalette.cyan, lineWidth: 2))
            .shadow(color: AssistantHUDPalette.cyan.opacity(0.07), radius: 7)
    }
}

private struct AssistantHUDAddButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AssistantHUDPalette.cyan)
                .frame(width: 20, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(AssistantHUDPalette.cyan.opacity(0.5), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct AssistantHUDEmpty: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AssistantHUDPalette.mono(11))
            .kerning(1)
            .foregroundStyle(AssistantHUDPalette.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }
}

private struct AssistantHUDScroll<Content: View>: View {
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

// MARK: - System status

private struct AssistantHUDSystemStatus: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    let readout: CockpitReadout
    let now: Date

    var body: some View {
        AssistantHUDPanel(
            index: "00",
            title: "SYSTEM STATUS",
            trailing: ThemeText.probedLabel(capacity.lastRefresh, now: now),
            spacing: 10
        ) {
            HStack(spacing: 16) {
                AssistantHUDRadar(readout: readout).frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 2) {
                    Text("LOCAL TIME · \(TimeZone.current.abbreviation() ?? "")")
                        .font(AssistantHUDPalette.mono(11))
                        .kerning(2)
                        .foregroundStyle(AssistantHUDPalette.secondary)
                    Text(AssistantHUDText.time(now))
                        .font(AssistantHUDPalette.mono(46))
                        .foregroundStyle(AssistantHUDPalette.bright)
                        .shadow(color: AssistantHUDPalette.cyan.opacity(0.35), radius: 5)
                    Text(AssistantHUDText.longDate(now))
                        .font(AssistantHUDPalette.display(15, .semibold))
                        .kerning(2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            HStack(alignment: .center, spacing: 8) {
                stat("LINKS", "\(readout.accounts.filter(\.isLive).count)/\(readout.accounts.count) UP", AssistantHUDPalette.cyan)
                stat("ALERTS", "\(alertCount) ACTIVE", alertCount > 0 ? AssistantHUDPalette.amber : AssistantHUDPalette.text)
                stat("TASKS", "\(missions.board.openTaskCount) · \(missions.board.dueTodayCount(now: now)) TODAY", AssistantHUDPalette.text)
                Button {
                    Task { await capacity.refresh() }
                } label: {
                    Text(capacity.isRefreshing ? "PROBING" : "RE-PROBE")
                        .font(AssistantHUDPalette.mono(11, .semibold))
                        .kerning(1.5)
                        .foregroundStyle(AssistantHUDPalette.void)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            capacity.isRefreshing ? AssistantHUDPalette.secondary : AssistantHUDPalette.cyan,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
                .disabled(capacity.isRefreshing)
                .help("Check every account's usage now")
                .fixedSize()
            }
        }
    }

    private var alertCount: Int { readout.accounts.filter(\.isNearLimit).count + readout.needsSignIn.count }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(AssistantHUDPalette.mono(11)).foregroundStyle(AssistantHUDPalette.secondary)
            Text(value)
                .font(AssistantHUDPalette.mono(13))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .kerning(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Segment mid-angles (degrees clockwise from 12 o'clock) shared by the radar
/// blips and the central ring. Up to four accounts sit on the diagonals.
private enum AssistantHUDSegments {
    static func layout(count: Int) -> (mids: [Double], span: Double) {
        guard count > 0 else { return ([], 0) }
        if count <= 4 {
            return (Array([-45.0, 45, 135, 225].prefix(count)), 86)
        }
        let step = 360 / Double(count)
        return ((0..<count).map { -45 + Double($0) * step }, step - 4)
    }
}

private struct AssistantHUDRadar: View {
    let readout: CockpitReadout

    var body: some View {
        Canvas { context, size in
            let s = size.width / 96
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let cyan = AssistantHUDPalette.cyan
            func circle(_ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: c.x - r * s, y: c.y - r * s, width: 2 * r * s, height: 2 * r * s))
            }
            context.stroke(circle(44), with: .color(cyan.opacity(0.5)), lineWidth: 1)
            context.stroke(circle(30), with: .color(cyan.opacity(0.22)), lineWidth: 1)
            context.stroke(circle(16), with: .color(cyan.opacity(0.22)), lineWidth: 1)
            var cross = Path()
            cross.move(to: CGPoint(x: c.x - 44 * s, y: c.y)); cross.addLine(to: CGPoint(x: c.x + 44 * s, y: c.y))
            cross.move(to: CGPoint(x: c.x, y: c.y - 44 * s)); cross.addLine(to: CGPoint(x: c.x, y: c.y + 44 * s))
            context.stroke(cross, with: .color(cyan.opacity(0.18)), lineWidth: 1)
            var wedge = DialGeometry.arc(c, 44 * s, from: 0, to: 45)
            wedge.addLine(to: c)
            wedge.closeSubpath()
            context.fill(wedge, with: .color(cyan.opacity(0.12)))
            context.stroke(DialGeometry.tick(c, 44 * s, 0, 0), with: .color(cyan), lineWidth: 1.2)

            let mids = AssistantHUDSegments.layout(count: readout.accounts.count).mids
            for (index, account) in readout.accounts.enumerated() {
                let distance = (account.peakUsed ?? 0) / 100 * 40
                let p = DialGeometry.point(c, distance * s, mids[index])
                let dot = Path(ellipseIn: CGRect(x: p.x - 3 * s, y: p.y - 3 * s, width: 6 * s, height: 6 * s))
                if account.hasMeasurements {
                    context.fill(dot, with: .color(AssistantHUDText.isCritical(account) ? AssistantHUDPalette.amber : cyan))
                } else {
                    context.stroke(dot, with: .color(AssistantHUDPalette.secondary), lineWidth: 1)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Account radar")
        .accessibilityValue("\(readout.accounts.filter(\.hasMeasurements).count) accounts reporting")
    }
}

// MARK: - Accounts

private struct AssistantHUDAccountsPanel: View {
    let readout: CockpitReadout
    let now: Date
    let staticLayout: Bool

    var body: some View {
        AssistantHUDPanel(index: "01", title: "ACCOUNT CAPACITY", trailing: "OUT 5H · IN WK", spacing: 4) {
            if readout.accounts.isEmpty {
                AssistantHUDEmpty(text: "NO ACCOUNTS CONFIGURED.")
                Spacer(minLength: 0)
            } else if staticLayout || readout.accounts.count <= 4 {
                VStack(spacing: 0) { rows(flexible: true) }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()
            } else {
                ScrollView { VStack(spacing: 0) { rows(flexible: false) } }
                    .scrollIndicators(.never)
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func rows(flexible: Bool) -> some View {
        let bestID = readout.bestClaude?.snapshot.id
        ForEach(readout.accounts, id: \.snapshot.id) { account in
            AssistantHUDAccountRow(account: account, isRoute: account.snapshot.id == bestID, now: now)
                .frame(minHeight: 96, maxHeight: flexible ? .infinity : nil)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(AssistantHUDPalette.cyan.opacity(0.1)).frame(height: 1)
                }
        }
    }
}

private struct AssistantHUDMiniGauge: View {
    let account: AccountReadout
    var size: CGFloat = 88

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 88
            let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            for index in 0..<10 {
                context.stroke(
                    DialGeometry.tick(c, 42 * s, 39.5 * s, -135 + Double(index) * 30),
                    with: .color(AssistantHUDPalette.cyan.opacity(0.45)),
                    lineWidth: 1
                )
            }
            func band(_ window: CapacityWindow?, radius: CGFloat, width: CGFloat) {
                context.stroke(DialGeometry.arc(c, radius * s, from: -135, to: 135),
                               with: .color(AssistantHUDPalette.track), lineWidth: width * s)
                if let window, window.usedPercent > 0 {
                    context.stroke(
                        DialGeometry.arc(c, radius * s, from: -135, to: -135 + 270 * window.usedPercent / 100),
                        with: .color(AssistantHUDPalette.tone(window.usedPercent)),
                        lineWidth: width * s
                    )
                }
            }
            band(account.fiveHour, radius: 35, width: 5)
            band(account.weekly, radius: 26, width: 3)
            let headroom = account.headroom.map { "\(Int($0.rounded()))" } ?? "--"
            let color = AssistantHUDText.isCritical(account) ? AssistantHUDPalette.amber
                : account.hasMeasurements ? AssistantHUDPalette.bright : AssistantHUDPalette.secondary
            context.draw(Text(headroom).font(AssistantHUDPalette.mono(19 * s)).foregroundColor(color),
                         at: CGPoint(x: c.x, y: c.y))
            context.draw(Text("HDRM%").font(AssistantHUDPalette.mono(10 * s)).foregroundColor(AssistantHUDPalette.secondary),
                         at: CGPoint(x: c.x, y: 77 * s))
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(account.snapshot.account.label) capacity")
        .accessibilityValue(
            account.hasMeasurements
                ? "5-hour \(AssistantHUDText.percent(account.fiveHour)) used, weekly \(AssistantHUDText.percent(account.weekly)) used, \(Int((account.headroom ?? 0).rounded()))% headroom"
                : account.snapshot.state.label
        )
    }
}

private struct AssistantHUDAccountRow: View {
    let account: AccountReadout
    let isRoute: Bool
    let now: Date
    var gaugeSize: CGFloat = 88

    private var snapshot: ProviderSnapshot { account.snapshot }
    private var isStale: Bool { snapshot.state == .error && account.hasMeasurements }

    var body: some View {
        HStack(spacing: 12) {
            AssistantHUDMiniGauge(account: account, size: gaugeSize)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(snapshot.account.label)
                        .font(AssistantHUDPalette.display(17, .bold))
                        .kerning(0.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    Text(chip.text)
                        .font(AssistantHUDPalette.mono(10))
                        .kerning(1.5)
                        .foregroundStyle(chip.color)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(chip.color, lineWidth: 1))
                        .fixedSize()
                }
                Text(account.hasMeasurements ? ThemeText.identityLine(account) : snapshot.state.label.uppercased())
                    .font(account.hasMeasurements ? AssistantHUDPalette.display(13, .medium) : AssistantHUDPalette.mono(11, .semibold))
                    .foregroundStyle(isStale || !account.hasMeasurements ? AssistantHUDPalette.amber : AssistantHUDPalette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if account.hasMeasurements {
                    HStack {
                        reading("5H", AssistantHUDText.percent(account.fiveHour), account.fiveHour)
                        Spacer(minLength: 4)
                        reading("WK", AssistantHUDText.percent(account.weekly), account.weekly)
                        Spacer(minLength: 4)
                        (Text("RST ").foregroundColor(AssistantHUDPalette.secondary) + Text(ThemeText.resetText(account, now: now)))
                            .lineLimit(1)
                    }
                    .font(AssistantHUDPalette.mono(12))
                    .padding(.top, 6)
                } else {
                    Text(snapshot.message ?? "No usage reported yet.")
                        .font(AssistantHUDPalette.mono(10.5))
                        .foregroundStyle(AssistantHUDPalette.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.top, 3)
                }
            }
        }
        .padding(.vertical, 4)
        .help(ThemeText.guide(snapshot.provider))
    }

    private var chip: (text: String, color: Color) {
        if !account.hasMeasurements {
            let text = switch snapshot.state {
            case .unauthenticated: "SIGN-IN"
            case .loading: "LOADING"
            case .unavailable: "OFFLINE"
            case .error: "FAULT"
            case .connected: "NO DATA"
            }
            return (text, AssistantHUDPalette.amber)
        }
        if AssistantHUDText.isCritical(account) { return ("CRITICAL", AssistantHUDPalette.amber) }
        if isStale { return ("STALE", AssistantHUDPalette.amber) }
        if isRoute { return ("ROUTE", AssistantHUDPalette.cyan) }
        return ("NOMINAL", AssistantHUDPalette.secondary)
    }

    private func reading(_ label: String, _ value: String, _ window: CapacityWindow?) -> some View {
        (Text("\(label) ").foregroundColor(AssistantHUDPalette.secondary)
            + Text(value).foregroundColor(window.map { AssistantHUDPalette.tone($0.usedPercent) } ?? AssistantHUDPalette.secondary))
            .lineLimit(1)
    }
}

// MARK: - Centre column

private struct AssistantHUDCenter: View {
    @ObservedObject var missions: MissionStore
    let readout: CockpitReadout
    let now: Date
    @Binding var editor: MissionEditor?
    let staticLayout: Bool

    var body: some View {
        GeometryReader { proxy in
            let ring = max(280, min(proxy.size.width, proxy.size.height - 250, 600))
            VStack(spacing: 12) {
                AssistantHUDReactor(readout: readout, objectives: missions.board.objectives, now: now, staticLayout: staticLayout)
                    .frame(width: ring, height: ring)
                AssistantHUDBriefing(readout: readout, now: now)
                objectives
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    private var objectives: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                (Text("04").foregroundColor(AssistantHUDPalette.cyan) + Text(" // OBJECTIVES · \(missions.board.periodTitle.uppercased())"))
                Spacer()
                AssistantHUDAddButton(help: "Add an objective") {
                    editor = .objective(MissionObjective(title: ""))
                }
            }
            .font(AssistantHUDPalette.mono(11))
            .kerning(2)
            .foregroundStyle(AssistantHUDPalette.secondary)
            AssistantHUDScroll(staticLayout: staticLayout) {
                if missions.board.objectives.isEmpty {
                    AssistantHUDEmpty(text: "NO OBJECTIVES LOGGED FOR \(missions.board.periodTitle.uppercased()). USE + AND I'LL TRACK THEM ON THE CORE RINGS.")
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3),
                        spacing: 12
                    ) {
                        ForEach(Array(missions.board.objectives.enumerated()), id: \.element.id) { index, objective in
                            objectiveCell(objective, index: index)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func objectiveCell(_ objective: MissionObjective, index: Int) -> some View {
        let color = index < 3 ? AssistantHUDPalette.objectiveColors[index] : AssistantHUDPalette.secondary
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("O\(index + 1) · \(missions.board.periodTitle.uppercased())").foregroundStyle(color)
                Spacer()
                Text("\(Int(objective.progress.rounded()))%").foregroundStyle(AssistantHUDPalette.bright)
            }
            .font(AssistantHUDPalette.mono(12))
            Text(objective.title)
                .font(AssistantHUDPalette.display(15, .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !objective.summary.isEmpty {
                Text(objective.summary)
                    .font(AssistantHUDPalette.mono(11))
                    .foregroundStyle(AssistantHUDPalette.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.top, 6)
        .overlay(alignment: .top) { Rectangle().fill(color).frame(height: 2) }
        .frame(maxWidth: .infinity, alignment: .leading)
        .objectiveActions(objective, missions: missions, editor: $editor)
    }
}

// MARK: - Central ring

private struct AssistantHUDReactor: View {
    let readout: CockpitReadout
    let objectives: [MissionObjective]
    let now: Date
    let staticLayout: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width
            let k = size / 540
            ZStack {
                AssistantHUDReactorBase(readout: readout, objectives: objectives)
                rotatingRings(size: size)
                core(k: k)
                    .frame(width: 200 * k)
                    .position(x: size / 2, y: size / 2)
                callouts(size: size, k: k)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Two slowly counter-rotating rings. Still when drawn for a snapshot.
    @ViewBuilder
    private func rotatingRings(size: CGFloat) -> some View {
        if staticLayout {
            AssistantHUDSpinRings(outerAngle: 0, innerAngle: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                AssistantHUDSpinRings(
                    outerAngle: -(t.truncatingRemainder(dividingBy: 180) / 180 * 360),
                    innerAngle: t.truncatingRemainder(dividingBy: 90) / 90 * 360
                )
            }
        }
    }

    private func core(k: CGFloat) -> some View {
        let best = readout.bestClaude
        return VStack(spacing: 4 * k) {
            Text("ROUTE NEXT CLAUDE TO")
                .font(AssistantHUDPalette.mono(11 * max(k, 0.85)))
                .kerning(2)
                .foregroundStyle(AssistantHUDPalette.secondary)
            Text(best.map { AssistantHUDText.short($0.snapshot.account.label).uppercased() } ?? "NO ACCOUNT")
                .font(AssistantHUDPalette.display(24 * k, .bold))
                .kerning(3)
                .foregroundStyle(AssistantHUDPalette.bright)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(best.flatMap(\.headroom).map { "\(Int($0.rounded()))%" } ?? "--")
                .font(AssistantHUDPalette.mono(56 * k))
                .foregroundStyle(best == nil ? AssistantHUDPalette.secondary : AssistantHUDPalette.cyan)
                .shadow(color: AssistantHUDPalette.cyan.opacity(best == nil ? 0 : 0.35), radius: 6)
            Text(best.map { "HEADROOM · RST \(ThemeText.resetText($0, now: now))" } ?? "STANDBY · NO LIVE CLAUDE")
                .font(AssistantHUDPalette.mono(11 * max(k, 0.85)))
                .kerning(1.5)
                .foregroundStyle(AssistantHUDPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func callouts(size: CGFloat, k: CGFloat) -> some View {
        let accounts = readout.accounts
        let layout = AssistantHUDSegments.layout(count: accounts.count)
        if accounts.count <= 4 {
            let corners: [Alignment] = [.topLeading, .topTrailing, .bottomTrailing, .bottomLeading]
            ForEach(Array(accounts.enumerated()), id: \.element.snapshot.id) { index, account in
                AssistantHUDCallout(account: account, trailing: index == 1 || index == 2)
                    .frame(width: 150)
                    .frame(width: size, height: size, alignment: corners[index])
            }
        } else {
            ForEach(Array(accounts.enumerated()), id: \.element.snapshot.id) { index, account in
                let p = DialGeometry.point(CGPoint(x: size / 2, y: size / 2), 300 * k, layout.mids[index])
                VStack(spacing: 0) {
                    Text(AssistantHUDText.short(account.snapshot.account.label).uppercased())
                        .font(AssistantHUDPalette.display(12, .bold))
                    Text(account.headroom.map { "\(Int($0.rounded()))%" } ?? "--")
                        .font(AssistantHUDPalette.mono(12))
                        .foregroundStyle(AssistantHUDText.isCritical(account) ? AssistantHUDPalette.amber : AssistantHUDPalette.cyan)
                }
                .fixedSize()
                .position(x: min(max(p.x, 40), size - 40), y: min(max(p.y, 14), size - 14))
            }
        }
    }
}

private struct AssistantHUDCallout: View {
    let account: AccountReadout
    let trailing: Bool

    var body: some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
            Text(account.snapshot.account.label.uppercased())
                .font(AssistantHUDPalette.display(14, .bold))
                .kerning(1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if account.hasMeasurements {
                (Text("\(Int((account.headroom ?? 0).rounded()))% ").font(AssistantHUDPalette.mono(22))
                    .foregroundColor(AssistantHUDText.isCritical(account) ? AssistantHUDPalette.amber : AssistantHUDPalette.cyan)
                    + Text("HDRM").font(AssistantHUDPalette.mono(11)).foregroundColor(AssistantHUDPalette.secondary))
                Text("5H \(short(account.fiveHour)) · WK \(short(account.weekly))")
                    .font(AssistantHUDPalette.mono(11))
                    .foregroundStyle(AssistantHUDPalette.secondary)
            } else {
                Text("--").font(AssistantHUDPalette.mono(22)).foregroundStyle(AssistantHUDPalette.secondary)
                Text(account.snapshot.state.label.uppercased())
                    .font(AssistantHUDPalette.mono(11))
                    .foregroundStyle(AssistantHUDPalette.amber)
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(trailing ? .trailing : .leading)
        .accessibilityElement(children: .combine)
    }

    private func short(_ window: CapacityWindow?) -> String {
        window.map { "\(Int($0.usedPercent.rounded()))" } ?? "N/D"
    }
}

/// Everything on the central ring that does not move.
private struct AssistantHUDReactorBase: View {
    let readout: CockpitReadout
    let objectives: [MissionObjective]

    var body: some View {
        Canvas { context, size in
            let k = size.width / 540
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let cyan = AssistantHUDPalette.cyan
            func circle(_ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: c.x - r * k, y: c.y - r * k, width: 2 * r * k, height: 2 * r * k))
            }

            // Glow.
            context.fill(circle(268), with: .radialGradient(
                Gradient(stops: [
                    .init(color: cyan.opacity(0.16), location: 0),
                    .init(color: cyan.opacity(0.05), location: 0.55),
                    .init(color: cyan.opacity(0), location: 1),
                ]),
                center: c, startRadius: 0, endRadius: 268 * k
            ))

            // Outer tick ring.
            for index in 0..<120 {
                let major = index % 10 == 0, mid = index % 5 == 0
                context.stroke(
                    DialGeometry.tick(c, 252 * k, (major ? 238 : mid ? 242 : 246) * k, Double(index) * 3),
                    with: .color(major ? cyan : mid ? AssistantHUDPalette.midTick : AssistantHUDPalette.minorTick),
                    lineWidth: major ? 1.6 : 1
                )
            }
            context.stroke(circle(234), with: .color(cyan.opacity(0.25)), lineWidth: 1)

            // One arc per account, filled by headroom.
            let layout = AssistantHUDSegments.layout(count: readout.accounts.count)
            for (index, account) in readout.accounts.enumerated() {
                let mid = layout.mids[index]
                let start = mid - layout.span / 2
                let critical = AssistantHUDText.isCritical(account)
                let color = critical ? AssistantHUDPalette.amber : account.hasMeasurements ? cyan : AssistantHUDPalette.secondary
                context.stroke(DialGeometry.arc(c, 222 * k, from: start, to: start + layout.span),
                               with: .color(AssistantHUDPalette.deepTrack), lineWidth: 14 * k)
                if let headroom = account.headroom, headroom > 0 {
                    context.stroke(DialGeometry.arc(c, 222 * k, from: start, to: start + layout.span * headroom / 100),
                                   with: .color(color), lineWidth: 14 * k)
                }
                context.stroke(DialGeometry.tick(c, 256 * k, 296 * k, mid), with: .color(color.opacity(0.8)), lineWidth: 1)
                let end = DialGeometry.point(c, 296 * k, mid)
                context.fill(Path(ellipseIn: CGRect(x: end.x - 2.5, y: end.y - 2.5, width: 5, height: 5)), with: .color(color))
            }
            context.stroke(circle(210), with: .color(cyan.opacity(0.25)), lineWidth: 1)

            // Objective rings: 270° sweeps with their labels in the gap.
            let radii: [CGFloat] = [182, 160, 138]
            for (index, radius) in radii.enumerated() {
                context.stroke(DialGeometry.arc(c, radius * k, from: -135, to: 135),
                               with: .color(AssistantHUDPalette.deepTrack), lineWidth: 8 * k)
                guard index < objectives.count else { continue }
                let objective = objectives[index]
                let color = AssistantHUDPalette.objectiveColors[index]
                let progress = min(max(objective.progress, 0), 100)
                if progress > 0 {
                    context.stroke(DialGeometry.arc(c, radius * k, from: -135, to: -135 + 270 * progress / 100),
                                   with: .color(color), lineWidth: 8 * k)
                }
                context.draw(
                    Text("O\(index + 1) \(Int(progress.rounded()))%").font(AssistantHUDPalette.mono(12 * k)).foregroundColor(color),
                    at: CGPoint(x: c.x, y: c.y + radius * k)
                )
            }

            // Core ticks and disk.
            for index in 0..<72 {
                let major = index % 6 == 0
                context.stroke(DialGeometry.tick(c, 116 * k, (major ? 110 : 113) * k, Double(index) * 5),
                               with: .color(cyan.opacity(major ? 0.9 : 0.35)), lineWidth: 1)
            }
            context.fill(circle(108), with: .color(AssistantHUDPalette.core))
            context.stroke(circle(108), with: .color(cyan.opacity(0.6)), lineWidth: 1)

            // Hex cells inside the core.
            var cells = context
            cells.clip(to: circle(106))
            cells.opacity = 0.12
            var hexes = Path()
            let w = 14 * k, h = 24 * k
            var y = c.y - 108 * k
            while y < c.y + 108 * k {
                var x = c.x - 112 * k
                while x < c.x + 112 * k {
                    hexes.move(to: CGPoint(x: x + w / 2, y: y))
                    hexes.addLine(to: CGPoint(x: x + w, y: y + 4 * k))
                    hexes.addLine(to: CGPoint(x: x + w, y: y + 12 * k))
                    hexes.addLine(to: CGPoint(x: x + w / 2, y: y + 16 * k))
                    hexes.addLine(to: CGPoint(x: x, y: y + 12 * k))
                    hexes.addLine(to: CGPoint(x: x, y: y + 4 * k))
                    hexes.closeSubpath()
                    hexes.move(to: CGPoint(x: x + w / 2, y: y + 16 * k))
                    hexes.addLine(to: CGPoint(x: x + w / 2, y: y + h))
                    x += w
                }
                y += h
            }
            cells.stroke(hexes, with: .color(cyan), lineWidth: 0.7)
        }
        .accessibilityElement()
        .accessibilityLabel("Capacity ring")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        readout.accounts.map { account in
            "\(account.snapshot.account.label): " + (account.headroom.map { "\(Int($0.rounded()))% headroom" } ?? account.snapshot.state.label)
        }
        .joined(separator: ", ")
    }
}

private struct AssistantHUDSpinRings: View {
    let outerAngle: Double
    let innerAngle: Double

    var body: some View {
        GeometryReader { proxy in
            let k = proxy.size.width / 540
            let cyan = AssistantHUDPalette.cyan
            ZStack {
                ZStack {
                    Circle()
                        .stroke(cyan.opacity(0.55), style: StrokeStyle(lineWidth: 3 * k, dash: [2 * k, 9 * k]))
                    Circle()
                        .stroke(cyan.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [90 * k, 224 * k, 30 * k, 284 * k, 60 * k, 769 * k]))
                }
                .frame(width: 400 * k, height: 400 * k)
                .rotationEffect(.degrees(outerAngle))
                Circle()
                    .stroke(cyan.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [150 * k, 118 * k]))
                    .frame(width: 248 * k, height: 248 * k)
                    .rotationEffect(.degrees(innerAngle))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Briefing

private struct AssistantHUDBriefing: View {
    let readout: CockpitReadout
    let now: Date
    var compact = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if !compact {
                VStack(alignment: .leading, spacing: 6) {
                    (Text("MC").foregroundColor(AssistantHUDPalette.cyan) + Text(" // BRIEFING"))
                        .font(AssistantHUDPalette.mono(11))
                        .kerning(2)
                        .foregroundStyle(AssistantHUDPalette.secondary)
                    AssistantHUDWave().frame(width: 120, height: 30)
                }
                .frame(width: 120)
            }
            message
                .font(AssistantHUDPalette.display(compact ? 14 : 17, .medium))
                .lineSpacing(2)
                .foregroundStyle(AssistantHUDPalette.bright)
                .lineLimit(compact ? 5 : 4)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, compact ? 14 : 18)
        .padding(.vertical, 12)
        .hudPanel()
        .accessibilityElement(children: .combine)
    }

    private var message: Text {
        var text = Text(AssistantHUDText.greeting(now) + " ")
        if let caution = readout.masterCaution, let window = caution.bindingWindow {
            text = text
                + Text(caution.snapshot.account.label).fontWeight(.bold)
                + Text(" is at ")
                + Text("\(Int(window.usedPercent.rounded()))%").font(AssistantHUDPalette.mono(compact ? 13 : 16)).foregroundColor(AssistantHUDPalette.amber)
                + Text(" of its \(AssistantHUDText.windowName(window)) window. ")
        } else if readout.accounts.contains(where: \.hasMeasurements) {
            text = text + Text("Every measured account is below \(Int(AccountReadout.cautionThreshold))% of its limits. ")
        } else {
            text = text + Text("I have no usage readings yet. ")
        }
        if let best = readout.bestClaude {
            text = text
                + Text("I recommend routing your next Claude session to ")
                + Text(AssistantHUDText.short(best.snapshot.account.label)).fontWeight(.bold).foregroundColor(AssistantHUDPalette.cyan)
                + Text(" — ")
                + Text("\(Int((best.headroom ?? 0).rounded()))%").font(AssistantHUDPalette.mono(compact ? 13 : 16)).foregroundColor(AssistantHUDPalette.cyan)
                + Text(" headroom.")
        } else {
            text = text + Text("No Claude account is available for routing right now.")
        }
        let signIn = readout.needsSignIn.count
        if signIn > 0 {
            text = text + Text(" \(signIn) account\(signIn == 1 ? " needs" : "s need") sign-in.").foregroundColor(AssistantHUDPalette.amber)
        }
        return text
    }
}

private struct AssistantHUDWave: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 120
            for index in 0..<30 {
                let i = Double(index)
                let h = (4 + abs(sin(i * 0.72) * cos(i * 0.21)) * 22).rounded()
                let rect = CGRect(x: CGFloat(index) * 4 * s, y: (15 - h / 2) * s, width: 2 * s, height: h * s)
                context.fill(Path(rect), with: .color(AssistantHUDPalette.cyan.opacity(index < 22 ? 0.9 : 0.35)))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Projects

private struct AssistantHUDProjectsPanel: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let staticLayout: Bool

    var body: some View {
        AssistantHUDPanel(
            index: "02",
            title: "PROJECT ORBITS",
            trailing: "\(missions.board.projects.count) ACTIVE",
            addHelp: "Add a project",
            add: { editor = .project(MissionProject(name: "")) },
            spacing: 6
        ) {
            AssistantHUDScroll(staticLayout: staticLayout) {
                VStack(alignment: .leading, spacing: 6) {
                    if missions.board.projects.isEmpty {
                        AssistantHUDEmpty(text: "NO PROJECTS IN ORBIT. USE + TO ADD ONE.")
                    }
                    ForEach(missions.board.projects) { project in
                        AssistantHUDProjectRow(project: project)
                            .projectActions(project, missions: missions, editor: $editor)
                    }
                }
            }
        }
    }
}

private struct AssistantHUDProjectRow: View {
    let project: MissionProject

    var body: some View {
        HStack(spacing: 12) {
            Canvas { context, size in
                let s = size.width / 50
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let cyan = AssistantHUDPalette.cyan
                let progress = min(max(project.progress, 0), 100)
                context.stroke(Path(ellipseIn: CGRect(x: c.x - 23 * s, y: c.y - 23 * s, width: 46 * s, height: 46 * s)),
                               with: .color(cyan.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                context.stroke(Path(ellipseIn: CGRect(x: c.x - 18 * s, y: c.y - 18 * s, width: 36 * s, height: 36 * s)),
                               with: .color(AssistantHUDPalette.deepTrack), lineWidth: 4 * s)
                if progress > 0 {
                    context.stroke(DialGeometry.arc(c, 18 * s, from: 0, to: 360 * progress / 100), with: .color(cyan), lineWidth: 4 * s)
                }
                let dot = DialGeometry.point(c, 18 * s, 360 * progress / 100)
                context.fill(Path(ellipseIn: CGRect(x: dot.x - 2.5 * s, y: dot.y - 2.5 * s, width: 5 * s, height: 5 * s)),
                             with: .color(AssistantHUDPalette.bright))
                context.draw(Text("\(Int(progress.rounded()))").font(AssistantHUDPalette.mono(12 * s)).foregroundColor(AssistantHUDPalette.bright), at: c)
            }
            .frame(width: 50, height: 50)
            .accessibilityElement()
            .accessibilityLabel("\(project.name) progress")
            .accessibilityValue("\(Int(project.progress.rounded()))%")
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text(project.name)
                        .font(AssistantHUDPalette.display(16, .bold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(project.phase.uppercased())
                        .font(AssistantHUDPalette.mono(10))
                        .kerning(1.5)
                        .foregroundStyle(AssistantHUDPalette.cyan)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AssistantHUDPalette.cyan.opacity(0.5), lineWidth: 1))
                        .fixedSize()
                }
                (Text("NEXT › ").font(AssistantHUDPalette.mono(11)).foregroundColor(AssistantHUDPalette.cyan)
                    + Text(project.nextAction.isEmpty ? "—" : project.nextAction))
                    .font(AssistantHUDPalette.display(13, .medium))
                    .foregroundStyle(AssistantHUDPalette.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Tasks

private struct AssistantHUDTasksPanel: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let now: Date
    let staticLayout: Bool

    var body: some View {
        AssistantHUDPanel(
            index: "03",
            title: "TASK QUEUE",
            trailing: "\(missions.board.openTaskCount) OPEN",
            addHelp: "Add a task",
            add: { editor = .task(MissionTask(title: "")) }
        ) {
            AssistantHUDScroll(staticLayout: staticLayout) {
                VStack(alignment: .leading, spacing: 8) {
                    if missions.board.tasks.isEmpty {
                        AssistantHUDEmpty(text: "QUEUE EMPTY. USE + TO GIVE ME SOMETHING TO TRACK.")
                    } else {
                        ForEach(TaskBucket.allCases) { bucket in
                            group(bucket)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func color(_ bucket: TaskBucket) -> Color {
        switch bucket {
        case .now: AssistantHUDPalette.amber
        case .next: AssistantHUDPalette.cyan
        case .later: AssistantHUDPalette.secondary
        }
    }

    private func group(_ bucket: TaskBucket) -> some View {
        let tasks = missions.board.tasks(in: bucket, now: now)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Rectangle().fill(color(bucket)).frame(width: 18, height: 2)
                Text(tasks.isEmpty ? "\(bucket.title) · CLEAR" : "\(bucket.title) · \(tasks.count)")
            }
            .font(AssistantHUDPalette.mono(11))
            .kerning(2)
            .foregroundStyle(color(bucket))
            ForEach(tasks) { task in
                AssistantHUDTaskRow(task: task, missions: missions, editor: $editor, now: now)
            }
        }
    }
}

private struct AssistantHUDTaskRow: View {
    let task: MissionTask
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(isOn: doneBinding(task, missions: missions)) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(task.title)
                        .font(AssistantHUDPalette.display(14, .semibold))
                        .strikethrough(task.isDone, color: AssistantHUDPalette.secondary)
                        .foregroundStyle(task.isDone ? AssistantHUDPalette.secondary : AssistantHUDPalette.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let project = missions.board.project(for: task) {
                        Text(project.name)
                            .font(AssistantHUDPalette.display(12, .medium))
                            .foregroundStyle(AssistantHUDPalette.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(AssistantHUDCheckStyle())
            if let due = ThemeText.dueLabel(task, now: now) {
                Text(due)
                    .font(AssistantHUDPalette.mono(11))
                    .kerning(1)
                    .foregroundStyle(task.isDue(on: now) ? AssistantHUDPalette.amber : AssistantHUDPalette.secondary)
                    .padding(.top, 2)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AssistantHUDPalette.cyan.opacity(0.14), lineWidth: 1))
        .taskActions(task, missions: missions, editor: $editor)
    }
}

private struct AssistantHUDCheckStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(configuration.isOn ? AssistantHUDPalette.cyan : Color.clear)
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(AssistantHUDPalette.cyan, lineWidth: 1.2)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(AssistantHUDPalette.void)
                    }
                }
                .frame(width: 14, height: 14)
                .shadow(color: AssistantHUDPalette.cyan.opacity(configuration.isOn ? 0.6 : 0), radius: 3)
                .padding(.top, 3)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Done" : "Open")
    }
}

// MARK: - Menu

struct AssistantHUDMenuView: View {
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
                route(now: context.date)
                if staticLayout {
                    content(now: context.date)
                } else {
                    ScrollView { content(now: context.date) }.scrollIndicators(.never)
                }
                footer
            }
        }
        .padding(14)
        .background { AssistantHUDGrid() }
        .background(AssistantHUDPalette.void)
        .foregroundStyle(AssistantHUDPalette.text)
        .missionEditorSheet($editor, missions: missions)
    }

    private func header(now: Date) -> some View {
        HStack(spacing: 10) {
            AssistantHUDLogo().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("MC · MISSION CONTROL")
                    .font(AssistantHUDPalette.display(17, .bold))
                    .kerning(3)
                Text("\(ThemeText.plateDate(now)) · \(ThemeText.probedLabel(capacity.lastRefresh, now: now))")
                    .font(AssistantHUDPalette.mono(10))
                    .kerning(1)
                    .foregroundStyle(AssistantHUDPalette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Circle().fill(AssistantHUDPalette.cyan).frame(width: 7, height: 7)
                    .shadow(color: AssistantHUDPalette.cyan, radius: 3)
                Text(capacity.isRefreshing ? "PROBING" : "ONLINE")
                    .font(AssistantHUDPalette.mono(10))
                    .kerning(1.5)
                    .foregroundStyle(AssistantHUDPalette.cyan)
            }
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AssistantHUDPalette.cyan.opacity(0.28)).frame(height: 1)
        }
    }

    private func route(now: Date) -> some View {
        let best = readout.bestClaude
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ROUTE NEXT CLAUDE TO")
                        .font(AssistantHUDPalette.mono(10))
                        .kerning(2)
                        .foregroundStyle(AssistantHUDPalette.secondary)
                    Text(best.map { AssistantHUDText.short($0.snapshot.account.label).uppercased() } ?? "NO ACCOUNT AVAILABLE")
                        .font(AssistantHUDPalette.display(20, .bold))
                        .kerning(2)
                        .foregroundStyle(best == nil ? AssistantHUDPalette.secondary : AssistantHUDPalette.bright)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(best.map { "HEADROOM · RST \(ThemeText.resetText($0, now: now))" } ?? "STANDBY")
                        .font(AssistantHUDPalette.mono(10))
                        .kerning(1)
                        .foregroundStyle(AssistantHUDPalette.secondary)
                }
                Spacer(minLength: 0)
                Text(best.flatMap(\.headroom).map { "\(Int($0.rounded()))%" } ?? "--")
                    .font(AssistantHUDPalette.mono(38))
                    .foregroundStyle(best == nil ? AssistantHUDPalette.secondary : AssistantHUDPalette.cyan)
                    .shadow(color: AssistantHUDPalette.cyan.opacity(best == nil ? 0 : 0.35), radius: 5)
            }
            if let caution = readout.masterCaution, let window = caution.bindingWindow {
                HStack(spacing: 8) {
                    Text("CRITICAL")
                        .font(AssistantHUDPalette.mono(10))
                        .kerning(1.5)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AssistantHUDPalette.amber, lineWidth: 1))
                    Text("\(caution.snapshot.account.label.uppercased()) AT \(Int(window.usedPercent.rounded()))% OF \(AssistantHUDText.windowName(window).uppercased())")
                        .font(AssistantHUDPalette.mono(11))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(AssistantHUDPalette.amber)
            } else {
                Text("ALL ACCOUNTS NOMINAL · NO LIMIT WARNINGS")
                    .font(AssistantHUDPalette.mono(11))
                    .kerning(1)
                    .foregroundStyle(AssistantHUDPalette.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .hudPanel()
        .accessibilityElement(children: .combine)
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AssistantHUDPanel(index: "01", title: "ACCOUNTS", trailing: "OUTER 5H · INNER WK", spacing: 4) {
                if readout.accounts.isEmpty {
                    AssistantHUDEmpty(text: "NO ACCOUNTS CONFIGURED.")
                }
                ForEach(readout.accounts, id: \.snapshot.id) { account in
                    AssistantHUDAccountRow(
                        account: account,
                        isRoute: account.snapshot.id == readout.bestClaude?.snapshot.id,
                        now: now,
                        gaugeSize: 70
                    )
                }
            }
            nowTasks(now: now)
        }
    }

    private func nowTasks(now: Date) -> some View {
        let tasks = missions.board.tasks(in: .now, now: now)
        return AssistantHUDPanel(
            index: "03",
            title: "NOW QUEUE",
            trailing: "\(tasks.count) ITEMS",
            addHelp: "Add a task",
            add: { editor = .task(MissionTask(title: "")) },
            spacing: 6
        ) {
            if tasks.isEmpty {
                AssistantHUDEmpty(text: "NOTHING IN NOW. OPEN THE DASHBOARD TO PLAN.")
            }
            ForEach(tasks) { task in
                AssistantHUDTaskRow(task: task, missions: missions, editor: $editor, now: now)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                OpenDashboardAction(openWindow: openWindow)()
            } label: {
                Text("OPEN DASHBOARD")
                    .foregroundStyle(AssistantHUDPalette.void)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(AssistantHUDPalette.cyan, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            Button {
                Task { await capacity.refresh() }
            } label: {
                Text(capacity.isRefreshing ? "PROBING" : "RE-PROBE")
                    .hudChip()
            }
            .buttonStyle(.plain)
            .disabled(capacity.isRefreshing)
            .help("Check every account's usage now")
            Spacer(minLength: 0)
            ThemePicker { Text("THEME ▾").hudChip() }
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("QUIT").hudChip()
            }
            .buttonStyle(.plain)
        }
        .font(AssistantHUDPalette.mono(11, .semibold))
        .kerning(1.5)
    }
}

private extension View {
    func hudChip() -> some View {
        foregroundStyle(AssistantHUDPalette.cyan)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AssistantHUDPalette.cyan.opacity(0.5), lineWidth: 1))
            .contentShape(Rectangle())
    }
}
