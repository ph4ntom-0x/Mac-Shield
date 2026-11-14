<div align="center">

# 🔐 How I Handled macOS Permissions (TCC)

**The hardest part of Mac Shield was not the code. It was getting macOS to trust it.**

[← Back to README](../README.md) · [User Guide](USER_GUIDE.md) · [Architecture](ARCHITECTURE.md)

</div>

---

## 📑 Contents

1. [Why this matters](#1--why-this-matters)
2. [TCC in one minute](#2--tcc-in-one-minute)
3. [What Mac Shield needs](#3--what-mac-shield-needs)
4. [The problems and how I fixed them](#4--the-problems-and-how-i-fixed-them)
5. [Smart techniques I now use](#5--smart-techniques-i-now-use)
6. [The final setup checklist](#6--the-final-setup-checklist)
7. [Design choices that keep it honest](#7--design-choices-that-keep-it-honest)
8. [What I still do not know](#8--what-i-still-do-not-know)

---

## 1 · Why this matters

Mac Shield needs the camera, your location, and the system logs. macOS protects all three, and for good reason. A background app that quietly takes photos is exactly what the protection is meant to stop.

So Mac Shield cannot just take what it needs. It has to **ask, get a yes from the owner, and keep that yes**. Getting that to work reliably for a faceless background app took most of my debugging time. Almost every "it works on my Mac but then stops" bug in this project came back to permissions.

---

## 2 · TCC in one minute

**TCC** stands for *Transparency, Consent and Control*. It is the macOS system that decides whether an app may use the camera, microphone, location, files and more.

The key ideas:

- A background service called `tccd` makes the decision. Apps cannot talk around it.
- Your answers are stored in a database called `TCC.db`. It is protected by SIP, so you cannot edit it by hand.
- **An answer belongs to an app identity, not to a file path.** The identity is the bundle ID plus the app's **code signature**.

That last point is the one that cost me days. If the signature changes, macOS sees a *different app*. Your old "Allow" no longer applies.

```text
Camera = Allowed  →  for "com.ph4ntom.shadow.ShadowAgent" signed by identity X
                     If the app is rebuilt and signed as identity Y, macOS asks again.
```

---

## 3 · What Mac Shield needs

| Permission | Used for | Can the app ask for it? |
|---|---|---|
|  **Camera** | Taking the photo |  Yes, with `AVCaptureDevice.requestAccess` |
|  **Location Services** | Adding coordinates |  Yes, with `requestWhenInUseAuthorization` |
|  **Full Disk Access** | Reading login failure messages in the log |  No. The user must add the app by hand |

Two of the three can be requested by code. Full Disk Access cannot, so the User Guide has to tell the user to do it, and the agent has to cope while it is missing.

---

## 4 · The problems and how I fixed them

Each problem below follows the same pattern: what I saw, the real cause, the fix, and what I learned.

### Problem 1 · The camera prompt never appeared

**What I saw.** The agent tried to use the camera. No permission prompt showed up, and ShadowAgent never appeared in *Privacy & Security → Camera*.

**The cause.** My code *checked* the camera's authorization status but never actually *asked*. Reading the status is not the same as requesting access. macOS only shows the prompt, and only adds the app to the list, when the app calls `requestAccess`.

**The fix.** Ask explicitly, and wait for the answer before touching the camera:

```swift
switch AVCaptureDevice.authorizationStatus(for: .video) {
case .authorized:
    startCapture()
case .notDetermined:
    AVCaptureDevice.requestAccess(for: .video) { granted in
        granted ? startCapture() : log("Camera permission denied")
    }
default:
    log("Camera permission denied or restricted")
}
```

**What I learned.** "Status" and "request" are two different calls. A missing prompt usually means the request was never made.

---

### Problem 2 · Permissions reset after every rebuild

**What I saw.** I would grant Camera and Location, rebuild, and macOS would ask again. Sometimes the old entry stayed in the list but did nothing.

**The cause.** `deploy.sh` signs with `codesign --sign -`. That is an **ad-hoc signature**. Its identity is based on a hash of the exact build, so it changes on every compile. macOS sees a brand new app each time, and the old permission no longer matches.

**The fix.** Sign every build with the **same identity**. I created a self-signed code-signing certificate named `ShadowAgentCert`:

1. Open **Keychain Access → Certificate Assistant → Create a Certificate**.
2. Name it `ShadowAgentCert`, set *Identity Type* to **Self Signed Root** and *Certificate Type* to **Code Signing**.
3. Sign with it in `deploy.sh`:

```bash
codesign --force --deep --sign "ShadowAgentCert" "/Applications/ShadowAgent.app"
```

You can see the difference yourself:

```bash
codesign -dr - /Applications/ShadowAgent.app
```

An ad-hoc build shows a requirement tied to a build hash (`cdhash H"..."`). A build signed with a certificate shows a requirement tied to the certificate, which stays the same from build to build.

**What I learned.** Permissions follow the *signing identity*. A stable identity is not a nice extra. It is what makes consent last.

> [!IMPORTANT]
> The `deploy.sh` in the repo may still use ad-hoc signing. If you do not create your own certificate, expect to grant permissions again after each deploy.

---

### Problem 3 · `AVCapturePhotoOutput` crashed

**What I saw.** The app crashed the moment it tried to take a photo.

**The cause.** `AVCapturePhotoOutput` misbehaves when it runs outside a full app context. This is a known Apple issue that I found discussed on the Apple Developer Forums, and it was not resolved when I hit it.

**The fix.** I stopped using that API and grabbed a single video frame instead, using `AVCaptureVideoDataOutput`. It gives the same result, a picture from the front camera, without the unstable part.

**What I learned.** When a framework has a bug you cannot fix, change which part of it you use. The goal was a picture, not that particular class.

---

### Problem 4 · Location never came back

**What I saw.** `CLLocationManager` asked for updates, permission was fine, and no location ever arrived.

**The cause.** CoreLocation delivers its results through a **run loop**. My background process was not running one, so the callbacks had nowhere to land. Everything looked correct, and nothing happened.

**The fix.** First I kept the run loop alive with `RunLoop.main.run()`. Later, when I moved into a proper Xcode app target, `main.swift` started a real application session:

```swift
let app = NSApplication.shared
app.delegate = delegate
app.run()
```

This gives the process a proper run loop and lifecycle. Because the app is marked `LSUIElement`, it still has no Dock icon.

**Plan B built in.** `LocationManager` does not depend on CoreLocation alone:

- If location is denied, restricted or switched off, it goes straight to an IP-based lookup.
- If no fix arrives within 8 seconds, it falls back to the IP lookup as well.

**What I learned.** Background code still needs an event loop to receive callbacks. And a permission feature should always have a fallback, because the user may say no.

---

### Problem 5 · A hidden second copy kept running

**What I saw.** After I killed the agent, something still ran, and actions fired twice.

**The cause.** An earlier test had installed the agent as a **root-owned LaunchDaemon** using `sudo launchctl bootstrap system/...`. `pkill` did not stop it because launchd restarted it. It also ran in a different security context than my login session, so permission behavior was confusing.

**The fix.** I removed the root copy with `launchctl bootout` in the correct domain, and I keep only one install, as a user **LaunchAgent** in `gui/$(id -u)`. I also added a single-instance lock using `flock()`, so a second copy refuses to start.

**What I learned.** launchd has separate domains (system and per-user). Always remove a service with `bootout` first, and install permission-sensitive apps in the user's own session.

---

### Problem 6 · Login failures showed as `<private>`

**What I saw.** The log monitor ran, but no failed logins were detected.

**The cause.** Without Full Disk Access, macOS hides the useful part of the authentication log lines. They appear as `<private>`, so the filter never matches.

**The fix.** There is no API to request this one. It has to be added manually in **System Settings → Privacy & Security → Full Disk Access**. So I made it a clear step in the [User Guide](USER_GUIDE.md), and the symptom ("No alerts at all") appears in the troubleshooting table.

**What I learned.** Some permissions can only be granted by the user. The honest solution is clear documentation, not a workaround.

---

### Problem 7 · macOS did not treat the background service as a proper app

**What I saw.** The service needed to start at login and keep running, but macOS manages background items closely. If the service is not clearly tied to an app, it can be blocked or show up as a confusing, unnamed item.

**The cause.** Since macOS 13, a system called **Background Task Management (BTM)** tracks every background item and lets the user switch each one on or off in *System Settings → General → Login Items*. A bare binary with a loose plist does not fit that model well.

**The fix.** I treated the agent as a real app instead of a loose program:

1. It is built as a proper `ShadowAgent.app` and installed in `/Applications`.
2. It is code signed before it is registered.
3. The LaunchAgent plist names the app it belongs to:

```xml
<key>AssociatedBundleIdentifiers</key>
<array>
    <string>com.ph4ntom.shadow.ShadowAgent</string>
</array>
```

Now ShadowAgent shows up by name under **Allow in the Background**, and the owner can see it and control it.

**What I learned.** Being visible is part of being trusted. A service the owner can see and switch off is easier for macOS, and for people, to accept.

---

### Problem 8 · `launchctl bootstrap` failed with error 5

**What I saw.** `Bootstrap failed: 5: Input/output error`. The message says nothing useful.

**The cause.** In my case the plist had the wrong owner, wrong permissions, or quarantine flags picked up when the file was copied. launchd rejects a plist it does not trust. (Error 5 can also appear when the same service is already loaded, which is why the script runs `bootout` first.)

**The fix.** I put a cleanup step into `deploy.sh`, so it runs on every deploy:

```bash
chown $(whoami) "$HOME/Library/LaunchAgents/com.ph4ntom.shadow.ShadowAgent.plist"
chmod 644       "$HOME/Library/LaunchAgents/com.ph4ntom.shadow.ShadowAgent.plist"
xattr -c        "$HOME/Library/LaunchAgents/com.ph4ntom.shadow.ShadowAgent.plist"
```

**What I learned.** Fix a problem once, then put the fix in the script so you never meet it again.

---

## 5 · Smart techniques I now use

| Technique | Command or idea | Why it helps |
|---|---|---|
| **See the signing identity** | `codesign -dr - /Applications/ShadowAgent.app` | Shows whether the identity is stable or build-specific |
| **Check the full signature** | `codesign -dvvv /Applications/ShadowAgent.app` | Shows the bundle ID and signing authority |
| **Reset one permission, one app** | `tccutil reset Camera com.ph4ntom.shadow.ShadowAgent` | Replay the first-run prompt without touching other apps |
| **List valid signing identities** | `security find-identity -v -p codesigning` | Confirms `ShadowAgentCert` is installed and usable |
| **Look for quarantine flags** | `xattr -l ~/Library/LaunchAgents/com.ph4ntom.shadow.ShadowAgent.plist` | Shows what could make launchd reject the plist |
| **Check what is running** | `pgrep -fl ShadowAgent` | Catches hidden duplicate copies fast |
| **Check launchd domains** | `launchctl list \| grep ShadowAgent` and `sudo launchctl list \| grep ShadowAgent` | Finds a copy in the wrong domain |
| **Use the log as a debugger** | Log every permission status before using the hardware | Turns "it silently failed" into a clear message |
| **Fail soft** | Camera or location fails, the incident still uploads | The owner still gets the alert |

---

## 6 · The final setup checklist

Follow this order and permissions will stay put:

- [ ] Create a stable signing certificate (`ShadowAgentCert`) and use it in `deploy.sh`
- [ ] Make sure `Info.plist` has the usage description texts for Camera and Location
- [ ] Keep the app as `LSUIElement` with a real `NSApplication` run loop
- [ ] Call `requestAccess` and `requestWhenInUseAuthorization` explicitly
- [ ] Install **one** copy only, as a user LaunchAgent
- [ ] Put `AssociatedBundleIdentifiers` in the plist so the service is tied to the app
- [ ] Clean the plist on every deploy (`chown`, `chmod 644`, `xattr -c`)
- [ ] Add ShadowAgent to **Full Disk Access** by hand
- [ ] Confirm it appears under **Camera**, **Location Services** and **Login Items**
- [ ] After any signing change, re-check all three lists

---

## 7 · Design choices that keep it honest

- **Not sandboxed, on purpose.** The agent has to run `/usr/bin/log`, which a sandbox would block. I traded containment for capability and wrote it down in [Architecture](ARCHITECTURE.md#8--security-considerations).
- **Permissions stay with the owner.** The agent can only use the camera and location the owner approved in System Settings. It cannot bypass TCC, and I did not try to.
- **Alert first, capture on request.** By default the camera is not used until the owner taps *Capture photo*. This means fewer surprise photos and fewer permission-sensitive moments.
- **Release the hardware.** The camera session stops right after the shot so the camera light does not stay on.
- **Fail soft.** If the camera or location is unavailable, the incident is still uploaded with what exists, instead of being lost.
- **Clear fallback disclosure.** If the agent falls back to IP location, the incident says so in its `locationSource` field.

---

## 8 · What I still do not know

- I fixed these by testing on my own Mac. I have **not** tested other macOS versions, so permission prompts may look different on yours.
- A self-signed certificate keeps permissions stable on *my* machine. Anyone who builds from source must make their own.
- Public distribution would need an Apple Developer ID and notarization. That is not done.
- If Hardened Runtime is turned on later, the camera and location entitlements must be added.

---

<div align="center">

[← Back to README](../README.md) · [User Guide](USER_GUIDE.md)

</div>
