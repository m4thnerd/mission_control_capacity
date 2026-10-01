import SwiftUI

/// Olive instrument-panel palette and type for the analog cockpit.
enum Cockpit {
    static let panel = Color(hex: 0x4B4D41)
    static let subpanel = Color(hex: 0x43453A)
    static let subpanelBorder = Color(hex: 0x6A6C5E)
    static let plate = Color(hex: 0x1E1E1A)
    static let plateBorder = Color(hex: 0x77786A)
    static let bezel = Color(hex: 0x0E0E0C)
    static let bezelRing = Color(hex: 0x2A2A23)
    static let bezelEdge = Color(hex: 0x55554A)
    static let face = Color(hex: 0x151513)
    static let cream = Color(hex: 0xF4F1E6)
    static let text = Color(hex: 0xF1EDE0)
    static let secondary = Color(hex: 0xD2CCB8)
    static let dim = Color(hex: 0xB3AE98)
    static let screw = Color(hex: 0x8E8B7C)
    static let screwSlot = Color(hex: 0x2A2A24)
    static let paper = Color(hex: 0xEDE6D0)
    static let paperInk = Color(hex: 0x2A2720)
    static let paperEdge = Color(hex: 0xB9B09A)
    static let amber = Color(hex: 0xF2A31B)
    static let amberInk = Color(hex: 0x1A1408)
    static let routeGreen = Color(hex: 0x8FD19E)
    static let routeInk = Color(hex: 0x10200F)
    static let lampOff = Color(hex: 0x2B2A22)
    static let bandGreen = Color(hex: 0x4FA36B)
    static let bandYellow = Color(hex: 0xE3B23C)
    static let bandRed = Color(hex: 0xD8442F)

    /// Engraved-label type: condensed system sans standing in for Oswald.
    static func label(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    /// Logbook type.
    static func typewriter(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "Courier New Bold" : "Courier New", size: size)
    }

    static func readoutColor(_ percent: Double) -> Color {
        switch percent {
        case 85...: Color(hex: 0xFF7A5C)
        case 65..<85: Color(hex: 0xF2C14E)
        default: routeGreen
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Geometry

/// Angles are degrees clockwise from 12 o'clock, as on a real instrument.
enum DialGeometry {
    static func point(_ center: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + radius * sin(radians), y: center.y - radius * cos(radians))
    }

    static func arc(_ center: CGPoint, _ radius: CGFloat, from start: Double, to end: Double) -> Path {
        var path = Path()
        // Path angles run from 3 o'clock; shift ours by -90°.
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(start - 90),
            endAngle: .degrees(end - 90),
            clockwise: false
        )
        return path
    }

    static func tick(_ center: CGPoint, _ outer: CGFloat, _ inner: CGFloat, _ degrees: Double) -> Path {
        var path = Path()
        path.move(to: point(center, outer, degrees))
        path.addLine(to: point(center, inner, degrees))
        return path
    }

    static func needle(_ center: CGPoint, length: CGFloat, tail: CGFloat, width: CGFloat, degrees: Double) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - length))
        path.addLine(to: CGPoint(x: center.x + width, y: center.y - 4 * width / 2.6))
        path.addLine(to: CGPoint(x: center.x, y: center.y + tail))
        path.addLine(to: CGPoint(x: center.x - width, y: center.y - 4 * width / 2.6))
        path.closeSubpath()
        return path.applying(
            CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: degrees * .pi / 180)
                .translatedBy(x: -center.x, y: -center.y)
        )
    }
}

// MARK: - Instruments

/// Main steam gauge: 270° sweep, green/yellow/red bands and a redline at 90.
struct DialGauge: View {
    let value: Double?
    let label: String
    var size: CGFloat = 140

    private static func degrees(_ percent: Double) -> Double { -135 + percent * 2.7 }

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 140
            let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let circle = { (r: CGFloat) in Path(ellipseIn: CGRect(x: c.x - r * s, y: c.y - r * s, width: 2 * r * s, height: 2 * r * s)) }

            context.fill(circle(69), with: .color(Cockpit.bezel))
            context.fill(circle(66), with: .color(Cockpit.bezelRing))
            context.stroke(circle(66), with: .color(Cockpit.bezelEdge), lineWidth: s)
            context.fill(circle(61), with: .color(Cockpit.face))

