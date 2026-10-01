import AppKit
import CapacityCore
import SwiftUI

// Departure Board: a railway-station timetable. Accounts are gates on a black
// split-flap board, tasks are departures, projects are lines and objectives
// sit on a printed timetable. Split-flap text is drawn one tile per character.

// MARK: - Palette & type

private enum DepartureBoardPalette {
    static let page = Color(hex: 0xF3F2EE)
    static let ink = Color(hex: 0x141414)
    static let muted = Color(hex: 0x55544E)
    static let faint = Color(hex: 0x8A8982)
    static let boardText = Color(hex: 0xF2F0E8)
    static let boardMuted = Color(hex: 0xB4B3AC)
    static let flap = Color(hex: 0x262624)
    static let flapLine = Color(hex: 0x0A0A0A)
    static let boardRule = Color(hex: 0x3A3A37)
    static let boardRowRule = Color(hex: 0x2A2A28)
    static let lightRule = Color(hex: 0xDCDBD5)
    static let white = Color.white
    static let accent = Color(hex: 0xD5001C)
    static let go = Color(hex: 0x7BE3A3)
    static let amber = Color(hex: 0xFFC845)
    static let stop = Color(hex: 0xFF7A6B)

    /// Schibsted Grotesk stand-in.
    static func grotesk(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Antonio stand-in: tall condensed figures for flaps and big numbers.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    /// IBM Plex Mono stand-in.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

private typealias DBP = DepartureBoardPalette

// MARK: - Shared wording

private enum DepartureBoardText {
    /// "C1", "O1": provider letter plus its position among that provider's accounts.
    static func gate(_ account: AccountReadout, in accounts: [AccountReadout]) -> String {
        let provider = account.snapshot.provider
        let letter: String = switch provider {
        case .anthropic: "C"
        case .openAI: "O"
        case .google: "G"
        case .cursor: "K"
        case .xAI: "X"
        }
        let siblings = accounts.filter { $0.snapshot.provider == provider }
        let index = (siblings.firstIndex { $0.snapshot.id == account.snapshot.id } ?? 0) + 1
        return "\(letter)\(index)"
    }

    /// Account label as it would be set on flaps: "CLAUDE WORK".
    static func flapName(_ account: AccountReadout) -> String {
        account.snapshot.account.label
            .replacingOccurrences(of: " · ", with: " ")
            .replacingOccurrences(of: "·", with: " ")
            .uppercased()
    }

    struct Status {
        let flaps: String
        let color: Color
        let note: String
    }

    static func status(_ account: AccountReadout, isBest: Bool, now: Date) -> Status {
        let snapshot = account.snapshot
        guard account.hasMeasurements, let headroom = account.headroom else {
            switch snapshot.state {
            case .unauthenticated: return Status(flaps: "CHECK-IN", color: DBP.amber, note: snapshot.state.label)
            case .loading: return Status(flaps: "EXPECTED", color: DBP.boardMuted, note: snapshot.state.label)
            case .unavailable: return Status(flaps: "CANCELLED", color: DBP.stop, note: snapshot.state.label)
            case .error, .connected: return Status(flaps: "DIVERTED", color: DBP.stop, note: snapshot.state.label)
            }
        }
        let reset = ThemeText.resetText(account, now: now)
        let stale = snapshot.state == .error ? "Stale · " : ""
        if headroom < 15 {
            return Status(flaps: "DELAYED", color: DBP.stop, note: "\(stale)Delayed — resets \(reset)")
        }
        let note = isBest ? "Recommended · resets \(reset)" : "\(stale)Resets in \(reset)"
        if headroom < 25 { return Status(flaps: "FINAL CALL", color: DBP.amber, note: note) }
        return Status(flaps: "BOARDING", color: DBP.go, note: note)
    }

    static func headroomColor(_ headroom: Double) -> Color {
        headroom < 15 ? DBP.stop : headroom < 25 ? DBP.amber : DBP.boardText
    }

    /// Lane status for a departure.
    static func taskStatus(_ task: MissionTask, now: Date) -> (String, Color) {
        if task.isDone { return ("DEPARTED", DBP.boardMuted) }
        if let due = task.due, due < now, !Calendar.current.isDate(due, inSameDayAs: now) {
            return ("DELAYED", DBP.stop)
        }
        switch task.bucket {
        case .now: return ("BOARDING", DBP.go)
        case .next: return ("ON TIME", DBP.boardText)
        case .later: return ("SCHEDULED", DBP.boardMuted)
        }
    }

    static func timeFlaps(_ task: MissionTask, now: Date) -> String {
        guard let label = ThemeText.dueLabel(task, now: now) else { return "" }
        return label == "OVERDUE" ? "LATE" : label
    }

    static func headerDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE d MMM yyyy"
        return formatter.string(from: date)
    }

    static func clockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Split flaps

/// One character per tile, with the hinge line across the middle.
private struct DepartureBoardFlaps: View {
    let text: String
    let count: Int
    var width: CGFloat = 15
    var height: CGFloat = 24
    var fontSize: CGFloat = 16
    var weight: Font.Weight = .bold
    var color: Color = DBP.boardText
    var radius: CGFloat = 2
    var spacing: CGFloat = 2

    var body: some View {
        let characters = Array(text.uppercased())
        HStack(spacing: spacing) {
            ForEach(0..<max(count, 0), id: \.self) { index in
                let character = index < characters.count ? String(characters[index]) : " "
                ZStack {
                    RoundedRectangle(cornerRadius: radius).fill(DBP.flap)
                    Text(character)
                        .font(DBP.display(fontSize, weight))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Rectangle()
                        .fill(DBP.flapLine)
                        .frame(height: height > 40 ? 2 : 1)
                }
                .frame(width: width, height: height)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(text.trimmingCharacters(in: .whitespaces))
    }
}

/// As many flaps as fit the available width, filled from the left.
private struct DepartureBoardFittedFlaps: View {
    let text: String
    var width: CGFloat = 16
    var height: CGFloat = 26
    var fontSize: CGFloat = 18
    var weight: Font.Weight = .semibold
    var color: Color = DBP.boardText

    var body: some View {
        GeometryReader { proxy in
            let count = max(1, Int((proxy.size.width + 2) / (width + 2)))
            DepartureBoardFlaps(
                text: text,
                count: count,
                width: width,
                height: height,
                fontSize: fontSize,
                weight: weight,
                color: color
            )
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

// MARK: - Chrome

private struct DepartureBoardArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 34
        var path = Path()
        path.move(to: CGPoint(x: 4 * s, y: 17 * s))
        path.addLine(to: CGPoint(x: 26 * s, y: 17 * s))
        path.move(to: CGPoint(x: 18 * s, y: 8 * s))
        path.addLine(to: CGPoint(x: 27 * s, y: 17 * s))
        path.addLine(to: CGPoint(x: 18 * s, y: 26 * s))
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

private struct DepartureBoardArrowTile: View {
    var size: CGFloat = 46
    var background: Color = DBP.accent
    var stroke: Color = .white

    var body: some View {
        DepartureBoardArrow()
            .stroke(stroke, style: StrokeStyle(lineWidth: 4.5 * size / 46, lineCap: .square))
            .frame(width: size * 0.74, height: size * 0.74)
            .frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: size * 0.22))
            .accessibilityHidden(true)
    }
}

/// Numbered section on either the black board or a white printed card.
private struct DepartureBoardSection<Content: View>: View {
    let number: Int
    let title: String
    let subtitle: String
    var note: String?
    let dark: Bool
    var addHelp: String?
    var add: (() -> Void)?
    var padding = EdgeInsets(top: 14, leading: 18, bottom: 16, trailing: 18)
    var spacing: CGFloat = 8
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(DBP.grotesk(13, .black))
                    .foregroundStyle(dark ? DBP.ink : DBP.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(dark ? DBP.boardText : DBP.ink, in: RoundedRectangle(cornerRadius: 5))
                Text(title).font(DBP.grotesk(19, .heavy))
                Text(subtitle)
                    .font(DBP.grotesk(15, .medium))
                    .foregroundStyle(dark ? DBP.boardMuted : DBP.muted)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let note {
                    Text(note)
                        .font(DBP.mono(11))
                        .foregroundStyle(dark ? DBP.boardMuted : DBP.muted)
                        .lineLimit(1)
                }
                if let add, let addHelp {
                    Button(action: add) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 10, weight: .heavy))
                            Text("Add").font(DBP.grotesk(12, .heavy))
                        }
                        .foregroundStyle(dark ? DBP.ink : DBP.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(dark ? DBP.boardText : DBP.ink, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(addHelp)
                    .accessibilityLabel(addHelp)
                }
            }
            .frame(minHeight: 28)
            content
        }
        .foregroundStyle(dark ? DBP.boardText : DBP.ink)
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(dark ? DBP.ink : DBP.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            if !dark { RoundedRectangle(cornerRadius: 16).stroke(DBP.ink, lineWidth: 2) }
        }
    }
}

/// Scrolls in the live window, lays out flat for the renderer.
private struct DepartureBoardScroll<Content: View>: View {
    let staticLayout: Bool
    var spacing: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        if staticLayout {
            VStack(alignment: .leading, spacing: spacing) { content }
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
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

/// The station clock, hands at the given time.
private struct DepartureBoardClock: View {
    let date: Date
    var size: CGFloat = 46

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 100
            let c = CGPoint(x: 50 * s, y: 50 * s)
            func rotated(_ path: Path, _ degrees: Double) -> Path {
                path.applying(
                    CGAffineTransform(translationX: c.x, y: c.y)
                        .rotated(by: degrees * .pi / 180)
                        .translatedBy(x: -c.x, y: -c.y)
                )
            }
            let face = Path(ellipseIn: CGRect(x: 2 * s, y: 2 * s, width: 96 * s, height: 96 * s))
            context.fill(face, with: .color(.white))
            context.stroke(face, with: .color(DBP.ink), lineWidth: 3 * s)
            for i in 0..<60 {
                let major = i % 5 == 0
                var tick = Path()
                tick.move(to: CGPoint(x: c.x, y: (major ? 20 : 14) * s))
                tick.addLine(to: CGPoint(x: c.x, y: 10 * s))
                context.stroke(rotated(tick, Double(i * 6)), with: .color(DBP.ink), lineWidth: (major ? 4 : 1.4) * s)
            }
            let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let h = Double(parts.hour ?? 0), m = Double(parts.minute ?? 0), sec = Double(parts.second ?? 0)
            context.fill(rotated(Path(CGRect(x: 47 * s, y: 24 * s, width: 6 * s, height: 30 * s)), (h.truncatingRemainder(dividingBy: 12) + m / 60) * 30), with: .color(DBP.ink))
            context.fill(rotated(Path(CGRect(x: 48 * s, y: 12 * s, width: 4 * s, height: 42 * s)), m * 6 + sec / 10), with: .color(DBP.ink))
            var second = Path()
            second.move(to: CGPoint(x: c.x, y: 62 * s))
            second.addLine(to: CGPoint(x: c.x, y: 22 * s))
            context.stroke(rotated(second, sec * 6), with: .color(DBP.accent), lineWidth: 1.6 * s)
            context.fill(rotated(Path(ellipseIn: CGRect(x: 45 * s, y: 17 * s, width: 10 * s, height: 10 * s)), sec * 6), with: .color(DBP.accent))
            context.fill(Path(ellipseIn: CGRect(x: 48 * s, y: 48 * s, width: 4 * s, height: 4 * s)), with: .color(DBP.ink))
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Station clock")
        .accessibilityValue(DepartureBoardText.clockTime(date))
    }
}

/// Square checkbox in the accent colour, for ticking a departure off.
private struct DepartureBoardCheckStyle: ToggleStyle {
    var size: CGFloat = 17
    var offStroke: Color = DBP.boardMuted

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(configuration.isOn ? DBP.accent : Color.clear)
                RoundedRectangle(cornerRadius: 3)
                    .stroke(configuration.isOn ? DBP.accent : offStroke, lineWidth: 1.5)
                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.6, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Departed" : "Not departed")
    }
}

// MARK: - Dashboard

struct DepartureBoardDashboardView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    var staticLayout = false

    @State private var editor: MissionEditor?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        VStack(spacing: 18) {
            header
            GeometryReader { proxy in
                let right = min(max(proxy.size.width * 0.328, 380), 452)
                HStack(alignment: .top, spacing: 24) {
                    VStack(spacing: 14) {
                        DepartureBoardGates(readout: readout)
                        HStack(spacing: 14) {
                            DepartureBoardRouteBar(readout: readout, compact: false)
                            DepartureBoardNotice(readout: readout, compact: false)
                                .frame(width: 250)
                        }
                        .frame(height: 60)
                        DepartureBoardDepartures(missions: missions, editor: $editor, staticLayout: staticLayout)
                            .frame(minHeight: 0, maxHeight: .infinity)
                            .layoutPriority(-1)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    VStack(spacing: 14) {
                        DepartureBoardLines(missions: missions, editor: $editor, staticLayout: staticLayout)
                        DepartureBoardTimetable(missions: missions, editor: $editor, staticLayout: staticLayout)
                            .frame(minHeight: 0, maxHeight: .infinity)
                            .layoutPriority(-1)
                    }
                    .frame(width: right)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .padding(EdgeInsets(top: 22, leading: 32, bottom: 24, trailing: 32))
        .background(DBP.page)
        .foregroundStyle(DBP.ink)
        .missionEditorSheet($editor, missions: missions)
    }

    // MARK: Header

    private var header: some View {
        TimelineView(.periodic(from: .now, by: staticLayout ? 3_600 : 1)) { context in
            HStack(alignment: .center, spacing: 24) {
                HStack(spacing: 16) {
                    DepartureBoardArrowTile()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mission Control")
                            .font(DBP.grotesk(32, .black))
                            .kerning(-0.8)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Text("Departures")
                            Text("/").foregroundStyle(DBP.faint)
                            Text("Capacity")
                            Text("/").foregroundStyle(DBP.faint)
                            Text(DepartureBoardText.headerDate(context.date))
                        }
                        .font(DBP.grotesk(14, .medium))
                        .foregroundStyle(DBP.muted)
                        .lineLimit(1)
                    }
                    .fixedSize()
                }
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 30) {
                    stat("DEPARTURES", "\(missions.board.openTaskCount) scheduled · \(missions.board.dueTodayCount(now: context.date)) today")
                    stat("NEXT RESET", nextReset(now: context.date))
                    HStack(spacing: 12) {
                        DepartureBoardClock(date: context.date)
                        Text(DepartureBoardText.clockTime(context.date))
                            .font(DBP.display(36, .bold))
                            .monospacedDigit()
                    }
                    controls(now: context.date)
                }
                .fixedSize()
            }
            .padding(.bottom, 12)
            .frame(height: 64)
            .overlay(alignment: .bottom) { Rectangle().fill(DBP.ink).frame(height: 3) }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(DBP.mono(11)).kerning(1).foregroundStyle(DBP.muted)
            Text(value).font(DBP.grotesk(16, .bold)).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func controls(now: Date) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(ThemeText.probedLabel(capacity.lastRefresh, now: now))
                .font(DBP.mono(10.5))
                .kerning(0.5)
                .foregroundStyle(DBP.muted)
            HStack(spacing: 6) {
                Button {
                    Task { await capacity.refresh() }
                } label: {
                    Text(capacity.isRefreshing ? "Probing…" : "Re-probe")
                        .font(DBP.grotesk(12, .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(capacity.isRefreshing ? DBP.muted : DBP.ink, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(capacity.isRefreshing)
                .help("Check every account's usage now")
                ThemePicker {
                    Text("Theme ▾")
                        .font(DBP.grotesk(12, .heavy))
                        .foregroundStyle(DBP.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .overlay(Capsule().stroke(DBP.ink, lineWidth: 1.5))
                }
            }
        }
    }

    private func nextReset(now: Date) -> String {
        let accounts = readout.accounts
        let soonest = accounts
            .filter { $0.hasMeasurements }
            .compactMap { account -> (AccountReadout, Date)? in
                guard let reset = account.bindingWindow?.resetsAt, reset > now else { return nil }
                return (account, reset)
            }
            .min { $0.1 < $1.1 }
        guard let (account, _) = soonest else { return "—" }
        return "Gate \(DepartureBoardText.gate(account, in: accounts)) · \(ThemeText.resetText(account, now: now))"
    }
}

// MARK: - Gates (accounts)

private struct DepartureBoardGates: View {
    let readout: CockpitReadout

    private let gateWidth: CGFloat = 52
    private let usedWidth: CGFloat = 150
    private let headroomWidth: CGFloat = 120
    private let statusWidth: CGFloat = 176

    var body: some View {
        DepartureBoardSection(
            number: 1,
            title: "Gates",
            subtitle: "AI capacity by account",
            note: "HEADROOM = 100 − MAX(5H, WEEK)",
            dark: true
        ) {
            HStack(spacing: 16) {
                Text("GATE").frame(width: gateWidth, alignment: .leading)
                Text("ACCOUNT").frame(maxWidth: .infinity, alignment: .leading)
                Text("USED 5H / WEEK").frame(width: usedWidth, alignment: .leading)
                Text("HEADROOM").frame(width: headroomWidth, alignment: .leading)
                Text("STATUS").frame(width: statusWidth, alignment: .leading)
            }
            .font(DBP.mono(10.5))
            .kerning(1)
            .foregroundStyle(DBP.boardMuted)
            .lineLimit(1)
            .padding(.bottom, 5)
            .overlay(alignment: .bottom) { Rectangle().fill(DBP.boardRule).frame(height: 1) }

            if readout.accounts.isEmpty {
                Text("No gates open. Add an account to accounts.json to see its capacity here.")
                    .font(DBP.grotesk(13, .medium))
                    .foregroundStyle(DBP.boardMuted)
                    .padding(.vertical, 12)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(spacing: 0) {
                    ForEach(readout.accounts, id: \.snapshot.id) { account in
                        row(account, now: context.date)
                    }
                }
            }
        }
    }

    private func row(_ account: AccountReadout, now: Date) -> some View {
        let snapshot = account.snapshot
        let isBest = snapshot.id == readout.bestClaude?.snapshot.id
        let status = DepartureBoardText.status(account, isBest: isBest, now: now)
        return HStack(spacing: 16) {
            Text(DepartureBoardText.gate(account, in: readout.accounts))
                .font(DBP.grotesk(19, .black))
                .foregroundStyle(isBest ? DBP.white : DBP.ink)
                .frame(width: 46, height: 46)
                .background(isBest ? DBP.accent : DBP.boardText, in: RoundedRectangle(cornerRadius: 8))
                .frame(width: gateWidth, alignment: .leading)
                .accessibilityLabel("Gate \(DepartureBoardText.gate(account, in: readout.accounts))")
            VStack(alignment: .leading, spacing: 5) {
                DepartureBoardFittedFlaps(text: DepartureBoardText.flapName(account))
                    .help(ThemeText.guide(snapshot.provider))
                Text(ThemeText.identityLine(account))
                    .font(DBP.grotesk(12))
                    .foregroundStyle(snapshot.state == .error && account.hasMeasurements ? DBP.amber : DBP.boardMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if account.hasMeasurements {
                VStack(alignment: .leading, spacing: 6) {
                    usageLine("5H", account.fiveHour?.usedPercent)
                    usageLine("WK", account.weekly?.usedPercent)
                }
                .frame(width: usedWidth, alignment: .leading)
                headroom(account)
                    .frame(width: headroomWidth, alignment: .leading)
            } else {
                Text(snapshot.message ?? "No usage reported yet.")
                    .font(DBP.mono(10.5))
                    .foregroundStyle(DBP.boardText)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .frame(width: usedWidth + headroomWidth + 16, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 5) {
                DepartureBoardFlaps(text: status.flaps, count: 10, width: 15.6, height: 24, fontSize: 16, color: status.color)
                Text(status.note)
                    .font(DBP.mono(11))
                    .foregroundStyle(DBP.boardMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: statusWidth, alignment: .leading)
        }
        .padding(.vertical, 7)
        .frame(minHeight: 60)
        .overlay(alignment: .bottom) { Rectangle().fill(DBP.boardRowRule).frame(height: 1) }
    }

    private func usageLine(_ title: String, _ value: Double?) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(DBP.boardMuted).frame(width: 22, alignment: .leading)
            HStack(spacing: 2) {
                let lit = Int(((value ?? 0) / 10).rounded())
                ForEach(0..<10, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(index < lit ? ((value ?? 0) >= 85 ? DBP.amber : DBP.boardText) : DBP.boardRule)
                        .frame(width: 7, height: 11)
                }
            }
            .frame(width: 88, alignment: .leading)
            Text(value.map { "\(Int($0.rounded()))%" } ?? "--")
                .foregroundStyle(value == nil ? DBP.boardMuted : DBP.boardText)
                .frame(width: 30, alignment: .trailing)
        }
        .font(DBP.mono(11))
        .accessibilityElement()
        .accessibilityLabel(title == "5H" ? "5 hour window" : "Weekly window")
        .accessibilityValue(value.map { "\(Int($0.rounded())) percent used" } ?? "No data")
    }

    private func headroom(_ account: AccountReadout) -> some View {
        let value = Int((account.headroom ?? 0).rounded())
        let text = String(value)
        let digits = max(2, text.count)
        let padded = String(repeating: " ", count: digits - text.count) + text
        return HStack(alignment: .bottom, spacing: 3) {
            DepartureBoardFlaps(
                text: padded,
                count: digits,
                width: digits > 2 ? 34 : 40,
                height: 54,
                fontSize: 46,
                weight: .bold,
                color: DepartureBoardText.headroomColor(account.headroom ?? 0),
                radius: 4,
                spacing: 3
            )
            Text("%")
                .font(DBP.display(18, .semibold))
                .foregroundStyle(DBP.boardMuted)
                .padding(.bottom, 4)
        }
        .accessibilityElement()
        .accessibilityLabel("Headroom")
        .accessibilityValue("\(value) percent")
    }
}

// MARK: - Route & notice

private struct DepartureBoardRouteBar: View {
    let readout: CockpitReadout
    let compact: Bool

    var body: some View {
        let best = readout.bestClaude
        let foreground = best == nil ? DBP.boardText : DBP.white
        HStack(spacing: compact ? 10 : 16) {
            DepartureBoardArrowTile(size: compact ? 32 : 40, background: .white, stroke: DBP.ink)
            VStack(alignment: .leading, spacing: 1) {
                Text(best == nil ? "No Claude account available" : "Route next Claude session to")
                    .font(DBP.grotesk(compact ? 11 : 13, .medium))
                if let best {
                    HStack(spacing: 0) {
                        Text(best.snapshot.account.label).font(DBP.grotesk(compact ? 16 : 22, .black))
                        Text(" · Gate \(DepartureBoardText.gate(best, in: readout.accounts))")
                            .font(DBP.grotesk(compact ? 16 : 22, .medium))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                } else {
                    Text("Sign in a Claude account to board")
                        .font(DBP.grotesk(compact ? 14 : 18, .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 4)
            if let best {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(Int((best.headroom ?? 0).rounded()))%")
                            .font(DBP.display(compact ? 22 : 30, .bold))
                        Text("headroom · resets \(ThemeText.resetText(best, now: context.date))")
                            .font(DBP.mono(compact ? 9.5 : 11))
                            .lineLimit(1)
                    }
                }
                .fixedSize()
            }
        }
        .foregroundStyle(foreground)
        .padding(.leading, 14)
        .padding(.trailing, compact ? 12 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(best == nil ? DBP.boardRule : DBP.accent, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

/// Master caution as a station service notice.
private struct DepartureBoardNotice: View {
    let readout: CockpitReadout
    let compact: Bool

    var body: some View {
        let caution = readout.masterCaution
        Group {
            if compact {
                HStack(spacing: 8) {
                    Image(systemName: caution == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("SERVICE NOTICE").font(DBP.mono(10, .semibold)).kerning(1)
                    Text(detail).font(DBP.grotesk(12.5, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 30)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: caution == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("SERVICE NOTICE").font(DBP.mono(11, .semibold)).kerning(1)
                    }
                    Text(detail)
                        .font(DBP.grotesk(16, .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(DBP.ink)
        .background(caution == nil ? DBP.white : DBP.amber, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DBP.ink, lineWidth: 2))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Master caution")
        .accessibilityValue(detail)
    }

    private var detail: String {
        guard let caution = readout.masterCaution, let window = caution.bindingWindow else {
            return "Good service on all gates"
        }
        let name = window.durationMinutes == 300 ? "5H" : "week"
        return "Gate \(DepartureBoardText.gate(caution, in: readout.accounts)) delayed · \(name) \(Int(window.usedPercent.rounded()))%"
    }
}

// MARK: - Departures (tasks)

private struct DepartureBoardDepartures: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let staticLayout: Bool

    var body: some View {
        DepartureBoardSection(
            number: 2,
            title: "Departures",
            subtitle: "Tasks · Now, Next, Later",
            note: "TICK TO MARK DEPARTED",
            dark: true,
            addHelp: "Add a task",
            add: { editor = .task(MissionTask(title: "")) },
            padding: EdgeInsets(top: 14, leading: 18, bottom: 12, trailing: 18),
            spacing: 6
        ) {
            HStack(spacing: 14) {
                Text("TIME").frame(width: 100, alignment: .leading)
                Text("PLAT.").frame(width: 58, alignment: .leading)
                Text("DEPARTURE").frame(maxWidth: .infinity, alignment: .leading)
                Text("DESTINATION").frame(width: 140, alignment: .leading)
                Text("STATUS").frame(width: 133, alignment: .leading)
                Color.clear.frame(width: 20, height: 1)
            }
            .font(DBP.mono(10.5))
            .kerning(1)
            .foregroundStyle(DBP.boardMuted)
            .lineLimit(1)
            .padding(.bottom, 5)
            .overlay(alignment: .bottom) { Rectangle().fill(DBP.boardRule).frame(height: 1) }

            TimelineView(.periodic(from: .now, by: 60)) { context in
                let tasks = TaskBucket.allCases.flatMap { missions.board.tasks(in: $0, now: context.date) }
                DepartureBoardScroll(staticLayout: staticLayout) {
                    if tasks.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            DepartureBoardFlaps(text: "NO SERVICE", count: 10)
                            Text("No departures scheduled. Use Add to put a task on the board.")
                                .font(DBP.grotesk(13, .medium))
                                .foregroundStyle(DBP.boardMuted)
                        }
                        .padding(.vertical, 10)
                    }
                    ForEach(tasks) { task in
                        DepartureBoardTaskRow(task: task, missions: missions, editor: $editor, now: context.date)
                    }
                }
            }
        }
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
        .background(DBP.ink, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct DepartureBoardTaskRow: View {
    let task: MissionTask
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let now: Date

    var body: some View {
        let status = DepartureBoardText.taskStatus(task, now: now)
        HStack(spacing: 14) {
            DepartureBoardFlaps(text: DepartureBoardText.timeFlaps(task, now: now), count: 6, width: 15, height: 24, fontSize: 16, weight: .semibold)
                .frame(width: 100, alignment: .leading)
            platform
            Text(task.title)
                .font(DBP.grotesk(14.5, .semibold))
                .strikethrough(task.isDone, color: DBP.boardMuted)
                .foregroundStyle(task.isDone ? DBP.boardMuted : DBP.boardText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(missions.board.project(for: task)?.name.uppercased() ?? "—")
                .font(DBP.display(16, .semibold))
                .kerning(0.6)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
            DepartureBoardFlaps(text: status.0, count: 9, width: 13, height: 22, fontSize: 14, color: status.1)
                .frame(width: 133, alignment: .leading)
            Toggle(isOn: doneBinding(task, missions: missions)) { Text(task.title) }
                .toggleStyle(DepartureBoardCheckStyle())
                .accessibilityLabel(task.title)
                .frame(width: 20)
        }
        .frame(height: 34)
        .overlay(alignment: .bottom) { Rectangle().fill(DBP.boardRowRule).frame(height: 1) }
        .taskActions(task, missions: missions, editor: $editor)
    }

    private var platform: some View {
        let colors: (Color, Color) = switch task.bucket {
        case .now: (DBP.accent, DBP.white)
        case .next: (DBP.boardText, DBP.ink)
        case .later: (DBP.boardRule, DBP.boardText)
        }
        return Text(task.bucket.title)
            .font(DBP.grotesk(11, .heavy))
            .kerning(0.8)
            .foregroundStyle(colors.1)
            .frame(width: 58)
            .padding(.vertical, 3)
            .background(colors.0, in: RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Lines (projects)

private struct DepartureBoardLines: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let staticLayout: Bool

    var body: some View {
        let projects = missions.board.projects
        DepartureBoardSection(
            number: 3,
            title: "Lines",
            subtitle: "Projects",
            dark: false,
            addHelp: "Add a project",
            add: { editor = .project(MissionProject(name: "")) },
            spacing: 10
        ) {
            if projects.isEmpty {
                Text("No lines in service yet. Use Add to open your first project.")
                    .font(DBP.grotesk(13, .medium))
                    .foregroundStyle(DBP.muted)
                    .padding(.top, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Rectangle().fill(DBP.lightRule).frame(height: 1) }
            } else if projects.count > 5 {
                DepartureBoardScroll(staticLayout: staticLayout, spacing: 10) { rows(projects) }
                    .frame(height: 330)
            } else {
                rows(projects)
            }
        }
    }

    @ViewBuilder
    private func rows(_ projects: [MissionProject]) -> some View {
        ForEach(projects) { project in
            row(project).projectActions(project, missions: missions, editor: $editor)
        }
    }

    private func row(_ project: MissionProject) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(DepartureBoardText.initials(project.name))
                .font(DBP.grotesk(12, .black))
                .kerning(0.3)
                .foregroundStyle(DBP.white)
                .frame(width: 32, height: 32)
                .background(DBP.ink, in: Circle())
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(project.name).font(DBP.grotesk(15, .heavy)).lineLimit(1)
                    Text(project.phase.uppercased())
                        .font(DBP.mono(10, .semibold))
                        .kerning(1)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .overlay(Capsule().stroke(DBP.ink, lineWidth: 1.5))
                        .fixedSize()
                    Spacer(minLength: 4)
                    Text("\(Int(project.progress.rounded()))%").font(DBP.display(20, .bold))
                }
                GeometryReader { proxy in
                    let width = proxy.size.width * min(max(project.progress, 0), 100) / 100
                    ZStack(alignment: .leading) {
                        Capsule().fill(DBP.lightRule)
                        Capsule().fill(DBP.ink).frame(width: width)
                        Circle()
                            .fill(DBP.white)
                            .overlay(Circle().stroke(DBP.accent, lineWidth: 2))
                            .frame(width: 10, height: 10)
                            .offset(x: width - 7)
                    }
                }
                .frame(height: 6)
                .padding(.vertical, 2)
                .padding(.trailing, 7)
                .accessibilityElement()
                .accessibilityLabel("Progress")
                .accessibilityValue("\(Int(project.progress.rounded())) percent")
                HStack(spacing: 4) {
                    Text("Next stop:").foregroundStyle(DBP.muted)
                    Text(project.nextAction.isEmpty ? "—" : project.nextAction).fontWeight(.semibold)
                }
                .font(DBP.grotesk(12.5))
                .lineLimit(1)
            }
        }
        .padding(.top, 9)
        .overlay(alignment: .top) { Rectangle().fill(DBP.lightRule).frame(height: 1) }
    }
}

// MARK: - Timetable (objectives)

private struct DepartureBoardTimetable: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let staticLayout: Bool

    var body: some View {
        let objectives = missions.board.objectives
        DepartureBoardSection(
            number: 4,
            title: "Timetable",
            subtitle: "Objectives \(missions.board.periodTitle)",
            dark: false,
            addHelp: "Add an objective",
            add: { editor = .objective(MissionObjective(title: "")) },
            spacing: 10
        ) {
            DepartureBoardScroll(staticLayout: staticLayout, spacing: 7) {
                if objectives.isEmpty {
                    Text("Nothing on the \(missions.board.periodTitle) timetable yet. Use Add to set an objective.")
                        .font(DBP.grotesk(13, .medium))
                        .foregroundStyle(DBP.muted)
                        .padding(.top, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) { Rectangle().fill(DBP.lightRule).frame(height: 1) }
                }
                ForEach(objectives) { objective in
                    row(objective).objectiveActions(objective, missions: missions, editor: $editor)
                }
            }
        }
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
        .background(DBP.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private func row(_ objective: MissionObjective) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(objective.title)
                    .font(DBP.grotesk(14.5, .heavy))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(Int(objective.progress.rounded()))%").font(DBP.display(26, .bold))
            }
            HStack(spacing: 2) {
                let lit = Int((objective.progress / 5).rounded())
                ForEach(0..<20, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(index < lit ? DBP.ink : DBP.lightRule)
                        .frame(maxWidth: .infinity)
                        .frame(height: 9)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue("\(Int(objective.progress.rounded())) percent")
            if !objective.summary.isEmpty {
                Text(objective.summary).font(DBP.mono(11)).foregroundStyle(DBP.muted)
            }
        }
        .padding(.top, 7)
        .overlay(alignment: .top) { Rectangle().fill(DBP.lightRule).frame(height: 1) }
    }
}

// MARK: - Menu

struct DepartureBoardMenuView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    var staticLayout = false
    @Environment(\.openWindow) private var openWindow
    @State private var editor: MissionEditor?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        VStack(spacing: 10) {
            header
            DepartureBoardRouteBar(readout: readout, compact: true).frame(height: 50)
            DepartureBoardNotice(readout: readout, compact: true)
            if staticLayout {
                content
            } else {
                ScrollView { content }.scrollIndicators(.never)
            }
            footer
        }
        .padding(12)
        .background(DBP.page)
        .foregroundStyle(DBP.ink)
        .missionEditorSheet($editor, missions: missions)
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: staticLayout ? 3_600 : 1)) { context in
            HStack(spacing: 10) {
                DepartureBoardArrowTile(size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Mission Control").font(DBP.grotesk(18, .black)).kerning(-0.4)
                    Text("Departures · \(DepartureBoardText.headerDate(context.date))")
                        .font(DBP.grotesk(11.5, .medium))
                        .foregroundStyle(DBP.muted)
                }
                Spacer(minLength: 4)
                DepartureBoardClock(date: context.date, size: 28)
                Text(DepartureBoardText.clockTime(context.date))
                    .font(DBP.display(24, .bold))
                    .monospacedDigit()
            }
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(DBP.ink).frame(height: 2) }
        }
    }

    private var content: some View {
        VStack(spacing: 10) {
            gates
            nowDepartures
        }
    }

    private var gates: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Gates").font(DBP.grotesk(15, .heavy))
                    Spacer()
                    Text("HEADROOM").font(DBP.mono(9.5)).kerning(1).foregroundStyle(DBP.boardMuted)
                }
                .padding(.bottom, 4)
                if readout.accounts.isEmpty {
                    Text("No gates open. Add an account to accounts.json.")
                        .font(DBP.grotesk(12, .medium))
                        .foregroundStyle(DBP.boardMuted)
                        .padding(.vertical, 6)
                }
                ForEach(readout.accounts, id: \.snapshot.id) { account in
                    gateRow(account, now: context.date)
                }
            }
            .foregroundStyle(DBP.boardText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(DBP.ink, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func gateRow(_ account: AccountReadout, now: Date) -> some View {
        let isBest = account.snapshot.id == readout.bestClaude?.snapshot.id
        let status = DepartureBoardText.status(account, isBest: isBest, now: now)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(DepartureBoardText.gate(account, in: readout.accounts))
                    .font(DBP.grotesk(14, .black))
                    .foregroundStyle(isBest ? DBP.white : DBP.ink)
                    .frame(width: 34, height: 34)
                    .background(isBest ? DBP.accent : DBP.boardText, in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 3) {
                    DepartureBoardFittedFlaps(text: DepartureBoardText.flapName(account), width: 13, height: 20, fontSize: 14)
                    Text(ThemeText.identityLine(account))
                        .font(DBP.grotesk(10.5))
                        .foregroundStyle(account.snapshot.state == .error && account.hasMeasurements ? DBP.amber : DBP.boardMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if account.hasMeasurements {
                    let value = Int((account.headroom ?? 0).rounded())
                    let text = String(value)
                    let digits = max(2, text.count)
                    DepartureBoardFlaps(
                        text: String(repeating: " ", count: digits - text.count) + text,
                        count: digits,
                        width: 24,
                        height: 34,
                        fontSize: 28,
                        color: DepartureBoardText.headroomColor(account.headroom ?? 0),
                        radius: 3
                    )
                    .accessibilityLabel("Headroom \(value) percent")
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                DepartureBoardFlaps(text: status.flaps, count: 10, width: 11, height: 18, fontSize: 12, color: status.color)
                if account.hasMeasurements {
                    Text("5H \(account.fiveHour.map { "\(Int($0.usedPercent.rounded()))%" } ?? "--") · WK \(account.weekly.map { "\(Int($0.usedPercent.rounded()))%" } ?? "--") · \(status.note)")
                        .font(DBP.mono(9.5))
                        .foregroundStyle(DBP.boardMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text(status.note).font(DBP.mono(9.5)).foregroundStyle(DBP.boardMuted)
                }
            }
            .padding(.leading, 44)
            if !account.hasMeasurements {
                Text(account.snapshot.message ?? "No usage reported yet.")
                    .font(DBP.mono(9.5))
                    .foregroundStyle(DBP.boardText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 44)
            }
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) { Rectangle().fill(DBP.boardRowRule).frame(height: 1) }
    }

    private var nowDepartures: some View {
        let tasks = missions.board.tasks(in: .now)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Now boarding").font(DBP.grotesk(15, .heavy))
                Text("\(tasks.count) departure\(tasks.count == 1 ? "" : "s")")
                    .font(DBP.grotesk(12, .medium))
                    .foregroundStyle(DBP.boardMuted)
                Spacer()
                Button {
                    editor = .task(MissionTask(title: ""))
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(DBP.ink)
                        .frame(width: 22, height: 18)
                        .background(DBP.boardText, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Add a task")
                .accessibilityLabel("Add a task")
            }
            .padding(.bottom, 4)
            if tasks.isEmpty {
                Text("Nothing boarding now. Open the dashboard to plan.")
                    .font(DBP.grotesk(12, .medium))
                    .foregroundStyle(DBP.boardMuted)
                    .padding(.vertical, 6)
            }
            ForEach(tasks) { task in
                HStack(spacing: 10) {
                    DepartureBoardFlaps(text: DepartureBoardText.timeFlaps(task, now: Date()), count: 5, width: 12, height: 20, fontSize: 13, weight: .semibold)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(task.title)
                            .font(DBP.grotesk(13, .semibold))
                            .strikethrough(task.isDone, color: DBP.boardMuted)
                            .foregroundStyle(task.isDone ? DBP.boardMuted : DBP.boardText)
                            .lineLimit(1)
                        if let project = missions.board.project(for: task) {
                            Text(project.name.uppercased())
                                .font(DBP.display(11.5, .semibold))
                                .kerning(0.5)
                                .foregroundStyle(DBP.boardMuted)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Toggle(isOn: doneBinding(task, missions: missions)) { Text(task.title) }
                        .toggleStyle(DepartureBoardCheckStyle())
                        .accessibilityLabel(task.title)
                }
                .padding(.vertical, 6)
                .overlay(alignment: .top) { Rectangle().fill(DBP.boardRowRule).frame(height: 1) }
                .taskActions(task, missions: missions, editor: $editor)
            }
        }
        .foregroundStyle(DBP.boardText)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DBP.ink, in: RoundedRectangle(cornerRadius: 14))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button { OpenDashboardAction(openWindow: openWindow)() } label: {
                pill("Open dashboard", filled: true)
            }
            .buttonStyle(.plain)
            Button { Task { await capacity.refresh() } } label: {
                pill(capacity.isRefreshing ? "Probing…" : "Re-probe", filled: false)
            }
            .buttonStyle(.plain)
            .disabled(capacity.isRefreshing)
            .help(ThemeText.probedLabel(capacity.lastRefresh, now: Date()))
            ThemePicker { pill("Theme ▾", filled: false) }
            Spacer(minLength: 0)
            Button { NSApp.terminate(nil) } label: { pill("Quit", filled: false) }
                .buttonStyle(.plain)
        }
    }

    private func pill(_ title: String, filled: Bool) -> some View {
        Text(title)
            .font(DBP.grotesk(12, .heavy))
            .foregroundStyle(filled ? DBP.white : DBP.ink)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(filled ? DBP.ink : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(DBP.ink, lineWidth: 1.5))
            .contentShape(Capsule())
    }
}
