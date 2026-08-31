import Darwin
import Foundation

public struct CommandResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
}

public enum CommandRunnerError: LocalizedError {
    case executableMissing(String)
    case launchFailed(String)
    case timedOut(String)

    public var errorDescription: String? {
        switch self {
        case .executableMissing(let name): "Could not find \(name) on this Mac."
        case .launchFailed(let message): message
        case .timedOut(let name): "\(name) did not return usage data in time."
        }
    }
}

public struct ExecutableLocator: Sendable {
    public init() {}

    public func locate(_ name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)"
        ]

        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map {
            URL(fileURLWithPath: $0)
        }
    }
}

public struct CommandRunner: Sendable {
    public init() {}

    public func run(
        executable: URL,
        arguments: [String] = [],
        environment overrides: [String: String] = [:],
        timeout: TimeInterval = 15
    ) async throws -> CommandResult {
        try await Task.detached(priority: .utility) {
            try Self.runSynchronously(
                executable: executable,
                arguments: arguments,
                environment: overrides,
                timeout: timeout
            )
        }.value
    }

    private static func runSynchronously(
        executable: URL,
        arguments: [String],
        environment overrides: [String: String],
        timeout: TimeInterval
    ) throws -> CommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let preferredPath = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        environment["PATH"] = preferredPath + ":" + (environment["PATH"] ?? "")
        // LaunchServices commonly supplies TERM=dumb to GUI apps. The provider
        // CLIs are terminal UIs, so give their tmux/expect clients a real terminal.
        environment["TERM"] = "xterm-256color"
        for (key, value) in overrides {
            environment[key] = value
        }
        process.environment = environment

        do {
            try process.run()
            // Process owns duplicated write descriptors after launch. Closing the
            // parent's copies ensures readDataToEndOfFile observes EOF reliably,
            // including for commands that briefly fork a tmux server.
            stdoutPipe.fileHandleForWriting.closeFile()
            stderrPipe.fileHandleForWriting.closeFile()
        } catch {
            throw CommandRunnerError.launchFailed("Could not launch \(executable.lastPathComponent): \(error.localizedDescription)")
        }

        let completion = DispatchGroup()
        completion.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            completion.leave()
        }

        let timedOut = completion.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            if completion.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = completion.wait(timeout: .now() + 1)
            }
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let result = CommandResult(
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            exitCode: process.terminationStatus
        )

        if timedOut {
            throw CommandRunnerError.timedOut(executable.lastPathComponent)
        }
        return result
    }
}
