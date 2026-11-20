# Calendar and participant seed maintenance

The bundled JSON is a shipped fallback, maintained manually in this repository.
Pull-to-refresh does **not** rewrite it. Use this procedure for an approved season
or schedule/roster correction; do not reset a league to test a seed change.

## Files and runtime precedence

| File | Top-level key | Required record fields |
| --- | --- | --- |
| `Chicane/Resources/Seed/calendar.json` | `events` | `id`, `series`, `season`, `round`, `title`, `circuit`, `raceDate`; optional `trackTimeZoneID` |
| `Chicane/Resources/Seed/drivers.json` | `drivers` | `id`, `series`, `name`, `team`, `number` (string, which can be empty) |

`series` is exactly `formula1` or `motoGP`. Dates decode as ISO 8601 instants.
The authoritative models are [Models.swift](../Chicane/Domain/Models.swift).

On launch, foreground return, or refresh, the app requests official calendars and
participants. Calendar precedence is a nonempty live response, then the last
successful per-series calendar saved on this installation, then bundled JSON.
Calendar cache writes are atomic and separate from season/player state, under
Application Support/Chicane/CalendarCache (`formula1-v1.json`, `motoGP-v1.json`).
Saved/bundled calendar use has a persistent notice on Weekend; a cache write
failure also has a notice. A cache timestamp describes the last successful fetch,
not a guarantee that the source's schedule is still current.

Participants currently use live data, then bundled participants; they do not use
the calendar cache. Read [FallbackRepositories.swift](../Chicane/Data/Repositories/FallbackRepositories.swift)
and [ChicaneApp.swift](../Chicane/ChicaneApp.swift) before changing precedence.

The app and widget include the seed resources. The widget normally reads the
app's shared live/calendar/results/cancellation snapshot; bundled calendar data
is its initial fallback before an app snapshot exists. Updating a seed therefore
requires rebuilding the app and widget. A pull-to-refresh alone does not publish
new bundled resources.

## Authoritative references

