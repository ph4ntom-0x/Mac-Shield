# Mac Shield

An open-source intrusion-alert system for macOS. When someone fails your lock-screen password
three times, Mac Shield alerts your phone and lets **you** decide whether to capture a photo and
location, instead of firing the camera on its own.

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

Last summer, while I was home for the holidays, my 7-year-old cousin tried to
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
