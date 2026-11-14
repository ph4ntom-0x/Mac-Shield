<div align="center">

# 🛠️ Problems Solved

**The complete debugging journal of Mac Shield: what broke, what was really wrong, and how I fixed it.**

[← Back to README](../README.md) · [User Guide](USER_GUIDE.md) · [Architecture](ARCHITECTURE.md) · [TCC Permissions](TCC_PERMISSIONS.md)

</div>

---

Most of what I learned on this project came from things breaking. This page is the honest record of 24 problems, grouped by area. Each one follows the same shape: **symptom → real cause → fix → how to check → lesson.**

Built and tested on a **MacBook Air, macOS 27.0.1, Xcode 27.2**. Other versions may behave differently.

**Severity tags:** 🔴 stopped the project · 🟡 slowed me down · 🟢 harmless

## 🏆 The five lessons that mattered most

1. **Read the real error.** A vague message hid the true cause for days ([#7](#7--restart-loop-another-instance-is-already-running)).
2. **Test with a real event.** A filter can silently throw away the signal you want ([#11](#11--my-filter-ate-the-real-signal)).
3. **`KeepAlive` turns one failure into a loop.** Read the log before assuming ([#7](#7--restart-loop-another-instance-is-already-running)).
4. **Permissions follow the code signature.** A new signing identity means macOS treats you as a new app ([#18](#18--signing-and-permissions-across-rebuilds)).
5. **Count actions, not log lines.** One wrong password writes many log lines ([#12](#12--one-wrong-password-counted-several-times)).

## 📑 Contents

| Area | Problems |
|---|---|
| [A · Building in Xcode](#a--building-in-xcode) | [1](#1--codesign-failed-in-xcode) · [2](#2--missing-package-product-firebasefirestore) · [3](#3--swift-6-concurrency-errors) · [4](#4--xcode-run-while-the-service-was-alive) · [5](#5--linkd-noise-in-the-console) |
| [B · Starting up and staying alive](#b--starting-up-and-staying-alive) | [6](#6--the-agent-quit-right-after-starting) · [7](#7--restart-loop-another-instance-is-already-running) · [8](#8--a-hidden-second-copy) · [9](#9--nothing-happened-during-testing) |
| [C · Detecting the right event](#c--detecting-the-right-event) | [10](#10--false-alarms-from-the-lock-screen) · [11](#11--my-filter-ate-the-real-signal) · [12](#12--one-wrong-password-counted-several-times) · [13](#13--log-banner-lines) · [14](#14--touch-id-and-the-alert-first-design) |
| [D · Logging](#d--logging) | [15](#15--logs-empty-or-missing) |
| [E · Hardware](#e--hardware) | [16](#16--camera-light-stayed-on) |
| [F · launchd and signing](#f--launchd-and-signing) | [17](#17--launchctl-bootstrap-error-5) · [18](#18--signing-and-permissions-across-rebuilds) |
| [G · Secrets and Git](#g--secrets-and-git) | [19](#19--secrets-in-source-files) · [20](#20--git-push-rejected) |
| [H · Cloud and app](#h--cloud-and-app) | [21](#21--a-burst-of-taps) · [22](#22--everything-went-quiet-one-day) · [23](#23--the-app-showed-blank-fields) · [24](#24--expo-icon-not-changing) |

Permission-specific problems (camera prompt, TCC resets, location) have their own page: **[TCC Permissions](TCC_PERMISSIONS.md)**.

---

## A · Building in Xcode

### 1 · CodeSign failed in Xcode

<details>
<summary>🔴 <b>Command CodeSign failed with a nonzero exit code</b></summary>

**Symptom.** The build stopped with `Command CodeSign failed with a nonzero exit code`.

**Real cause.** Leftover `ShadowAgentCert` keys in my Keychain (an old certificate and its key pair) clashed with Xcode's own signing. Xcode could not settle which identity to use. I do not know the exact internal reason, only that removing the leftovers fixed it.

**Fix.**
1. In **Keychain Access → login**, delete the old `ShadowAgentCert` certificate and its keys.
2. In Xcode, open the target's **Signing & Capabilities** and choose **Sign to Run Locally**, or *Automatically manage signing* with a Personal Team.
3. Clean with `⌘ + Shift + K`, then run with `⌘ + R`.

**Check.** The build finishes with `BUILD SUCCEEDED`.

**Lesson.** There are two separate signing steps. **Xcode** signs the build it runs. **`deploy.sh`** signs the installed copy in `/Applications`. Keep them apart in your head. `deploy.sh` stops with a clear message if the certificate it was asked to use does not exist.

</details>

### 2 · Missing package product FirebaseFirestore

<details>
<summary>🟡 <b>Missing package product 'FirebaseFirestore'</b></summary>

**Symptom.** Xcode stopped with `Missing package product 'FirebaseFirestore'`.

**Real cause.** I had wiped `DerivedData`, which broke Swift Package Manager's link to the `firebase-ios-sdk` package, even though the package URL was still in the project file.

**Fix.**
1. **File → Packages → Resolve Package Versions.**
2. If it stalls, **File → Packages → Reset Package Caches**.
3. Check the target's **General → Frameworks, Libraries, and Embedded Content** and re-add the product if it is missing.
4. Build with `⌘ + B`.

**Check.** The build passes.

**A discovery afterwards.** Searching the project showed `FirebaseFirestore` is still linked, yet none of the agent's source files import it. The agent talks to Firestore with plain REST calls. So the package is dead weight that slows builds and caused this failure.

**Lesson.** Remove dependencies you do not use. (This clean-up is listed under [Still open](#-still-open).)

</details>

### 3 · Swift 6 concurrency errors

<details>
<summary>🟡 <b>Three compiler errors in a row: AppDelegate isolation, top-level code, and <code>@main</code></b></summary>

**Symptom.** Enabling Swift 6 mode produced three errors one after another:

```text
Main actor-isolated conformance of 'AppDelegate' to 'NSApplicationDelegate'
cannot be used in nonisolated context

Call to main actor-isolated global function in a synchronous nonisolated context

'main' attribute cannot be used in a module that contains top-level code
```

**Real cause.**
1. `NSApplicationDelegate` belongs to the main actor, so `AppDelegate` must be marked `@MainActor`.
2. Top-level code in `main.swift` is *not* main-actor isolated, so it cannot call main-actor code directly.
3. My first fix, an `@main` struct, failed because the compiler reserves a file named `main.swift` for top-level code, which conflicts with `@main`.

**Fix.** Keep `main.swift`, mark `AppDelegate` as `@MainActor`, and start the app inside `MainActor.assumeIsolated`:

```swift
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
```

**Check.** The project builds cleanly in Swift 6 mode.

**Lesson.** Read compiler errors in order. Each fix can reveal the next one.

</details>

### 4 · Xcode Run while the service was alive

<details>
<summary>🟡 <b>"Xcode has killed the LLDB RPC server..."</b></summary>

**Symptom.** Pressing `⌘ + R` while the background copy was running showed:

```text
Xcode has killed the LLDB RPC server (pid: ...) to allow the debugger to
detach from your process. ... You may need to manually terminate your process
```

**Real cause.** Xcode tried to run and debug a new copy while another copy of the agent was already alive. I did not find a deeper reason than that, only that stopping the old copy first avoided it.

**Fix.** Stop the service, clear orphans, then run:

```bash
launchctl bootout gui/$(id -u)/com.ph4ntom.shadow.ShadowAgent
killall -9 ShadowAgent 2>/dev/null
pgrep -fl ShadowAgent     # should print nothing
```

Then press `⌘ + R`.

**Lesson.** Stop the service before debugging in Xcode. Debug builds also **skip** the single-instance lock (see [#7](#7--restart-loop-another-instance-is-already-running)), so a Debug copy and the service copy can run together and raise **duplicate alerts**.

</details>

### 5 · linkd noise in the console

<details>
<summary>🟢 <b>Repeated <code>com.apple.linkd.autoShortcut</code> errors</b></summary>

**Symptom.** The Xcode console filled with messages like:

```text
Unable to get synchronousRemoteObjectProxy, error: ... connection to service
named com.apple.linkd.autoShortcut
```

**Real cause.** It appears to be a macOS system service (`linkd`) trying to register the app for Shortcuts and App Intents. ShadowAgent defines none, so the connection fails. This is my reading of the message, not something I confirmed in Apple's documentation.

**Impact.** None. The agent starts and works normally.

**Fix.** Ignore it. To hide it in Xcode only: **Edit Scheme → Run → Arguments → Environment Variables**, add `OS_ACTIVITY_MODE = disable`. This also hides other system log output in the console, so I leave it off.

**Lesson.** Not every red message is your bug. Check whether anything actually stopped working.

</details>

---

## B · Starting up and staying alive

### 6 · The agent quit right after starting

<details>
<summary>🔴 <b>"Initializing…" then "Security Log Monitor stopped" a moment later</b></summary>

**Symptom.** The log showed the start-up line and then the monitor stopping almost at once, and the process vanished from Activity Monitor:

```text
[AppDelegate] Initializing ShadowAgent daemon (PID: ...)...
[LogMonitor] Security Log Monitor stopped.
```

**Real cause.** `NSApplication` keeps its delegate **weakly**. In an earlier version of `main.swift`, the only strong reference to `AppDelegate` was a local variable. When that went away, ARC freed the delegate, and `LogMonitor`'s `deinit` called `stop()`, which shut the log stream down.

**Fix.** Keep a strong top-level reference, as in the code in [#3](#3--swift-6-concurrency-errors).

**Check.** The process stays in Activity Monitor and the log shows "Security Log Monitor active."

**Lesson.** When an object keeps something alive indirectly, a "clean up" in `deinit` can look like a crash. Know who owns what.

</details>

### 7 · Restart loop: "another instance is already running"

<details>
<summary>🔴 <b>The lock-file saga: three different causes behind one message</b></summary>

**Symptom.** The log repeated every 10 seconds:

```text
[SingleInstanceLock] Failed to open lock file descriptor.
Another instance is already running. Exiting.
```

I hit this several times over the project, and it had **three different causes**.

**Cause A: I was looking in the wrong place.** The lock file is at `~/Library/Application Support/ShadowAgent/ShadowAgent.lock`, not in `/tmp`. macOS apps' temporary folder is also not `/tmp`. It is under `/var/folders/.../T/` (the `$TMPDIR` variable). On top of that, zsh refuses a pattern that matches nothing:

```text
zsh: no matches found: /tmp/*Shadow*
```

**Cause B: a live orphan held the lock.** After `kill -9`, a crashed Xcode session, or a stuck debugger, an old copy was still alive and still held the lock.

```bash
pgrep -fl ShadowAgent
```

**Cause C: the lock file itself was unreadable.** The most recent one. The file had these permissions:

```text
--w---x---  1 youruser  staff  0  ShadowAgent.lock
```

The owner could write but not read. The agent opens the file for reading *and* writing, so macOS refused. I do not know how it got those permissions. It was weeks old.

**What made it worse.**
- The code reported *any* failure to open the file as "another instance is running", so it blamed the wrong thing.
- `KeepAlive` is on, so launchd restarted the agent every 10 seconds instead of showing a single clear error.

**An important correction to my own first theory.** I first believed a leftover lock *file* blocks the next start. It does not. `flock()` locks are released by the kernel when the process exits, so an old file alone blocks nothing. What blocks is **a live process**, or **a file the agent cannot open**.

**Fix.**

```bash
# 1. Stop the loop
launchctl bootout gui/$(id -u)/com.ph4ntom.shadow.ShadowAgent

# 2. Confirm nothing is alive, then remove a bad lock file
pgrep -fl ShadowAgent
rm ~/Library/Application\ Support/ShadowAgent/ShadowAgent.lock
```

Then make the code repair permissions and say the real reason:

```swift
fileDescriptor = open(lockPath, O_CREAT | O_RDWR, 0o600)
guard fileDescriptor != -1 else {
    print(" [SingleInstanceLock] Cannot open \(lockPath): \(String(cString: strerror(errno)))")
    return false
}
fchmod(fileDescriptor, 0o600)
```

**Do not** make `deploy.sh` delete the lock file blindly before starting. If an orphan still holds the *old* file, a new copy creates a *new* file and **both run**. Stop the service and check for processes first. The current `deploy.sh` stops the service before replacing anything.

**Debug builds** skip the lock on purpose, so leftover state cannot block Xcode runs:

```swift
#if !DEBUG
guard SingleInstanceLock.acquire() else { ... }
#else
log("Debug build detected: bypassing SingleInstanceLock")
#endif
```

**Check.** `pgrep -fl ShadowAgent` shows one process, and the log shows "Exclusive kernel lock acquired."

**Lesson.** The lock worked perfectly. The bug was a vague error message. Always log the real reason (`strerror(errno)`). And `KeepAlive` can hide a start-up failure, so read the log first.

</details>

### 8 · A hidden second copy

<details>
<summary>🔴 <b>I killed the agent, but something kept running and actions fired twice</b></summary>

**Symptom.** After `pkill`, a process came back, and alerts and captures happened twice.

**Real cause.** An earlier test had installed a copy as a **root-owned LaunchDaemon** (`sudo launchctl bootstrap system/...`). launchd restarted it every time I killed it, and it ran in a different security context from my login session.

**Fix.** Remove it with `bootout` in the right domain, and keep a single install as a user LaunchAgent in `gui/$(id -u)`.

```bash
sudo launchctl list | grep -i shadow      # system-level copies
launchctl list | grep -i shadow           # user-level copies
ls /Library/LaunchDaemons | grep -i shadow
```

**Check.** Only one entry shows up, and it is yours.

**Lesson.** launchd has separate domains (system and per-user). Stop services with `bootout`, not `pkill`.

</details>

### 9 · Nothing happened during testing

<details>
<summary>🟡 <b>Three wrong passwords in Terminal produced no alert, no photo, no upload</b></summary>

**Symptom.** I ran `sudo -k && sudo ls` and entered three wrong passwords. Nothing happened, and ShadowAgent was missing from Activity Monitor.

**Real cause.** Two separate things:
1. The agent was **not running**. Cleaning the build folder or stopping the Xcode scheme had ended it.
2. `sudo` failures are not what the agent watches. The predicate only matches `loginwindow` **lock-screen** failures.

**Fix.**
1. Make sure the agent is running (`pgrep -fl ShadowAgent`).
2. Test the real way: lock the screen with **Control + Command + Q**, then type three wrong passwords, about 5 seconds apart.

**Lesson.** Test the exact event your detector looks for. (And note that `⌘ + Shift + Q` is *Log Out*, not lock.)

</details>

---

## C · Detecting the right event

### 10 · False alarms from the lock screen

<details>
<summary>🔴 <b>Locking the screen or unlocking correctly raised failure counts</b></summary>

**Symptom.** Locking the screen, or unlocking with the correct password, increased the failure counter.

**Real cause.** My first predicate was too broad. It picked up messages from other system components (for example `opendirectoryd`) that mention authentication during normal screen-lock handling. I confirmed this by watching the log: one session ID repeated every few seconds for over a minute, far too often for real typing.

**Fix.** Narrow the predicate to the one reliable signal:

```text
process == "loginwindow"
  AND eventMessage CONTAINS[c] "authFailWithMessage"
  AND eventMessage CONTAINS[c] "INCORRECT password"
```

**Check.** Lock and unlock with the correct password. The counter stays at zero.

**Lesson.** Find the *narrowest* signal that is true, not the widest one that seems related.

</details>

### 11 · My filter ate the real signal

<details>
<summary>🔴 <b>Real failures stopped being detected after I added an exclusion</b></summary>

**Symptom.** After I tried to filter out noise with a broad word, genuine failures vanished.

**Real cause.** I excluded lines containing `screenlock`. But the real event comes from a class named `LWDefaultScreenLockUI`, which contains `screenlock`. I was deleting exactly what I wanted.

**Fix.** Keep only filters that cannot match the real event. The agent now drops just its own echoed messages:

```swift
if lower.contains("incident triggered") ||
   lower.contains("unauthorized access attempt") ||
   lower.contains("companions not supported") {
    // ignore: this is the agent's own log text coming back through the stream
    continue
}
```

**Check.** A real wrong password at the lock screen still produces `VERIFIED AUTH FAILURE`.

**Lesson.** A filter can fail silently. Test with a real event, and log what you filter out (the agent does).

</details>

### 12 · One wrong password counted several times

<details>
<summary>🔴 <b>A single wrong password triggered the 3-failure alert</b></summary>

**Symptom.** One wrong password could count as 4 to 6 failures at once.

**Real cause.** Several system components write log lines for the same attempt within a fraction of a second. Each line looked like a separate failure.

**Fix.** Two layers of debounce:
- `LogMonitor` ignores matches within **4 seconds** of the last one.
- `IncidentEngine` applies the same 4-second window again, counts attempts, and **resets the counter after 60 seconds** without a failure.

**Check.** One wrong password shows `Count: 1/3`. Three, spaced out, reach `3/3`.

**Lesson.** Count what a person did, not how many lines the system wrote.

</details>

### 13 · Log banner lines

<details>
<summary>🟡 <b><code>log stream</code> prints a header that can be mistaken for events</b></summary>

**Symptom.** At start-up, the stream prints a banner, which can be read as an event.

```text
Filtering the log data using ...
Timestamp                       Ty Process[PID:TID]
```

**Real cause.** `/usr/bin/log stream` always prints that header. Anything not filtered out is treated as an event.

**Fix.** Drop banner lines before evaluating anything:

```swift
if trimmed.hasPrefix("Filtering") ||
   (trimmed.contains("Timestamp") && trimmed.contains("Process")) {
    continue
}
```

The agent also ignores everything in the first 5 seconds after launch.

**A gap I know about.** After these filters, `LogMonitor` does not re-check that a remaining line really contains the failure text. The error output of `log stream` shares the same pipe, so an unexpected line could count as a failure. Adding that check is listed under [Still open](#-still-open).

**Lesson.** Anything you do not filter, you accept.

</details>

### 14 · Touch ID and the alert-first design

<details>
<summary>🔴 <b>The camera fired when I used the wrong finger</b></summary>

**Symptom.** In the first version, the agent captured a photo automatically on the third failure. A few Touch ID misses did the same, and photographed the owner.

**Real cause.** Touch ID misses are logged through the same system components as password failures, and separating them in the log was not reliable.

**Fix.** I changed the design instead of building a smarter filter. By default the agent sends a **text-only alert**, and the owner decides whether to take a photo. **Real-Time Mode**, which captures at once, is an opt-in switch in the app.

**Lesson.** When a system cannot be sure, put a human in the loop. A wrong alert costs a glance at your phone. A wrong photo costs privacy. The reasoning is in [Architecture](ARCHITECTURE.md#7--design-decisions).

</details>

---

## D · Logging

### 15 · Logs empty or missing

<details>
<summary>🟡 <b><code>agent.log</code> stayed empty, or missed events</b></summary>

**Symptom.** Xcode's console showed rich output, but as a launchd service, `~/Library/Logs/ShadowAgent/agent.log` was empty or missing events.

**Real cause.** Three separate things:
1. `print()` is **buffered** when output goes to a file in a background process, so lines sat in memory. The fix is `fflush(stdout)` after each line, which the agent does.
2. `Logger` (OSLog) writes to the **unified log database**, not a text file.
3. **Only some components write to `agent.log`.** `AppDelegate` and `LogMonitor` do. The shared `log()` function used by `IncidentEngine`, `CommandPoller` and the others prints to standard output only, which launchd stores in `/tmp/ShadowAgent.log`.

**Where to look**

| What you want | Where |
|---|---|
| Start-up and log-monitor messages | `~/Library/Logs/ShadowAgent/agent.log` |
| **Everything**, including incidents, captures and uploads | `/tmp/ShadowAgent.log` (cleared on reboot) |
| Messages from `AppDelegate` and `LogMonitor` in the system log | `log stream --predicate 'subsystem == "com.ph4ntom.shadow.ShadowAgent"' --style compact` |

**Lesson.** Know where each log goes. Making the shared `log()` write to `agent.log` too is listed under [Still open](#-still-open).

</details>

---

## E · Hardware

### 16 · Camera light stayed on

<details>
<summary>🔴 <b>The green camera light stayed on after a capture</b></summary>

**Symptom.** After a successful capture and upload, the green light stayed on until I quit the agent.

**Real cause.** The session was started but never stopped after the photo was taken, so macOS kept the camera in use.

**Fix.** Stop the session as soon as the capture callback finishes, using `defer` so it happens on both the success and error paths:

```swift
defer {
    sessionQueue.async { [weak self] in
        if self?.captureSession.isRunning == true {
            self?.captureSession.stopRunning()
        }
    }
}
```

**Check.** The light goes off shortly after each capture.

**A gap I know about.** If the capture callback never fires, the 8-second timeout in `IncidentEngine` gives up, but nothing stops the session. That edge case is listed under [Still open](#-still-open).

**Lesson.** Whatever you switch on, make sure every path switches it off.

</details>

---

## F · launchd and signing

### 17 · launchctl bootstrap error 5

<details>
<summary>🟡 <b><code>Bootstrap failed: 5: Input/output error</code></b></summary>

**Symptom.** `launchctl bootstrap` failed with error 5 and gave no useful detail.

**Real cause.** launchd rejects a plist it does not trust. In my case the plist had the wrong owner, wrong permissions, or extended attributes picked up when the file was copied. Error 5 can also appear when the same service is already loaded, which is why the script runs `bootout` first.

**Fix.** `deploy.sh` cleans the plist on every deploy:

```bash
launchctl bootout gui/$(id -u)/com.ph4ntom.shadow.ShadowAgent 2>/dev/null || true
cp -f com.ph4ntom.shadow.ShadowAgent.plist ~/Library/LaunchAgents/
chown "$(whoami)" ~/Library/LaunchAgents/com.ph4ntom.shadow.ShadowAgent.plist
chmod 644         ~/Library/LaunchAgents/com.ph4ntom.shadow.ShadowAgent.plist
xattr -c          ~/Library/LaunchAgents/com.ph4ntom.shadow.ShadowAgent.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.ph4ntom.shadow.ShadowAgent.plist
```

**Check.** `launchctl list | grep ShadowAgent` shows one entry.

**Lesson.** Put every fix you find by hand into the script, so you never meet it again.

</details>

### 18 · Signing and permissions across rebuilds

<details>
<summary>🔴 <b>Camera and location permissions kept resetting</b></summary>

**Symptom.** After rebuilding or redeploying, macOS asked for Camera and Location again, or the old "Allow" no longer worked.

**Real cause.** Ad-hoc signing (`codesign --sign -`) gives each build a different identity, so macOS treats every build as a new app.

**A correction to my own early theory.** I first blamed reboots. An ad-hoc identity changes when the binary is **rebuilt or re-signed**, not when the Mac restarts. The failure I actually reproduced after a restart was the lock file in [#7](#7--restart-loop-another-instance-is-already-running).

**Fix.** Sign every build with the same self-signed certificate, `ShadowAgentCert` (create it in **Keychain Access → Certificate Assistant → Create a Certificate**, type *Code Signing*), and deploy with it:

```bash
SIGN_IDENTITY="ShadowAgentCert" ./deploy.sh
```

**Check.**

```bash
codesign -dr - /Applications/ShadowAgent.app
```

Deploy twice. With the certificate, the requirement line is the same both times. With ad-hoc signing, it changes.

**Not used by this project.** The Keychain: the agent reads its key from `Secrets.swift`, so there is no Keychain code to unlock after a reboot.

**Lesson.** Permissions follow the signing identity. Full details are in [TCC Permissions](TCC_PERMISSIONS.md).

</details>

---

## G · Secrets and Git

### 19 · Secrets in source files

<details>
<summary>🔴 <b>The API key was written directly into <code>Config.swift</code></b></summary>

**Symptom.** The Firebase API key and project ID were hardcoded in a file I was about to publish.

**Real cause.** I had not set up a `.gitignore` yet. Dotfiles are hidden in Finder, which made it easy to forget.

**Fix.**
1. Move the values into `ShadowAgent/Secrets.swift` and read them from `Config.swift`.
2. Commit a template, `Secrets.swift.example`, with placeholders.
3. Add the real file to `.gitignore`, along with build output and logs:

```text
ShadowAgent/Secrets.swift
build/
DerivedData/
xcuserdata/
*.log
.DS_Store
```

4. Check it, and check that the key never reached history:

```bash
git check-ignore -v ShadowAgent/Secrets.swift
git log -p -S "AIzaSy" --all | head
```

5. **Rotate the key** if it ever appeared in a chat, a commit, or a screenshot, and restrict the new one to the Firestore API.

The phone app's Firebase config file (`firebase.ts`) must be ignored the same way.

**Lesson.** Keeping a key out of Git is not the same as keeping it secret. It is still compiled into the app. Real protection comes from Firestore rules and sign-in. See [Architecture](ARCHITECTURE.md#8--security-considerations).

</details>

### 20 · Git push rejected

<details>
<summary>🟡 <b><code>! [rejected] main -> main (fetch first)</code></b></summary>

**Symptom.** `git push origin main` was rejected.

**Real cause.** The GitHub repository already had commits I did not have locally (for example a README created on the website), and Git refuses to overwrite them.

**Fix.**

```bash
git pull origin main --rebase
git push origin main
```

If the rebase reports a conflict, fix the files, then run `git add` and `git rebase --continue`.

**Check.** `git log --oneline` shows your commits on top of the remote ones.

**Lesson.** Pull before you push, and create an empty repository if you already have local work.

</details>

---

## H · Cloud and app

### 21 · A burst of taps

<details>
<summary>🟡 <b>Tapping <i>Capture</i> several times started several captures at once</b></summary>

**Symptom.** Quick repeated taps ran several captures together, all fighting over one camera.

**Real cause.** Queued commands ran at the same time on shared objects.

**Fix.** Two guards: `IncidentEngine` skips a new capture while one is running (`isProcessingIncident`), and `CommandPoller` handles one poll at a time (`isProcessing`).

**A limit I know about.** A command that arrives during a capture is skipped, but still marked completed.

**Lesson.** Anything a person can trigger, they can trigger many times. Hardware needs a "busy" flag.

</details>

### 22 · Everything went quiet one day

<details>
<summary>🟡 <b>No errors, but nothing worked</b></summary>

**Symptom.** The agent stopped responding, with no obvious error.

**Real cause.** The agent polls Firestore for commands, and I hit the free-tier quota. Quota errors looked like silence.

**Fix.** I raised the polling interval to 10 seconds.

**Lesson.** Polling has a real cost. Better designs back off when idle, or use push. Backoff is not built yet.

</details>

### 23 · The app showed blank fields

<details>
<summary>🟡 <b>The data was in Firestore, but the app showed nothing</b></summary>

**Symptom.** Incidents existed in Firestore, but the phone app and dashboard showed empty fields.

**Real cause.** The agent writes raw REST JSON, where every value is wrapped with its type, like `{"stringValue": "hello"}`. The apps read through the Firebase SDK, which unwraps values automatically. I had mixed up the two shapes.

**Fix.** The agent wraps values, and the apps read plain fields. This is written in [Architecture](ARCHITECTURE.md#rest-versus-sdk-field-shapes).

**Lesson.** Two clients can read the same data in two different shapes, so write the contract down.

</details>

### 24 · Expo icon not changing

<details>
<summary>🟢 <b>My custom icon did not appear in Expo Go</b></summary>

**Symptom.** I changed `assets/icon.png` and `app.json`, but the phone kept showing Expo's default icon.

**Real cause.** **Expo Go always shows its own icon** for projects you run inside it. Your own icon appears only in a standalone or development build. Separately, Metro caches assets, which can make other changes look stale.

**Fix.** Clear the cache when things look stale, and build a real app to see the icon:

```bash
cd shadow-app
npx expo start -c
eas build -p android --profile preview
```

Check that `app.json` points to your files:

```json
{
  "expo": {
    "icon": "./assets/icon.png",
    "android": {
      "adaptiveIcon": {
        "foregroundImage": "./assets/adaptive-icon.png",
        "backgroundColor": "#121212"
      }
    }
  }
}
```

**Lesson.** Know what the tool you test in can and cannot show.

</details>

---

## 🧰 Debug toolbox

| I want to know… | Command |
|---|---|
| Is it running? | `pgrep -fl ShadowAgent` |
| Is launchd managing it? | `launchctl list \| grep ShadowAgent` |
| Why did launchd stop it? | `launchctl print gui/$(id -u)/com.ph4ntom.shadow.ShadowAgent \| head -40` |
| Is there a hidden system-level copy? | `sudo launchctl list \| grep -i shadow` |
| What did it log? | `tail -f /tmp/ShadowAgent.log` and `tail -f ~/Library/Logs/ShadowAgent/agent.log` |
| What is the app's signing identity? | `codesign -dr - /Applications/ShadowAgent.app` |
| Is my certificate usable? | `security find-identity -v -p codesigning` |
| Replay a permission prompt | `tccutil reset Camera com.ph4ntom.shadow.ShadowAgent` |
| Does the plist carry extra flags? | `xattr -l ~/Library/LaunchAgents/com.ph4ntom.shadow.ShadowAgent.plist` |
| Stop it properly | `launchctl bootout gui/$(id -u)/com.ph4ntom.shadow.ShadowAgent` |

---

## 🚧 Still open

Honest list of what is not fixed yet:

- **Remove the unused `FirebaseFirestore` package** from the Xcode project ([#2](#2--missing-package-product-firebasefirestore)).
- **Make the shared `log()` write to `agent.log` too** ([#15](#15--logs-empty-or-missing)).
- **Check each log line's text** in `LogMonitor` before counting it as a failure ([#13](#13--log-banner-lines)).
- **Stop the camera session if a capture times out** ([#16](#16--camera-light-stayed-on)).
- **Re-test Touch ID** against the narrow predicate, to see whether misses still match ([#14](#14--touch-id-and-the-alert-first-design)).
- **Offline capture.** If the Mac has no internet at the third failure, the incident is lost. A disk queue is designed, but parked, because coordinates cannot be found offline.
- **Firebase sign-in for the agent, app and dashboard**, so Firestore rules can tell the owner from anyone else.
- **Backoff for polling** ([#22](#22--everything-went-quiet-one-day)).

---

<div align="center">

[← Back to README](../README.md) · [User Guide](USER_GUIDE.md) · [TCC Permissions](TCC_PERMISSIONS.md)

</div>
