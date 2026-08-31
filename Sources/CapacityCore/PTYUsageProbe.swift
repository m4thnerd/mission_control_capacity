import Foundation

public enum PTYProbeKind: String, Sendable {
    case cursor
    case anthropic
    case google
    case openAI
}

public struct PTYUsageProbe: Sendable {
    private let runner = CommandRunner()

    public init() {}

    public func run(kind: PTYProbeKind, executable: URL) async throws -> String {
        if kind == .openAI {
            return try await runOpenAI(executable: executable)
        }
        do {
            return try await runInteractive(kind: kind, executable: executable)
        } catch {
            // Terminal UIs can occasionally miss their first readiness window.
            // Background polling makes one clean, isolated retry inexpensive.
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return try await runInteractive(kind: kind, executable: executable)
        }
    }

    private func runInteractive(kind: PTYProbeKind, executable: URL) async throws -> String {
        guard let tmux = ExecutableLocator().locate("tmux") else {
            throw CommandRunnerError.executableMissing("tmux")
        }
        guard let shell = ExecutableLocator().locate("zsh") else {
            throw CommandRunnerError.executableMissing("zsh")
        }

        // Each probe gets its own tmux server. This avoids lock contention with other
        // provider refreshes and guarantees that user-owned tmux sessions are untouched.
        // Keep this deliberately short: GUI apps inherit a long $TMPDIR and tmux's
        // full Unix-domain socket path has a strict platform length limit.
        let kindTag: String = switch kind {
        case .cursor: "cu"
        case .anthropic: "an"
        case .google: "go"
        case .openAI: "oa"
        }
        let nonce = UUID().uuidString.prefix(8)
        let socket = "mcc-\(kindTag)-\(nonce)"

        do {
            let result = try await runner.run(
                executable: shell,
                arguments: ["-c", Self.interactiveProbeScript],
                environment: [
                    "MCC_PROBE_KIND": kind.rawValue,
                    "MCC_PROBE_EXECUTABLE": executable.path,
                    "MCC_PROBE_SOCKET": socket,
                    "MCC_PROBE_TMUX": tmux.path,
                    "MCC_PROBE_WORKDIR": Self.probeWorkingDirectory
                ],
                timeout: 45
            )
            await killOrphan(socket)
            guard result.exitCode == 0 else {
                throw probeFailure(executable.lastPathComponent, result: result)
            }
            return result.stdout
        } catch {
            await killOrphan(socket)
            throw error
        }
    }

    private func runOpenAI(executable: URL) async throws -> String {
        guard let expect = ExecutableLocator().locate("expect") else {
            throw CommandRunnerError.executableMissing("expect")
        }

        let result = try await runner.run(
            executable: expect,
            arguments: ["-c", Self.openAIExpectScript],
            environment: [
                "MCC_PROBE_EXECUTABLE": executable.path,
                "MCC_PROBE_WORKDIR": Self.probeWorkingDirectory
            ],
            timeout: 15
        )
        guard result.exitCode == 0 else {
            throw probeFailure(executable.lastPathComponent, result: result)
        }
        return result.stdout
    }

    private func killOrphan(_ socket: String) async {
        // The socket label is random and project-scoped, so this fallback targets
        // only the exact probe process created above.
        if let pkill = ExecutableLocator().locate("pkill") {
            _ = try? await runner.run(
                executable: pkill,
                arguments: ["-f", "tmux -L \(socket)"],
                timeout: 3
            )
        }
    }

    private func probeFailure(_ name: String, result: CommandResult) -> CommandRunnerError {
        let stderr = ANSIText.clean(result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = ANSIText.clean(result.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
        let diagnostic = (stderr + "\n" + stdout)
            .split(separator: "\n")
            .suffix(8)
            .joined(separator: " ")
        return .launchFailed(diagnostic.isEmpty ? "\(name) usage probe failed." : diagnostic)
    }

    private static var probeWorkingDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let development = home.appendingPathComponent("dev", isDirectory: true)
        return FileManager.default.fileExists(atPath: development.path) ? development.path : home.path
    }

    private static let interactiveProbeScript = #"""
        set -u
        socket="$MCC_PROBE_SOCKET"
        session="probe"
        tmux_bin="$MCC_PROBE_TMUX"
        exe="$MCC_PROBE_EXECUTABLE"
        workdir="$MCC_PROBE_WORKDIR"
        kind="$MCC_PROBE_KIND"

        cleanup() {
            /usr/bin/pkill -f "tmux -L $socket" >/dev/null 2>&1 || true
        }
        trap cleanup EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM

        run_bounded() {
            "$@" &
            local child=$!
            local ticks=0
            while /bin/kill -0 "$child" >/dev/null 2>&1; do
                if (( ticks >= 120 )); then
                    /bin/kill "$child" >/dev/null 2>&1 || true
                    sleep 0.2
                    /bin/kill -9 "$child" >/dev/null 2>&1 || true
                    wait "$child" >/dev/null 2>&1 || true
                    return 124
                fi
                sleep 0.1
                (( ticks += 1 ))
            done
            wait "$child"
        }

        case "$kind" in
            cursor)
                run_bounded "$tmux_bin" -L "$socket" new-session -d -s "$session" -x 160 -y 60 -c "$workdir" "$exe" --trust --mode ask || exit $?
                ;;
            anthropic)
                run_bounded "$tmux_bin" -L "$socket" new-session -d -s "$session" -x 160 -y 60 -c "$workdir" "$exe" --permission-mode plan || exit $?
                ;;
            google)
                run_bounded "$tmux_bin" -L "$socket" new-session -d -s "$session" -x 160 -y 60 -c "$workdir" "$exe" --mode plan || exit $?
                ;;
            *)
                print -u2 "Unknown interactive provider: $kind"
                exit 64
                ;;
        esac

        sleep 5
        run_bounded "$tmux_bin" -L "$socket" send-keys -t "$session" -l /usage || exit $?
        run_bounded "$tmux_bin" -L "$socket" send-keys -t "$session" Enter || exit $?
        if [[ "$kind" == "cursor" ]]; then
            sleep 0.6
            run_bounded "$tmux_bin" -L "$socket" send-keys -t "$session" Enter || exit $?
            sleep 3
        elif [[ "$kind" == "anthropic" ]]; then
            sleep 5
        else
            sleep 4
        fi

        run_bounded "$tmux_bin" -L "$socket" capture-pane -p -J -t "$session" -S -100 || exit $?
        """#

    private static let openAIExpectScript = #"""
        set timeout 12
        match_max 200000
        log_user 1
        set exe $env(MCC_PROBE_EXECUTABLE)
        set env(TERM) "xterm-256color"
        if {[info exists env(MCC_PROBE_WORKDIR)]} {
            cd $env(MCC_PROBE_WORKDIR)
        }

        proc fail {message} {
            puts stderr $message
            exit 124
        }

        spawn -noecho $exe app-server --stdio
        send -- "{\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"mission-control-capacity\",\"version\":\"0.1.0\"}}}\r"
        expect {
            -re {\"id\":1.*\"result\"} {}
            timeout { fail "Codex app server did not initialize" }
        }
        send -- "{\"method\":\"initialized\"}\r"
        send -- "{\"id\":2,\"method\":\"account/rateLimits/read\"}\r"
        expect {
            -re {\"id\":2,\"result\":.*\}\r\n} {}
            timeout { fail "Codex did not return rate limits" }
        }
        after 300
        catch { close }
        catch { wait }
        exit 0
        """#
}
