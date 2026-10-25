# AGENTS.project.md

# Chicane Project Guide for Agents

## Product intent
- Audience: two or more family/friend viewers tracking F1 and MotoGP weekend podium bets plus season champion predictions.
- Problem solved: fast, spoiler-safe pick entry and season-long scoring with optional iCloud league sync.
- Success criteria: simple flow for older users (large controls, clear labels), deterministic scoring, reliable offline persistence, and low-friction shared-state sync.

## Current product phase (MVP implemented)
1) MVP scope: Weekend, Standings, Results, Settings, with full race/champion picks available from Weekend.
2) Architecture boundaries: SwiftUI views + single app-level `AppViewModel`, repository layer, scoring services.
3) Reliability/UX goals: no default spoilers, locked results protection, locked season champion protection, atomic file writes, online data with bundled fallback.
4) Testing priorities: scoring rule correctness and standings aggregation.

## Architecture snapshot (current)
- App entry/navigation:
  - `ChicaneApp` injects `AppViewModel`.
  - `RootTabView` hosts tabs for Weekend, Standings, Results, Settings.
  - `PicksView` is opened from Weekend for all-race/manual picks and season champion selections.
- Core view models/services:
  - `AppViewModel` (main-actor UI state orchestration)
  - `ScoringService` and `ScoreboardCalculator` (pure logic)
  - `SeasonArchiveService` (versioned historical scoring and year-end review assembly)
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
  - Next-race countdown should prefer official race-session start times (F1 race page session start; MotoGP `RAC` session date) rather than day-level placeholders or weekend-end timestamps.
  - The widget reads an atomic calendar/results/cancellations snapshot from the shared App Group's Library/Application Support directory. Publish live event identities and start times together; filter canceled/settled races before selecting the next pending race, and never let a result advance a race before its scheduled start. The bundled calendar is a fallback until the app supplies its first snapshot.
  - Official championship leaders (F1 + MotoGP top 3) refresh from official sources on app reload and after each successful "Fetch Results".
  - Seed data from bundled JSON in `Chicane/Resources/Seed` when online fetch fails.
  - User state persisted to application-support JSON file with atomic writes.
- Schema 7 adds durable partial/cleared race-pick drafts and timestamped, reversible race cancellations. Incomplete drafts never score or count as ready. Canceled races keep their predictions as void, award no points, are skipped by Weekend/widgets, and count as settled in archives. Undo is a persisted status update, so stale devices cannot resurrect cancellation.
- Schema 6 adds self-contained season archives and explicit official-result provenance. A fetched official finale creates that series' archive; missing race results or a missing confirmed champion keep it pending. Combined reviews are final only when both series are complete.
- Archives preserve names, bets, participants, calendars, predictions and results. Active-season resets/player removals must never delete archived identities. Sync unions archive years/series independently of the active reset cutoff and shares only the current league's archives; prior groups/private archives remain local.

## Concurrency rules (important)
- Keep SwiftUI/view model state on `@MainActor`.
- Keep disk IO and repository mutations off main actor via actors.
- Default actor isolation is configured to `nonisolated`; do not rely on broad global actor defaults.

## Behavior invariants (do not regress)
- No spoilers shown unless user explicitly enters or fetches results.
- Podium picks/results must contain 3 unique participants (drivers for F1, riders for MotoGP).
- Scoring is position-exact only (P1/P2/P3 exact matches only, 0-3 points per event).
- Locked official results must not be manually editable once retrieved; an official-source refresh may correct the same event and keep it locked.
- Locked season champions must not be editable once entered, and player champion picks must freeze for that series at the same moment.
- Season reset clears active picks/results but preserves players/settings and saved season reviews, including incomplete reviews.

## UX rules
- Large controls and readable typography by default.
- Keep interactions short and explicit with clear confirmation/error copy.

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
  - `xcodebuild -scheme Chicane -project Chicane.xcodeproj -destination 'platform=iOS Simulator' -only-testing:ChicaneTests test`

## Coverage status and remaining documentation

- The generic lock-flow UI-test task is implemented in `ChicaneUITests/ChicaneUITests.swift`, including locked results, disabled Weekend picks, and champion lock behavior.
- Parser and repository coverage exists in `ChicaneTests/F1HTMLParserTests.swift`, `OnlineChampionshipRepositoryTests.swift`, `FallbackRepositoryTests.swift`, and `LocalSeasonRepositoryTests.swift`. Cases include malformed/missing HTML fields, date/season parsing, MotoGP payload shapes, fallback behavior, and local persistence. Retire the generic missing-test tasks; add specific gaps only when identified.
- This October 18, 2026 status correction is based on source inspection, not a new test run or a claim of exhaustive coverage.
- Expand calendar/driver seed update documentation.

## Output expectations per patch
Provide:
- Summary of change
- Files modified
- Any migration considerations
- Commit message suggestion

## CI reliability and local validation

- For ordinary changes, start with the narrowest relevant build, unit test or UI check. Expand for shared behavior, persistence, startup or release risk. Documentation and local tool-selection helper changes need scoped structural/contract checks; they do not require an application rebuild solely to repeat CI.
- Use `bash scripts/local-check.sh <command> [args...]` for local checks. It selects already-installed Xcode 26.6 for that command without changing global defaults, and preserves an explicit `DEVELOPER_DIR`. If unavailable, focused commands can use the existing compiler with the difference reported; the strict CI driver still rejects a mismatch.
- GitHub keeps Xcode 26.6 and Simulator 26.5. For deliberate complete reproduction use `bash scripts/local-check.sh bash scripts/ci.sh all <fresh-iOS-26.5-simulator-UDID>`. Fresh simulators are for isolated/full reproduction; preserve existing simulator data. Upgrade pinned baselines in a separate validated change.
- Run the complete affected suites when changing build/test workflow behavior, test harnesses or shared fixtures, or when reproducing a hosted failure. Full local CI is not a blanket prerequisite for every edit. Keep GitHub CI enabled and all existing suites/assertions; a focused pass is not a full-suite pass.
- Check installed tools and equivalent capabilities before proposing a download. Do not install or switch global tools merely to obtain exact CI parity for an unrelated change. Report local compiler/runtime/browser/OS differences and checks not run; only observed GitHub results establish hosted CI success.
- Keep the build, unit-test, and UI-test phases and all existing assertions. Build/test workflow, harness and shared-fixture changes require complete affected-suite evidence.
- Use explicit calendars/timezones for date fixtures, deterministic verified text replacement and readiness conditions for UI, and isolated cloud/Keychain fixtures where those services are not being tested. Repair a failing assumption across related tests rather than retrying or disabling it.
- Classify zero-step payment/spending-limit failures as unavailable execution evidence, separately from compilation, assertions, and deployment. Inspect annotations before editing code for an account block.
- Documentation-only pushes skip expensive CI; optional pull-request checks remain present. Superseded same-ref runs are cancelled. Change pinned compiler/runtime versions deliberately and validate the complete suite.
