# GuildCotiz

GuildCotiz is a World of Warcraft Retail addon for tracking guild raid
contributions from the guild bank.

Instead of charging every guild member once per week, GuildCotiz lets officers
enter how many raid nights each player attended during a selected week. The
amount owed is calculated from the configured contribution per raid.

## Features

- Configurable contribution amount per raid.
- Manual raid attendance entry for each player and week.
- Bulk attendance entry for the currently displayed players.
- Filters by player name and guild rank.
- Historical weekly view using ISO week numbers.
- Automatic scanning of guild bank gold deposits, including repeated deposits
  of the same amount.
- Separate withdrawal history for officers.
- Running balance showing whether a player is current, ahead or behind.
- Weekly player details with deposits, amount owed and cumulative balance.
- CSV exports for Excel and Google Sheets.
- Officer-to-officer sync of guild bank transactions.
- Automatic detection of members who left the guild, hidden from the table
  while their deposit history is preserved.
- Automatic French or English interface based on the WoW client language.
- All information remains stored locally in WoW SavedVariables.

## How it works

```text
Amount owed = raids attended × contribution per raid
Balance     = total deposited − amount owed
```

A larger deposit can cover several future raids. A player who did not raid
does not owe anything for that week.

## Installation

1. Download and extract the release archive.
2. Copy the `GuildCotiz` folder into:
   `World of Warcraft/_retail_/Interface/AddOns/`
3. Restart World of Warcraft or run `/reload`.
4. Open the addon with `/cotiz` or `/gc`.

## Usage

1. Set the amount due per raid with **Amount / raid** or `/cotiz set 1000`.
2. Open the guild bank regularly so GuildCotiz can scan its limited transaction
   history.
3. Select a week in the summary view.
4. Enter each player's raid count, or filter by rank and use
   **Apply to all** before correcting absences.
5. Click a player to inspect their weekly history.
6. Use the export buttons to copy CSV data into Excel or Google Sheets.

## Important limitations

- WoW only exposes a limited number of recent guild bank transactions. Open the
  guild bank frequently so deposits and withdrawals are recorded before they
  disappear from the journal.
- The character scanning the bank must have permission to view its money log.
- Attendance is intentionally entered manually; the addon does not infer raid
  attendance from group composition.
- Only deposits and withdrawals are synchronized between officers. Raid
  attendance, manual corrections and settings stay local to each officer.
- The member list is not synchronized: every officer reads the same guild roster
  from the game and detects departures on their own.
- Sync is opportunistic: two officers must be online at the same time to
  exchange data. Information spreads as officers connect.
- Only transactions from the last 30 days are shared. Beyond that, WoW reports
  transaction age in whole months, which is too coarse to match the same
  transaction reliably across two clients.

## Former members

GuildCotiz reconciles its member list against the real guild roster. A character
that is no longer in the guild is marked as gone, disappears from the table, and
stops counting toward contributions — but stays in the database, because their
deposit history is part of the accounting.

Use the **Former members** entry in the rank filter menu to show them again,
`/cotiz roster` to force a refresh and list them, and `/cotiz purge` to delete
them for good. The plain `purge` only deletes former members who never deposited
anything, which is safe for the accounting; `/cotiz purge all` deletes the rest
too.

Departures are only applied when the roster read is complete. World of Warcraft
only indexes the guild members currently displayed, so with offline members
hidden the addon would see a handful of online characters and wrongly conclude
that everyone else left. When that happens, `/cotiz roster` says so and applies
nothing.

## Officer sync

Officers running GuildCotiz exchange the guild bank transactions they have
recorded. Because WoW only exposes a short window of the money log, each officer
captures a different slice of it; merging those slices recovers deposits that
would otherwise be lost.

Merging cannot conflict: transactions are facts, so combining two sets is a
plain union. When both officers hold the same transaction, the earlier of the
two timestamps is kept — WoW reports transaction age truncated to the hour, so
the smallest recorded value is the closest to the real one, and picking the
minimum makes every client converge on the same value.

Messages travel on the `OFFICER` addon channel, which restricts the exchange to
characters holding officer chat rights. Use `/cotiz sync` to trigger an exchange
manually, `/cotiz sync status` to inspect the state, and the addon options to
disable it or fall back to the `GUILD` channel.

## Privacy

GuildCotiz does not transmit data outside the guild's own addon channel. Guild names, character names, deposits,
withdrawals and attendance remain in:

`WTF/Account/<account>/SavedVariables/GuildCotizDB.lua`

Officer sync only ever carries guild bank deposits and withdrawals, and only to
other GuildCotiz users in the same guild.

## License

GuildCotiz is distributed under the MIT License. See [LICENSE](LICENSE).
