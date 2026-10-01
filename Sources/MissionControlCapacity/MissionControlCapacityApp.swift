import CapacityCore
import SwiftUI

@main
struct MissionControlCapacityApp: App {
    @StateObject private var store = CapacityStore()
    @StateObject private var missions = MissionStore()
    @AppStorage(DashboardTheme.storageKey) private var theme = DashboardTheme.default

    init() {
        PreviewRenderer.runIfRequested()
    }

    var body: some Scene {
        MenuBarExtra {
            ThemedMenu(capacity: store, missions: missions)
                .frame(width: 430, height: theme.showsMissions ? 760 : 800)
                .onAppear { store.start() }
        } label: {
            Label("Capacity", systemImage: menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Window("Mission Control", id: "dashboard") {
            ThemedDashboard(capacity: store, missions: missions)
                .onAppear { store.start() }
        }
        .defaultSize(width: theme.showsMissions ? 1440 : 520, height: theme.showsMissions ? 900 : 860)
        .commands {
            CommandMenu("Theme") {
                Picker("Theme", selection: $theme) {
                    ForEach(DashboardTheme.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.inline)
            }
        }
    }

    private var menuBarSymbol: String {
        let connected = store.snapshots.filter { $0.state == .connected }
        let highestUsage = connected.flatMap(\.windows).map(\.usedPercent).max() ?? 0
        if store.snapshots.contains(where: { $0.state == .error || $0.state == .unauthenticated }) {
            return "gauge.with.dots.needle.67percent.and.arrowtriangle"
        }
        if highestUsage >= 80 { return "gauge.with.dots.needle.100percent" }
        if highestUsage >= 50 { return "gauge.with.dots.needle.67percent" }
        return "gauge.with.dots.needle.33percent"
    }
}
