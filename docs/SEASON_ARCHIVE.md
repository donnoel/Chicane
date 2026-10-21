# Season Archive

Results has four choices: Formula 1, MotoGP, Seasons, and Bets. Seasons lists saved
year/group reviews newest first. The live race picker remains unchanged for
the first two choices. Bets shows current season stakes; original historical
stakes stay inside each saved season review.

## Completion

- Fetching and locking the final scheduled race from the official result source
  starts that series' archive. The final event comes from the loaded season
  calendar, not a hard-coded round number.
- Earlier missing results and an unconfirmed season champion keep the series
  marked **Awaiting results**. The combined winner is final only when both series
  are complete. A first-place championship standings entry alone is not treated
  as confirmation of the world champion.
- The review provides a champion picker and explicit confirmation for the active
  season. Confirmation uses the existing champion-result lock and +5 bonus rules.
  Champion predictions become locked. A race-result refresh can correct recorded
  race points; an already confirmed champion remains locked.
- Refresh/relaunch retries report assembly after an interrupted save. A report
  save or sync failure does not roll back a saved official race result and is
  surfaced as a warning. Sync Now retries league synchronization.

## The report

Reviews include a factual recap, combined/F1/MotoGP standings with separate race
points and champion bonuses, shared winners on ties, perfect podiums, best scoring
race week, champion predictions, final-race race-points lead changes when present,
official champion confirmations, original player bets, and expandable race-by-race
predictions/results. Best-weekend grouping uses ISO weeks in UTC. No payment or
settlement is inferred from a saved bet.

Reports are assembled locally from recorded evidence. Version-one historical
scoring stays at one point per exact position and five per correct champion;
future scoring changes must introduce a new archive scoring version.

## Persistence and league boundaries

`PersistedState` schema 6 adds `seasonArchives`. Existing payloads decode with an
empty archive without clearing active state. Legacy race results have unknown
official provenance (`isOfficial = false`): re-fetch a legacy finale to start its
review. Champion records now carry an optional explicit season; legacy champion
records fall back to their recorded UTC year.

Each archive is keyed by group, year, and series, and includes its own player
names, bets, driver/rider names, calendar, picks, results, and champion records.
Corrections update the same record. Names/stakes are frozen when the series is
first archived. Participant/event aliases are reconciled by participant name and
series/season/round when merging independently generated snapshots.

Archives use the existing atomic local-state write and backup path. Resetting
the active season, removing players, or replacing active state when joining a
league preserves existing archives. An incomplete archive remains incomplete
after reset; its status is never promoted merely because the active data cleared.

League sync unions archive records independently of active-season reset cutoffs.
Only records belonging to the target league are uploaded to that league. A new
league does not inherit private or previous-group archives. Those records remain
available on the device and are distinguished by group when years overlap.

No new CloudKit record types, fields, permissions, analytics, AI calls, or external
dependencies are introduced. Archive data travels in the existing league-state
payload. Tests cover a representative two-player, five-year/50-race-per-year
round trip; this is not a claim of unlimited CloudKit record capacity.

## Verification

`SeasonArchiveTests` covers official-source gating, partial completion, ties,
bonuses, idempotence, corrections, legacy decoding, year identity, multi-year
retention, reset/removal/reload, alias reconciliation, group isolation, local
retention on cloud failure, and the official-fetch-to-archive integration.
Focused UI tests cover empty/live Results switching, winner display/relaunch,
and champion confirmation finalizing the report. Physical installation/launch
and actual shared-league archive propagation are separate verification stages.
