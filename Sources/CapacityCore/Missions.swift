import Foundation

public enum TaskBucket: String, Codable, CaseIterable, Identifiable, Sendable {
    case now, next, later

    public var id: String { rawValue }
    public var title: String { rawValue.uppercased() }
}

public struct MissionProject: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var phase: String
    public var progress: Double
    public var nextAction: String

    public init(id: UUID = UUID(), name: String, phase: String = "Build", progress: Double = 0, nextAction: String = "") {
        self.id = id
        self.name = name
        self.phase = phase
        self.progress = progress
        self.nextAction = nextAction
    }
}

public struct MissionObjective: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var progress: Double
    public var keyResultsOnTrack: Int
    public var keyResultsTotal: Int
    public var note: String

    public init(
        id: UUID = UUID(),
        title: String,
        progress: Double = 0,
        keyResultsOnTrack: Int = 0,
        keyResultsTotal: Int = 0,
        note: String = ""
    ) {
        self.id = id
        self.title = title
        self.progress = progress
        self.keyResultsOnTrack = keyResultsOnTrack
        self.keyResultsTotal = keyResultsTotal
        self.note = note
    }

    /// "2 of 4 key results on track", or the note when there are no key results.
    public var summary: String {
        guard keyResultsTotal > 0 else { return note }
        return "\(keyResultsOnTrack) of \(keyResultsTotal) key results on track"
    }
}

public struct MissionTask: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var projectID: UUID?
    public var bucket: TaskBucket
    public var due: Date?
    public var isDone: Bool
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        projectID: UUID? = nil,
        bucket: TaskBucket = .now,
        due: Date? = nil,
        isDone: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.projectID = projectID
        self.bucket = bucket
        self.due = due
        self.isDone = isDone
        self.completedAt = completedAt
    }

    public func isDue(on day: Date, calendar: Calendar = .current) -> Bool {
        guard let due, !isDone else { return false }
        return calendar.compare(due, to: day, toGranularity: .day) != .orderedDescending
    }
}

/// Everything on the operations side of the panel, saved as one JSON file.
public struct MissionBoard: Codable, Sendable {
    public var periodTitle: String
    public var projects: [MissionProject]
    public var objectives: [MissionObjective]
    public var tasks: [MissionTask]

    public init(
        periodTitle: String,
        projects: [MissionProject] = [],
        objectives: [MissionObjective] = [],
        tasks: [MissionTask] = []
    ) {
        self.periodTitle = periodTitle
        self.projects = projects
        self.objectives = objectives
        self.tasks = tasks
    }

    public func project(for task: MissionTask) -> MissionProject? {
        task.projectID.flatMap { id in projects.first { $0.id == id } }
    }

    /// Open tasks in a bucket, plus ones completed today so a flipped switch
    /// stays visible until tomorrow.
    public func tasks(in bucket: TaskBucket, now: Date = Date(), calendar: Calendar = .current) -> [MissionTask] {
        tasks.filter { task in
            guard task.bucket == bucket else { return false }
            guard task.isDone else { return true }
            return task.completedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        }
    }

    public var openTaskCount: Int { tasks.filter { !$0.isDone }.count }

    public func dueTodayCount(now: Date = Date(), calendar: Calendar = .current) -> Int {
        tasks.filter { $0.isDue(on: now, calendar: calendar) }.count
    }

    /// The board a first launch starts with: empty, titled for this quarter.
    public static func starter(now: Date = Date(), calendar: Calendar = .current) -> MissionBoard {
        MissionBoard(periodTitle: quarterTitle(for: now, calendar: calendar))
    }

    public static func quarterTitle(for date: Date, calendar: Calendar = .current) -> String {
        let month = calendar.component(.month, from: date)
        return "Q\((month - 1) / 3 + 1)"
    }
}

public enum MissionBoardFile {
    public static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mission Control Capacity", isDirectory: true)
            .appendingPathComponent("missions.json", isDirectory: false)
    }

    /// The saved board, a starter board on first launch, or nil when a file
    /// exists but cannot be read (so it is never silently overwritten).
    public static func load(from url: URL = fileURL) -> MissionBoard? {
        guard FileManager.default.fileExists(atPath: url.path) else { return .starter() }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(MissionBoard.self, from: data)
    }

    public static func save(_ board: MissionBoard, to url: URL = fileURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(board).write(to: url, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
