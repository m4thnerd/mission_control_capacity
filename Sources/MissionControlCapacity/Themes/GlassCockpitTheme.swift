import AppKit
import CapacityCore
import SwiftUI

// Glass Cockpit: black display units set in grey bezels, EICAS round dials and
// vertical tapes for each account, an ND-style flight plan of projects, ring
// gauges for objectives and an ECAM checklist for tasks.

// MARK: - Palette & type

private enum GlassCockpitPalette {
    static let background = Color(hex: 0x14171A)
    static let bezel = Color(hex: 0x22262B)
    static let screen = Color(hex: 0x050708)
    static let white = Color(hex: 0xF4F6F8)
    static let grey = Color(hex: 0x9AA3AD)
    static let cyan = Color(hex: 0x3FD0F0)
    static let green = Color(hex: 0x3EE07A)
    static let amber = Color(hex: 0xFFB020)
    static let magenta = Color(hex: 0xFF4FD8)
    static let rule = Color(hex: 0x3A4047)
    static let divider = Color(hex: 0x2A3138)
    static let rowRule = Color(hex: 0x1C2329)
    static let ringTrack = Color(hex: 0x1F272E)
    static let sector = Color(hex: 0x1C252D)
    static let tapeFill = Color(hex: 0x0E1418)
    static let lamp = Color(hex: 0x4A525B)
    static let key = Color(hex: 0x2E343B)

    /// B612 stand-in: the plain system sans.
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// B612 Mono stand-in.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Green in the normal band, amber from the caution line up.
    static func tone(_ percent: Double) -> Color {
        percent >= AccountReadout.cautionThreshold ? amber : green
    }
}

private typealias GCP = GlassCockpitPalette

// MARK: - Dashboard

