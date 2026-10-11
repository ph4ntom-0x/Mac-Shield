import Foundation

// Project Configuration
let PROJECT_ID = Secrets.projectID
let API_KEY    = Secrets.apiKey
let DEVICE_NAME = Host.current().localizedName ?? "MacBook"

/// Toggles between local Firebase Emulator and live Google Cloud Firestore
let USE_EMULATOR = false

/// Dynamic Firestore REST Endpoint
var BASE_URL: String {
    if USE_EMULATOR {
        return "http://127.0.0.1:8080/v1/projects/\(PROJECT_ID)/databases/(default)/documents"
    } else {
        return "https://firestore.googleapis.com/v1/projects/\(PROJECT_ID)/databases/(default)/documents"
    }
}

//  Global Logging

private let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}()

/// Global logger with timestamping and immediate stdout flushing for background agents.
func log(_ message: String) {
    let timestamp = timestampFormatter.string(from: Date())
    print("[\(timestamp)] \(message)")
    fflush(stdout)
}
