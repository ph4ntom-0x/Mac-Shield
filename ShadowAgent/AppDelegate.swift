import Cocoa
import OSLog

extension Logger {
    static let app = Logger(subsystem: "com.ph4ntom.shadow.ShadowAgent", category: "AppDelegate")
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = LogMonitor()
    private var statusItem: NSStatusItem?

    private let logFileURL: URL = {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("ShadowAgent", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        return logsDir.appendingPathComponent("agent.log")
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        log(" [AppDelegate] Initializing ShadowAgent daemon (PID: \(getpid()))...")

        setupStatusItem()

        #if !DEBU
        guard SingleInstanceLock.acquire() else {
            log(" Another instance is already running. Exiting.")
            updateStatusItem(running: false)
            NSApp.terminate(nil)
            return
        }
        #else
        log(" Debug build detected: Bypassing SingleInstanceLock for Xcode development session.")
        #endif

        let mode = USE_EMULATOR ? "Local Emulator Mode: 127.0.0.1:8080" : "Cloud Production Mode"
        log(" ShadowAgent active [\(mode)]")

        monitor.start()
        CommandPoller.start()
        updateStatusItem(running: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Status Item (Menu Bar)
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "ShadowAgent")
        item.button?.imagePosition = .imageLeading
        item.button?.title = "Starting…"

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Log File", action: #selector(openLogFile), keyEquivalent: "l")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit ShadowAgent", action: #selector(quitApp), keyEquivalent: "q")
        item.menu = menu

        self.statusItem = item
    }

    private func updateStatusItem(running: Bool) {
        guard let button = statusItem?.button else { return }
        if running {
            button.title = "Running"
            button.contentTintColor = NSColor.systemGreen
        } else {
            button.title = "Stopped"
            button.contentTintColor = NSColor.systemRed
        }
    }

    @objc private func openLogFile() {
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Logging Helper
    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)"

        // 1. Standard Output
        print(line)
        fflush(stdout)

        // 2. OSLog Stream
        Logger.app.info("\(message, privacy: .public)")

        // 3. Disk File (~/Library/Logs/ShadowAgent/agent.log)
        if let data = (line + "\n").data(using: .utf8) {
            if !FileManager.default.fileExists(atPath: logFileURL.path) {
                FileManager.default.createFile(atPath: logFileURL.path, contents: data)
            } else if let handle = try? FileHandle(forWritingTo: logFileURL) {
                defer { _ = try? handle.close() }
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: data)
            }
        }
    }
}
