# GuildCotiz publishing and release guide

This file is the canonical release procedure for humans and coding agents.
Merging a pull request does **not** publish the addon. The release workflow is
triggered only when a tag whose name starts with `v` is pushed to GitHub.

## Release pipeline

```text
merge to main -> update local main -> validate -> push tag vX.Y.Z
              -> GitHub Actions -> GitHub release + CurseForge upload
```

The workflow is `.github/workflows/release.yml`. It uses the
BigWigsMods packager and reads the CurseForge project ID from
`GuildCotiz.toc`.

## Required version files

Before publishing `X.Y.Z`, verify all of the following:

- `GuildCotiz.toc` contains `## Version: X.Y.Z` without a `-test` suffix.
- `CHANGELOG.md` starts with a `## X.Y.Z - YYYY-MM-DD` section.
- The release commit is merged into `main` and pushed to `origin/main`.
- The working tree is clean.
- The tag `vX.Y.Z` does not already exist locally or remotely.

Do not change an existing release tag. If a published release is wrong, create
a new patch version instead.

## Tests

When a Lua interpreter is available, run:

```powershell
lua tests/roster_test.lua
lua tests/sync_test.lua
lua tests/contribution_test.lua
lua tests/layout_test.lua
```

Always run these static checks as well:

```powershell
git diff --check
git status -sb
```

Test the addon in the installed Retail client before publishing. When a new Lua
file is added to the TOC, fully restart World of Warcraft; `/reload` alone may
not be sufficient during development.

## Publish a release

From the repository root on Windows, use the release helper:

```powershell
.\scripts\release.ps1 -Push
```

The script reads the version from `GuildCotiz.toc`, validates the repository,
creates the annotated tag and pushes it. Without `-Push`, it performs only the
preflight checks:

```powershell
.\scripts\release.ps1
```

Equivalent manual commands are:

```powershell
git switch main
git pull --ff-only origin main
git status -sb
git tag -a vX.Y.Z -m "GuildCotiz X.Y.Z"
git push origin vX.Y.Z
```

Pushing the tag starts the workflow. Follow it with:

```powershell
gh run list --workflow release.yml --limit 5
gh run watch <run-id> --exit-status
```

Then verify both outputs:

```powershell
gh release view vX.Y.Z
gh run view <run-id> --log
```

The log must contain a successful CurseForge upload. CurseForge may still show
the file as processing for a few minutes after the workflow succeeds.

## Recovery: version merged but not published

If the TOC and changelog were updated but no deployment appeared:

1. Check whether `vX.Y.Z` exists with `git ls-remote --tags origin vX.Y.Z`.
2. Check whether the workflow ran with `gh run list --workflow release.yml`.
3. If there is no tag, update local `main`, run the tests and execute
   `.\scripts\release.ps1 -Push`.
4. If the tag exists but the workflow failed, inspect the run log. Do not delete
   and recreate the tag; fix the problem and publish a new patch version.

The 1.4.1 and 1.4.2 incident was caused by steps 1 and 3 being omitted: both
pull requests were merged, but neither release tag was created, so GitHub
Actions and CurseForge were never invoked.

## Repository secrets

The GitHub repository must contain `CF_API_KEY`. `WAGO_API_TOKEN` is optional
until Wago publishing is configured. Tokens must never be committed to the
repository. The workflow uses GitHub's automatic `GITHUB_TOKEN` for the GitHub
release.

## Project name

GuildCotiz

## Short summary

Track raid-based guild contributions, bank deposits, withdrawals and payment
history with officer-friendly filters and CSV exports.

## Full English description

GuildCotiz is a World of Warcraft Retail addon designed for guild officers who
manage raid contributions through the guild bank.

Rather than charging every member a fixed weekly amount, GuildCotiz calculates
what each player owes from the number of raid nights they attended. Officers
enter attendance manually for each ISO week, making the system reliable even
when players miss raids, join late, use alts or attend a run without the addon
owner.

The addon automatically scans the guild bank money log whenever the bank is
opened. Deposits are added to each player's running balance, while withdrawals
are kept in a separate officer-focused history. A player may deposit a larger
amount in advance, and GuildCotiz will show how many future raids that balance
covers.

Main features:

- Configurable gold contribution per raid.
- Manual raid attendance per player and week.
- Bulk attendance entry for filtered guild ranks.
- Filters by player name and guild rank.
- Historical status for any selected ISO week.
- Automatic guild bank deposit scanning and deduplication.
- Separate withdrawal and repair history.
- Per-player weekly breakdown with amount due, deposits and cumulative balance.
- Clear current, ahead and behind statuses.
- CSV exports compatible with Excel and Google Sheets.
- Automatic French or English localization based on the WoW client language.
- Local SavedVariables storage with no external data transmission.

Important: World of Warcraft exposes only a limited number of recent guild bank
transactions. An authorized officer should open the guild bank regularly so
GuildCotiz can save transactions before they disappear from the in-game log.

Commands:

- `/cotiz` or `/gc` — open GuildCotiz.
- `/cotiz set 1000` — set the contribution to 1,000 gold per raid.
- `/cotiz scan` — scan the guild bank money log while the bank is open.
- `/cotiz export` — open the CSV summary export.

## Suggested categories

- Guild
- Economy
- Data Export

## Required screenshots

Capture these images in game before submitting:

1. Summary view with several players and different statuses.
2. Weekly detail view for one player.
3. Guild-rank filter menu.
4. Withdrawal history.
5. CSV export window.

Hide the chat window or any personal information that should not be public.

## Platform identifiers

The CurseForge project is already connected:

```toc
## X-Curse-Project-ID: 1625909
```

After creating the Wago project page, add:

```toc
## X-Wago-ID: <Wago eight-character project ID>
```

Then add `WAGO_API_TOKEN` as a GitHub Actions repository secret. Never commit
the token.
