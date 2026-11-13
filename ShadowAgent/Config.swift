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

//  Telegram (optional)

let TELEGRAM_TOKEN = Secrets.telegramBotToken
let TELEGRAM_OWNER_ID: Int64 = Secrets.telegramOwnerID

/// false = Telegram gets text alerts   but no photo
let TELEGRAM_SEND_PHOTOS = true

/// false = only Telegram can send commands (the Shadow app's Capture/Alarm stop working)
let FIRESTORE_COMMANDS_ENABLED = true

/// false when the Firebase values in Secrets.swift are empty: Telegram-only mode
let FIRESTORE_ENABLED = !PROJECT_ID.isEmpty && !API_KEY.isEmpty
