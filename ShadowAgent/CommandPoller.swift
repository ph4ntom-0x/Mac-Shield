import Foundation

/// Periodically queries Firestore REST API for pending remote commands 
@MainActor
enum CommandPoller {
    private static var isProcessing = false
    private static let pollingInterval: TimeInterval = 10.0
    private static var pollingTask: Task<Void, Never>?

    static func start() {
        log(" [CommandPoller] Command Poller active. Checking every \(Int(pollingInterval))s...")
        
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await pollOnce()
                try? await Task.sleep(for: .seconds(pollingInterval))
            }
        }
    }

    static func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    static func pollOnce() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        guard let queryRequest = buildQueryRequest() else { return }

        do {
            let (data, response) = try await URLSession.shared.data(for: queryRequest)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }

            let pendingCommands = try parsePendingCommands(from: data)
            for command in pendingCommands {
                await executeCommand(command)
            }
        } catch {
            log(" [CommandPoller] Poll request failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Request Building

    private static func buildQueryRequest() -> URLRequest? {
        let endpoint = "\(BASE_URL):runQuery"
        var components = URLComponents(string: endpoint)
        if !USE_EMULATOR {
            components?.queryItems = [URLQueryItem(name: "key", value: API_KEY)]
        }
        guard let url = components?.url else { return nil }

        let payload: [String: Any] = [
            "structuredQuery": [
                "from": [["collectionId": "commands"]],
                "where": [
                    "fieldFilter": [
                        "field": ["fieldPath": "status"],
                        "op": "EQUAL",
                        "value": ["stringValue": "pending"]
                    ]
                ]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        return request
    }

    //  Response Parsing

    private static func parsePendingCommands(from data: Data) throws -> [PendingCommand] {
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var results: [PendingCommand] = []
        for item in jsonArray {
            guard let doc = item["document"] as? [String: Any],
                  let name = doc["name"] as? String,
                  let fields = doc["fields"] as? [String: Any] else {
                continue
            }

            let docId = name.components(separatedBy: "/").last ?? ""

            let action: String
            if let actionDict = fields["action"] as? [String: Any],
               let val = actionDict["stringValue"] as? String {
                action = val.uppercased()
            } else if let commandDict = fields["command"] as? [String: Any],
                      let val = commandDict["stringValue"] as? String {
                action = val.uppercased()
            } else {
                action = ""
            }

            guard !action.isEmpty else { continue }
            results.append(PendingCommand(id: docId, action: action))
        }
        return results
    }

    // MARK: - Command Execution

    private static func executeCommand(_ command: PendingCommand) async {
        log(" [CommandPoller] Executing command '\(command.action)' [ID: \(command.id)]...")

        switch command.action {
        case "CAPTURE_NOW", "CAPTURE_PHOTO", "CAPTURE", "REMOTE_CAPTURE":
            IncidentEngine.shared.handleManualCapture()
        case "TRIGGER_ALARM", "ALARM":
            AlarmEngine.trigger()
        default:
            log(" [CommandPoller] Unrecognized command action: '\(command.action)'")
        }

        await markAsCompleted(command.id)
    }

    //  Status Update

    private static func markAsCompleted(_ docId: String) async {
        let base = "\(BASE_URL)/commands/\(docId)"
        var components = URLComponents(string: base)
        components?.queryItems = [
            URLQueryItem(name: "updateMask.fieldPaths", value: "status")
        ]
        if !USE_EMULATOR {
            components?.queryItems?.append(URLQueryItem(name: "key", value: API_KEY))
        }

        guard let url = components?.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "fields": ["status": ["stringValue": "completed"]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        _ = try? await URLSession.shared.data(for: request)
        log(" [CommandPoller] Command [\(docId)] marked as completed.")
    }
}

//  Helper Models

private struct PendingCommand: Sendable {
    let id: String
    let action: String
}