struct GlassCockpitDashboardView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    var staticLayout = false

    @State private var editor: MissionEditor?
    @State private var acknowledgedCaution: String?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        VStack(spacing: 14) {
            header.frame(height: 56)
            GlassCockpitAccountRows(readout: readout, compact: false)
            GeometryReader { proxy in
                // Columns share the width 520 : 400 : 452, as on the approved design.
                let unit = (proxy.size.width - 28) / 1372
                HStack(alignment: .top, spacing: 14) {
                    GlassCockpitProjectsUnit(missions: missions, editor: $editor, staticLayout: staticLayout)
                        .frame(width: unit * 520)
                    GlassCockpitObjectivesUnit(missions: missions, editor: $editor, staticLayout: staticLayout)
                        .frame(width: unit * 400)
                    GlassCockpitChecklistUnit(missions: missions, editor: $editor, staticLayout: staticLayout)
                        .frame(width: unit * 452)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(20)
        .background(GCP.background)
        .foregroundStyle(GCP.white)
        .missionEditorSheet($editor, missions: missions)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            titleBlock.frame(width: 232, alignment: .leading)
            statusStrip
            GlassCockpitCautionKey(
                caution: readout.masterCaution,
                acknowledged: readout.masterCaution.map { cautionKey($0) == acknowledgedCaution } ?? false,
                compact: false
            ) {
                acknowledgedCaution = readout.masterCaution.map(cautionKey)
            }
            .frame(width: 210)
        }
    }

    private func cautionKey(_ account: AccountReadout) -> String {
        "\(account.snapshot.id)-\(Int(account.peakUsed ?? 0))"
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MISSION CONTROL")
                .font(GCP.sans(20, .bold))
                .kerning(3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            ThemePicker {
                Text("GLASS COCKPIT · FLT DAY \(dayOfYear) ▾")
                    .font(GCP.mono(10))
                    .kerning(1.5)
                    .foregroundStyle(GCP.grey)
            }
        }
        .padding(.leading, 4)
    }

    private var dayOfYear: Int {
        Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
    }

    private var statusStrip: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 0) {
                stripCell("DATE") {
                    Text(ThemeText.plateDate(context.date))
                }
                stripDivider
                stripCell("TASKS") {
                    HStack(spacing: 0) {
                        Text("\(missions.board.openTaskCount) OPEN · ")
                        Text("\(missions.board.dueTodayCount(now: context.date)) TODAY").foregroundStyle(GCP.amber)
                    }
                }
                stripDivider
                stripCell("OBJ \(missions.board.periodTitle.uppercased()) AVG") {
                    Text(objectiveAverage.map { "\($0)%" } ?? "--")
                        .foregroundStyle(objectiveAverage == nil ? GCP.grey : GCP.green)
                }
                stripDivider
                VStack(alignment: .leading, spacing: 3) {
                    Text(ThemeText.probedLabel(capacity.lastRefresh, now: context.date))
                        .font(GCP.mono(9.5))
                        .kerning(1.5)
                        .foregroundStyle(GCP.cyan)
                        .lineLimit(1)
                    Button {
                        Task { await capacity.refresh() }
                    } label: {
                        Text(capacity.isRefreshing ? "PROBING…" : "RE-PROBE")
                            .font(GCP.mono(10.5, .bold))
                            .kerning(1)
                            .foregroundStyle(capacity.isRefreshing ? GCP.grey : GCP.cyan)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(capacity.isRefreshing ? GCP.rule : GCP.cyan, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(capacity.isRefreshing)
                    .help("Check every account's usage now")
                }
                .padding(.horizontal, 12)
                .fixedSize()
                stripDivider
                routeCell
            }
            .frame(maxHeight: .infinity)
            .background(GCP.screen, in: RoundedRectangle(cornerRadius: 9))
            .padding(6)
            .background(GCP.bezel, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var stripDivider: some View {
        Rectangle().fill(GCP.rule).frame(width: 1)
    }

    private func stripCell<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(GCP.mono(9.5)).kerning(1.5).foregroundStyle(GCP.cyan)
            value().font(GCP.mono(13, .bold))
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .fixedSize()
    }

    private var routeCell: some View {
        let best = readout.bestClaude
        let tint = best == nil ? GCP.grey : GCP.magenta
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                ViewThatFits(in: .horizontal) {
                    Text("ROUTE NEXT CLAUDE SESSION")
                    Text("ROUTE NEXT CLAUDE")
                    Text("ROUTE")
                }
                .font(GCP.mono(9.5))
                .kerning(1.5)
                .foregroundStyle(GCP.cyan)
                .lineLimit(1)
                Text(best.map { "TO \($0.snapshot.account.label.uppercased())" } ?? "NO CLAUDE ACCOUNT AVAILABLE")
                    .font(GCP.mono(13, .bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Text("HDRM \(best?.headroom.map { "\(Int($0.rounded()))%" } ?? "--")")
                .font(GCP.mono(12, .bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(tint, lineWidth: 1.5))
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var objectiveAverage: Int? {
        let objectives = missions.board.objectives
        guard !objectives.isEmpty else { return nil }
        return Int((objectives.map(\.progress).reduce(0, +) / Double(objectives.count)).rounded())
    }
}

// MARK: - Master caution key

private struct GlassCockpitCautionKey: View {
    let caution: AccountReadout?
    let acknowledged: Bool
    let compact: Bool
    let acknowledge: () -> Void

    private var lit: Bool { caution != nil && !acknowledged }

    var body: some View {
        Button {
            if caution != nil { acknowledge() }
        } label: {
            VStack(spacing: 2) {
                Text("MASTER CAUTION")
                    .font(GCP.mono(compact ? 10.5 : 12, .bold))
                    .kerning(compact ? 1.5 : 2)
                Text(detail)
                    .font(GCP.mono(compact ? 9 : 10))
                    .kerning(1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(caution == nil ? GCP.grey : GCP.amber)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(lit ? GCP.amber.opacity(0.14) : GCP.screen, in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(lit ? GCP.amber : GCP.rule, lineWidth: 1.5)
            )
            .shadow(color: lit ? GCP.amber.opacity(0.45) : .clear, radius: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .background(GCP.bezel, in: RoundedRectangle(cornerRadius: 14))
        .help(caution == nil ? "No account is near its limit." : "Push to acknowledge. It lights again if usage climbs.")
        .accessibilityLabel("Master caution")
        .accessibilityValue(detail)
    }

    private var detail: String {
        guard let caution, let window = caution.bindingWindow else { return "NONE" }
        let name = window.durationMinutes == 300 ? "5H" : "WK"
        return "\(caution.snapshot.account.label.uppercased()) \(name) \(Int(window.usedPercent.rounded()))%"
    }
}

// MARK: - Display unit chrome

/// A grey bezel with a caption row above a black screen.
private struct GlassCockpitDisplayUnit<Caption: View, Content: View>: View {
    var frameColor: Color = .black
    var padding = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    @ViewBuilder let caption: Caption
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) { caption }
                .font(GCP.mono(10))
                .kerning(1.5)
                .foregroundStyle(GCP.grey)
                .lineLimit(1)
                .padding(.horizontal, 4)
            content
                .padding(padding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(GCP.screen, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(frameColor, lineWidth: 1.5))
        }
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 10, trailing: 10))
        .background(GCP.bezel, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Small bezel push-button used for "+".
private struct GlassCockpitAddKey: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(GCP.cyan)
                .frame(width: 22, height: 15)
                .background(GCP.key, in: RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(GCP.rule, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct GlassCockpitLamp: View {
    var body: some View {
        Circle().fill(GCP.lamp).frame(width: 6, height: 6)
    }
}

/// Scrolls in the live window, lays out flat for the renderer.
private struct GlassCockpitScroll<Content: View>: View {
    let staticLayout: Bool
    var spacing: CGFloat = 9
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

private struct GlassCockpitEmpty: View {
    let text: String

    var body: some View {
        Text(text)
            .font(GCP.mono(10.5))
            .foregroundStyle(GCP.grey)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}

// MARK: - Accounts

private struct GlassCockpitAccountRows: View {
    let readout: CockpitReadout
    let compact: Bool

    var body: some View {
        let accounts = readout.accounts
        let perRow = max(1, min(accounts.count, 4))
        let rows = stride(from: 0, to: accounts.count, by: perRow).map { Array(accounts[$0..<min($0 + perRow, accounts.count)]) }
        let bestID = readout.bestClaude?.snapshot.id
        let gaugeHeight: CGFloat = rows.count > 1 ? 112 : 172
        VStack(spacing: 14) {
            if accounts.isEmpty {
                GlassCockpitDisplayUnit {
                    Text("DU1")
                    Spacer()
                    Text("ACCOUNTS")
                } content: {
                    GlassCockpitEmpty(text: "NO ACCOUNTS CONFIGURED · ADD ONE IN ACCOUNTS.JSON")
                }
                .frame(height: 90)
            }
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(alignment: .top, spacing: 14) {
                    ForEach(rows[rowIndex], id: \.snapshot.id) { account in
                        GlassCockpitAccountUnit(
                            account: account,
                            unit: (accounts.firstIndex { $0.snapshot.id == account.snapshot.id } ?? 0) + 1,
                            isRoute: account.snapshot.id == bestID,
                            gaugeHeight: gaugeHeight
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    ForEach(0..<(perRow - rows[rowIndex].count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct GlassCockpitAccountUnit: View {
    let account: AccountReadout
    let unit: Int
    let isRoute: Bool
    let gaugeHeight: CGFloat

    private var snapshot: ProviderSnapshot { account.snapshot }
    private var isStale: Bool { snapshot.state == .error && account.hasMeasurements }

    var body: some View {
        GlassCockpitDisplayUnit(
            frameColor: isRoute ? GCP.magenta : .black,
            padding: EdgeInsets(top: 11, leading: 13, bottom: 11, trailing: 13)
        ) {
            GlassCockpitLamp()
            Text("DU\(unit)")
            Spacer(minLength: 4)
            Text(snapshot.provider.shortName.uppercased())
            GlassCockpitLamp()
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(snapshot.account.label)
                        .font(GCP.sans(15, .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .help(ThemeText.guide(snapshot.provider))
                    Spacer(minLength: 0)
                    Text(status.text)
                        .font(GCP.mono(10, .bold))
                        .kerning(1)
                        .foregroundStyle(status.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(status.color, lineWidth: 1))
                        .fixedSize()
                }
                Text(ThemeText.identityLine(account))
                    .font(GCP.mono(10.5))
                    .foregroundStyle(isStale ? GCP.amber : GCP.grey)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if account.hasMeasurements {
                    GlassCockpitInstrument(fiveHour: account.fiveHour?.usedPercent, weekly: account.weekly?.usedPercent)
                        .frame(maxWidth: .infinity, maxHeight: gaugeHeight)
                    readings
                    ForEach(account.otherWindows.prefix(2)) { window in
                        HStack {
                            Text(window.label.uppercased()).foregroundStyle(GCP.grey)
                            Spacer(minLength: 6)
                            Text("\(Int(window.usedPercent.rounded()))%").foregroundStyle(GCP.tone(window.usedPercent))
                        }
                        .font(GCP.mono(10))
                        .lineLimit(1)
                    }
                } else {
                    offlinePanel
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var status: (text: String, color: Color) {
        switch snapshot.state {
        case .unauthenticated where !account.hasMeasurements: return ("SIGN IN", GCP.amber)
        case .loading where !account.hasMeasurements: return ("ALIGNING", GCP.cyan)
        case .unavailable where !account.hasMeasurements: return ("INOP", GCP.amber)
        case .error where !account.hasMeasurements: return ("FAULT", GCP.amber)
        default: break
        }
        if isRoute { return ("ROUTE HERE", GCP.magenta) }
        if isStale { return ("STALE", GCP.amber) }
        if account.isNearLimit { return ("LOW HDRM", GCP.amber) }
        return ("NORM", GCP.green)
    }

    private var readings: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(alignment: .top, spacing: 8) {
                reading("HDRM", account.headroom.map { "\(Int($0.rounded()))%" } ?? "--",
                        color: account.isNearLimit ? GCP.amber : GCP.green)
                reading("RESET", ThemeText.resetText(account, now: context.date), color: GCP.white)
                reading("LIMITING", limiting, color: GCP.white)
            }
            .padding(.top, 7)
            .overlay(alignment: .top) { Rectangle().fill(GCP.divider).frame(height: 1) }
        }
    }

    private var limiting: String {
        guard let window = account.bindingWindow else { return "--" }
        return window.durationMinutes == 300 ? "5H" : "WEEK"
    }

    private func reading(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(GCP.mono(9.5)).kerning(1.5).foregroundStyle(GCP.cyan)
            Text(value)
                .font(GCP.mono(19, .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var offlinePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                Text(snapshot.state.label.uppercased())
                    .font(GCP.mono(11, .bold))
                    .kerning(1.5)
            }
            .foregroundStyle(snapshot.state == .loading ? GCP.cyan : GCP.amber)
            Text(snapshot.message ?? "No usage reported yet.")
                .font(GCP.mono(10.5))
                .foregroundStyle(GCP.white)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                reading("HDRM", "--", color: GCP.grey)
                reading("5H", "--", color: GCP.grey)
                reading("WEEK", "--", color: GCP.grey)
            }
            .padding(.top, 7)
            .overlay(alignment: .top) { Rectangle().fill(GCP.divider).frame(height: 1) }
        }
        .padding(.top, 6)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The EICAS round dial (5-hour window) beside a vertical tape (weekly window),
/// drawn on the mockup's 300 × 168 grid.
private struct GlassCockpitInstrument: View {
    let fiveHour: Double?
    let weekly: Double?

    private nonisolated static let center = CGPoint(x: 86, y: 90)
    private static let radius: CGFloat = 62
    private static let tapeTop: CGFloat = 14
    private static let tapeBottom: CGFloat = 140

    var body: some View {
        Canvas { context, size in
            let s = min(size.width / 300, size.height / 168)
            let ox = (size.width - 300 * s) / 2
            let oy = (size.height - 168 * s) / 2
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
            func angle(_ v: Double) -> Double { 180 + 2.1 * v }
            func polar(_ r: CGFloat, _ v: Double) -> CGPoint {
                let a = angle(v) * .pi / 180
                return p(Self.center.x + r * cos(a), Self.center.y + r * sin(a))
            }
            func arc(_ r: CGFloat, _ v0: Double, _ v1: Double) -> Path {
                var path = Path()
                path.addArc(center: p(Self.center.x, Self.center.y), radius: r * s,
                            startAngle: .degrees(angle(v0)), endAngle: .degrees(angle(v1)), clockwise: false)
                return path
            }
            func text(_ string: String, _ at: CGPoint, size: CGFloat, weight: Font.Weight = .regular, color: Color, kerning: CGFloat = 0, anchor: UnitPoint = .center) {
                context.draw(
                    Text(string).font(GCP.mono(size * s, weight)).kerning(kerning * s).foregroundColor(color),
                    at: at,
                    anchor: anchor
                )
            }
            let caution = AccountReadout.cautionThreshold

            // Round dial.
            if let fiveHour, fiveHour > 0 {
                var sector = Path()
                sector.move(to: p(Self.center.x, Self.center.y))
                sector.addPath(arc(Self.radius - 4, 0, fiveHour))
                sector.closeSubpath()
                context.fill(sector, with: .color(GCP.sector))
            }
            context.stroke(arc(Self.radius, 0, caution), with: .color(GCP.white), lineWidth: 2 * s)
            context.stroke(arc(Self.radius + 1, caution, 100), with: .color(GCP.amber), lineWidth: 4 * s)
            for i in 0...10 {
                let v = Double(i * 10)
                let major = i % 2 == 0
                var tick = Path()
                tick.move(to: polar(Self.radius, v))
                tick.addLine(to: polar(major ? Self.radius - 9 : Self.radius - 5, v))
                context.stroke(tick, with: .color(v >= caution ? GCP.amber : GCP.white), lineWidth: (major ? 2 : 1) * s)
            }
            for n in [0, 2, 4, 6, 8, 10] {
                text(String(n), polar(Self.radius - 19, Double(n * 10)), size: 10, color: GCP.white)
            }
            let tone1 = fiveHour.map(GCP.tone) ?? GCP.grey
            if let fiveHour {
                var needle = Path()
                needle.move(to: p(Self.center.x, Self.center.y))
                needle.addLine(to: polar(Self.radius - 6, fiveHour))
                context.stroke(needle, with: .color(tone1), style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))
                let hub = p(Self.center.x, Self.center.y)
                context.fill(Path(ellipseIn: CGRect(x: hub.x - 4 * s, y: hub.y - 4 * s, width: 8 * s, height: 8 * s)), with: .color(tone1))
            }
            let box1 = Path(roundedRect: CGRect(origin: p(54, 108), size: CGSize(width: 64 * s, height: 26 * s)), cornerRadius: 2 * s)
            context.fill(box1, with: .color(GCP.screen))
            context.stroke(box1, with: .color(fiveHour == nil ? GCP.rule : tone1), lineWidth: 1.5 * s)
            if let fiveHour {
                text("\(Int(fiveHour.rounded()))%", p(86, 121), size: 17, weight: .bold, color: tone1)
            } else {
                text("NO DATA", p(86, 121), size: 10, weight: .bold, color: GCP.amber)
            }
            text("5H WINDOW", p(86, 155), size: 10, color: GCP.cyan, kerning: 1.5)

            // Vertical tape.
            let k = (Self.tapeBottom - Self.tapeTop) / 100
            for i in 0...10 {
                let y = Self.tapeBottom - CGFloat(i * 10) * k
                var tick = Path()
                tick.move(to: p(i % 5 == 0 ? 192 : 198, y))
                tick.addLine(to: p(204, y))
                context.stroke(tick, with: .color(GCP.white), lineWidth: 1 * s)
            }
            for v in [100, 50, 0] {
                text(String(v), p(188, Self.tapeBottom - CGFloat(v) * k), size: 10, color: GCP.white, anchor: .trailing)
            }
            let tapeRect = Path(CGRect(origin: p(204, Self.tapeTop), size: CGSize(width: 30 * s, height: 126 * s)))
            context.fill(tapeRect, with: .color(GCP.tapeFill))
            context.stroke(tapeRect, with: .color(GCP.rule), lineWidth: 1 * s)
            context.fill(
                Path(CGRect(origin: p(235, Self.tapeTop), size: CGSize(width: 3 * s, height: CGFloat(100 - caution) * k * s))),
                with: .color(GCP.amber)
            )
            let tone2 = weekly.map(GCP.tone) ?? GCP.grey
            var boxY = Self.tapeBottom - 18
            if let weekly {
                let ty = Self.tapeBottom - CGFloat(weekly) * k
                context.fill(
                    Path(CGRect(origin: p(204, ty), size: CGSize(width: 30 * s, height: CGFloat(weekly) * k * s))),
                    with: .color(tone2.opacity(0.32))
                )
                var level = Path()
                level.move(to: p(204, ty))
                level.addLine(to: p(234, ty))
                context.stroke(level, with: .color(tone2), lineWidth: 2 * s)
                var pointer = Path()
                pointer.move(to: p(240, ty))
                pointer.addLine(to: p(248, ty - 6))
                pointer.addLine(to: p(248, ty + 6))
                pointer.closeSubpath()
                context.fill(pointer, with: .color(tone2))
                boxY = min(max(ty - 11, Self.tapeTop - 4), Self.tapeBottom - 18)
            }
            let box2 = Path(roundedRect: CGRect(origin: p(248, boxY), size: CGSize(width: 48 * s, height: 22 * s)), cornerRadius: 2 * s)
            context.fill(box2, with: .color(GCP.screen))
            context.stroke(box2, with: .color(weekly == nil ? GCP.rule : tone2), lineWidth: 1.5 * s)
            if let weekly {
                text("\(Int(weekly.rounded()))%", p(272, boxY + 11), size: 14, weight: .bold, color: tone2)
            } else {
                text("NO DATA", p(272, boxY + 11), size: 8, weight: .bold, color: GCP.amber)
            }
            text("WEEKLY", p(219, 155), size: 10, color: GCP.cyan, kerning: 1.5)
        }
        .aspectRatio(300 / 168, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Usage gauges")
        .accessibilityValue(
            "5 hour window \(fiveHour.map { "\(Int($0.rounded())) percent used" } ?? "no data"), "
                + "weekly window \(weekly.map { "\(Int($0.rounded())) percent used" } ?? "no data")"
        )
    }
}

// MARK: - Projects (ND · flight plan)

private struct GlassCockpitProjectsUnit: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let staticLayout: Bool

    private let nameWidth: CGFloat = 150
    private let phaseWidth: CGFloat = 66
    private let pctWidth: CGFloat = 44

    var body: some View {
        let projects = missions.board.projects
        GlassCockpitDisplayUnit {
            Text("DU5 · ND")
            Spacer()
            Text("PROJECTS · FLIGHT PLAN")
            GlassCockpitAddKey(help: "Add a project") { editor = .project(MissionProject(name: "")) }
        } content: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 12) {
                    Text("WPT").frame(width: nameWidth, alignment: .leading)
                    Text("PHASE").frame(width: phaseWidth, alignment: .leading)
                    Text("PROGRESS 0 · 50 · 100").frame(maxWidth: .infinity, alignment: .leading)
                    Text("PCT").frame(width: pctWidth, alignment: .trailing)
                }
                .font(GCP.mono(9.5))
                .kerning(1.5)
                .foregroundStyle(GCP.cyan)
                .lineLimit(1)
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(GCP.divider).frame(height: 1) }

                GlassCockpitScroll(staticLayout: staticLayout) {
                    if projects.isEmpty {
                        GlassCockpitEmpty(text: "NO WAYPOINTS FILED · PRESS + TO ADD A PROJECT")
                    }
                    ForEach(projects) { project in
                        row(project)
                            .projectActions(project, missions: missions, editor: $editor)
                    }
                }

                HStack {
                    Text("\(projects.count) WAYPOINT\(projects.count == 1 ? "" : "S") ACTIVE")
                    Spacer()
                    Text("AVG PROGRESS")
                    Text(average.map { "\($0)%" } ?? "--").bold().foregroundStyle(GCP.white)
                }
                .font(GCP.mono(10.5))
                .foregroundStyle(GCP.grey)
            }
        }
    }

    private var average: Int? {
        let projects = missions.board.projects
        guard !projects.isEmpty else { return nil }
        return Int((projects.map(\.progress).reduce(0, +) / Double(projects.count)).rounded())
    }

    private func row(_ project: MissionProject) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 12) {
                Text(project.name)
                    .font(GCP.sans(14, .bold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: nameWidth, alignment: .leading)
                Text(project.phase.uppercased())
                    .font(GCP.mono(10, .bold))
                    .kerning(1)
                    .foregroundStyle(GCP.cyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: phaseWidth)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(GCP.cyan, lineWidth: 1))
                GlassCockpitProgressTrack(value: project.progress)
                    .frame(height: 18)
                    .frame(maxWidth: .infinity)
                Text("\(Int(project.progress.rounded()))%")
                    .font(GCP.mono(14, .bold))
                    .frame(width: pctWidth, alignment: .trailing)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("NEXT").foregroundStyle(GCP.cyan).kerning(1)
                Text(project.nextAction.isEmpty ? "—" : project.nextAction).lineLimit(1)
            }
            .font(GCP.mono(11))
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(GCP.rowRule).frame(height: 1) }
    }
}

private struct GlassCockpitProgressTrack: View {
    let value: Double

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let x = { (v: CGFloat) in v / 200 * w }
            let track = Path(CGRect(x: 0.5, y: 4.5, width: w - 1, height: 9))
            context.fill(track, with: .color(GCP.tapeFill))
            context.stroke(track, with: .color(GCP.rule), lineWidth: 1)
            let fw = max(CGFloat(min(max(value, 0), 100)) * 2 - 1, 0)
            context.fill(Path(CGRect(x: 1, y: 5, width: x(fw), height: 8)), with: .color(GCP.green.opacity(0.38)))
            var marker = Path()
            marker.move(to: CGPoint(x: x(fw), y: 1))
            marker.addLine(to: CGPoint(x: x(fw), y: 17))
            context.stroke(marker, with: .color(GCP.green), lineWidth: 2.5)
            for (v, y0, y1, color) in [(50.0, 14.0, 17.0, GCP.grey), (100, 13, 18, GCP.white), (150, 14, 17, GCP.grey)] {
                var tick = Path()
                tick.move(to: CGPoint(x: x(v), y: y0))
                tick.addLine(to: CGPoint(x: x(v), y: y1))
                context.stroke(tick, with: .color(color), lineWidth: 1)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(value.rounded())) percent")
    }
}

// MARK: - Objectives (EICAS)

private struct GlassCockpitObjectivesUnit: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let staticLayout: Bool

    var body: some View {
        let objectives = missions.board.objectives
        GlassCockpitDisplayUnit(padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) {
            Text("DU6 · EICAS")
            Spacer()
            Text("OBJECTIVES · \(missions.board.periodTitle.uppercased())")
            GlassCockpitAddKey(help: "Add an objective") { editor = .objective(MissionObjective(title: "")) }
        } content: {
            GlassCockpitScroll(staticLayout: staticLayout, spacing: 12) {
                if objectives.isEmpty {
                    GlassCockpitEmpty(text: "NO OBJECTIVES FOR \(missions.board.periodTitle.uppercased()) · PRESS + TO ADD ONE")
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3),
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(Array(objectives.enumerated()), id: \.element.id) { index, objective in
                        cell(objective, number: index + 1)
                            .objectiveActions(objective, missions: missions, editor: $editor)
                    }
                }
            }
        }
    }

    private func cell(_ objective: MissionObjective, number: Int) -> some View {
        VStack(spacing: 8) {
            Text("OBJ \(number)").font(GCP.mono(10)).kerning(1.5).foregroundStyle(GCP.cyan)
            GlassCockpitRing(value: objective.progress)
            Text(objective.title)
                .font(GCP.sans(12.5, .bold))
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .top)
            HStack(spacing: 4) {
                ForEach(0..<min(objective.keyResultsTotal, 8), id: \.self) { index in
                    Rectangle()
                        .fill(index < objective.keyResultsOnTrack ? GCP.green : .clear)
                        .overlay(Rectangle().stroke(GCP.green, lineWidth: 1))
                        .frame(width: 14, height: 8)
                }
            }
            .frame(minHeight: 10)
            Text(objective.summary.isEmpty ? "—" : objective.summary)
                .font(GCP.mono(10))
                .lineSpacing(2)
                .foregroundStyle(GCP.grey)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(status(objective).text)
                .font(GCP.mono(10, .bold))
                .kerning(1)
                .foregroundStyle(status(objective).color)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .overlay(alignment: .top) { Rectangle().fill(GCP.divider).frame(height: 1) }
        }
    }

    private func status(_ objective: MissionObjective) -> (text: String, color: Color) {
        if objective.keyResultsTotal > 0 {
            let healthy = objective.keyResultsOnTrack * 2 >= objective.keyResultsTotal
            return ("\(objective.keyResultsOnTrack)/\(objective.keyResultsTotal) ON TRACK", healthy ? GCP.green : GCP.amber)
        }
        if objective.progress >= 100 { return ("COMPLETE", GCP.green) }
        return ("IN PROGRESS", GCP.cyan)
    }
}

/// 270° ring gauge on the mockup's 110 × 100 grid.
private struct GlassCockpitRing: View {
    let value: Double

    var body: some View {
        Canvas { context, size in
            let s = min(size.width / 110, size.height / 100)
            let ox = (size.width - 110 * s) / 2
            let oy = (size.height - 100 * s) / 2
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
            let center = p(55, 52)
            func ring(_ fraction: Double) -> Path {
                var path = Path()
                path.addArc(center: center, radius: 38 * s, startAngle: .degrees(135),
                            endAngle: .degrees(135 + 270 * fraction), clockwise: false)
                return path
            }
            context.stroke(ring(1), with: .color(GCP.ringTrack), lineWidth: 8 * s)
            let fraction = min(max(value, 0), 100) / 100
            if fraction > 0 {
                context.stroke(ring(fraction), with: .color(GCP.green), lineWidth: 8 * s)
            }
            for v in [0.0, 25, 50, 75, 100] {
                let a = (135 + 2.7 * v) * .pi / 180
                var tick = Path()
                tick.move(to: p(55 + 44 * cos(a), 52 + 44 * sin(a)))
                tick.addLine(to: p(55 + 48 * cos(a), 52 + 48 * sin(a)))
                context.stroke(tick, with: .color(GCP.white), lineWidth: 1.5 * s)
            }
            context.draw(Text("\(Int(value.rounded()))").font(GCP.mono(20 * s, .bold)).foregroundColor(GCP.white), at: p(55, 51))
            context.draw(Text("PCT").font(GCP.mono(8.5 * s)).foregroundColor(GCP.grey), at: p(55, 69))
            context.draw(Text("0 · 100").font(GCP.mono(8.5 * s)).foregroundColor(GCP.grey), at: p(55, 93))
        }
        .aspectRatio(1.1, contentMode: .fit)
        .frame(maxWidth: 124)
        .accessibilityElement()
        .accessibilityLabel("Objective progress")
        .accessibilityValue("\(Int(value.rounded())) percent")
    }
}

// MARK: - Tasks (ECAM checklist)

private struct GlassCockpitChecklistUnit: View {
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let staticLayout: Bool

    var body: some View {
        GlassCockpitDisplayUnit {
            Text("DU7 · ECAM")
            Spacer()
            Text("TASK CHECKLIST")
            GlassCockpitAddKey(help: "Add a task") { editor = .task(MissionTask(title: "")) }
        } content: {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                GlassCockpitScroll(staticLayout: staticLayout, spacing: 10) {
                    if missions.board.tasks.isEmpty {
                        GlassCockpitEmpty(text: "CHECKLIST EMPTY · PRESS + TO ADD A TASK")
                    }
                    ForEach(TaskBucket.allCases) { bucket in
                        section(bucket, now: context.date)
                    }
                }
            }
        }
    }

    private func color(_ bucket: TaskBucket) -> Color {
        switch bucket {
        case .now: GCP.white
        case .next: GCP.cyan
        case .later: GCP.grey
        }
    }

    private func section(_ bucket: TaskBucket, now: Date) -> some View {
        let tasks = missions.board.tasks(in: bucket, now: now)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(bucket.title).font(GCP.mono(12, .bold)).kerning(2).foregroundStyle(color(bucket))
                Spacer()
                Text("\(tasks.count) ITEM\(tasks.count == 1 ? "" : "S")").font(GCP.mono(10)).foregroundStyle(GCP.grey)
            }
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) { Rectangle().fill(GCP.divider).frame(height: 1) }
            if tasks.isEmpty {
                Text("— NO ITEMS —").font(GCP.mono(10)).foregroundStyle(GCP.grey).padding(.vertical, 3)
            }
            ForEach(tasks) { task in
                GlassCockpitTaskRow(task: task, missions: missions, editor: $editor, now: now)
            }
        }
    }
}

private struct GlassCockpitTaskRow: View {
    let task: MissionTask
    @ObservedObject var missions: MissionStore
    @Binding var editor: MissionEditor?
    let now: Date
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(isOn: doneBinding(task, missions: missions)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(GCP.sans(compact ? 12.5 : 13))
                        .strikethrough(task.isDone, color: GCP.grey)
                        .foregroundStyle(task.isDone ? GCP.grey : GCP.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let project = missions.board.project(for: task) {
                        Text(project.name).font(GCP.mono(10)).foregroundStyle(GCP.grey).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(GlassCockpitCheckStyle())
            if let label = ThemeText.dueLabel(task, now: now) {
                Text(label)
                    .font(GCP.mono(11, .bold))
                    .foregroundStyle(task.isDue(on: now) ? GCP.amber : GCP.cyan)
                    .fixedSize()
                    .padding(.top, 1)
            }
        }
        .padding(.vertical, 4)
        .taskActions(task, missions: missions, editor: $editor)
    }
}

/// ECAM-style checkbox: cyan square that fills when the item is done.
private struct GlassCockpitCheckStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(configuration.isOn ? GCP.cyan : Color.clear)
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(GCP.cyan, lineWidth: 1.5)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(GCP.screen)
                    }
                }
                .frame(width: 14, height: 14)
                .padding(.top, 2)
                .frame(width: 18, alignment: .leading)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Done" : "Open")
    }
}

// MARK: - Menu

struct GlassCockpitMenuView: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    var staticLayout = false
    @Environment(\.openWindow) private var openWindow
    @State private var editor: MissionEditor?
    @State private var acknowledgedCaution: String?

    private var readout: CockpitReadout { CockpitReadout(snapshots: capacity.snapshots) }

    var body: some View {
        VStack(spacing: 10) {
            annunciators
            if staticLayout {
                content
            } else {
                ScrollView { content }.scrollIndicators(.never)
            }
            footer
        }
        .padding(12)
        .background(GCP.background)
        .foregroundStyle(GCP.white)
        .missionEditorSheet($editor, missions: missions)
    }

    private var annunciators: some View {
        let best = readout.bestClaude
        let tint = best == nil ? GCP.grey : GCP.magenta
        return HStack(spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ROUTE NEXT CLAUDE").font(GCP.mono(9)).kerning(1.5).foregroundStyle(GCP.cyan)
                    Text(best.map { "TO \($0.snapshot.account.label.uppercased())" } ?? "NO ACCOUNT AVAILABLE")
                        .font(GCP.mono(12, .bold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                Text(best?.headroom.map { "\(Int($0.rounded()))%" } ?? "--")
                    .font(GCP.mono(12, .bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(tint, lineWidth: 1.5))
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GCP.screen, in: RoundedRectangle(cornerRadius: 9))
            .padding(6)
            .background(GCP.bezel, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)

            GlassCockpitCautionKey(
                caution: readout.masterCaution,
                acknowledged: readout.masterCaution.map { key($0) == acknowledgedCaution } ?? false,
                compact: true
            ) {
                acknowledgedCaution = readout.masterCaution.map(key)
            }
            .frame(width: 150)
        }
        .frame(height: 54)
    }

    private func key(_ account: AccountReadout) -> String {
        "\(account.snapshot.id)-\(Int(account.peakUsed ?? 0))"
    }

    private var content: some View {
        VStack(spacing: 10) {
            ForEach(Array(readout.accounts.enumerated()), id: \.element.snapshot.id) { index, account in
                GlassCockpitCompactAccount(
                    account: account,
                    unit: index + 1,
                    isRoute: account.snapshot.id == readout.bestClaude?.snapshot.id
                )
            }
            nowChecklist
        }
    }

    private var nowChecklist: some View {
        let tasks = missions.board.tasks(in: .now)
        return GlassCockpitDisplayUnit {
            Text("ECAM")
            Spacer()
            Text("NOW · \(tasks.count) ITEM\(tasks.count == 1 ? "" : "S")")
            GlassCockpitAddKey(help: "Add a task") { editor = .task(MissionTask(title: "")) }
        } content: {
            VStack(alignment: .leading, spacing: 2) {
                if tasks.isEmpty {
                    GlassCockpitEmpty(text: "NOTHING IN NOW · OPEN THE DASHBOARD TO PLAN")
                }
                ForEach(tasks) { task in
                    GlassCockpitTaskRow(task: task, missions: missions, editor: $editor, now: Date(), compact: true)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            softKey(capacity.isRefreshing ? "PROBING…" : "RE-PROBE") {
                Task { await capacity.refresh() }
            }
            .disabled(capacity.isRefreshing)
            .help(ThemeText.probedLabel(capacity.lastRefresh, now: Date()))
            softKey("DASHBOARD") { OpenDashboardAction(openWindow: openWindow)() }
            ThemePicker { softKeyLabel("THEME ▾") }
            softKey("QUIT") { NSApp.terminate(nil) }
        }
        .padding(6)
        .background(GCP.bezel, in: RoundedRectangle(cornerRadius: 12))
    }

    private func softKey(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { softKeyLabel(title) }
            .buttonStyle(.plain)
    }

    private func softKeyLabel(_ title: String) -> some View {
        Text(title)
            .font(GCP.mono(10, .bold))
            .kerning(1)
            .foregroundStyle(GCP.cyan)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.horizontal, 6)
            .background(GCP.screen, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(GCP.rule, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

private struct GlassCockpitCompactAccount: View {
    let account: AccountReadout
    let unit: Int
    let isRoute: Bool

    private var snapshot: ProviderSnapshot { account.snapshot }

    var body: some View {
        GlassCockpitDisplayUnit(
            frameColor: isRoute ? GCP.magenta : .black,
            padding: EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        ) {
            GlassCockpitLamp()
            Text("DU\(unit) · \(snapshot.account.label.uppercased())")
            Spacer(minLength: 4)
            if snapshot.account.label.caseInsensitiveCompare(snapshot.provider.shortName) != .orderedSame {
                Text(snapshot.provider.shortName.uppercased())
            }
            GlassCockpitLamp()
        } content: {
            if account.hasMeasurements {
                HStack(alignment: .center, spacing: 10) {
                    GlassCockpitInstrument(fiveHour: account.fiveHour?.usedPercent, weekly: account.weekly?.usedPercent)
                        .frame(width: 168)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(ThemeText.identityLine(account))
                            .font(GCP.mono(9.5))
                            .foregroundStyle(snapshot.state == .error ? GCP.amber : GCP.grey)
                            .lineLimit(2)
                        compactReading("HDRM", account.headroom.map { "\(Int($0.rounded()))%" } ?? "--",
                                       color: account.isNearLimit ? GCP.amber : GCP.green)
                        compactReading("RESET", ThemeText.resetText(account, now: Date()), color: GCP.white)
                        if isRoute {
                            Text("ROUTE HERE")
                                .font(GCP.mono(9.5, .bold))
                                .foregroundStyle(GCP.magenta)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(GCP.magenta, lineWidth: 1))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                        Text(snapshot.state.label.uppercased()).font(GCP.mono(10.5, .bold)).kerning(1.5)
                    }
                    .foregroundStyle(snapshot.state == .loading ? GCP.cyan : GCP.amber)
                    Text(snapshot.message ?? "No usage reported yet.")
                        .font(GCP.mono(10))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func compactReading(_ title: String, _ value: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(GCP.mono(9)).kerning(1.5).foregroundStyle(GCP.cyan)
            Text(value).font(GCP.mono(16, .bold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }
}
