# Chicane
### A premium iOS/iPadOS podium-picks app for friendly Formula 1 and MotoGP weekend betting.

<p align="center">
  <img src="https://img.shields.io/badge/SwiftUI-MVVM-orange?logo=swift" alt="SwiftUI MVVM">
  <img src="https://img.shields.io/badge/Platform-iOS%20%2B%20iPadOS-blue" alt="iOS and iPadOS">
  <img src="https://img.shields.io/badge/Persistence-Local%20JSON%20%2B%20iCloud-lightgrey" alt="Local JSON and iCloud">
</p>

---

## What is Chicane?

Chicane is a SwiftUI app for simple, weekend podium-pick betting between family and friends.

For each race event, each player picks:
- P1
- P2
- P3

Each player also picks a season world champion for:
- Formula 1
- MotoGP

When actual results are entered, scoring is position-exact:
- +1 for correct P1
- +1 for correct P2
- +1 for correct P3
- Total: 0 to 3 points per event
- +5 bonus when a saved season world champion pick matches the locked season champion

Chicane tracks standings across:
- Formula 1 season totals
- MotoGP season totals
- Combined totals

---

## Core Features

| Feature | Description |
|--------|-------------|
| Podium Picks | Create/edit picks per series, round, and player. Supports multiple concurrent players with independent drafts. |
| Season Champion Picks | Each player can pick the F1 and MotoGP world champion for an end-of-season 5-point bonus, and those picks lock once the official season champion is entered. |
| Results Update + Locking | Tap `Update Results` to fetch official top-3 podium, then lock to prevent accidental edits. |
| Season Champion Locking | Once the season champion is entered for a series, it locks and immediately applies the bonus to standings. |
| Exact Scoring | Position-only scoring (no points for correct driver/rider in wrong position). |
| Scoreboard | Series and combined standings, plus per-event score history. |
| Track-Local Time | Hero cards show each circuit's current local clock time with a day cue (`Yesterday`, `Today`, `Tomorrow`). |
| Bet Ledger | Home shows each player's current bet in a premium card. |
| Shared League Sync | Create one league code and use it on each phone to sync picks, results, and player names through iCloud. Joining prompts before replacing existing local season data. |
| Offline Fallback | Works with bundled seed data if network sources are unavailable. |
| Accessibility | Large tap targets, Dynamic Type, VoiceOver labels, and contrast-safe light/dark mode surfaces. |
| Premium UI | Apple-material based "Liquid Glass" visual design with themed motorsport color accents. |

---

## Main Screens

- **Home** — Next race countdown, race-track local time with relative day context, season standings snapshot, and player bet ledger
  - Formula 1 countdown uses the official race-session start time from the event page when available, not a date-only noon placeholder.
  - MotoGP countdown uses the official MotoGP race (`RAC`) session start time when available, not the GP weekend end timestamp.
- **Picks** — Enter each player's season champion and P1/P2/P3 predictions
- **Results** — Enter official results and lock events, plus lock the season champion
- **Scoreboard** — Season standings and per-event history (F1, MotoGP, Combined)
- **Settings** — Manage players, shared league sync, per-player bets, and season reset
  - Player names cannot be blank when saving; use `Remove` to delete a player.
  - Shows the installed app version/build in an `About` section.
  - Reset clears race picks/results and season champion picks/results.

---

## How it works

1. App launches and loads local season state.
2. If a shared league code is configured, it syncs the latest shared state from iCloud.
3. Driver/rider lists and calendars refresh from online sources when available.
4. If network fetch fails, bundled seed JSON is used automatically.
5. Users enter season champion picks and race picks for each player.
6. Local changes save immediately, then sync back to the shared iCloud league in the background.
7. While the app is active in a shared league, it automatically re-syncs periodically so updates from other phones appear without opening Settings.
8. If shared sync fails, the app keeps the local save and shows a visible warning.
9. Users tap `Update Results` to pull official podium results and lock the event.
10. When the season champion is entered for a series, it locks, freezes all player champion picks for that series, and awards the 5-point bonus to matching players.
11. Standings are computed deterministically from stored picks and results.

