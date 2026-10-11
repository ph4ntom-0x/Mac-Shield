import Foundation

/// Manages remote configuration and feature flags from Firestore.
enum SettingsManager {
    
    /// Fetches the Real-Time Mode flag from Firestore.
    /// - ON: Auto-capture photo and location on failed attempts.
    /// - OFF: Alert-only mode.
    static func fetchRealTimeMode() async -> Bool {
        let base = "\(BASE_URL)/settings/config"
        var components = URLComponents(string: base)
        if !USE_EMULATOR {
            components?.queryItems = [URLQueryItem(name: "key", value: API_KEY)]
        }
        
        guard let url = components?.url else {
            log(" [SettingsManager] Invalid URL configuration.")
            return false
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                log(" [SettingsManager] Non-200 HTTP response while fetching config.")
                return false
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let fields = json["fields"] as? [String: Any] else {
                log(" [SettingsManager] Config document missing — defaulting Real-Time to OFF.")
                return false
            }

            // Check common boolean field aliases across schema iterations
            let targetKeys = ["realTimeMode", "isRealTime", "realtime", "enabled", "active"]
            for key in targetKeys {
                if let dict = fields[key] as? [String: Any],
                   let boolVal = dict["booleanValue"] as? Bool {
                    return boolVal
                }
            }
            
            return false
        } catch {
            log(" [SettingsManager] Network error fetching settings: \(error.localizedDescription)")
            return false
        }
    }
}
