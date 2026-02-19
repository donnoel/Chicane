# Chicane
### A premium iOS/iPadOS podium-picks app for friendly Formula 1 and MotoGP weekend betting.

<p align="center">
  <img src="https://img.shields.io/badge/SwiftUI-MVVM-orange?logo=swift" alt="SwiftUI MVVM">
  <img src="https://img.shields.io/badge/Platform-iOS%20%2B%20iPadOS-blue" alt="iOS and iPadOS">
  <img src="https://img.shields.io/badge/Persistence-Local%20JSON-lightgrey" alt="Local JSON">
  <img src="https://img.shields.io/badge/Spoilers-Hidden%20by%20default-critical" alt="Spoilers hidden by default">
</p>

---

## What is Chicane?

Chicane is a SwiftUI app for simple, weekend podium-pick betting between family and friends.

For each race event, each player picks:
- P1
- P2
- P3

When actual results are entered, scoring is position-exact:
- +1 for correct P1
- +1 for correct P2
- +1 for correct P3
- Total: 0 to 3 points per event

Chicane tracks standings across:
- Formula 1 season totals
- MotoGP season totals
- Combined totals

---

## Core Features

| Feature | Description |
|--------|-------------|
| Podium Picks | Create/edit picks per series, round, and player. |
| Results Update + Locking | Tap `Update Results` to fetch official top-3 podium, then lock to prevent accidental edits. |
| Exact Scoring | Position-only scoring (no points for correct rider/driver in wrong position). |
| Scoreboard | Series and combined standings, plus per-event history. |
| Spoiler Safety | No race spoilers by default; Spoilers section is optional and gated. |
| Offline Fallback | Works with bundled seed data if network sources are unavailable. |
| Accessibility | Large tap targets, Dynamic Type, VoiceOver labels, high-contrast friendly UI. |
| Premium UI | Apple-material based "Liquid Glass" visual design with themed motorsport color accents. |

---

## Main Screens

- Home
- Picks
- Results
- Scoreboard
- Spoilers (optional)
- Settings

---

## How it works

1. App launches and loads local season state.
2. Driver/rider lists and calendars refresh from online sources when available.
3. If network fetch fails, bundled seed JSON is used automatically.
4. Users enter picks for each event.
5. Users tap `Update Results` to pull official podium results and lock the event.
6. Standings are computed deterministically from stored picks/results.

---

## Architecture Overview

Chicane follows SwiftUI + MVVM with focused repositories/services.

### App Layer
- `ChicaneApp` injects `AppViewModel`.
- `RootTabView` manages tab navigation.

### View Model
- `AppViewModel` orchestrates UI state, load/save operations, and screen-level interactions.

### Repositories
- `OnlineDriverRepository` (Formula 1 drivers + MotoGP riders)
- `OnlineCalendarRepository` (Formula 1 + MotoGP event calendars)
- `FallbackDriverRepository`
- `FallbackCalendarRepository`
- `LocalSeasonRepository` for local picks/results/settings persistence

### Services
- `ScoringService` for event scoring
- `ScoreboardCalculator` for standings aggregation
- `FileStateStore` actor for atomic local file writes

---

## Data Sources

Online-first with offline fallback:

- Formula 1 official site (`formula1.com`) for current Formula 1 drivers and calendar page parsing.
- MotoGP official ecosystem (`motogp.com` / Pulse Live API used by MotoGP) for current MotoGP riders and calendar events.
- Bundled seed data at:
  - `Chicane/Resources/Seed/drivers.json`
  - `Chicane/Resources/Seed/calendar.json`

---

## Project Structure

```text
Chicane/
├── Chicane/
│   ├── App/
│   ├── Data/
│   ├── Domain/
│   ├── Features/
│   ├── Shared/
│   └── Resources/
│       └── Seed/
├── ChicaneTests/
└── ChicaneUITests/
```

---

## Build and Run

### Requirements
- macOS with Xcode 16+
- iOS Simulator runtime (26.2 used in CI/local commands below)

### Xcode
1. Open `Chicane.xcodeproj`
2. Select scheme `Chicane`
3. Run on iPhone or iPad simulator

### CLI
```bash
xcodebuild -scheme Chicane -project Chicane.xcodeproj -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme Chicane -project Chicane.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:ChicaneTests test
```

---

## Persistence and Privacy

- No account required.
- Picks, results, players, and settings are stored on device.
- Local state is written atomically for reliability.
- Spoilers are hidden by default and only shown after explicit opt-in confirmation.

---

## Notes

- MotoGP participants are labeled as Riders throughout the app.
- Season reset clears picks/results while preserving players/settings behavior as implemented.

---

Built by Don Noel with AI collaboration.
