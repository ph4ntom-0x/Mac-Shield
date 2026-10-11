import Cocoa

@MainActor
private var globalDelegate: AppDelegate?

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    globalDelegate = delegate
    
    let app = NSApplication.shared
    app.delegate = delegate
    app.run()
}