---

## Architecture Overview

Chicane follows SwiftUI + MVVM with focused repositories and services.

### App Layer
- `ChicaneApp` — entry point; injects all repositories into `AppViewModel`.
- `RootTabView` — tab navigation with banner and loading overlays.

### View Model
- `AppViewModel` — single source of truth; orchestrates UI state, load/save operations, scoring, and screen-level interactions.

### Repositories
- `OnlineDriverRepository` — fetches current F1 drivers and MotoGP riders from official sources
- `OnlineCalendarRepository` — fetches F1 and MotoGP event calendars
- `OnlineResultRepository` — fetches official top-3 podium results
- `FallbackDriverRepository` / `FallbackCalendarRepository` — online-first with bundled seed fallback
- `LocalSeasonRepository` — actor-isolated persistence for picks, results, players, and settings
- `CloudSyncSeasonRepository` — local-first repository wrapper that syncs shared league state through CloudKit

### Services
- `ScoringService` — per-event points calculation
- `ScoreboardCalculator` — season standings and event history aggregation
- `FileStateStore` — actor-based atomic JSON file I/O
- `PublicCloudLeagueStore` — CloudKit public-database store for shared league state
- `F1OfficialHTMLParser` — parses formula1.com for drivers, calendar, and results
- `RemoteDataClient` — shared URLSession HTTP client with encoding fallback
- `BundleJSONLoader` — loads bundled seed JSON resources

---

## Data Sources

Online-first with offline fallback:

- **Formula 1** — `formula1.com` for drivers, calendar, and official podium results
- **MotoGP** — `motogp.com` / Pulse Live API for riders and calendar events
- **Bundled seed data** (fallback):
  - `Chicane/Resources/Seed/drivers.json`
  - `Chicane/Resources/Seed/calendar.json`

---

## Project Structure

```text
Chicane/
├── Chicane/
│   ├── App/                     # Entry point, AppViewModel, RootTabView
│   ├── Domain/                  # Core models (Driver, RaceEvent, RacePick, RaceResult, etc.)
│   ├── Data/
│   │   ├── Persistence/         # LocalSeasonRepository, FileStateStore
│   │   ├── Repositories/        # Driver, Calendar, Result repositories + protocols
│   │   └── Services/            # Scoring, parsing, HTTP client
│   ├── Features/
│   │   ├── Home/
│   │   ├── Picks/
│   │   ├── Results/
│   │   ├── Scoreboard/
│   │   └── Settings/
│   ├── Shared/                  # Reusable views and components
│   └── Resources/
│       └── Seed/                # Bundled fallback JSON
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

- Local use still works without a shared league code.
- All picks, results, season champion choices, players, and settings are stored on-device first.
  - Location: `~/Library/Application Support/Chicane/season_state_v1.json`
- When a shared league code is enabled, the same season state is mirrored to iCloud CloudKit so other phones can pull it automatically.
- CloudKit setup requirement for cross-account leagues: in the `iCloud.dn.chicane` container, `LeagueState` in the public database must allow authenticated users to create/read/write in both Development and Production schemas.
- Shared league state is auto-polled while the app is active, so manual `Sync Now` is optional.
- Shared sync merges picks/results by item timestamp, unions players by `playerID` across devices (breaking same-player conflicts by newest section/overall timestamp), and resolves settings from the newest section change while union-merging per-player bet text keys.
- During explicit local saves, the just-edited local key/section is preferred on same-key conflicts so iPhone/iPad updates for one player converge predictably.
- Cloud sync retries transient CloudKit failures and write conflicts before surfacing an error, and warnings now include CloudKit error-code detail for troubleshooting.
- Explicit refreshes bypass the in-memory cache and reload the latest on-disk state before syncing.
- State is written atomically for crash-safety.
- Schema versioning is in place for future migrations.
- Legacy stored driver/rider IDs are normalized against current rosters so older saved picks continue to score after feed ID changes.

---

## Notes

- MotoGP participants are labeled as Riders throughout the app.
- Season reset clears picks, results, and season champion choices while preserving players and settings.

---

Built by Don Noel with AI collaboration.
