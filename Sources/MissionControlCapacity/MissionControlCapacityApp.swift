import CapacityCore
import SwiftUI

@main
struct MissionControlCapacityApp: App {
    @StateObject private var store = CapacityStore()

    init() {
        PreviewRenderer.runIfRequested()
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView(store: store, compact: true)
                .frame(width: 430, height: 800)
                .onAppear { store.start() }
        } label: {
            Label("Capacity", systemImage: menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Window("Mission Control: Capacity", id: "dashboard") {
            DashboardView(store: store, compact: false)
                .frame(minWidth: 480, minHeight: 760)
                .onAppear { store.start() }
        }
        .defaultSize(width: 520, height: 860)
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