            for (from, to, color) in [(0.0, 65.0, Cockpit.bandGreen), (65, 85, Cockpit.bandYellow), (85, 100, Cockpit.bandRed)] {
                context.stroke(
                    DialGeometry.arc(c, 59 * s, from: Self.degrees(from), to: Self.degrees(to)),
                    with: .color(color.opacity(value == nil ? 0.35 : 1)),
                    lineWidth: 4 * s
                )
            }
            for v in stride(from: 0, through: 100, by: 5) {
                let major = v % 10 == 0
                context.stroke(
                    DialGeometry.tick(c, 57 * s, (major ? 49 : 53) * s, Self.degrees(Double(v))),
                    with: .color(Cockpit.cream),
                    lineWidth: (major ? 2 : 1) * s
                )
            }
            context.stroke(DialGeometry.tick(c, 61 * s, 47 * s, Self.degrees(90)), with: .color(Cockpit.bandRed), lineWidth: 2.5 * s)
            for v in stride(from: 0, through: 100, by: 20) {
                let p = DialGeometry.point(c, 41 * s, Self.degrees(Double(v)))
                context.draw(Text("\(v)").font(Cockpit.label(11 * s)).foregroundColor(Cockpit.cream), at: p)
            }
            context.draw(Text(label).font(Cockpit.label(9 * s)).kerning(1.5).foregroundColor(Cockpit.secondary), at: CGPoint(x: c.x, y: c.y - 21 * s))
            context.draw(Text("% USED").font(Cockpit.label(7 * s, .regular)).kerning(1).foregroundColor(Cockpit.dim), at: CGPoint(x: c.x, y: c.y - 11 * s))

            let window = CGRect(x: c.x - 16 * s, y: c.y + 18 * s, width: 32 * s, height: 17 * s)
            context.fill(Path(roundedRect: window, cornerRadius: 2 * s), with: .color(.black))
            context.stroke(Path(roundedRect: window, cornerRadius: 2 * s), with: .color(Cockpit.bezelEdge), lineWidth: s)
            let reading = value.map { "\(Int($0.rounded()))" } ?? "--"
            context.draw(
                Text(reading).font(Cockpit.label(13 * s, .semibold)).foregroundColor(value.map(Cockpit.readoutColor) ?? Cockpit.dim),
                at: CGPoint(x: window.midX, y: window.midY)
            )

            if let value {
                context.fill(
                    DialGeometry.needle(c, length: 56 * s, tail: 14 * s, width: 2.6 * s, degrees: Self.degrees(value)),
                    with: .color(Cockpit.cream)
                )
            }
            context.fill(circle(6.5), with: .color(Cockpit.bezelRing))
            context.stroke(circle(6.5), with: .color(Cockpit.screw), lineWidth: s)
            context.fill(circle(2), with: .color(Cockpit.cream))
            // Glass glint.
            context.stroke(
                DialGeometry.arc(c, 48 * s, from: -62, to: -8),
                with: .color(.white.opacity(0.08)),
                style: StrokeStyle(lineWidth: 5 * s, lineCap: .round)
            )
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(label) window")
        .accessibilityValue(value.map { "\(Int($0.rounded())) percent used" } ?? "No data")
    }
}

/// Secondary round gauge for project progress.
struct ProgressGauge: View {
    let value: Double
    let tint: Color
    var size: CGFloat = 66

