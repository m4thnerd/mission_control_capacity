import AppKit
import CapacityCore
import SwiftUI

/// Every look the dashboard can wear. All themes show the same live readout
/// and the same projects, objectives and tasks; only the presentation differs.
enum DashboardTheme: String, CaseIterable, Identifiable {
    case console
    case flightDeck
    case flightManual
    case orbital
    case opsBoard
    case instrumentPanel
    case glassCockpit
    case departureBoard
    case blueprint
    case analogCockpit
    case dailyBriefing
    case assistantHUD

    static let storageKey = "dashboardTheme"
    static let `default` = DashboardTheme.console

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .console: "Console"
        case .flightDeck: "Flight Deck"
        case .flightManual: "Flight Manual"
        case .orbital: "Orbital"
        case .opsBoard: "Ops Board"
        case .instrumentPanel: "Instrument Panel"
        case .glassCockpit: "Glass Cockpit"
        case .departureBoard: "Departure Board"
        case .blueprint: "Blueprint"
        case .analogCockpit: "Analog Cockpit"
        case .dailyBriefing: "Daily Briefing"
        case .assistantHUD: "Assistant HUD"
        }
    }

    /// Light themes get light system controls (sheets, menus, pickers).
    var colorScheme: ColorScheme {
        switch self {
        case .flightManual, .opsBoard, .instrumentPanel, .departureBoard, .dailyBriefing: .light
        default: .dark
        }
    }

    /// The original console shows capacity only; every other theme is a full
    /// mission panel and needs a wide window.
    var showsMissions: Bool { self != .console }
}

// MARK: - Routing

/// The dashboard window's content, in the chosen theme.
struct ThemedDashboard: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    var staticLayout = false
    @AppStorage(DashboardTheme.storageKey) private var theme = DashboardTheme.default

    var body: some View {
        Group {
            switch theme {
            case .console: DashboardView(store: capacity, compact: false, staticLayout: staticLayout)
            case .flightDeck: FlightDeckDashboardView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .flightManual: FlightManualDashboardView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .orbital: OrbitalDashboardView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .opsBoard: OpsBoardDashboardView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .instrumentPanel: InstrumentPanelDashboardView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .glassCockpit: GlassCockpitDashboardView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .departureBoard: DepartureBoardDashboardView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .blueprint: BlueprintDashboardView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .analogCockpit: CockpitDashboardView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .dailyBriefing: DailyBriefingDashboardView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .assistantHUD: AssistantHUDDashboardView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            }
        }
        .frame(
            minWidth: theme.showsMissions ? 1280 : 480,
            minHeight: theme.showsMissions ? 820 : 760
        )
        .preferredColorScheme(theme.colorScheme)
    }
}

/// The menu-bar popover's content, in the chosen theme.
struct ThemedMenu: View {
    @ObservedObject var capacity: CapacityStore
    @ObservedObject var missions: MissionStore
    var staticLayout = false
    @AppStorage(DashboardTheme.storageKey) private var theme = DashboardTheme.default

    var body: some View {
        Group {
            switch theme {
            case .console: DashboardView(store: capacity, compact: true, staticLayout: staticLayout)
            case .flightDeck: FlightDeckMenuView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .flightManual: FlightManualMenuView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .orbital: OrbitalMenuView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .opsBoard: OpsBoardMenuView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .instrumentPanel: InstrumentPanelMenuView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .glassCockpit: GlassCockpitMenuView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .departureBoard: DepartureBoardMenuView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .blueprint: BlueprintMenuView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .analogCockpit: CockpitMenuView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .dailyBriefing: DailyBriefingMenuView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            case .assistantHUD: AssistantHUDMenuView(capacity: capacity, missions: missions, staticLayout: staticLayout)
            }
        }
        .preferredColorScheme(theme.colorScheme)
    }
}

/// Theme switcher for any header or footer. Pass the theme's own label view.
struct ThemePicker<Label: View>: View {
    @AppStorage(DashboardTheme.storageKey) private var theme = DashboardTheme.default
    @ViewBuilder let label: Label

