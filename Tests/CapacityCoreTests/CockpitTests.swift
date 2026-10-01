import Foundation
import Testing
@testable import CapacityCore

@Suite("Cockpit readout")
struct CockpitReadoutTests {
    private func claude(_ id: String, fiveHour: Double, weekly: Double, state: ConnectionState = .connected) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: .anthropic,
            account: AccountRef(id: id, label: id),
            state: state,
            windows: [
                CapacityWindow(id: "anthropic-session", label: "5 hours", usedPercent: fiveHour, durationMinutes: 300),
                CapacityWindow(id: "anthropic-weekly", label: "Weekly", usedPercent: weekly, durationMinutes: 10_080)
            ]
        )
    }

    @Test("routes to the Claude account with the most headroom and flags the one near its limit")
    func routesAndCautions() {
        let readout = CockpitReadout(snapshots: [
            claude("work", fiveHour: 91, weekly: 55),
            claude("personal", fiveHour: 72, weekly: 44),
            claude("org", fiveHour: 12, weekly: 80)
        ])

        #expect(readout.bestClaude?.snapshot.id == "personal")
        #expect(readout.bestClaude?.headroom == 28)
        #expect(readout.masterCaution?.snapshot.id == "work")
    }

    @Test("signed-out accounts are never routed to")
    func skipsSignedOut() {
        let signedOut = ProviderSnapshot(provider: .anthropic, account: AccountRef(id: "org", label: "Org"), state: .unauthenticated)
        let readout = CockpitReadout(snapshots: [claude("work", fiveHour: 40, weekly: 10), signedOut])

        #expect(readout.bestClaude?.snapshot.id == "work")
        #expect(readout.needsSignIn.map(\.snapshot.id) == ["org"])
        #expect(readout.masterCaution == nil)
    }

    @Test("OpenAI dials use the account-wide windows, not model pools")
    func openAIDials() {
        let snapshot = ProviderSnapshot(provider: .openAI, state: .connected, windows: [
            CapacityWindow(id: "codex-primary", label: "Codex account-wide · Weekly", usedPercent: 48, durationMinutes: 10_080),
            CapacityWindow(id: "codex_spark-primary", label: "Spark · 5 hours", usedPercent: 12, durationMinutes: 300)
        ])
        let account = AccountReadout(snapshot)

        #expect(account.fiveHour == nil)
        #expect(account.weekly?.usedPercent == 48)
        #expect(account.otherWindows.map(\.id) == ["codex_spark-primary"])
        #expect(account.headroom == 52)
    }
}

@Suite("Mission board")
struct MissionBoardTests {
    @Test("done tasks stay on their switch bank until the next day")
    func doneTasksStayForTheDay() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let yesterday = now.addingTimeInterval(-86_400)
        let board = MissionBoard(periodTitle: "Q4", tasks: [
            MissionTask(title: "Open", bucket: .now),
            MissionTask(title: "Done today", bucket: .now, isDone: true, completedAt: now),
            MissionTask(title: "Done yesterday", bucket: .now, isDone: true, completedAt: yesterday),
            MissionTask(title: "Later", bucket: .later)
        ])

        #expect(board.tasks(in: .now, now: now, calendar: calendar).map(\.title) == ["Open", "Done today"])
        #expect(board.openTaskCount == 2)
    }

    @Test("counts open tasks due today or overdue")
    func dueToday() {
        let now = Date()
        let board = MissionBoard(periodTitle: "Q4", tasks: [
            MissionTask(title: "Today", due: now),
            MissionTask(title: "Overdue", due: now.addingTimeInterval(-3 * 86_400)),
            MissionTask(title: "Done", due: now, isDone: true),
            MissionTask(title: "Future", due: now.addingTimeInterval(5 * 86_400))
        ])
        #expect(board.dueTodayCount(now: now) == 2)
    }

    @Test("round-trips through missions.json")
    func roundTrips() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missions.json")
        let project = MissionProject(name: "Apollo", phase: "Build", progress: 40, nextAction: "Test burn")
        let board = MissionBoard(
            periodTitle: "Q4",
            projects: [project],
            objectives: [MissionObjective(title: "Reach orbit", progress: 30, keyResultsOnTrack: 1, keyResultsTotal: 2)],
            tasks: [MissionTask(title: "Fuel check", projectID: project.id, due: Date())]
        )
        try MissionBoardFile.save(board, to: url)

        let loaded = try #require(MissionBoardFile.load(from: url))
        #expect(loaded.projects.map(\.name) == board.projects.map(\.name))
        #expect(loaded.tasks.first?.projectID == project.id)
        #expect(loaded.objectives.first?.keyResultsTotal == 2)
    }

    @Test("a first launch starts with an empty board for this quarter")
    func starterIsEmpty() {
        let october = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 10, day: 1).date!
        let board = MissionBoard.starter(now: october, calendar: Calendar(identifier: .gregorian))
        #expect(board.periodTitle == "Q4")
        #expect(board.projects.isEmpty && board.objectives.isEmpty && board.tasks.isEmpty)
    }

    @Test("an unreadable file is reported instead of replaced")
    func unreadableFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: url)
        #expect(MissionBoardFile.load(from: url) == nil)
    }
}
