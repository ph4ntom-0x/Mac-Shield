import Foundation

/// Handles physical audio alerts by maximizing system volume and playing alert sounds via afplay.
enum AlarmEngine {
    private static var currentProcess: Process?
    private static var isPlaying = false
    private static let lock = NSLock()

    static func trigger(durationSeconds: Int = 15) {
        lock.lock()
        guard !isPlaying else {
            lock.unlock()
            log(" [AlarmEngine] Alarm is already active, ignoring duplicate trigger.")
            return
        }
        isPlaying = true
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async {
            // Maximize system volume and un-mute output
            runOsascript("set volume output volume 100")
            runOsascript("set volume without output muted")

            let soundPath = "/System/Library/Sounds/Sosumi.aiff"
            let deadline = Date().addingTimeInterval(TimeInterval(durationSeconds))

            log(" [AlarmEngine] Alarm triggered for \(durationSeconds) seconds.")

            while Date() < deadline {
                lock.lock()
                let shouldContinue = isPlaying
                lock.unlock()
                
                guard shouldContinue else { break }

                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
                p.arguments = [soundPath]
                
                lock.lock()
                currentProcess = p
                lock.unlock()

                try? p.run()
                p.waitUntilExit()
            }

            lock.lock()
            isPlaying = false
            currentProcess = nil
            lock.unlock()
            
            log(" [AlarmEngine] Alarm completed.")
        }
    }

    static func stop() {
        lock.lock()
        defer { lock.unlock() }
        
        isPlaying = false
        if let process = currentProcess, process.isRunning {
            process.terminate()
        }
        currentProcess = nil
        log(" [AlarmEngine] Alarm stopped manually.")
    }

    private static func runOsascript(_ script: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath:"/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
        p.waitUntilExit()
    }
}
