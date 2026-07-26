# GuildCotiz publishing kit

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

## Release title

GuildCotiz 1.0.0

## Release changelog

Initial release of GuildCotiz:

- Raid-based contribution tracking.
- Manual weekly attendance entry.
- Guild rank and player filters.
- Automatic deposit scanning.
- Separate withdrawal history.
- Historical balances and CSV export.

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

Then add `CF_API_KEY` and `WAGO_API_TOKEN` as GitHub Actions repository
secrets. Never commit either token.
