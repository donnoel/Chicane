# AGENTS.project.md

# Chicane Project Guide for Agents

## Product intent
- Audience: two or more family/friend viewers tracking F1 and MotoGP weekend podium bets plus season champion predictions.
- Problem solved: fast, spoiler-safe pick entry and season-long scoring with optional iCloud league sync.
- Success criteria: simple flow for older users (large controls, clear labels), deterministic scoring, reliable offline persistence, and low-friction shared-state sync.

## Current product phase (MVP implemented)
1) MVP scope: Home, Picks, Results, Scoreboard, News, Settings.
2) Architecture boundaries: SwiftUI views + single app-level `AppViewModel`, repository layer, scoring services.
3) Reliability/UX goals: no default spoilers, locked results protection, locked season champion protection, atomic file writes, online data with bundled fallback.
4) Testing priorities: scoring rule correctness and standings aggregation.

## Architecture snapshot (current)
- App entry/navigation:
  - `ChicaneApp` injects `AppViewModel`.
  - `RootTabView` hosts tabs for Home, Picks, Results, Scoreboard, News, Settings.
- Core view models/services:
  - `AppViewModel` (main-actor UI state orchestration)
  - `ScoringService` and `ScoreboardCalculator` (pure logic)
  - `LocalSeasonRepository` + `FileStateStore` (actor-based persistence)
  - `CloudSyncSeasonRepository` + `PublicCloudLeagueStore` (optional iCloud-backed shared league sync)
  - `OnlineDriverRepository` / `OnlineCalendarRepository` (official source fetchers)
  - `FallbackDriverRepository` / `FallbackCalendarRepository` (automatic offline fallback)
  - `BundledDriverRepository` / `BundledCalendarRepository` (seed JSON loaders)
- Data flow/persistence:
  - Local state remains the offline source on disk and is saved atomically first.
  - If a shared league code is configured, the full season state is mirrored through CloudKit and refreshed on launch / foreground, plus periodic automatic pulls while the app is active. If that mirror step fails after a local save, the local save still stands and the UI must show a visible sync warning.
  - CloudKit operational guardrail: for multi-account shared leagues, `LeagueState` public-database permissions must allow authenticated create/read/write in both Development and Production environments for container `iCloud.dn.chicane`.
  - Joining a shared league should require explicit confirmation before replacing non-empty on-device season state.
  - Leaving a shared league should clear only the local league link so the same device can create or join a different league without wiping local season data.
  - Shared league merges keep per-pick/per-result timestamps authoritative, merge players by `playerID` across devices (using section/overall timestamps to break same-player conflicts), and resolve settings from the newest section timestamp while union-merging per-player bet text keys.
  - For explicit local saves (pick/result/champion/settings/player/reset), that just-edited local key/section should win same-key conflicts during the push merge so iPhone/iPad edits by the same player are deterministic even with stale caches or clock skew.
  - CloudKit transient failures and `serverRecordChanged` conflicts should retry before surfacing an error, and surfaced sync warnings should include actionable error-code detail.
  - Explicit `refreshState()` calls must bypass the warm local cache so restored or externally modified state can be reloaded from disk before sync.
  - In-memory reloads should preserve stable event/participant identities across bundled/online source switches so existing picks/champion selections stay attached.
  - Online refresh for calendars/drivers from official sources when reachable.
  - Official championship leaders (F1 + MotoGP top 3) refresh from official sources on app reload and after each successful "Fetch Results".
  - Seed data from bundled JSON in `Chicane/Resources/Seed` when online fetch fails.
  - User state persisted to application-support JSON file with atomic writes.

## Concurrency rules (important)
- Keep SwiftUI/view model state on `@MainActor`.
- Keep disk IO and repository mutations off main actor via actors.
- Default actor isolation is configured to `nonisolated`; do not rely on broad global actor defaults.

## Behavior invariants (do not regress)
- No spoilers shown unless user explicitly enters results or confirms the News entry gate.
- Podium picks/results must contain 3 unique participants (drivers for F1, riders for MotoGP).
- Scoring is position-exact only (P1/P2/P3 exact matches only, 0-3 points per event).
- Locked official results must not be editable once retrieved.
- Locked season champions must not be editable once entered, and player champion picks must freeze for that series at the same moment.
- Season reset clears picks/results but preserves players/settings.

## UX rules
- Large controls and readable typography by default.
- Keep interactions short and explicit with clear confirmation/error copy.
- News tab is always available; warning gate must appear on entry before articles are shown.

## Coding conventions
- Prefer small, focused types in `Domain`, `Data`, `Features`, `Shared`.
- Avoid third-party dependencies.
- Use deterministic services for business logic and unit testing.

## Build/run notes
- Platforms: iPhone + iPad only (`TARGETED_DEVICE_FAMILY = 1,2`).
- Warning policy: zero warnings for app build.
- Build command:
  - `xcodebuild -scheme Chicane -project Chicane.xcodeproj -destination 'generic/platform=iOS Simulator' build`
- Unit tests:
  - `xcodebuild -scheme Chicane -project Chicane.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:ChicaneTests test`

## Near-term priorities
- Add focused UI tests for picks/results lock flow.
- Add lightweight repository tests for online payload/HTML parsing edge cases.
- Expand calendar/driver seed update documentation.

## Output expectations per patch
Provide:
- Summary of change
- Files modified
- Any migration considerations
- Commit message suggestion
