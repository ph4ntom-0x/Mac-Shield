import Foundation

/// The Real-Time Mode setting.
///
/// - It can be changed from Telegram (/realtime) or from the Shadow app (through Firestore).
/// - When Firestore is configured, it is asked first, so the app's switch is respected.
/// - If Firestore cannot answer (offline, error, or not configured), the last known value
///   stored on this Mac is used.
/// - Telegram changes are saved on the Mac and mirrored to Firestore, so both stay in step.
enum SettingsManager {
    private static let localKey = "realTimeMode"
    private static let fieldName = "realTimeMode"
    // Older schema names the app might have used (read only)
    private static let readAliases = ["realTimeMode", "isRealTime", "realtime", "enabled", "active"]

    //  Public

    /// The value saved on this Mac. Defaults to OFF.
    static var localRealTimeMode: Bool {
        UserDefaults.standard.bool(forKey: localKey)
    }

    /// The value to use right now.
    static func currentRealTimeMode() async -> Bool {
        guard FIRESTORE_ENABLED else { return localRealTimeMode }

        if let remote = await fetchRemoteRealTimeMode() {
            saveLocal(remote)          // remember it as the fallback for next time
            return remote
        }
        return localRealTimeMode
    }

    /// Used by Telegram. Saves on this Mac, and mirrors to Firestore when it is configured.
    static func setRealTimeMode(_ value: Bool) async {
        saveLocal(value)

        guard FIRESTORE_ENABLED else { return }
        let mirrored = await pushRemoteRealTimeMode(value)
        if !mirrored {
            log(" [SettingsManager] Could not mirror Real-Time Mode to Firestore. The value saved on this Mac is used.")
        }
    }

    // Local copy

    private static func saveLocal(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: localKey)
    }

    // Firestore

    private static func settingsURL(extra: [URLQueryItem] = []) -> URL? {
        var components = URLComponents(string: "\(BASE_URL)/settings/config")
        var items = extra
        if !USE_EMULATOR {
            items.append(URLQueryItem(name: "key", value: API_KEY))
        }
        components?.queryItems = items.isEmpty ? nil : items
        return components?.url
    }

    /// nil means "Firestore could not tell us", so the caller falls back to the local value.
    private static func fetchRemoteRealTimeMode() async -> Bool? {
        guard let url = settingsURL() else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                log(" [SettingsManager] Firestore settings not available. Using the value saved on this Mac.")
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let fields = json["fields"] as? [String: Any] else {
                return nil
            }

            for key in readAliases {
                if let dict = fields[key] as? [String: Any],
                   let value = dict["booleanValue"] as? Bool {
                    return value
                }
            }
            return nil
        } catch {
            log(" [SettingsManager] Could not reach Firestore: \(error.localizedDescription). Using the value saved on this Mac.")
            return nil
        }
    }

    private static func pushRemoteRealTimeMode(_ value: Bool) async -> Bool {
        guard let url = settingsURL(extra: [URLQueryItem(name: "updateMask.fieldPaths", value: fieldName)]) else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["fields": [fieldName: ["booleanValue": value]]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
