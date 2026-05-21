# WakeHard

A reliable, opinionated alarm app for iOS that goes off when it's supposed to — even when iOS would rather it didn't.

WakeHard pairs Apple's modern **AlarmKit** system‑backed alarms (iOS 26+) with a hand‑rolled background audio engine, local notifications, Live Activities, and Dynamic Island support, so an alarm rings on time whether the app is foregrounded, backgrounded, or terminated.

---

## Features

**Alarms**

- Repeating alarms with any combination of weekdays (with "Every day", "Weekdays", "Weekends", and "Once" presets)
- Quick (one‑off) alarms that auto‑clean up after firing
- Skip‑once: silence the next occurrence of a repeating alarm without disabling it
- Per‑alarm label, time, sound, volume, vibration, snooze, and wake challenge

**Sound**

- Three built‑in alarm tones: **Pulse**, **Bell**, and **Rise**
- Pick any song from your local Apple Music library as the alarm sound (`MPMusicPlayerController`)
- Choose a clip start time and loop duration so a song can be used as a continuous alarm loop
- **Gentle Wake**: optional volume ramp (15s / 30s / 60s / 5min / 10min) that rises to your selected volume
- A silent keep‑alive audio loop keeps the audio session warm in the background so the alarm can actually play when it fires

**Vibration**

- Seven patterns: Alert, Heartbeat, Quick, Rapid, S.O.S., Staccato, and Symphony
- Per‑alarm strength control

**Snooze**

- Optional snooze with intervals from 1 to 60 minutes
- Limited (configurable count) or unlimited snoozes
- Pending snoozes survive app termination and re‑ring on time

**Wake Challenges**

- **Hold to dismiss** — a press‑and‑hold gesture to stop the alarm
- **Tap pattern** — a focused tap sequence to confirm you're actually awake

**System integration**

- **AlarmKit** (iOS 26+) for true system‑backed alarms that ring even if the app isn't running
- **Live Activities** for next alarm, skipped‑once, ringing, and snoozed states (toggleable in Settings)
- **Dynamic Island** support via the bundled Live Activity widget extension
- **Critical alert** local notifications as a backstop so the screen wakes and the alarm UI is presented
- Custom URL scheme `wakehard://` for deep links
- A "keep the app open" warning notification scheduled on app termination if an alarm is upcoming

---

## Architecture

WakeHard is a SwiftUI app organized around a few cooperating layers, each responsible for one piece of the "make sure the alarm rings" problem:

- **`Alarm.swift`** — the `Alarm` model plus enums for `Weekday`, `AlarmSound`, `WakeChallenge`, `GentleWakeDuration`, `VibrationPattern`, `SnoozeInterval`, and `SnoozeCount`. Handles next‑fire‑date computation including weekday repeats and skip‑once.
- **`AlarmStore.swift`** — persists the alarm list to `UserDefaults` (`wakehard.alarms.v1`).
- **`AlarmKitScheduler.swift`** — schedules alarms through `AlarmManager` on iOS 26+ and gracefully no‑ops on older OSes.
- **`NotificationScheduler.swift`** — schedules local `UNCalendarNotificationTrigger` notifications as a reliability backstop, with `ALARM` and `KEEP_OPEN` notification categories.
- **`BackgroundAlarmEngine.swift`** — the audio brain. Arms a silent keep‑alive audio loop, monitors the next fire date with a dispatch timer, and plays the alarm (built‑in `AVAudioPlayer` clip or library song via `MPMusicPlayerController`) when it fires. Handles audio‑session interruptions, ramp‑up volume, and clip looping.
- **`AlarmKitScheduler` + `BackgroundAlarmEngine` + `NotificationScheduler`** are layered intentionally — whichever path the OS allows on a given device/build, the alarm rings.
- **`WakeHardLiveActivityManager.swift`** + **`WakeHardLiveActivityAttributes.swift`** + the **`WakeHardLiveActivityExtension`** target — drive Live Activities and the Dynamic Island for `nextAlarm`, `skippedOnce`, `ringing`, and `snoozed` states.
- **`AppDelegate.swift`** — `UNUserNotificationCenterDelegate` that wakes the screen and surfaces the ringing UI when an alarm notification is presented.
- **`SoundManager.swift` / `VibrationManager.swift`** — playback and haptics.
- **`ContentView.swift` / `AlarmEditorView.swift` / `SnoozeEditorView.swift` / `MusicPickerView.swift`** — SwiftUI surface.
- **`AppTheme.swift`** — shared color and typography tokens.

Persistence uses `UserDefaults` with versioned keys (e.g. `wakehard.alarms.v1`, `wakehard.alarmKit.scheduledIDs.v1`).

---

