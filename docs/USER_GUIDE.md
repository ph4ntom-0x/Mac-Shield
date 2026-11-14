<div align="center">

# 🛡️ Mac Shield · User Guide

**From a fresh clone to a Mac that tells you when someone is trying to get in.**

![Platform](https://img.shields.io/badge/platform-macOS-lightgrey?logo=apple)
![Language](https://img.shields.io/badge/swift-agent-orange?logo=swift)
![Backend](https://img.shields.io/badge/backend-Firestore-yellow?logo=firebase)
![Alerts](https://img.shields.io/badge/alerts-Telegram%20%7C%20app-2CA5E0?logo=telegram)
![Status](https://img.shields.io/badge/status-working%20prototype-blue)

[← Back to README](../README.md) · [Architecture](ARCHITECTURE.md) · [Story](STORY.md)

</div>

---

## 📑 Contents

1. [What you need](#1--what-you-need)
2. [How the pieces fit](#2--how-the-pieces-fit)
3. [Set up Firebase](#3--set-up-firebase)
4. [Add your secrets](#4--add-your-secrets)
5. [Build and install](#5--build-and-install)
6. [Grant permissions](#6--grant-permissions)
7. [Check that it is running](#7--check-that-it-is-running)
8. [Connect the phone app and dashboard](#8--connect-the-phone-app-and-dashboard)
9. [Set up Telegram (optional)](#9--set-up-telegram-optional)
10. [Using Mac Shield](#10--using-mac-shield)
11. [Troubleshooting](#11--troubleshooting)
12. [Update](#12--update)
13. [Uninstall](#13--uninstall)
14. [Privacy and responsible use](#14--privacy-and-responsible-use)

> [!NOTE]
> Mac Shield is a **working prototype**, tested on the author's own Mac and not security audited.
> Read the [limitations](ARCHITECTURE.md#9--limitations) before relying on it.

---

## 1 · What you need

| Requirement | Details |
|---|---|
| 💻 **A Mac you own** | Developed and tested on a MacBook Air |
| 🔨 **Xcode** | The **full Xcode app** from the App Store, not only the Command Line Tools. The deploy script builds an `.xcodeproj`, which needs full Xcode |
| 👤 **Admin account** | To install into `/Applications` and register the background service |
| ☁️ **Google account** (optional) | For the Shadow app and dashboard. The free tier of Firebase is enough. Skip it if you use Telegram only |
| 📱 **Shadow app, browser or Telegram** | To receive alerts and send commands. Pick one or use several |
| ✈️ **Telegram account** (optional) | For alerts and buttons through a Telegram bot |
| ⏱️ **About 30 minutes** | Most of it is Firebase and permissions |

Check that the build tools are ready:

```bash
xcodebuild -version
```

You should see an Xcode version number. If you get an error about Command Line Tools, open Xcode once, accept the license, then run:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

---

## 2 · How the pieces fit

```text
 ┌──────────────┐      ┌───────────────────────┐      ┌─────────────────────┐
 │              │ ◀──▶ │  Firestore            │ ◀──▶ │  Shadow app         │
 │              │      │  (your own project)   │      │  Web dashboard      │
 │  ShadowAgent │      └───────────────────────┘      └─────────────────────┘
 │  on your Mac │                                                            
 │              │      ┌───────────────────────┐      ┌─────────────────────┐
 │              │ ◀──▶ │  Telegram bot         │ ◀──▶ │  Telegram on        │
 │              │      │  (your own bot)       │      │  your phone         │
 └──────────────┘      └───────────────────────┘      └─────────────────────┘
```

| Piece | Runs on | Job |
|---|---|---|
| **ShadowAgent** | Your Mac, in the background | Watches for failed logins, captures evidence on request |
| **Firestore** (optional) | Google's cloud, your own project | Passes messages between the Mac and the Shadow app |
| **Shadow app / dashboard** (optional) | Phone / browser | Shows alerts, sends *Capture* and *Alarm* commands, holds the Real-Time switch |
| **Telegram bot** (optional) | Telegram, a bot you create | Delivers alerts as real push notifications and takes button taps and commands |

You can use it three ways:

| Way | What you set up |
|---|---|
| **Telegram only** | A Telegram bot. No Firebase and no app ([section 9](#9--set-up-telegram-optional)) |
| **Shadow app only** | Firebase and the app (sections 3 and 8) |
| **Both** | Everything. The Real-Time switch stays in step between them |

---

## 3 · Set up Firebase

> [!NOTE]
> Skip this section and section 8 if you will use **Telegram only**. Go to [section 9](#9--set-up-telegram-optional).

1. Open the [Firebase console](https://console.firebase.google.com) and create a project, for example `mac-shield`.
2. Add a **Firestore Database**.
3. In **Project settings → General**, note your **Project ID** and **Web API key**.
4. In Google Cloud Console → **APIs & Services → Credentials**, open that API key and **restrict it to the Cloud Firestore API**.

> [!WARNING]
> **Understand the security model before you go live.**
> The agent talks to Firestore over REST using only the API key, with no sign-in. That means your
> Firestore rules must allow the agent's requests, and anyone who learns your project ID and key
> could potentially read incidents or write commands.
>
> - Use a **dedicated Firebase project** for Mac Shield and store nothing else in it.
> - Restrict the API key as described above, and never commit it.
> - Treat open rules as **testing only**. Signing the agent, app and dashboard in with Firebase Auth
>   is the proper fix and is on the roadmap.

---

## 4 · Add your secrets

Your keys live in a file that is **never committed**.

```bash
git clone https://github.com/YOUR_USERNAME/mac-shield.git
cd mac-shield
cp ShadowAgent/Secrets.swift.example ShadowAgent/Secrets.swift
```

Open `ShadowAgent/Secrets.swift` and fill in your values:

```swift
enum Secrets {
    // Firebase (for the Shadow app and dashboard). Empty strings = Firebase off.
    static let projectID = "your-firebase-project-id"
    static let apiKey    = "your-restricted-api-key"

    // Telegram (optional). Empty token = Telegram off. See section 9.
    static let telegramBotToken = ""
    static let telegramOwnerID: Int64 = 0
}
```

Using Telegram only? Leave `projectID` and `apiKey` as empty strings (`""`).

> [!TIP]
> In Xcode, select `Secrets.swift` and make sure the **ShadowAgent** target is ticked under
> *Target Membership*. Otherwise the build fails with `cannot find 'Secrets' in scope`.

Confirm Git is ignoring it (this should print the path):

```bash
git check-ignore -v ShadowAgent/Secrets.swift
```

---

## 5 · Build and install

```bash
chmod +x deploy.sh
./deploy.sh
```

<details>
<summary><b>What <code>deploy.sh</code> does, step by step</b></summary>

1. **Builds** a Release version with `xcodebuild`.
2. **Installs** `ShadowAgent.app` into `/Applications`.
3. **Signs** the app with `codesign` so macOS accepts it as a background item.
4. **Syncs the LaunchAgent plist** into `~/Library/LaunchAgents/`, sets ownership and `chmod 644`, and clears quarantine attributes with `xattr -c` (this prevents the `Input/output error` on bootstrap).
5. **Reloads the service** with `launchctl bootout` then `bootstrap` in your login session.

</details>

When it finishes you should see:

```text
✅ Deployment complete! ShadowAgent is active.
```

A small **shield icon** appears in the menu bar showing *Running*. There is no Dock icon.

> [!IMPORTANT]
> **About signing.** By default `deploy.sh` signs ad-hoc. An ad-hoc signature changes with every
> build, so macOS may forget your Camera, Location and Full Disk Access permissions after each deploy.
>
> To stop that, create a free self-signed certificate once and use it on every deploy:
>
> 1. Open **Keychain Access → Certificate Assistant → Create a Certificate**.
> 2. Name it `ShadowAgentCert`, set *Identity Type* to **Self Signed Root** and *Certificate Type* to **Code Signing**.
> 3. Check it with `security find-identity -v -p codesigning`.
> 4. Deploy with it:
>
> ```bash
> SIGN_IDENTITY="ShadowAgentCert" ./deploy.sh
> ```
>
> The first time, grant the permissions again. After that they stay. Details are in
> [TCC Permissions](TCC_PERMISSIONS.md).

---

## 6 · Grant permissions

Open **System Settings → Privacy & Security** and enable ShadowAgent in each list:

| Permission | Why it is needed |
|---|---|
| 🔓 **Full Disk Access** | Lets the agent read authentication log messages. Without it they show as `<private>` and nothing is detected |
| 📷 **Camera** | Takes a photo when you request one (or in Real-Time Mode) |
| 📍 **Location Services** | Attaches coordinates to captured incidents |

Then open **System Settings → General → Login Items & Extensions** and check that **ShadowAgent** is listed under *Allow in the Background* and switched **on**.

> [!NOTE]
> After granting Full Disk Access, run `./deploy.sh` again so the agent restarts with the new permission.

---

## 7 · Check that it is running

```bash
pgrep -fl ShadowAgent                  # exactly one process, owned by you
launchctl list | grep ShadowAgent      # one entry
```

Expected output looks like:

```text
4395 /Applications/ShadowAgent.app/Contents/MacOS/ShadowAgent
```

**Watch the live log** (press `Ctrl + C` to stop):

```bash
tail -f /tmp/ShadowAgent.log
```

| Log file | Contains |
|---|---|
| `~/Library/Logs/ShadowAgent/agent.log` | Start-up and log-monitor messages. Also reachable from the menu bar: **Open Log File** |
| `/tmp/ShadowAgent.log` | **Everything** the agent prints, including incidents, captures and uploads. Cleared on every reboot |
| `/tmp/ShadowAgent.err.log` | Errors captured by launchd. Check this first if it will not start |

A healthy start logs that the agent is active and that the log monitor and command poller have started.

### Stopping and restarting by hand

```bash
# Stop and unload
launchctl bootout gui/$(id -u)/com.ph4ntom.shadow.ShadowAgent

# Start again
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.ph4ntom.shadow.ShadowAgent.plist
```

> [!NOTE]
> Choosing **Quit** from the menu bar only quits that copy. The service is set to keep alive, so
> launchd starts it again. Use `launchctl bootout` to stop it for real.

---

## 8 · Connect the phone app and dashboard

The Shadow phone app (Expo / React Native) and the web dashboard (React) read and write the **same Firestore project** as the agent. Give each one the same Project ID and API key you used above.

They use these Firestore collections:

| Path | Purpose |
|---|---|
| `incidents/` | Alerts and captures written by the agent |
| `commands/` | Commands (`CAPTURE_PHOTO`, `TRIGGER_ALARM`) written by the app, polled by the agent |
| `settings/config` | Holds the `realTimeMode` switch |

### 📱 Set up the phone app

The Shadow app is built with **Expo (React Native)** and talks to Firestore through the Firebase JavaScript SDK. Because of that, it needs the Firebase **web** config, not `GoogleService-Info.plist` or `google-services.json`.

**You need:** [Node.js](https://nodejs.org) (LTS), and the **Expo Go** app on your phone (App Store or Google Play).

**Step 1 · Install dependencies**

```bash
cd shadow-app
npm install
```

**Step 2 · Add your Firebase config**

In the Firebase console go to **Project settings → General → Your apps**, add a **Web app**, and copy the config object. Put it in a git-ignored file:

```bash
cp firebaseConfig.example.js firebaseConfig.js
```

```js
export const firebaseConfig = {
  apiKey: "your-restricted-api-key",
  projectId: "your-firebase-project-id",
  // ...the other fields Firebase gives you
};
```

> [!WARNING]
> Never commit `firebaseConfig.js`. Confirm it is ignored with `git check-ignore -v firebaseConfig.js`.

**Step 3 · Run the app**

```bash
npx expo start
```

Scan the QR code with your phone camera (iOS) or the Expo Go app (Android). Your phone and computer must be on the same Wi-Fi network.

**Step 4 · Test the full loop**

1. Trigger three wrong passwords on your Mac (see [Test it safely](#-test-it-safely)).
2. With the app **open**, a **SUSPICIOUS ACTIVITY** card appears.
3. Tap **Capture photo**. Within about 10 to 20 seconds a **REMOTE CAPTURE** card appears with a map link.

> [!NOTE]
> The Shadow app shows alerts only while it is open and has no push notifications. For real push notifications on your phone, add [Telegram](#9--set-up-telegram-optional).

### 🖥️ Set up the web dashboard

The React dashboard uses the same Firebase config values. Install its dependencies, add the config the same way, and start it with the dev script listed in its `package.json`.

---

## 9 · Set up Telegram (optional)

Telegram gives you **real push notifications** on your phone and lets you control Mac Shield from a chat. If you want, you can skip Firebase and the Shadow app completely.

### What you get

| In Telegram | What happens |
|---|---|
| ⚠️ **An alert** after 3 wrong passwords | A message with **📸 Capture photo** and **🔔 Sound alarm** buttons. No photo or location yet |
| 📸 **Capture photo** button | The Mac takes a photo and finds its location, then sends them to the chat with a map link and a location pin |
| 🔔 **Sound alarm** button | Plays a loud alarm on the Mac for about 15 seconds |
| `/realtime` | Shows Real-Time Mode with a **Turn ON** or **Turn OFF** button. `/realtime on` and `/realtime off` also work |
| `/status` | Shows that the agent is running, and the current Real-Time Mode |

### Step 1 · Create the bot

1. In Telegram, open **@BotFather** (check the blue tick) and send `/newbot`.
2. Choose a name, and a username that ends in `bot`.
3. Copy the **token** BotFather gives you. Treat it like a password.
4. Open your new bot, press **Start**, and send it any message, such as `hello`. A bot cannot message you until you have started the chat.

### Step 2 · Add the token

In `ShadowAgent/Secrets.swift`:

```swift
static let telegramBotToken = "your-bot-token"
static let telegramOwnerID: Int64 = 0      // you will fill this in next
```

Then run `./deploy.sh`.

### Step 3 · Tell the agent who you are

The agent obeys **one** Telegram account: yours. While the owner ID is `0`, it is in **setup mode**. It does nothing except print the ID of anyone who messages the bot.

1. Watch the log:
   ```bash
   tail -f /tmp/ShadowAgent.log
   ```
2. Send your bot another message. The log shows a line like this:
   ```text
   [Telegram] Setup: a message arrived from user ID 123456789. Put this number in Secrets.swift as telegramOwnerID.
   ```
3. Put that number into `Secrets.swift`, as a plain number with no quotes, then run `./deploy.sh` again.
4. Send `/start`. The bot should reply that Mac Shield is running.

### Step 4 · Try it

1. Lock your screen with **Control + Command + Q** and type **3 wrong passwords**, about 5 seconds apart.
2. An alert with two buttons arrives in Telegram. Tap **📸 Capture photo**. The photo, map link and location pin follow within a few seconds.
3. Send `/realtime`, tap **⚡ Turn ON**, and repeat the wrong passwords. This time the photo arrives with no tap.
4. Send `/realtime` again and turn it **OFF**.

### Telegram only (no Firebase)

In `Secrets.swift`, set `projectID` and `apiKey` to empty strings (`""`) and fill in the two Telegram values. When the agent starts, the log says `Firestore commands are off. Only Telegram can send commands.`

| You keep | You lose |
|---|---|
| Alerts, photos, location, the alarm, `/realtime` and `/status` | Incident history (it lives only in the chat), the web dashboard, and the Shadow app |

With both Firebase and Telegram set up, `/realtime` and the app's switch stay in step. Telegram saves the choice on the Mac and also writes it to Firestore.

### Settings in `Config.swift`

| Setting | Default | Meaning |
|---|---|---|
| `TELEGRAM_SEND_PHOTOS` | `true` | `false` sends text and location only, and no photos |
| `FIRESTORE_COMMANDS_ENABLED` | `true` | `false` makes the agent ignore commands written to Firestore, so only Telegram can send commands |

### Keep it safe

- **Only your account can give commands.** Anyone can message a bot, so the agent ignores every message and button tap that does not come from your Telegram user ID.
- **The bot token is a secret.** It stays in the git-ignored `Secrets.swift`. If it leaks, send `/revoke` to BotFather, put the new token in `Secrets.swift`, and redeploy.
- **Old buttons stop working.** When the agent starts, it discards anything queued while it was off, and buttons older than 30 minutes are refused.
- **Telegram bot chats are not end-to-end encrypted.** Photos you send to Telegram are held on Telegram's servers. Set `TELEGRAM_SEND_PHOTOS` to `false` if you do not want that.
- **Use one bot per Mac.** Two agents polling the same bot will fight over its messages.

---

## 10 · Using Mac Shield

### The normal flow: alert first

```text
 3 wrong passwords ──▶ ⚠️ SUSPICIOUS ACTIVITY card ──▶ you decide ──▶ 📸 Capture / 🔔 Alarm
```

1. Someone enters a wrong password **three times** on the lock screen.
2. A **SUSPICIOUS ACTIVITY** card appears in your app, and an alert with buttons arrives in Telegram if you set it up. It has no photo and no location.
3. You decide whether it looks real.
4. Tap **Capture photo**, in the app or in Telegram. Within about 10 to 20 seconds the Mac takes a photo and finds its location. It appears as a separate **REMOTE CAPTURE** card with a map link.
5. Tap **Trigger alarm** to play a loud alarm on the Mac for about 15 seconds.

> [!NOTE]
> The agent checks for new commands every 10 seconds, so there can be a short delay after you tap.

### ⚡ Real-Time Mode (optional)

A switch in the app, or `/realtime` in Telegram. **On:** the third failed attempt captures a photo and location immediately. **Off (default):** you decide.

> [!CAUTION]
> A Touch ID miss can be logged like a wrong password, so Real-Time Mode may photograph you after a
> few fingerprint misses. That is why alert-first is the default.

### 🧪 Test it safely

1. Lock your screen with **Control + Command + Q**.
2. Type a wrong password **three times**, waiting about 5 seconds between tries and finishing within a minute.
3. Watch the log and the app, then unlock normally.

> [!TIP]
> Attempts closer together than 4 seconds count as one, and the counter resets after 60 seconds
> without a failure. That is the debounce at work.

---

## 11 · Troubleshooting

Stuck on something odd? The [Problems Solved](PROBLEMS_SOLVED.md) page explains the bugs I hit while building this, in detail.

| Symptom | Likely cause and fix |
|---|---|
| **No alerts at all** | Full Disk Access is missing. Add ShadowAgent, then run `./deploy.sh` again |
| **`cannot find 'Secrets' in scope`** | Create `Secrets.swift` (step 4) and tick the target membership box |
| **`Camera permission denied` in the log** | Permission not granted, or reset by a re-sign. Grant it again in Privacy & Security, or use a stable signing certificate |
| **Photo arrives but no map link** | Location was unavailable, for example right after waking from sleep. Try again once Wi-Fi is back |
| **Tapping Capture does nothing** | Check the log for errors. A Firestore free-tier quota limit can look like silence |
| **Log says "another instance is already running", and it restarts every 10 seconds** | Check the line above it. If it says `Failed to open lock file`, the lock file has bad permissions. Run `launchctl bootout gui/$(id -u)/com.ph4ntom.shadow.ShadowAgent`, then `rm ~/Library/Application\ Support/ShadowAgent/ShadowAgent.lock`, then `./deploy.sh`. If `pgrep -fl ShadowAgent` shows a real process, an old copy is alive, so use the uninstall steps first |
| **`./deploy.sh` says "not running" at the end** | Read `~/Library/Logs/ShadowAgent/agent.log` and `/tmp/ShadowAgent.err.log`. Note that `/tmp` is cleared on every reboot |
| **Stopped working after a restart** | Check `launchctl list \| grep ShadowAgent`, and make sure ShadowAgent is still switched on in *Login Items & Extensions*. Run `./deploy.sh` to load it again |
| **`Input/output error` from `launchctl bootstrap`** | The plist has wrong ownership or quarantine flags. `deploy.sh` clears these, so run it again |
| **Two copies running, doubled actions** | A leftover service under another owner. Run `sudo launchctl list \| grep ShadowAgent` and boot it out |
| **One real attempt raises several alerts** | Several system components log one attempt. The agent debounces this. Please report it if it persists |
| **The bot never answers `/start`** | The token or owner ID is wrong, or the Mac is offline. Read the `[Telegram]` lines in `/tmp/ShadowAgent.log` |
| **The log says "Setup mode" and nothing else works** | `telegramOwnerID` is still `0`. Follow step 3 of section 9 |
| **`[Telegram] Poll problem` with "Conflict"** | Another copy of the agent, or another program, is using the same bot token. Check `pgrep -fl ShadowAgent` |
| **Telegram buttons say "expired"** | Buttons work for 30 minutes after the alert. Wait for the next alert |
| **No photo in Telegram, but the text arrives** | Check the Camera permission and the log. Also check that `TELEGRAM_SEND_PHOTOS` is `true` |
| **`/realtime` and the app's switch disagree** | The change could not be written to Firestore. Read the log, then change it again |

---

## 12 · Update

```bash
git pull
./deploy.sh
```

Your `Secrets.swift` is git-ignored, so it stays in place.

---

## 13 · Uninstall

```bash
# 1. Stop and unregister the service
launchctl bootout gui/$(id -u)/com.ph4ntom.shadow.ShadowAgent

# 2. Remove the LaunchAgent and the app
rm -f ~/Library/LaunchAgents/com.ph4ntom.shadow.ShadowAgent.plist
rm -rf /Applications/ShadowAgent.app

# 3. Remove data and logs
rm -rf ~/Library/Application\ Support/ShadowAgent
rm -rf ~/Library/Logs/ShadowAgent
rm -f /tmp/ShadowAgent.log /tmp/ShadowAgent.err.log
defaults delete com.ph4ntom.shadow.ShadowAgent 2>/dev/null   # the saved Real-Time setting

# 4. Confirm it is gone (no output means removed)
pgrep -fl ShadowAgent
```

Finally, remove ShadowAgent from the **Camera**, **Location** and **Full Disk Access** lists in System Settings. If you used Telegram, also delete the bot or revoke its token with **@BotFather** (`/deletebot` or `/revoke`).

---

## 14 · Privacy and responsible use

- 🏠 Install it **only on a device you own**.
- ☁️ Photos go only to services **you** set up: your own Firebase project and/or your own Telegram bot. Nothing is sent to the author.
- ✈️ If you use Telegram, photos are held on **Telegram's servers**, and bot chats are not end-to-end encrypted. Set `TELEGRAM_SEND_PHOTOS` to `false` to keep photos off Telegram.
- 🌍 If CoreLocation fails, the agent falls back to an IP lookup through `ipapi.co`, which means your public IP is sent to that third-party service.
- 🔒 Keep your Firestore project private, your API key restricted, and your bot token secret. Anyone who can read your database can see your photos, and anyone with your bot token can act as your bot.
- 🚫 Never use Mac Shield to watch another person.

---

<div align="center">

**Found a problem or have an idea?** Open an issue on GitHub.

[← Back to README](../README.md)

</div>
