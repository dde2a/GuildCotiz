# GuildCotiz development guide

This document is the technical source of truth for humans and coding agents.
Read it before changing accounting, profiles, SavedVariables, UI layout or the
release workflow. Release-specific instructions remain in `PUBLISHING.md`.

## Product model

GuildCotiz is a World of Warcraft Retail addon that tracks guild-bank deposits,
withdrawals and raid attendance. WoW addons cannot write arbitrary CSV files:
exports are displayed in a copyable text window for Excel or Google Sheets.
Persistent data is stored in `GuildCotizDB` through WoW SavedVariables.

The accounting rules are:

```text
amount owed for a week = raids attended that week x that week's raid rate
running balance        = all deposits to date - all amounts owed to date
```

- A season/rate change never resets deposits, attendance, debt or credit.
- Each week uses the rate effective for that week.
- A rate becomes effective on its configured date. If that date is in the
  middle of a week, the containing Monday is still before the change and the
  new rate applies from the following Monday. Example: `2026-08-19` means that
  the week beginning `2026-08-24` uses the new rate.
- A main character's totals include deposits and attendance from linked alts.
  An alt's detail view remains its own individual history.
- Creating a season must never remove or hide transactions from older seasons.

## Repository map

- `GuildCotiz.toc`: metadata, supported interface versions and load order.
- `Locale.lua`: all French and English user-facing strings.
- `Core.lua`: SavedVariables, migrations, roster, bank journal, seasons,
  accounting and main/alt aggregation.
- `Theme.lua`: shared visual theme and widget styling.
- `Profiles.lua`: named profiles and the `GC1` import/export format.
- `Sync.lua`: officer-to-officer transaction synchronization through AceComm.
- Optional GRM integration in `Core.lua`: read-only main/alt import using
  `GRM.GetPlayerMain`; never write to GRM globals or SavedVariables.
- `Export.lua`: CSV builders and copyable export window.
- `UI.lua`: main window and tables.
- `Options.lua`: WoW Settings panel.
- `tests/`: standalone regression, cache and layout tests.
- `scripts/release.ps1`: release preflight and tag publication.

Keep new user-facing text in `Locale.lua`, and preserve key parity between the
English and French tables. Prefer shared theme helpers over local visual styles.

## Seasons and rates

The canonical season data is:

```lua
g.config.ratePeriods = {
    { name = "S1", start = timestamp, amount = copper },
    { name = "S2", start = timestamp, amount = copper },
}
```

Periods are sorted by ascending `start`. Use these public helpers rather than
writing the table directly:

- `GuildCotiz.EnsureRatePeriods(g)` migrates and normalizes season data.
- `GuildCotiz.SetRatePeriod(g, start, amount, name)` adds or replaces a period.
- `GuildCotiz.RatePeriodAt(g, weekTs)` returns the period effective that week.
- `GuildCotiz.RaidAmountAt(g, weekTs)` returns its amount in copper.

`g.config.seasonStart` and `g.config.raidAmount` are legacy mirrors of the
latest/current period. They exist for compatibility and must not be treated as
the complete history. Migrations must be idempotent and preserve older profile
formats and SavedVariables.

Profiles include configuration, rank classification and rate periods when the
corresponding export option is enabled. Profiles never contain bank
transactions, manual corrections or attendance history. Continue accepting
older version-1 profile records; season records use `start|amount|name`.

## Derived caches

Two derived caches keep a summary refresh linear in the number of members. Both
live in memory only, are keyed by the guild table, and are dropped on reload;
nothing derived is ever written to SavedVariables.

- Season normalization (`NormalizeRatePeriods`) scans every member and every
  deposit to find the earliest accounting activity, which may push the tracking
  start backwards. Its result is reused until the next accounting write.
- The main/alt group index backs `GuildCotiz.GetLinkedCharacters`, which the
  summary view calls five times per member.