## Requirements

- iOS **17.0** or later (deployment target)
- iOS **26.0** or later required for system‑backed AlarmKit alarms (older versions still get the local‑notification + background‑audio path)
- Xcode 16 or later
- Swift 5.0
- iPhone (`TARGETED_DEVICE_FAMILY = 1`)

---

## Project Layout

```
WakeHard/
├── WakeHard.xcodeproj/
├── WakeHard/                          # Main app target
│   ├── WakeHardApp.swift              # App entry point
│   ├── AppDelegate.swift              # Notification + screen-wake handling
│   ├── ContentView.swift              # Main alarms list
│   ├── AlarmEditorView.swift          # Create/edit alarm
│   ├── SnoozeEditorView.swift
│   ├── MusicPickerView.swift          # Pick a song from the library
│   ├── Alarm.swift                    # Model + enums
│   ├── AlarmStore.swift               # UserDefaults persistence
│   ├── AlarmRuntimeStore.swift        # Active snooze state
│   ├── AlarmKitScheduler.swift        # iOS 26+ system alarms
│   ├── NotificationScheduler.swift    # Local notification fallback
│   ├── BackgroundAlarmEngine.swift    # Background audio engine
│   ├── SoundManager.swift             # Audio playback
│   ├── VibrationManager.swift         # Haptic patterns
│   ├── AlarmNowPlayingInfo.swift      # Lock-screen now-playing
│   ├── WakeHardLiveActivityManager.swift
│   ├── WakeHardLiveActivityAttributes.swift
│   ├── AppTheme.swift
│   ├── Info.plist
│   ├── Assets.xcassets/
│   └── Sounds/                        # pulse.wav, bell.wav, rise.wav,
│                                      # silence.wav, keepalive.wav
└── WakeHardLiveActivityExtension/     # Widget extension (Live Activity / Dynamic Island)
    ├── WakeHardLiveActivityWidget.swift
    └── Info.plist
```

---

## Permissions & Capabilities

WakeHard requests the following at runtime / declares them in `Info.plist`:

- **Notifications** — including `criticalAlert` so the alarm UI can wake the screen and present full‑screen even in Do Not Disturb / Focus
- **AlarmKit** — `NSAlarmKitUsageDescription` ("WakeHard schedules system‑backed alarms so your alarms can still ring reliably if the app is not running.")
- **Apple Music / Media Library** — `NSAppleMusicUsageDescription` ("WakeHard can use locally available songs you choose as alarm audio while the app is armed.")
- **Background Modes** — `audio` and `bluetooth-central` (for the silent keep‑alive loop and BT audio routing)
- **Live Activities** — `NSSupportsLiveActivities` is `YES`

URL scheme: `wakehard://` (bundle URL name `com.javierrivera.wakehard`).

---

## Building & Running

1. Clone the repo:
   ```bash
   git clone https://github.com/javuls/WakeHard.git
   cd WakeHard
   ```
2. Open `WakeHard.xcodeproj` in Xcode 16+.
3. Select the **WakeHard** scheme and an iPhone destination (a real device is recommended — many of the background‑audio and AlarmKit behaviors don't fully exercise in the Simulator).
4. Build and run. On first launch, grant Notifications, AlarmKit (iOS 26+), and (optionally) Apple Music access when prompted.

The Live Activity widget is part of the **WakeHardLiveActivityExtension** target and ships in the same app bundle — no extra steps required.

### Signing

The project uses bundle identifiers `com.javierrivera.wakehard` (app) and `com.javierrivera.wakehard.liveactivity` (widget extension). If you're building under your own account, update both to your team's identifiers in Xcode → Signing & Capabilities.

---

## Design Notes

- **Why three scheduling paths?** iOS aggressively suspends apps, and a single approach (notifications, background audio, or AlarmKit) is never enough on its own. WakeHard runs all three in parallel and lets whichever fires first dismiss the others. This is the whole point of the project.
- **The silent keep‑alive loop** (`Sounds/silence.wav`, `keepalive.wav`) is what keeps the audio session active in the background so a custom song or built‑in tone can actually start playing at fire time. It's gated by `isArmed` so it's not running when there's nothing scheduled.
- **AlarmKit is preferred** on iOS 26+ because it survives termination and respects system alarm UI conventions, but WakeHard still arms the background engine and schedules notifications as a belt‑and‑suspenders backup.

---

## Roadmap / Ideas

- Apple Watch companion
- Sleep‑schedule analytics
- Math/QR/photo wake challenges
- iCloud sync of alarms across devices

---

## License

No license file is currently included. All rights reserved by the author until a license is added.

---

## Author

Made by **Javier Rivera** ([@javuls](https://github.com/javuls)).
