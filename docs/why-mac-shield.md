<div align="center">

# 💡 Why Mac Shield

**The story behind it, the gap I wanted to fill, and an honest look at the tools that already exist.**

[← Back to README](../README.md) · [Architecture](ARCHITECTURE.md) · [Problems Solved](PROBLEMS_SOLVED.md)

</div>

---

## 📑 Contents

1. [The short version](#1--the-short-version)
2. [Why I built it](#2--why-i-built-it)
3. [The gap I wanted to fill](#3--the-gap-i-wanted-to-fill)
4. [What already exists](#4--what-already-exists)
5. [What is new here, and what is not](#5--what-is-new-here-and-what-is-not)
6. [Where other tools are better](#6--where-other-tools-are-better)
7. [Who Mac Shield is for](#7--who-mac-shield-is-for)
8. [How I checked, and what I did not check](#8--how-i-checked-and-what-i-did-not-check)

---

## 1 · The short version

Mac Shield tells you, on your phone, when someone types the wrong password three times on your Mac's lock screen. You can get the alert in a **Telegram bot**, in the **Shadow app**, or in both. You then decide whether to take a photo and record the location, or you can switch on **Real-Time Mode** and let it do that straight away.

Taking a photo after a failed login is **not a new idea**. Several tools have done it for years. What I wanted was a small, open, **owner-controlled** version: alert first, capture only when I say so, and keep the data in my own storage.

---

## 2 · Why I built it

Last summer, while I was home for the holidays, my 7-year-old cousin tried to unlock my MacBook, probably to watch cartoons. He typed passwords again and again and failed. Then he decided the next step was to put the laptop in a bathtub full of water. The MacBook did not survive.

I had no idea any of it was happening. Nothing told me someone was trying to get into my Mac, and by the time I found out it was too late.

Mac Shield is what I wanted at that moment: a message saying *someone is failing to unlock your laptop right now*, so I could react while it still mattered.

> [!NOTE]
> Mac Shield cannot physically stop anyone. What it can do is tell you early, so you can act.

---

## 3 · The gap I wanted to fill

Apple's **Find My** can locate, lock or erase a Mac, but it does not tell you that someone is guessing your password, and it does not show you who. I wanted something for one narrow situation: **a failed unlock attempt on a Mac I own.**

I had three rules for it:

| Rule | Why |
|---|---|
| **Alert first, capture on request** | A Touch ID mistake looks like a wrong password in the log. Taking a photo of the owner by accident is a privacy problem, so a human should decide |
| **Services I control** | Photos should go to a Firebase project or a Telegram bot that I create and control, not to a server run by the author or by an anti-theft vendor |
| **Small and readable** | I wanted to see exactly what the code does with my camera |

---

## 4 · What already exists

I looked at the tools below. Most are older, so check each one's current status before relying on it.

| Tool | Open source? | What triggers a capture | Does the owner decide first? | Where the data goes |
|---|---|---|---|---|
| **Mac Shield** | Yes | 3 wrong passwords, then the owner's command. Real-Time Mode captures immediately | **Yes** by default | Your own Firebase project and/or your own Telegram bot chat |
| **Apple Find My** | No | The owner's request (locate, lock, erase) | Not applicable | Apple |
| **Mac-Watcher** | Yes (MIT) | Waking from sleep. It can be set to act only on login failures (Touch ID and password) | No, it captures automatically | A local folder, and email if configured |
| **iAlertU** | Yes (GPLv2) | Motion, keyboard or device changes while armed | No | Photo sent by email, optional AppleScript |
| **Prey** | The client code is public on GitHub. The service is hosted | The owner marks the device **Missing** in the Prey panel | Yes, but it is not tied to failed logins | Prey's servers |
| **Undercover** | No (commercial) | The owner marks the Mac as stolen | Yes, after it is marked | The vendor's servers |
| **ProteMac LoginTrap, Spy Lock** | No (commercial apps) | A failed login. They photograph the person, and LoginTrap emails it | No | Email (LoginTrap) |

Also worth knowing: tips for taking a webcam photo on a failed Mac login have been published as scripts for many years. The idea is old.

Watching the unified log for repeated `loginwindow` failures is also a standard technique in security monitoring, not something I invented.

---

## 5 · What is new here, and what is not

**Not new**
- Taking a photo after a failed login.
- Sending an alert or photo by email.
- Remote alarm from a phone (iAlertU and Prey both have forms of this).
- Being open source (Mac-Watcher and iAlertU are too).

**What I think is different**

> **To my knowledge**, among the tools I looked at, Mac Shield combines three things in one small project: an alert that lets the **owner decide** before any photo is taken, **remote capture, alarm and Real-Time controls** from a phone (through the Shadow app or a Telegram bot), and **no vendor server in the middle**, because alerts and photos go through a Firebase project and/or a Telegram bot that you create yourself.

I only looked at a handful of tools, so there may be others that do the same. I am not claiming this is the first or the only one.

| Design choice | How Mac Shield does it |
|---|---|
| **Capture policy** | Alert first. A photo only on the owner's command, with an opt-in automatic mode that can be switched from the app or from Telegram |
| **Hosting** | You run your own Firebase project and/or your own Telegram bot. Nothing is sent to the author. In Telegram mode, photos are held on Telegram's servers, and bot chats are not end-to-end encrypted |
| **Detection** | Reads macOS's own unified log for lock-screen failures. No kernel extension |
| **Transparency** | A small Swift codebase you can read in an afternoon |
| **Documentation** | The real macOS problems met along the way are written down in [Problems Solved](PROBLEMS_SOLVED.md) and [TCC Permissions](TCC_PERMISSIONS.md) |

---

## 6 · Where other tools are better

Mac Shield is a **working prototype**, tested on my own Mac and not audited. Be honest about what that means:

- **Theft recovery.** Find My works when the Mac is offline and can lock or erase it. Prey and Undercover were built for recovering stolen devices, with reports on a schedule. Mac Shield is not a theft-recovery tool.
- **Offline.** If the Mac has no internet when the third failure happens, Mac Shield cannot upload the alert. There is no offline queue yet.
- **Alerts.** The Shadow app has no push notifications and shows alerts only while it is open. Telegram gives real push notifications, but only when the Mac has internet.
- **Tampering.** Someone with access to the Mac can quit or remove the agent. There is no anti-tampering. but password based things can be add so that required of password for deleting. 
- **Security of the cloud side.** The agent does not sign in to Firebase yet, so your Firestore rules cannot fully tell you apart from anyone else holding the key. Telegram-only mode avoids this, because only your own Telegram account can give commands. See [Architecture](ARCHITECTURE.md#8--security-considerations).
- **Platform.** macOS only.

The full list is in [Limitations](ARCHITECTURE.md#9--limitations).

---

## 7 · Who Mac Shield is for

 **A good fit if** you want to know when someone is guessing your Mac's password, you like keeping your data in your own project, and you are happy to run a prototype.

* Use Find My find can be helpful in recovery along with this for monitor . 

 **Only on a Mac you own.** Do not use it to watch another person.

---

## 8 · How I checked, and what I did not check

**What I did.** In November 2026 I read each tool's own documentation or repository page where one exists, plus press coverage of it. The sources are listed below.

**What I did not do.**
- I did not install or test any of these tools.
- Most press coverage of Undercover, iAlertU, LoginTrap and Spy Lock dates from the OS X era (roughly 2006 to 2014), so I could not confirm that they still work on current macOS or are still maintained.
- I did not check Prey's licence or its newest macOS behaviour.
- I did not look at how any of these tools are built or how they handle macOS permissions (TCC). I make no claim that they are blocked on current macOS. Every tool that uses the camera, location or system logs faces the same rules.
- I did not check whether any of these tools can send alerts or take commands through Telegram or another chat app.

**Please check this table again** before relying on a row, and tell me if you find a tool I missed or a row that is wrong.

<details>
<summary><b>Sources</b></summary>

- Mac-Watcher: <https://github.com/ramanaraj7/mac-watcher>
- iAlertU: <https://sourceforge.net/p/ialertu/> and <https://www.techspot.com/downloads/2272-ialert-for-mac.html>
- Prey, how it works: <https://help.preyproject.com/article/195-how-does-prey-work>
- Prey, photos and screenshots: <https://help.preyproject.com/article/194-taking-webcam-photos-and-screenshots-with-prey>
- Prey, older client notice: <https://github.com/prey/prey-bash-client>
- Undercover: <https://www.macstories.net/reviews/tracking-stolen-macs-with-undercover-5/> and <https://www.macworld.com/article/178534/undercover.html>
- ProteMac LoginTrap: <https://www.iclarified.com/7914/protemac-releases-protemac-logintrap-10/amp>
- Spy Lock: <https://mac.softpedia.com/get/Utilities/Spy-Lock.shtml> and <https://www.mactech.com/2011/11/01/spy-lock-released-for-mac-os-x/amp/>
- Failed-login photo scripts: <https://gizmodo.com/protect-your-macbook-isight-pics-of-failed-logins-221581>

</details>

---

<div align="center">

[← Back to README](../README.md) · [Architecture](ARCHITECTURE.md) · [Problems Solved](PROBLEMS_SOLVED.md)

</div>