    var body: some View {
        Menu {
            Picker("Theme", selection: $theme) {
                ForEach(DashboardTheme.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            label
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Change the dashboard's theme")
        .accessibilityLabel("Theme: \(theme.displayName)")
    }
}

// MARK: - Mission actions shared by every theme

extension View {
    /// Edit / Move To / Delete for a task.
    func taskActions(_ task: MissionTask, missions: MissionStore, editor: Binding<MissionEditor?>) -> some View {
        contextMenu {
            Button("Edit Task…") { editor.wrappedValue = .task(task) }
            Menu("Move To") {
                ForEach(TaskBucket.allCases.filter { $0 != task.bucket }) { bucket in
                    Button(bucket.title) { missions.move(task, to: bucket) }
                }
            }
            Divider()
            Button("Delete Task", role: .destructive) { missions.delete(task) }
        }
    }

    /// Edit / Add Task / Delete for a project; double-click edits.
    func projectActions(_ project: MissionProject, missions: MissionStore, editor: Binding<MissionEditor?>) -> some View {
        contentShape(Rectangle())
            .onTapGesture(count: 2) { editor.wrappedValue = .project(project) }
            .contextMenu {
                Button("Edit Project…") { editor.wrappedValue = .project(project) }
                Button("Add Task to \(project.name)…") {
                    editor.wrappedValue = .task(MissionTask(title: "", projectID: project.id))
                }
                Divider()
                Button("Delete Project", role: .destructive) { missions.delete(project) }
            }
    }

    /// Edit / Delete for an objective; double-click edits.
    func objectiveActions(_ objective: MissionObjective, missions: MissionStore, editor: Binding<MissionEditor?>) -> some View {
        contentShape(Rectangle())
            .onTapGesture(count: 2) { editor.wrappedValue = .objective(objective) }
            .contextMenu {
                Button("Edit Objective…") { editor.wrappedValue = .objective(objective) }
                Divider()
                Button("Delete Objective", role: .destructive) { missions.delete(objective) }
            }
    }

    /// Presents the task/project/objective editor sheets.
    func missionEditorSheet(_ editor: Binding<MissionEditor?>, missions: MissionStore) -> some View {
        sheet(item: editor) { MissionEditorSheet(editor: $0, missions: missions) }
    }
}

/// Binding that flips a task's done state, for Toggle-based checkboxes.
@MainActor
func doneBinding(_ task: MissionTask, missions: MissionStore) -> Binding<Bool> {
    Binding(get: { task.isDone }, set: { _ in missions.toggle(task) })
}

// MARK: - Shared wording

enum ThemeText {
    /// "WED 01 OCT 2026".
    static func plateDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE dd MMM yyyy"
        return formatter.string(from: date).uppercased()
    }

    /// "PROBED 4M AGO" style freshness label.
    static func probedLabel(_ lastRefresh: Date?, now: Date) -> String {
        guard let lastRefresh else { return "FIRST PROBE PENDING" }
        let seconds = max(0, Int(now.timeIntervalSince(lastRefresh)))
        if seconds < 60 { return "PROBED JUST NOW" }
        if seconds < 3_600 { return "PROBED \(seconds / 60)M AGO" }
        return "PROBED \(seconds / 3_600)H AGO"
    }

    /// Time until the account's binding window resets: "21M", "1H 02M", "5D 14H".
    static func resetText(_ account: AccountReadout, now: Date) -> String {
        guard let window = account.bindingWindow else { return "—" }
        if let reset = window.resetsAt {
            let seconds = max(0, Int(reset.timeIntervalSince(now)))
            if seconds < 60 { return "<1M" }
            if seconds < 3_600 { return "\(seconds / 60)M" }
            if seconds < 86_400 { return "\(seconds / 3_600)H \(String(format: "%02d", (seconds % 3_600) / 60))M" }
            return "\(seconds / 86_400)D \(seconds % 86_400 / 3_600)H"
        }
        return (window.resetDescription ?? "—").replacingOccurrences(of: "Resets ", with: "").uppercased()
    }

    /// Fraction of the binding window still to run before reset, for clock hands.
    static func resetFraction(_ account: AccountReadout, now: Date) -> Double? {
        guard let window = account.bindingWindow,
              let reset = window.resetsAt,
              let duration = window.durationMinutes else { return nil }
        return min(max(reset.timeIntervalSince(now) / Double(duration * 60), 0), 1)
    }

    /// "TODAY", "OVERDUE", "SAT" or "OCT 14"; nil without a due date.
    static func dueLabel(_ task: MissionTask, now: Date) -> String? {
        guard let due = task.due else { return nil }
        let calendar = Calendar.current
        if calendar.isDate(due, inSameDayAs: now) { return "TODAY" }
        if due < now, !task.isDone { return "OVERDUE" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        if days < 7 { return due.formatted(.dateTime.weekday(.abbreviated)).uppercased() }
        return due.formatted(.dateTime.month(.abbreviated).day()).uppercased()
    }

    /// One-line identity under an account's name: email/org and plan, or staleness.
    static func identityLine(_ account: AccountReadout) -> String {
        let snapshot = account.snapshot
        if snapshot.state == .error, account.hasMeasurements {
            let minutes = max(0, Int(Date().timeIntervalSince(snapshot.updatedAt)) / 60)
            return "STALE · LAST GOOD \(minutes)M AGO"
        }
        let parts = [snapshot.account.identity, snapshot.plan.map { "\($0) plan" }].compactMap { $0 }
        return parts.isEmpty ? snapshot.provider.displayName : parts.joined(separator: " · ")
    }

    /// Plain-language situation report used by logbooks, headlines and briefings.
    static func briefing(_ readout: CockpitReadout) -> [String] {
        var lines: [String] = []
        if let caution = readout.masterCaution, let peak = caution.peakUsed {
            lines.append("\(caution.snapshot.account.label) is at \(Int(peak.rounded()))% of a usage window.")
        } else {
            lines.append("Every account is below \(Int(AccountReadout.cautionThreshold))% of its limits.")
        }
        if let best = readout.bestClaude, let headroom = best.headroom {
            lines.append("Route the next Claude session to \(best.snapshot.account.label) — \(Int(headroom.rounded()))% headroom.")
        }
        for account in readout.needsSignIn {
            lines.append("\(account.snapshot.account.label) needs sign-in.")
        }
        return lines
    }

    /// "Best for" guidance as a tooltip.
    static func guide(_ provider: ProviderID) -> String {
        let guide = ProviderGuide.forProvider(provider)
        return ([guide.headline] + guide.bestFor.map { "• \($0)" }).joined(separator: "\n")
    }
}

/// Opens the dashboard window from a menu-bar popover.
struct OpenDashboardAction {
    let openWindow: OpenWindowAction

    @MainActor
    func callAsFunction() {
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
    }
}
