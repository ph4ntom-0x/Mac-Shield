# Mac Shield

Mac Shield tells you when someone is trying to break into your MacBook.

If someone types the wrong password 3 times on your lock screen, Mac Shield
sends an alert to the **Shadow app** on your phone. You can also have it take a
photo of that person and note the location of your Mac.

## What's inside

This project has two parts:

1. **Shadow Agent** runs on your MacBook in the background. It watches the
   system logs and notices when the wrong password is typed 3 times in a row.
2. **Shadow App** is the app on your phone. It shows you the alerts and lets
   you control the agent.

## Two ways to use it

You choose with the **Real-Time** button in the Shadow app.

- **Real-Time ON:** after the 3rd wrong password, the agent instantly takes a
  photo and records the location. You get the picture and the location in the
  app right away.
- **Real-Time OFF (default):** you only get an alert in the app. No photo is
  taken and no location is sent. If the alert looks real, you tap
 **Capture photo** and the agent takes the photo and location then.
-**Capture :** you can capture anytime using that capture button manually

> **Status:** working prototype, tested on  my  own Mac. Not audited. See
> [Limitations](docs/ARCHITECTURE.md#limitations).

## How it works

```
ShadowAgent (Swift, runs in background)  ⇄  Firestore  ⇄  Shadow phone app (React Native)
                                                 ⇅
                                          Web dashboard (React)
```

1. **ShadowAgent** watches macOS's unified log for failed authentication events.
2. After 3 failures it posts a **text-only alert** (no photo, no location) , if real time off from mobile app.
3. Your phone shows the alert along with capture at that instant (if real time on).
4. You can directly tap capture to take capture of any instant and can see who using my mac , tap **Capture photo** or **Trigger alarm**.
5. The agent picks up the command and only then captures a photo and coordinates.
6. Optional **Real-Time Mode** captures immediately on the third failure, with no tap.


## Why I built this

This  summer, while I was home for the holidays, my 7-year-old cousin tried to
unlock my MacBook, probably to watch cartoons. He typed passwords again and
again, failed, and eventually decided the next step was to put the laptop in a
bathtub full of water. The MacBook didn't survive.

I had no idea any of it was happening. Nothing told me someone was trying to get
into my Mac, and by the time I found out it was too late. Mac Shield is what I
wanted at that moment: a message on my phone saying *someone is failing to unlock
your laptop right now*, so I could react while it still mattered.

It started as a one-time fix for one bad summer. It turned into a project about
macOS internals, background services, code signing and privacy design.

## Documentation


| Read this | If you want to |
|---|---|
| [User Guide](docs/USER_GUIDE.md) | Install, configure and use Mac Shield |
| [Architecture](docs/ARCHITECTURE.md) | Understand the code, file by file |
| [Story](docs/STORY.md) | Read how and why it was built, and the problems solved |
| [Why Mac Shield](docs/WHY_MACSHIELD.md) | See how it compares with existing tools |
| [Research Roadmap](docs/RESEARCH_ROADMAP.md) | Follow the planned study of macOS internals and seL4 |

## Responsible use

Mac Shield is for a computer **you own and control**. It asks for visible system permissions
(Camera, Location, Full Disk Access) during setup. Do not install it on someone else's device or
use it to watch another person.

## License

This project is licensed under the MIT License.
