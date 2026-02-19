# Chicane

Chicane is an iOS/iPadOS SwiftUI app for friendly weekend podium-pick betting across Formula 1 and MotoGP.

## Build and run
- Open `/Users/donnoel/Development/Chicane/Chicane.xcodeproj` in Xcode 16+
- Select scheme `Chicane`
- Run on an iPhone or iPad simulator

### CLI build/test (used for this patch)
```bash
xcodebuild -scheme Chicane -project Chicane.xcodeproj -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme Chicane -project Chicane.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:ChicaneTests test
```

## MVP scope implemented
- Home with next-race card and standings summary
- Picks flow for F1/MotoGP by event and player
- Results entry with lock/unlock protection
- Scoreboard totals (F1, MotoGP, Combined) + event history
- Spoilers tab hidden by default and gated by confirmation
- Settings for players, season reset, spoiler behavior, and season bet text

## Architecture
SwiftUI + MVVM with online-first repositories and offline fallback:
- `AppViewModel` orchestrates app state for all screens
- `OnlineDriverRepository` and `OnlineCalendarRepository` fetch current data from:
  - `https://www.formula1.com` (drivers + season calendar page parsing)
  - `https://api.pulselive.motogp.com/motogp/v1` (riders + events API used by motogp.com)
- `FallbackDriverRepository` and `FallbackCalendarRepository` automatically fall back to bundled JSON when online fetch fails
- `SeasonRepository` (`LocalSeasonRepository`) persists picks/results/settings
- `ScoringService` and `ScoreboardCalculator` provide deterministic scoring logic

## Bundled JSON seed data
- Drivers: `/Users/donnoel/Development/Chicane/Chicane/Resources/Seed/drivers.json`
- Calendar placeholder: `/Users/donnoel/Development/Chicane/Chicane/Resources/Seed/calendar.json`

To update drivers/calendar for a new season, edit those files and rebuild.

## Persistence
State is stored locally on-device as JSON via atomic file writes:
- App support file: `.../Application Support/Chicane/season_state_v1.json`
- Stored entities: players, picks, results, and settings

## Privacy
- No account
- Picks, results, players, and settings stay on device
- Calendar/driver reference data is fetched from official Formula 1 and MotoGP sources when online
- If online fetch is unavailable, the app uses bundled offline seed data
