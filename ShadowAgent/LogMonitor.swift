import Foundation
import OSLog

extension Logger {
    static let logMonitor = Logger(subsystem: "com.ph4ntom.shadow.ShadowAgent", category: "LogMonitor")
}

/// Monitors macOS system logs for authentication failures and notifies IncidentEngine.
final class LogMonitor {
    private var logProcess: Process?
    private var logPipe: Pipe?
    private let launchTime = Date()
    private let startupGracePeriod: TimeInterval = 5.0

    // MARK: - Debounce State
    private var lastFailureTimestamp: Date = Date.distantPast
    private let debounceInterval: TimeInterval = 4.0

    // MARK: - Predicate Builder
    // Narrowed to the one confirmed-precise signal: loginwindow's screen-lock
    // UI reporting an incorrect password. Broader matching against
    // opendirectoryd/sudo/PAM/generic "authentication failed" text was
    // picking up unrelated background credential-retry noise from other
    // services entirely unrelated to the lock screen — confirmed by a single
    // session UUID repeating every few seconds for over a minute, far more
    // often than any real password attempt could occur.
    private static var logPredicate: String {
        return "process == \"loginwindow\" AND eventMessage CONTAINS[c] \"authFailWithMessage\" AND eventMessage CONTAINS[c] \"INCORRECT password\""
    }

    // MARK: - Lifecycle

    func start() {
        guard logProcess == nil else {
            log("LogMonitor is already running.")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--style", "compact", "--predicate", Self.logPredicate]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        self.logPipe = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }

            let data = handle.availableData
            guard let rawOutput = String(data: data, encoding: .utf8), !rawOutput.isEmpty else { return }

            guard Date().timeIntervalSince(self.launchTime) >= self.startupGracePeriod else {
                return
            }

            let lines = rawOutput.components(separatedBy: .newlines)

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }

                // Drop system log headers and stream connection banners
                if trimmed.hasPrefix("Filtering") ||
                  (trimmed.contains("Timestamp") && trimmed.contains("Process")) {
                    continue
                }

                let lower = trimmed.lowercased()

                // Only keep filters that can't accidentally match the real
                // signal's own class/method names. "screenlock" was removed
                // here — it matched LWDefaultScreenLockUI, the exact class
                // that reports the real event, silently discarding it.
                if lower.contains("incident triggered") ||
                   lower.contains("unauthorized access attempt") ||
                   lower.contains("companions not supported") {
                    self.log("FILTERED OUT (self-log echo): \(trimmed)")
                    continue
                }

                // Debounce log bursts from the same underlying event
                let now = Date()
                if now.timeIntervalSince(self.lastFailureTimestamp) < self.debounceInterval {
                    self.log("SUPPRESSED DUPLICATE (within debounce window): \(trimmed)")
                    continue
                }

                self.lastFailureTimestamp = now
                self.log(" VERIFIED AUTH FAILURE: \(trimmed)")

                Task { @MainActor in
                    IncidentEngine.shared.handleFailedAttempt()
                }
            }
        }

        do {
            try process.run()
            self.logProcess = process
            log("Security Log Monitor active.")
        } catch {
            log("Failed to launch log stream process: \(error.localizedDescription)")
        }
    }

    func stop() {
        logPipe?.fileHandleForReading.readabilityHandler = nil
        logPipe = nil

        if let process = logProcess, process.isRunning {
            process.terminate()
        }
        logProcess = nil
        log("Security Log Monitor stopped.")
    }

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) [LogMonitor] \(message)"

        print(line)
        fflush(stdout)

        Logger.logMonitor.info("\(message, privacy: .public)")

        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("ShadowAgent", isDirectory: true)
        let logFileURL = logsDir.appendingPathComponent("agent.log")

        if let data = (line + "\n").data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                defer { _ = try? handle.close() }
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: data)
            }
        }
    }

    deinit {
        stop()
    }
}