    private static func degrees(_ percent: Double) -> Double { -135 + percent * 2.7 }

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 66
            let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let circle = { (r: CGFloat) in Path(ellipseIn: CGRect(x: c.x - r * s, y: c.y - r * s, width: 2 * r * s, height: 2 * r * s)) }
            context.fill(circle(32), with: .color(Cockpit.bezel))
            context.fill(circle(28), with: .color(Cockpit.face))
            context.stroke(DialGeometry.arc(c, 29.5 * s, from: Self.degrees(0), to: Self.degrees(max(value, 1))), with: .color(tint), lineWidth: 2.5 * s)
            for v in stride(from: 0, through: 100, by: 10) {
                let major = v % 50 == 0
                context.stroke(
                    DialGeometry.tick(c, 27 * s, (major ? 21 : 24) * s, Self.degrees(Double(v))),
                    with: .color(Cockpit.cream),
                    lineWidth: (major ? 1.6 : 1) * s
                )
            }
            context.draw(Text("\(Int(value.rounded()))").font(Cockpit.label(10 * s, .semibold)).foregroundColor(Cockpit.cream), at: CGPoint(x: c.x, y: c.y + 17 * s))
            context.fill(DialGeometry.needle(c, length: 24 * s, tail: 6 * s, width: 1.6 * s, degrees: Self.degrees(value)), with: .color(Cockpit.cream))
            context.fill(circle(3.5), with: .color(Cockpit.bezelRing))
            context.stroke(circle(3.5), with: .color(Cockpit.screw), lineWidth: s)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(value.rounded())) percent")
    }
}

/// Half-circle gauge for objectives.
struct SemicircleGauge: View {
    let value: Double

    private static func degrees(_ percent: Double) -> Double { -90 + percent * 1.8 }

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 124
            let c = CGPoint(x: 62 * s, y: 66 * s)
            var outer = DialGeometry.arc(c, 60 * s, from: -90, to: 90)
            outer.closeSubpath()
            context.fill(outer, with: .color(Cockpit.bezel))
            var inner = DialGeometry.arc(c, 55 * s, from: -90, to: 90)
            inner.closeSubpath()
            context.fill(inner, with: .color(Cockpit.face))
            context.stroke(DialGeometry.arc(c, 57 * s, from: -90, to: Self.degrees(value)), with: .color(Cockpit.bandGreen), lineWidth: 3 * s)
            for v in stride(from: 0, through: 100, by: 10) {
                let major = v % 50 == 0
                context.stroke(
                    DialGeometry.tick(c, 53 * s, (major ? 44 : 48) * s, Self.degrees(Double(v))),
                    with: .color(Cockpit.cream),
                    lineWidth: (major ? 1.8 : 1) * s
                )
            }
            for v in [0, 50, 100] {
                let p = DialGeometry.point(c, 37 * s, Self.degrees(Double(v)))
                context.draw(Text("\(v)").font(Cockpit.label(8 * s)).foregroundColor(Cockpit.secondary), at: CGPoint(x: p.x, y: p.y + 3 * s))
            }
            context.fill(DialGeometry.needle(c, length: 46 * s, tail: 6 * s, width: 1.8 * s, degrees: Self.degrees(value)), with: .color(Cockpit.cream))
            let hub = Path(ellipseIn: CGRect(x: c.x - 4.5 * s, y: c.y - 4.5 * s, width: 9 * s, height: 9 * s))
            context.fill(hub, with: .color(Cockpit.bezelRing))
            context.stroke(hub, with: .color(Cockpit.screw), lineWidth: s)
        }
        .frame(width: 124, height: 74)
        .accessibilityElement()
        .accessibilityLabel("Objective progress")
        .accessibilityValue("\(Int(value.rounded())) percent")
    }
}

