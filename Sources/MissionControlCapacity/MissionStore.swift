import CapacityCore
import Combine
import Foundation

/// Projects, objectives and tasks, saved to `missions.json` after every edit.
@MainActor
final class MissionStore: ObservableObject {
    @Published private(set) var board: MissionBoard
    @Published private(set) var saveError: String?

    /// False when an existing file could not be read; edits are then kept in
    /// memory only so the unreadable file is never overwritten.
    private let canSave: Bool

    init() {
        let isFirstLaunch = !FileManager.default.fileExists(atPath: MissionBoardFile.fileURL.path)
        if let board = MissionBoardFile.load() {
            self.board = board
            self.canSave = true
            // Keep the starter board's ids and due dates stable from day one.
            if isFirstLaunch, !CommandLine.arguments.contains(where: { $0.hasPrefix("--render-") }) {
                try? MissionBoardFile.save(board)
            }
        } else {
            self.board = MissionBoard(periodTitle: MissionBoard.quarterTitle(for: Date()))
            self.canSave = false
            self.saveError = "missions.json could not be read; changes are not being saved."
        }
    }

    // MARK: Tasks

    func toggle(_ task: MissionTask) {
        update(task.id, in: \.tasks) {
            $0.isDone.toggle()
            $0.completedAt = $0.isDone ? Date() : nil
        }
    }

    func upsert(_ task: MissionTask) { upsert(task, in: \.tasks) }

    func move(_ task: MissionTask, to bucket: TaskBucket) {
        update(task.id, in: \.tasks) { $0.bucket = bucket }
    }

    func delete(_ task: MissionTask) { mutate { $0.tasks.removeAll { $0.id == task.id } } }

    // MARK: Projects

    func upsert(_ project: MissionProject) { upsert(project, in: \.projects) }

    func delete(_ project: MissionProject) {
        mutate { board in
            board.projects.removeAll { $0.id == project.id }
            for index in board.tasks.indices where board.tasks[index].projectID == project.id {
                board.tasks[index].projectID = nil
            }
        }
    }

    // MARK: Objectives

    func upsert(_ objective: MissionObjective) { upsert(objective, in: \.objectives) }

    func delete(_ objective: MissionObjective) { mutate { $0.objectives.removeAll { $0.id == objective.id } } }

    func setPeriodTitle(_ title: String) { mutate { $0.periodTitle = title } }

    // MARK: Helpers

    private func upsert<Item: Identifiable>(_ item: Item, in path: WritableKeyPath<MissionBoard, [Item]>) {
        mutate { board in
            if let index = board[keyPath: path].firstIndex(where: { $0.id == item.id }) {
                board[keyPath: path][index] = item
            } else {
                board[keyPath: path].append(item)
            }
        }
    }

    private func update<Item: Identifiable>(
        _ id: Item.ID,
        in path: WritableKeyPath<MissionBoard, [Item]>,
        _ change: (inout Item) -> Void
    ) {
        mutate { board in
            guard let index = board[keyPath: path].firstIndex(where: { $0.id == id }) else { return }
            change(&board[keyPath: path][index])
        }
    }

    private func mutate(_ change: (inout MissionBoard) -> Void) {
        change(&board)
        guard canSave else { return }
        do {
            try MissionBoardFile.save(board)
            saveError = nil
        } catch {
            saveError = "Could not save missions.json: \(error.localizedDescription)"
        }
    }
}
