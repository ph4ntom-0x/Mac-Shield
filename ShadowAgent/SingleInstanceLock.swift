import Foundation

/// Ensures only a single instance of ShadowAgent executes concurrently using POSIX file descriptor locking.
enum SingleInstanceLock {
    private static var fileDescriptor: Int32 = -1

    /// Attempts to acquire an exclusive kernel lock for the current process.
    /// - Returns: `true` if lock was successfully acquired; `false` if another instance is active.
    @discardableResult
    static func acquire() -> Bool {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("ShadowAgent", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockPath = directory.appendingPathComponent("ShadowAgent.lock").path

        // Open or create the lock file
        fileDescriptor = open(lockPath, O_CREAT | O_RDWR, 0666)
        guard fileDescriptor != -1 else {
            print(" [SingleInstanceLock] Failed to open lock file descriptor.")
            return false
        }

        // Apply non-blocking exclusive lock managed directly by the kernel
        if flock(fileDescriptor, LOCK_EX | LOCK_NB) != 0 {
            close(fileDescriptor)
            fileDescriptor = -1
            print(" [SingleInstanceLock] Another instance is active. Lock acquisition failed.")
            return false
        }

        print(" [SingleInstanceLock] Exclusive kernel lock acquired [PID \(ProcessInfo.processInfo.processIdentifier)].")
        return true
    }
}
