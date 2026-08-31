import CapacityCore
import Combine
import Foundation

@MainActor
final class CapacityStore: ObservableObject {
    @Published private(set) var snapshots: [ProviderSnapshot]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?

    private let service: CapacityService
    private var refreshLoop: Task<Void, Never>?

    init(service: CapacityService = .live) {
        self.service = service
        let cached = CapacityCache.load()
        self.snapshots = cached.map(Self.validatedCachedSnapshots)
            ?? ProviderID.allCases.map(ProviderSnapshot.loading)
        self.lastRefresh = cached?.lastPolledAt

        // MenuBarExtra content is created only when clicked. Start here instead so
        // stale snapshots refresh while the app remains quietly in the menu bar.
        Task { [weak self] in self?.start() }
    }

    private static func validatedCachedSnapshots(_ cache: CapacityCacheEnvelope) -> [ProviderSnapshot] {
        cache.snapshots.map { snapshot in
            let successfulDataAgeAtLastCheck = cache.lastPolledAt.timeIntervalSince(snapshot.updatedAt)
            guard snapshot.state == .connected,
                  successfulDataAgeAtLastCheck > CapacityCache.pollInterval * 2 else {
                return snapshot
            }
            let failure = ProviderSnapshot(
                id: snapshot.id,
                state: .error,
                message: "Recent checks did not produce a successful update."
            )
            return snapshot.retainingMeasurements(after: failure)
        }
    }

    func start() {
        guard refreshLoop == nil else { return }
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let age = self.lastRefresh.map { Date().timeIntervalSince($0) }
                let interval = self.snapshots.contains(where: { $0.state == .error })
                    ? CapacityCache.failureRetryInterval
                    : CapacityCache.pollInterval
                if age == nil || age! >= interval {
                    await self.refresh()
                }

                let refreshedAge = self.lastRefresh.map { Date().timeIntervalSince($0) } ?? 0
                let refreshedInterval = self.snapshots.contains(where: { $0.state == .error })
                    ? CapacityCache.failureRetryInterval
                    : CapacityCache.pollInterval
                // Wake periodically so a manual failed refresh also switches the
                // background loop to the shorter retry interval promptly.
                let delay = min(30, max(5, refreshedInterval - refreshedAge))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let fetched = await service.refreshAll()
        snapshots = fetched.map { newSnapshot in
            guard newSnapshot.state == .error,
                  let previous = snapshots.first(where: { $0.id == newSnapshot.id }),
                  !previous.windows.isEmpty else {
                return newSnapshot
            }
            return previous.retainingMeasurements(after: newSnapshot)
        }
        let completedAt = Date()
        lastRefresh = completedAt
        CapacityCache.save(snapshots: snapshots, lastPolledAt: completedAt)
        isRefreshing = false
    }
}