Both are invalidated by a single counter through `GuildCotiz.InvalidateCaches()`.
Call it after any write to deposits, withdrawals, attendance, manual
corrections, rates, main/alt links, or after adding or removing a member. A
cache kept too long is an accounting bug, not a display bug: the tracking start
would stop moving back and deposits older than the first season would silently
drop out of the totals. `tests/cache_test.lua` covers each write path with an
already-warm cache.

Scans and roster reads refresh the UI only when data actually changed:
`ScanBankLog` returns a fourth value saying whether anything moved (new
transactions or realigned timestamps), and `ScanRoster` compares before writing.
`GUILDBANKLOG_UPDATE` events are coalesced through a short timer, since the
server emits several while the log loads.

## Data-safety invariants

- Never delete, replace or manually edit a player's SavedVariables.
- Never discard historical deposits, withdrawals, attendance, links or rates.
- Do not identify transactions only by player, amount and approximate time:
  repeated identical bank transactions are valid and use sequence-aware
  reconciliation.
- `/cotiz fix` must remain non-destructive; it may normalize indexes/order only.
- Sync sends deposits and withdrawals only. It does not send settings,
  attendance, manual corrections or profile choices.
- WoW exposes only a limited bank-log window, so old data already captured in
  SavedVariables is authoritative and must be retained.

## UI constraints

- The Settings panel must remain inside WoW's standard options viewport and use
  scrolling for content that exceeds it.
- Main tables use virtual scrolling and cached rows. Avoid rebuilding all
  accounting data on every mouse-wheel event.
- Run `tests/layout_test.lua` after any geometry, options or main-window change.
- Preserve the distinction between main totals and per-character detail views.

## Development workflow

1. Inspect `git status` and preserve unrelated user changes.
2. Make changes in this repository first. Do not develop directly in the WoW
   installation folder.
3. During in-game validation, use a version ending in `-test`.
4. Run the regression suite and `git diff --check`.
5. Copy the TOC-listed addon files and `Libs` to the Retail/PTR addon folder.
6. Use `/reload` for edits to existing files; restart WoW after adding a file to
   the TOC.
7. Wait for explicit in-game validation before creating a release tag.

Typical local install folders on the maintainer's machine are:

```text
C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\GuildCotiz
C:\Program Files (x86)\World of Warcraft\_ptr_\Interface\AddOns\GuildCotiz
```

Do not overwrite the `WTF` directory. SavedVariables normally live below:

```text
World of Warcraft\_retail_\WTF\Account\<account>\SavedVariables\GuildCotiz.lua
```

## Tests

Preferred commands with Lua 5.1:

```powershell
lua tests/roster_test.lua
lua tests/sync_test.lua
lua tests/contribution_test.lua
lua tests/grm_test.lua
lua tests/cache_test.lua
lua tests/layout_test.lua
git diff --check
```

If native Lua is unavailable, use Fengari:

```powershell
npx --yes --package=fengari-node-cli fengari tests/roster_test.lua
npx --yes --package=fengari-node-cli fengari tests/sync_test.lua
npx --yes --package=fengari-node-cli fengari tests/contribution_test.lua
npx --yes --package=fengari-node-cli fengari tests/grm_test.lua
npx --yes --package=fengari-node-cli fengari tests/cache_test.lua
npx --yes --package=fengari-node-cli fengari tests/layout_test.lua
```

Fengari validates the accounting, season, roster and layout logic. Some
simulated network-sync assertions can differ from native Lua/WoW; confirm sync
changes with native Lua or in game before release.

## Versioning and publication

- Patch release: compatible bug fix, for example `1.5.1`.
- Minor release: visible feature or meaningful data-model evolution, for
  example `1.6.0`.
- Development builds carry `-test`; published builds never do.
- A merged pull request does not publish the addon.
- Never rewrite an existing release tag.
- Never commit CurseForge or Wago API tokens.

Follow `PUBLISHING.md` exactly. The normal release command is:

```powershell
.\scripts\release.ps1 -Push
```

It validates the repository and pushes an annotated `vX.Y.Z` tag, which triggers
the GitHub Actions packaging and CurseForge publication workflow.
