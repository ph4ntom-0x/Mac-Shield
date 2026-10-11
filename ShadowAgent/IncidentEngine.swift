import Foundation

/// Coordinates evidence collection (camera snapshot + location) and uploads incident telemetry to Firestore.
@MainActor
final class IncidentEngine {
    static let shared = IncidentEngine()

    private let cameraManager = CameraManager()
    private let locationManager = LocationManager()

    private var isProcessingIncident = false

    // MARK: - Threshold / debounce state (restored)
    private var failedAttemptCount = 0
    private let maxThreshold = 3
    private var lastAttemptDate: Date = .distantPast
    private let counterResetTimeout: TimeInterval = 60.0
    private let debounceWindow: TimeInterval = 4.0

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {}

    // MARK: - Public Entry Points

    /// Called by LogMonitor on every matched log line. Counts toward the
    /// 3-attempt threshold with debounce; only branches into capture-or-alert
    /// once the threshold is actually reached.
    func handleFailedAttempt() {
        let now = Date()

        if now.timeIntervalSince(lastAttemptDate) > counterResetTimeout {
            failedAttemptCount = 0
        }
        guard now.timeIntervalSince(lastAttemptDate) > debounceWindow else { return }

        lastAttemptDate = now
        failedAttemptCount += 1
        log(" [IncidentEngine] Unauthorized access attempt detected! Count: \(failedAttemptCount)/\(maxThreshold)")

        guard failedAttemptCount >= maxThreshold else { return }
        failedAttemptCount = 0
        log(" [IncidentEngine] MAX THRESHOLD REACHED (\(maxThreshold)/\(maxThreshold))!")

        Task {
            let isRealTimeOn = await SettingsManager.fetchRealTimeMode()
            if isRealTimeOn {
                log(" [IncidentEngine] Real-Time Mode is ON — capturing immediately.")
                self.triggerPipeline(reason: "SUSPICIOUS_ACTIVITY")
            } else {
                log(" [IncidentEngine] Real-Time Mode is OFF — posting alert only.")
                await self.postAlertOnly()
            }
        }
    }

    /// Triggered remotely by CommandPoller on manual capture commands.
    /// Always captures, regardless of Real-Time Mode — this is the
    /// user-initiated path the toggle is meant to defer to.
    func handleManualCapture() {
        triggerPipeline(reason: "REMOTE_CAPTURE")
    }

    private func triggerPipeline(reason: String) {
        guard !isProcessingIncident else {
            log(" [IncidentEngine] Incident already in progress. Skipping trigger (\(reason)).")
            return
        }
        isProcessingIncident = true

        Task {
            defer { self.isProcessingIncident = false }
            await executeIncidentResponsePipeline(reason: reason)
        }
    }

    // MARK: - Core Pipeline

    private func executeIncidentResponsePipeline(reason: String) async {
        log("🔍 [IncidentEngine] Incident triggered (\(reason)). Gathering evidence...")

        async let photoData = fetchCameraSnapshotSafely()
        async let locationData = locationManager.fetchLocation()

        let (imageData, location) = await (photoData, locationData)

        let photoStatus = imageData != nil ? "\(imageData!.count) bytes" : "Unavailable"
        log(" [IncidentEngine] Evidence compiled. Photo: \(photoStatus), Location: \(location.0)")

        await uploadIncident(imageData: imageData, location: location, eventType: reason)
    }

    // MARK: - Alert-only path (Real-Time Mode OFF)

    private func postAlertOnly() async {
        let incidentID = "INC-" + String(UUID().uuidString.prefix(8)).uppercased()
        let fields: [String: Any] = [
            "incidentId": ["stringValue": incidentID],
            "eventType": ["stringValue": "SUSPICIOUS_ACTIVITY"],
            "photoBase64": ["stringValue": ""],
            "locationSource": ["stringValue": "Not requested — awaiting user confirmation"],
            "timestamp": ["stringValue": Self.dateFormatter.string(from: Date())],
            "device": ["stringValue": DEVICE_NAME],
            "failureCount": ["integerValue": "3"]
        ]
        await sendIncidentFields(fields, incidentID: incidentID)
    }

    // MARK: - Hardware Helpers

    private func fetchCameraSnapshotSafely() async -> Data? {
        await withCheckedContinuation { continuation in
            var hasResumed = false

            cameraManager.capturePhoto { data in
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: data)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                guard !hasResumed else { return }
                hasResumed = true
                log(" [IncidentEngine] Camera capture timed out.")
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Telemetry Dispatch (Firestore REST API)
    // Field names kept identical to the original schema — incidentId,
    // eventType, photoBase64, locationSource, latitude, longitude,
    // timestamp, device, failureCount — because the web dashboard and
    // Shadow mobile app both read these exact keys.

    private func uploadIncident(imageData: Data?, location: (String, Double?, Double?), eventType: String) async {
        let incidentID = "INC-" + String(UUID().uuidString.prefix(8)).uppercased()

        var fields: [String: Any] = [
            "incidentId": ["stringValue": incidentID],
            "eventType": ["stringValue": eventType],
            "locationSource": ["stringValue": location.0],
            "timestamp": ["stringValue": Self.dateFormatter.string(from: Date())],
            "device": ["stringValue": DEVICE_NAME],
            "failureCount": ["integerValue": "3"]
        ]
        if let lat = location.1 { fields["latitude"] = ["doubleValue": lat] }
        if let lon = location.2 { fields["longitude"] = ["doubleValue": lon] }
        if let imageData = imageData {
            fields["photoBase64"] = ["stringValue": imageData.base64EncodedString()]
        } else {
            fields["photoBase64"] = ["stringValue": ""]
        }

        await sendIncidentFields(fields, incidentID: incidentID)
    }

    private func sendIncidentFields(_ fields: [String: Any], incidentID: String) async {
        let base = "\(BASE_URL)/incidents"
        var components = URLComponents(string: base)
        var queryItems = [URLQueryItem(name: "documentId", value: incidentID)]
        if !USE_EMULATOR {
            queryItems.append(URLQueryItem(name: "key", value: API_KEY))
        }
        components?.queryItems = queryItems

        guard let url = components?.url,
              let jsonData = try? JSONSerialization.data(withJSONObject: ["fields": fields]) else {
            log(" [IncidentEngine] Failed to build incident request for [\(incidentID)]")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15.0
        request.httpBody = jsonData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                log(" [IncidentEngine] Incident [\(incidentID)] uploaded successfully.")
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                log(" [IncidentEngine] Incident upload failed [HTTP \(code)] for [\(incidentID)]")
            }
        } catch {
            log(" [IncidentEngine] Telemetry upload error: \(error.localizedDescription)")
        }
    }
}