/// Small clock whose hand shows how far through its window the reset is.
struct ResetClock: View {
    let fraction: Double?
    let hand: Color

    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let circle = { (r: CGFloat) in Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
            context.fill(circle(21), with: .color(Cockpit.bezel))
            context.fill(circle(18), with: .color(Cockpit.face))
            for i in 0..<12 {
                let major = i % 3 == 0
                context.stroke(DialGeometry.tick(c, 17, major ? 12.5 : 14.5, Double(i) * 30), with: .color(Cockpit.cream), lineWidth: major ? 1.6 : 1)
            }
            if let fraction {
                var handPath = Path()
                handPath.move(to: c)
                handPath.addLine(to: DialGeometry.point(c, 14, min(max(fraction, 0), 1) * 360))
                context.stroke(handPath, with: .color(hand), lineWidth: 2)
            }
            context.fill(circle(2.5), with: .color(Cockpit.cream))
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

/// Mechanical drum counter.
struct Odometer: View {
    let value: Int?

    var body: some View {
        let digits = value.map { Array(String(format: "%03d", min(max($0, 0), 999))) } ?? Array("---")
        HStack(spacing: 2) {
            ForEach(Array(digits.enumerated()), id: \.offset) { _, digit in
                Text(String(digit))
                    .font(Cockpit.label(18, .semibold))
                    .foregroundStyle(Cockpit.cream)
                    .frame(width: 16, height: 24)
                    .background(Color(hex: 0x1F1F1B))
                    .overlay(alignment: .top) { Rectangle().fill(Color(hex: 0x3A3A31)).frame(height: 1) }
            }
        }
        .padding(3)
        .background(Cockpit.bezel, in: RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Cockpit.plateBorder, lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel("Headroom")
        .accessibilityValue(value.map { "\($0) percent" } ?? "No data")
    }
}

struct Lamp: View {
    let text: String
    let isOn: Bool
    let color: Color
    let ink: Color
    var width: CGFloat = 62

    var body: some View {
        Text(text)
            .font(Cockpit.label(10, .semibold))
            .kerning(2)
            .foregroundStyle(isOn ? ink : Cockpit.dim)
            .frame(width: width)
            .padding(.vertical, 1)
            .background(isOn ? color : Cockpit.lampOff, in: RoundedRectangle(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Cockpit.bezel, lineWidth: 1))
            .shadow(color: isOn ? color.opacity(0.55) : .clear, radius: 4)
            .accessibilityLabel("\(text) lamp \(isOn ? "on" : "off")")
    }
}

struct Screw: View {
    let rotation: Double

    var body: some View {
        ZStack {
            Circle().fill(Cockpit.screw)
            Circle().stroke(Cockpit.screwSlot, lineWidth: 1)
            Rectangle().fill(Cockpit.screwSlot).frame(width: 7, height: 1.4).rotationEffect(.degrees(rotation))
        }
        .frame(width: 11, height: 11)
        .accessibilityHidden(true)
    }
}

/// Engraved label plate.
struct Placard: View {
    let text: String
    var size: CGFloat = 14

    var body: some View {
        Text(text)
            .font(Cockpit.label(size, .semibold))
            .kerning(size * 0.2)
            .foregroundStyle(Cockpit.text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(Cockpit.plate, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Cockpit.plateBorder, lineWidth: 1))
    }
}

/// Cream logbook strip.
struct LogStrip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .font(Cockpit.typewriter(12.5))
            .foregroundStyle(Cockpit.paperInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Cockpit.paper, in: RoundedRectangle(cornerRadius: 2))
            .overlay(alignment: .bottom) { Rectangle().fill(Cockpit.paperEdge).frame(height: 2) }
    }
}

/// Screwed-down sub-panel.
struct PanelPlate: ViewModifier {
    var border: Color = Cockpit.subpanelBorder
    var borderWidth: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .background(Cockpit.subpanel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(border, lineWidth: borderWidth))
            .overlay(alignment: .topLeading) { Screw(rotation: 25).padding(7) }
            .overlay(alignment: .topTrailing) { Screw(rotation: -40).padding(7) }
            .overlay(alignment: .bottomLeading) { Screw(rotation: 70).padding(7) }
            .overlay(alignment: .bottomTrailing) { Screw(rotation: 10).padding(7) }
    }
}

extension View {
    func panelPlate(border: Color = Cockpit.subpanelBorder, width: CGFloat = 1) -> some View {
        modifier(PanelPlate(border: border, borderWidth: width))
    }
}

/// A toggle drawn as a cockpit lever switch: up is ON.
struct LeverSwitchStyle: ToggleStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                VStack(spacing: 2) {
                    Text("ON").font(Cockpit.label(8)).kerning(1).foregroundStyle(Cockpit.secondary)
                    ZStack(alignment: configuration.isOn ? .top : .bottom) {
                        Capsule().fill(Cockpit.bezel).frame(width: 8, height: 20)
                        Capsule()
                            .fill(configuration.isOn ? tint : Cockpit.cream)
                            .frame(width: 8, height: 11)
                    }
                }
                .frame(width: 32, height: 40)
                .background(Cockpit.plate, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Cockpit.plateBorder, lineWidth: 1))
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Done" : "Open")
    }
}
