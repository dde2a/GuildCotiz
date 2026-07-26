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
- Automatic scanning of guild bank gold deposits.
- Separate withdrawal history for officers.
- Running balance showing whether a player is current, ahead or behind.
- Weekly player details with deposits, amount owed and cumulative balance.
- CSV exports for Excel and Google Sheets.
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
- SavedVariables are local and are not synchronized between officers.

## Privacy

GuildCotiz does not transmit data. Guild names, character names, deposits,
withdrawals and attendance remain in:

`WTF/Account/<account>/SavedVariables/GuildCotizDB.lua`

## License

GuildCotiz is distributed under the MIT License. See [LICENSE](LICENSE).
