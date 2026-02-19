# AGENTS.project.md

# Chicane Project Guide for Agents

## Product intent
- Audience: two or more family/friend viewers tracking F1 and MotoGP weekend podium bets.
- Problem solved: fast, spoiler-safe pick entry and season-long scoring without accounts or cloud setup.
- Success criteria: simple flow for older users (large controls, clear labels), deterministic scoring, reliable offline persistence.

## Current product phase (MVP implemented)
1) MVP scope: Home, Picks, Results, Scoreboard, Spoilers, Settings.
2) Architecture boundaries: SwiftUI views + single app-level `AppViewModel`, repository layer, scoring services.
3) Reliability/UX goals: no default spoilers, locked results protection, atomic file writes, online data with bundled fallback.
4) Testing priorities: scoring rule correctness and standings aggregation.

## Architecture snapshot (current)
- App entry/navigation:
  - `ChicaneApp` injects `AppViewModel`.
  - `RootTabView` hosts tabs for Home, Picks, Results, Scoreboard, optional Spoilers tab, Settings.
- Core view models/services:
  - `AppViewModel` (main-actor UI state orchestration)
  - `ScoringService` and `ScoreboardCalculator` (pure logic)
  - `LocalSeasonRepository` + `FileStateStore` (actor-based persistence)
  - `OnlineDriverRepository` / `OnlineCalendarRepository` (official source fetchers)
  - `FallbackDriverRepository` / `FallbackCalendarRepository` (automatic offline fallback)
  - `BundledDriverRepository` / `BundledCalendarRepository` (seed JSON loaders)
- Data flow/persistence:
  - Online refresh for calendars/drivers from official sources when reachable.
  - Seed data from bundled JSON in `Chicane/Resources/Seed` when online fetch fails.
  - User state persisted to application-support JSON file with atomic writes.

## Concurrency rules (important)
- Keep SwiftUI/view model state on `@MainActor`.
- Keep disk IO and repository mutations off main actor via actors.
- Default actor isolation is configured to `nonisolated`; do not rely on broad global actor defaults.

## Behavior invariants (do not regress)
- No spoilers shown unless user explicitly enters results or confirms spoiler gate.
- Podium picks/results must contain 3 unique participants (drivers for F1, riders for MotoGP).
- Scoring is position-exact only (P1/P2/P3 exact matches only, 0-3 points per event).
- Locked results must not be editable until explicit unlock confirmation.
- Season reset clears picks/results but preserves players/settings.

## UX rules
- Large controls and readable typography by default.
- Keep interactions short and explicit with clear confirmation/error copy.
- Spoilers tab hidden by default; warning gate must appear when enabled and configured.

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
