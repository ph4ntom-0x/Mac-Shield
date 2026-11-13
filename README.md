# Mac Shield 🛡️

Mac Shield is your MacBook's personal security guard. If someone types the wrong password 3 times on your lock screen, Mac Shield instantly sends an alert to your phone. 

You can receive these alerts—and picture and location (real time on) ,just receive notification if you had off real time mode and can take action, like snapping a photo of the intruder or grabbing your Mac's location—using either our dedicated **Shadow App** or directly through a **Telegram Bot**. 

## What's inside

1. **Shadow Agent:** A lightweight Swift program that runs quietly in the background of your Mac. It watches system logs for failed login attempts.
2. **Shadow App & Dashboard:** A dedicated mobile app (React Native) and web dashboard to receive alerts and send commands.
3. **Telegram Bot (New!):** Don't want to install another app? You can link Mac Shield to a Telegram bot to get instant messages and control your Mac right from your chat list.

## How you can use it

You can toggle how aggressive you want Mac Shield to be using the settings in the Shadow app or via Telegram. 

*   **Real-Time OFF (Default):** *Privacy first.* After 3 failed passwords, you get a simple text alert on your phone. No photos or locations are taken yet. If the alert seems suspicious, tap **Capture photo** to grab evidence right then.
*   **Real-Time ON:** *Total security.* After the 3rd failed attempt, the agent instantly takes a photo and grabs the Mac's location, sending it all to your app and Telegram immediately.
*   **Manual Capture:** *Check in anytime.* Wondering who is at your desk? Hit the **Capture** button in the app or Telegram bot at any time to discreetly snap a photo and see what's happening.

> **Status:** Working prototype, tested on my own Mac. Not audited. See [Limitations](docs/ARCHITECTURE.md#limitations).

## How it works

```text
ShadowAgent (Swift, macOS)  ⇄  Firestore  ⇄  Shadow App (React Native)
                                          ⇄  Web Dashboard (React)
                                          ⇄  Telegram Bot
```

1. **ShadowAgent** monitors the macOS unified log for failed authentication events.
2. Upon 3 failures, it posts an alert to Firestore. If "Real-Time" is off, this is a text-only alert to respect privacy.
3. You get a push notification via the **Shadow App** or a message from the **Telegram Bot**.
4. From your phone, you can tap **Capture photo** or **Trigger alarm**.
5. The agent on your Mac picks up your command, executes it, and sends the photo/coordinates back to your screen.

## The Bathtub Incident (Why I built this)

This summer, while I was home for the holidays, my 7-year-old cousin tried to unlock my MacBook, probably to watch cartoons. He typed passwords again and again, failed, and eventually decided his next best option was to put the laptop in a bathtub full of water. The MacBook didn't survive.

I had no idea any of this was happening. Nothing warned me, and by the time I found out, it was too late. Mac Shield is exactly what I wished I had in that moment: a quick message on my phone saying *"someone is failing to unlock your laptop right now,"* so I could react while it still mattered.

What started as a revenge-driven fix for one bad summer turned into a deep dive into macOS internals, background services, code signing, and privacy design.

## Documentation

| Read this | If you want to |
|---|---|
| [User Guide](docs/USER_GUIDE.md) | Install, configure, and connect the App/Telegram bot |
| [Architecture](docs/ARCHITECTURE.md) | Understand the code, file by file |
| [Story](docs/STORY.md) | Read the full backstory of how and why it was built |
| [Why Mac Shield](docs/WHY_MACSHIELD.md) | See how it compares to existing security tools |
| [Research Roadmap](docs/RESEARCH_ROADMAP.md) | Follow the planned study of macOS internals and seL4 |

## Responsible Use

Mac Shield is strictly for a computer **you own and control**. It requires visible system permissions (Camera, Location, Full Disk Access) during setup. Do not install it on someone else's device, and do not use it to spy on other people.

## License

This project is licensed under the MIT License.
