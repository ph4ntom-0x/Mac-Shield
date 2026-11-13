import Foundation
import AppKit

/// Sends incident alerts to a Telegram bot chat and receives the owner's button taps.
///
/// - Outbound HTTPS only: no server, no open port on the Mac.
/// - Commands are accepted ONLY from the owner's Telegram user ID (Secrets.telegramOwnerID).
/// - Leave the token empty in Secrets.swift to turn Telegram off completely.
@MainActor
final class TelegramNotifier {
    static let shared = TelegramNotifier()
    private init() {}

    //  State

    private var pollingTask: Task<Void, Never>?
    private var nextOffset: Int?

    private let longPollSeconds = 25
    /// Buttons older than this are refused, so an old tap cannot fire the camera later.
    private let buttonLifetime: TimeInterval = 1800

    private var isConfigured: Bool { !TELEGRAM_TOKEN.isEmpty }
    private var isReady: Bool { isConfigured && TELEGRAM_OWNER_ID != 0 }

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45   // longer than the 25 s long poll
        return URLSession(configuration: config)
    }()

    //  Lifecycle

    func start() {
        guard isConfigured else {
            log(" [Telegram] Off (no bot token in Secrets.swift).")
            return
        }
        guard pollingTask == nil else { return }

        if isReady {
            log(" [Telegram] Active. Listening for the owner's buttons and commands.")
        } else {
            log(" [Telegram] Setup mode: message your bot, then copy the user ID from this log into Secrets.swift.")
        }

        pollingTask = Task {
            await discardBacklog()
            await pollLoop()
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    //  Sending (called by IncidentEngine)

    /// Text-only alert with Capture and Alarm buttons.
    func sendAlert(incidentID: String, device: String) async {
        guard isReady else { return }
        let text = """
         Suspicious activity on \(device)
        Someone entered the wrong password 3 times on the lock screen.

        No photo or location was taken. Use the buttons below if you want one.
        Tip: send /realtime to capture automatically next time.
        Incident: \(incidentID)
        """
        await sendMessage(text, markup: keyboard(for: incidentID))
    }

    /// A capture result: photo (if allowed and available), plus location.
    func sendCapture(incidentID: String,
                     eventType: String,
                     device: String,
                     imageData: Data?,
                     locationText: String,
                     latitude: Double?,
                     longitude: Double?) async {
        guard isReady else { return }

        let title = (eventType == "REMOTE_CAPTURE")
            ? "Capture you asked for, from \(device)"
            : " Real-Time capture after 3 wrong passwords on \(device)"

        var caption = "\(title)\nLocation: \(locationText)"
        if let lat = latitude, let lon = longitude {
            caption += "\nMap: https://maps.google.com/?q=\(lat),\(lon)"
        }
        caption += "\nIncident: \(incidentID)"

        if TELEGRAM_SEND_PHOTOS, let imageData = imageData, let jpeg = jpegData(from: imageData) {
            let sent = await sendPhoto(jpeg, caption: caption)
            if !sent { await sendMessage(caption + "\n(The photo could not be sent.)") }
        } else if imageData == nil {
            await sendMessage(caption + "\n(No photo: the camera gave nothing.)")
        } else {
            await sendMessage(caption + (TELEGRAM_SEND_PHOTOS ? "\n(The photo could not be prepared.)" : "\n(Photos are switched off for Telegram.)"))
        }

        if let lat = latitude, let lon = longitude {
            await sendLocation(latitude: lat, longitude: lon)
        }
    }

    //  Receiving

    /// Skips anything that arrived while the agent was off, so old taps never run.
    private func discardBacklog() async {
        guard let updates = try? await fetchUpdates(offset: -1, timeout: 0),
              let last = updates.last else { return }
        nextOffset = last.updateId + 1
        log(" [Telegram] Ignored \(updates.count) old update(s) from before start-up.")
    }

    private func pollLoop() async {
        var failures = 0
        while !Task.isCancelled {
            do {
                let updates = try await fetchUpdates(offset: nextOffset, timeout: longPollSeconds)
                failures = 0
                for update in updates {
                    nextOffset = update.updateId + 1
                    await handle(update)
                }
            } catch {
                if Task.isCancelled { break }
                failures += 1
                let delay = min(Double(failures) * 5, 60)
                log(" [Telegram] Poll problem: \(safe(error.localizedDescription)). Retrying in \(Int(delay))s.")
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func handle(_ update: TGUpdate) async {
        if let callback = update.callbackQuery {
            await handleCallback(callback)
        } else if let message = update.message {
            await handleMessage(message)
        }
    }

    private func handleCallback(_ callback: TGCallback) async {
        guard isReady else { return }

        // Only the owner may press the buttons.
        guard callback.from.id == TELEGRAM_OWNER_ID else {
            log(" [Telegram] Ignored a button tap from an unknown user.")
            return
        }

        // Refuse old buttons.
        if let message = callback.message {
            let age = Date().timeIntervalSince1970 - TimeInterval(message.date)
            if message.date == 0 || age > buttonLifetime {
                await answerCallback(callback.id, text: "This button has expired. Wait for a new alert.")
                return
            }
        }

        let parts = (callback.data ?? "").split(separator: ":", maxSplits: 1).map(String.init)
        guard let action = parts.first else { return }

        switch action {
        case "cap":
            log(" [Telegram] Owner pressed Capture photo.")
            await answerCallback(callback.id, text: "Capturing… the photo will arrive in a few seconds.")
            IncidentEngine.shared.handleManualCapture()
        case "alarm":
            log(" [Telegram] Owner pressed Sound alarm.")
            await answerCallback(callback.id, text: "Alarm started.")
            AlarmEngine.trigger()
        case "rt":
            guard parts.count > 1, parts[1] == "on" || parts[1] == "off" else { return }
            let turnOn = (parts[1] == "on")
            await answerCallback(callback.id, text: turnOn ? "Real-Time Mode on." : "Real-Time Mode off.")
            await changeRealTime(to: turnOn)
        default:
            log(" [Telegram] Ignored an unknown button action.")
        }
    }

    private func handleMessage(_ message: TGMessage) async {
        // Setup mode: just show the sender's ID in the log so you can copy it.
        guard isReady else {
            if let user = message.from {
                log(" [Telegram] Setup: a message arrived from user ID \(user.id). Put this number in Secrets.swift as telegramOwnerID.")
            }
            return
        }

        // Only the owner, and only in a private chat.
        guard message.from?.id == TELEGRAM_OWNER_ID, message.chat.id == TELEGRAM_OWNER_ID else {
            log(" [Telegram] Ignored a message from an unknown user.")
            return
        }

        let text = (message.text ?? "").lowercased().trimmingCharacters(in: .whitespaces)

        if text.hasPrefix("/realtime") {
            let argument = text.dropFirst("/realtime".count).trimmingCharacters(in: .whitespaces)
            switch argument {
            case "on":  await changeRealTime(to: true)
            case "off": await changeRealTime(to: false)
            default:    await showRealTime()
            }
        } else if text.hasPrefix("/status") || text.hasPrefix("/start") {
            let on = await SettingsManager.currentRealTimeMode()
            await sendMessage("  Mac Shield is running on \(DEVICE_NAME).\nReal-Time Mode is \(on ? "ON" : "OFF").\n\nCommands: /status, /realtime")
        } else {
            await sendMessage("Commands: /status, /realtime. Alerts arrive here by themselves, with buttons.")
        }
    }

    // Real-Time Mode (controlled from Telegram)

    private func realTimeText(_ on: Bool) -> String {
        on
        ? "  Real-Time Mode is ON.\nAfter 3 wrong passwords I will take a photo and location straight away.\n\nNote: a few Touch ID misses can also trigger this."
        : "  Real-Time Mode is OFF.\nAfter 3 wrong passwords you get an alert first, and you choose whether to capture."
    }

    private func realTimeKeyboard(_ on: Bool) -> [String: Any] {
        [
            "inline_keyboard": [[
                ["text": on ? " Turn OFF" : "⚡ Turn ON", "callback_data": on ? "rt:off" : "rt:on"]
            ]]
        ]
    }

    private func showRealTime() async {
        let on = await SettingsManager.currentRealTimeMode()
        await sendMessage(realTimeText(on), markup: realTimeKeyboard(on))
    }

    private func changeRealTime(to on: Bool) async {
        await SettingsManager.setRealTimeMode(on)
        log(" [Telegram] Real-Time Mode set to \(on ? "ON" : "OFF") from Telegram.")
        await sendMessage(realTimeText(on), markup: realTimeKeyboard(on))
    }

    //  Telegram API calls

    private func endpoint(_ method: String) -> URL? {
        URL(string: "https://api.telegram.org/bot\(TELEGRAM_TOKEN)/\(method)")
    }

    private func fetchUpdates(offset: Int?, timeout: Int) async throws -> [TGUpdate] {
        guard let url = endpoint("getUpdates") else { throw URLError(.badURL) }

        var body: [String: Any] = [
            "timeout": timeout,
            "allowed_updates": ["message", "callback_query"]
        ]
        if let offset = offset { body["offset"] = offset }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(TGResponse<[TGUpdate]>.self, from: data)

        guard decoded.ok, let result = decoded.result else {
            throw TelegramError.api(decoded.description ?? "unknown error")
        }
        return result
    }

    @discardableResult
    private func sendMessage(_ text: String, markup: [String: Any]? = nil) async -> Bool {
        var body: [String: Any] = ["chat_id": TELEGRAM_OWNER_ID, "text": text]
        if let markup = markup { body["reply_markup"] = markup }
        return await postJSON("sendMessage", body: body)
    }

    @discardableResult
    private func sendLocation(latitude: Double, longitude: Double) async -> Bool {
        await postJSON("sendLocation", body: [
            "chat_id": TELEGRAM_OWNER_ID,
            "latitude": latitude,
            "longitude": longitude
        ])
    }

    private func answerCallback(_ id: String, text: String) async {
        _ = await postJSON("answerCallbackQuery", body: ["callback_query_id": id, "text": text])
    }

    private func sendPhoto(_ jpeg: Data, caption: String) async -> Bool {
        guard let url = endpoint("sendPhoto") else { return false }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        let fields: [String: String] = ["chat_id": String(TELEGRAM_OWNER_ID), "caption": caption]
        for (key, value) in fields {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.appendString("\(value)\r\n")
        }
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"photo\"; filename=\"capture.jpg\"\r\n")
        body.appendString("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpeg)
        body.appendString("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        return await perform(request, label: "sendPhoto")
    }

    private func postJSON(_ method: String, body: [String: Any]) async -> Bool {
        guard let url = endpoint(method),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        return await perform(request, label: method)
    }

    private func perform(_ request: URLRequest, label: String) async -> Bool {
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if status == 200 { return true }

            let description = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["description"] as? String
            log(" [Telegram] \(label) failed [HTTP \(status)]: \(safe(description ?? "no details"))")
            return false
        } catch {
            log(" [Telegram] \(label) error: \(safe(error.localizedDescription))")
            return false
        }
    }

    //  Helpers

    private func keyboard(for incidentID: String) -> [String: Any] {
        [
            "inline_keyboard": [[
                ["text": " Capture photo", "callback_data": "cap:\(incidentID)"],
                ["text": " Sound alarm", "callback_data": "alarm:\(incidentID)"]
            ]]
        ]
    }

    /// Telegram needs a standard picture format. This makes sure we send a JPEG.
    private func jpegData(from data: Data, quality: CGFloat = 0.7) -> Data? {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// Never let the bot token appear in the logs.
    private func safe(_ text: String) -> String {
        guard !TELEGRAM_TOKEN.isEmpty else { return text }
        return text.replacingOccurrences(of: TELEGRAM_TOKEN, with: "<token>")
    }
}

//  Telegram response models

private struct TGResponse<T: Decodable>: Decodable {
    let ok: Bool
    let result: T?
    let description: String?
}

private struct TGUpdate: Decodable {
    let updateId: Int
    let message: TGMessage?
    let callbackQuery: TGCallback?
}

private struct TGUser: Decodable { let id: Int64 }
private struct TGChat: Decodable { let id: Int64 }

private struct TGMessage: Decodable {
    let messageId: Int
    let date: Int
    let from: TGUser?
    let chat: TGChat
    let text: String?
}

private struct TGCallback: Decodable {
    let id: String
    let from: TGUser
    let data: String?
    let message: TGMessage?
}

private enum TelegramError: LocalizedError {
    case api(String)
    var errorDescription: String? {
        switch self {
        case .api(let text): return "Telegram said: \(text)"
        }
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