Start with the official [F1 season calendar](https://www.formula1.com/en/racing/2026),
[F1 drivers](https://www.formula1.com/en/drivers),
[MotoGP season calendar](https://www.motogp.com/en/calendar/2026), and
[MotoGP riders](https://www.motogp.com/en/riders/motogp). Select the intended year;
these are reference links, not a claim that the current seeds match today's pages.

The adapters actually used by the app are
[OnlineCalendarRepository.swift](../Chicane/Data/Repositories/OnlineCalendarRepository.swift)
and [OnlineDriverRepository.swift](../Chicane/Data/Repositories/OnlineDriverRepository.swift).
F1 uses its season page plus the upcoming race's session page. MotoGP uses
`https://api.pulselive.motogp.com/motogp/v1/events?seasonYear=YYYY`, the `/riders`
endpoint and `/results/seasons`, `/results/events`, `/results/categories`, and
`/results/sessions` to resolve the upcoming `RAC` session. These are the current
adapter endpoints, not a promise of a public stable API.

## Updating safely

1. Start with a clean diff or identify unrelated changes. Record the source URL,
   retrieval date, intended season, and the specific correction in the change
   description. There is no seed-generation command in this repository today.
2. Edit the appropriate JSON manually. Preserve existing IDs for the same event
   or person. Do not derive a new ID merely because a sponsor, team, name spelling,
   round number, or race date changed. Do not reuse an old event ID for a different
   season/event. New participants/events need new unique IDs using the established
   `f1-...` / `mgp-...` conventions. Keep old records only when their identity and
   intended season are clear; do not mix an old roster into a new-season update.
3. Confirm `series`, season, official round, event title, circuit, and roster
   membership against the intended season. A canceled or rescheduled round can
   change official numbering; do not silently renumber unrelated events merely
   to make a contiguous-round assertion pass. In-app cancellation remains a
   separate reversible season-state record and must not be erased by a seed edit.
4. Verify the actual **main race** start, not a sprint, qualifying session, the
   first day of the weekend, or a weekend-end timestamp. Convert the circuit-local
   time with that date's daylight-saving rules to an absolute UTC instant, and
   verify the displayed viewer-local date (night races can cross midnight).
   Add a valid IANA `trackTimeZoneID` when known. Many existing seed entries use
   `12:00:00Z` and have no timezone ID; treat those as unverified day-level times
   until checked against the session schedule. The F1 parser also uses noon UTC
   as a day-level fallback, then enriches the next event from its race page.
5. Preserve saved-pick compatibility. The view model retains IDs across source
   switches using exact IDs and nearby-date matching; scoring also resolves
   stored aliases. Neither heuristic is a substitute for stable IDs, especially
   after a large reschedule or a season change. See
   [AppViewModel.swift](../Chicane/Features/App/AppViewModel.swift) and
   [StoredIdentityResolver](../Chicane/Data/Services/ScoringService.swift).
6. Review the JSON diff for unintended deletions, duplicated IDs/rounds, changed
   series/years, or mass name changes. No picks, results, scores, settings, league
   codes, or season archives belong in these resource files.

## Validation

Run from the repository root. First check structure without touching app data:

```sh
python3 - <<'PY'
import json
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
root = Path('Chicane/Resources/Seed')
for filename, key in [('calendar.json', 'events'), ('drivers.json', 'drivers')]:
    records = json.loads((root / filename).read_text())[key]
    assert records and len({r['id'] for r in records}) == len(records)
    for r in records:
        assert r['series'] in ('formula1', 'motoGP')
        assert isinstance(r['id'], str) and r['id'].strip()
        if key == 'events':
            assert isinstance(r['season'], int) and isinstance(r['round'], int)
            assert r['round'] > 0 and r['title'].strip() and r['circuit'].strip()
            assert datetime.fromisoformat(r['raceDate'].replace('Z', '+00:00')).tzinfo
            if r.get('trackTimeZoneID'):
                ZoneInfo(r['trackTimeZoneID'])
        else:
            assert all(isinstance(r[k], str) for k in ('name', 'team', 'number'))
            assert r['name'].strip() and r['team'].strip()
    print(filename, len(records), 'records: structural checks passed')
PY
git diff --check
```

Read the fixed local target guide before Apple validation. It owns the compiler,
simulator, and serial helper; do not substitute a new simulator or older Xcode.

```sh
bash scripts/local-check.sh python3 /Users/donnoel/Development/DevSystem/scripts/apple-local.py run iphone -- \
  xcodebuild -project Chicane.xcodeproj -scheme Chicane test \
  -only-testing:ChicaneTests/SeedDataTests \
  -only-testing:ChicaneTests/FallbackCalendarRepositoryTests \
  -only-testing:ChicaneTests/FallbackDriverRepositoryTests \
  -only-testing:ChicaneTests/RaceEventDisplaySelectionTests \
  -only-testing:ChicaneTests/RaceWeekendWidgetScheduleTests
```

[SeedDataTests](../ChicaneTests/SeedDataTests.swift) currently check 22 events per
series, contiguous 1–22 rounds, specific 2026 round anchors, and minimum participant
counts. The participant test's name mentions fields, but its assertions only
check counts. These tests do not prove current official schedules, exact starts,
roster freshness, unique IDs, or every nonempty field. When an approved season
update changes counts/rounds, update those expectations from verified source
evidence; do not blindly preserve a stale count or weaken an assertion just to pass.
The structural check above covers additional basic JSON contracts, not official
schedule accuracy.

Fallback tests exercise live/empty/error responses and calendar cache recovery;
selection tests exercise time boundaries and canceled/completed events. Rebuild
the app plus widget with warnings treated as errors if seed resources change,
and inspect both built bundles for the updated JSON. GitHub CI and local compiler
baselines are separate; a local pass is not proof of a hosted pass.

## Offline verification without touching a real league

Use isolated repository tests and the UI fixture, not deletion of production data
or toggling the Mac's networking. The UI test below creates a unique temporary
season/cache directory and a fake offline repository. It saves picks online,
relaunches twice offline, and checks the saved schedule, picks, and offline notice.

```sh
bash scripts/local-check.sh python3 /Users/donnoel/Development/DevSystem/scripts/apple-local.py run iphone -- \
  xcodebuild -project Chicane.xcodeproj -scheme Chicane test \
  -only-testing:ChicaneUITests/ChicaneUITests/testCorrectedCalendarAndPicksSurviveRepeatedOfflineColdStarts
```

For a deliberate manual seed-only check, use an isolated test installation/state
with no calendar cache and an unavailable primary repository. Confirm the bundled
notice and expected event/participant lists. Test cache precedence separately:
after a successful live fetch, offline operation should keep that saved calendar,
so seeing cached dates is expected and does not mean the new seed failed to bundle.
Never reset season state, leave/join a league, clear player picks, erase a shared
simulator, or remove the production calendar cache merely to force fallback.

If a seed change is wrong, revert only its JSON and associated expected fixtures,
then rebuild. This does not alter saved season state or automatically replace a
previously cached live calendar; do not use data deletion as a rollback shortcut.
