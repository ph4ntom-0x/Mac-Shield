import AppKit
import AVFoundation

final class CameraManager: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.ph4ntom.shadow.cameraQueue")
    
    // Explicitly nonisolated storage synchronized via NSLock
    private let lock = NSLock()
    private nonisolated(unsafe) var _pendingCaptureCompletion: (@Sendable (Data?) -> Void)?
    
    // Explicitly nonisolated computed property for thread-safe delegate access
    private nonisolated var pendingCaptureCompletion: (@Sendable (Data?) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _pendingCaptureCompletion
        }
        set {
            lock.lock()
            _pendingCaptureCompletion = newValue
            lock.unlock()
        }
    }

    override init() {
        super.init()
        sessionQueue.async { [weak self] in
            self?.setupSession()
        }
    }

    private func setupSession() {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoInput) else {
            print("[CameraManager] Failed to access front camera input.")
            return
        }

        captureSession.addInput(videoInput)

        guard captureSession.canAddOutput(photoOutput) else {
            print("[CameraManager] Failed to add photo output.")
            return
        }

        captureSession.addOutput(photoOutput)
    }

    /// Primary interface for IncidentEngine: Captures photo and returns raw Data via completion block
    func capturePhoto(completion: @escaping @Sendable (Data?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else {
                completion(nil)
                return
            }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }

            self.sessionQueue.asyncAfter(deadline: .now() + 1.5) {
                let settings = AVCapturePhotoSettings()
                self.pendingCaptureCompletion = completion
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    // AVCapturePhotoCapture
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // Stop session and release webcam hardware immediately when function exits
        defer {
            sessionQueue.async { [weak self] in
                if self?.captureSession.isRunning == true {
                    self?.captureSession.stopRunning()
                }
            }
        }

        let completion = pendingCaptureCompletion
        pendingCaptureCompletion = nil

        if let error = error {
            print("[CameraManager] Capture error: \(error.localizedDescription)")
            completion?(nil)
            return
        }

        guard let rawData = photo.fileDataRepresentation() else {
            print("[CameraManager] Empty photo data payload.")
            completion?(nil)
            return
        }  

        print("[CameraManager] Photo successfully captured (\(rawData.count) bytes).")
        completion?(rawData)
    }

    //  Utility: Base64 Compression Helper for IncidentEngine Uploads
    static func compressAndEncodeBase64(rawData: Data, compressionQuality: CGFloat = 0.35) -> String? {
        guard let image = NSImage(data: rawData),
              let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality]) else {
            print("[CameraManager] Image compression failed.")
            return nil
        }

        print("[CameraManager] Compressed payload: \(rawData.count) B -> \(jpegData.count) B.")
        return jpegData.base64EncodedString()
    }
}
