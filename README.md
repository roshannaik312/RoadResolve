# Clear Roads

Clear Roads is a Flutter iOS app for reporting road hazards by voice while driving. It covers animal carcasses, fallen trees, and snow or ice, plus potholes, debris and "other". Reports are saved as **drafts** while you drive, and you can only **submit** them once the app detects you've stopped.

> Competition prototype. Triage, jurisdiction routing and crew recommendations are deterministic simulations, and reports stay on the device.

## What it does

| Flow | How |
|---|---|
| **Voice report** | You tap the mic and answer three short questions out loud: *What did you see? Is it blocking the road? Anything else?* You can say it all at once, e.g. "dead deer in the right lane", and the app skips the questions it already has answers to. |
| **Siri Shortcut** | "Hey Siri, report a fallen tree in Clear Roads". If you don't name the hazard, Siri asks for it. The app then opens, records GPS straight away, saves a draft, and offers optional follow-up questions. |
| **Driving mode** | When the app detects driving, the home screen switches to a dark, minimal layout. It has one large "Tap & speak" button and one-tap draft buttons for the three main hazards. |
| **Submit gate** | Submitting, editing and adding photos are locked while you drive. They unlock once the car has been still for 45 s, or straight away when you start walking, so a red light doesn't unlock them. |
| **Smart triage** | The app gives each report a priority score from 0 to 100 and explains every point. It also picks the jurisdiction (State DOT, County or Town, based on the road name), a recommended crew, equipment and a response target, and flags likely duplicates within 200 m. |
| **Dashboard** | Community map (OpenStreetMap), My Reports (Drafts / Submitted), a status timeline, and a "Simulate agency update" button that steps a report through Submitted → Under review → Acknowledged → Crew on the way → Resolved for demos. |

Hero demo: a dead deer partly in a lane on NY-50 scores **High** priority, is routed to **State DOT**, and gets a **carcass-removal crew with traffic cones and an arrow board**.

## Architecture

```
lib/
  models/           HazardType, Blockage, Report, ReportStatus
  services/
    voice_parser.dart        speech → hazard / blockage (on-device keyword NLP)
    voice_service.dart       speech_to_text + flutter_tts (Bluetooth/CarPlay audio)
    voice_report_flow.dart   the hands-free conversation state machine
    driving_detector.dart    pure GPS + CoreMotion fusion with hysteresis (unit-tested)
    driving_monitor.dart     live sensors → DrivingState, demo override
    triage_engine.dart       priority score, jurisdiction, crew, duplicates
    siri_bridge.dart         receives Siri requests from native code
    report_store.dart        local-first persistence (shared_preferences)
  screens/          home (stopped + driving mode), voice report, map, my reports, detail, settings
ios/Runner/
  HazardIntents.swift      App Intents + AppShortcutsProvider (Siri phrases)
  ClearRoadsNative.swift   CoreMotion activity stream + Siri request queue → Flutter channels
```

How Siri reaches Flutter: the App Intent runs `perform()` in the app process and adds the request to a queue in `UserDefaults`. Flutter empties that queue on launch and on resume, and native code also notifies Flutter when a request arrives while the app is already running. This works on a cold launch too.

## Running

Requires Xcode 15+, iOS 16+ and Flutter 3.38+.

```bash
flutter pub get
open ios/Runner.xcworkspace   # set your Signing Team on the Runner target
flutter run                    # on a real iPhone
```

- Siri phrases register automatically when the app is installed; you don't need to set anything up. You can also find them in the Shortcuts app under **Clear Roads**.
- Motion activity and Siri need a **physical device**. On the simulator the app falls back to GPS speed only, and you can simulate a drive with *Features → Location → Freeway Drive*.
- For demos without a car, go to **Settings → Driving detection → Demo override** and choose *Driving* or *Stopped*.

```bash
flutter analyze
flutter test      # parser, triage rules, driving-detector hysteresis, JSON
```

## Phase 2 (out of scope for the prototype)

Backend (e.g. Supabase) and a multi-user dashboard, photo-based AI classification, real road-ownership data, DOT and work-order integrations, a CarPlay app, Android Auto, push status updates.
