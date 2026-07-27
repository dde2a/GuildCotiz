# Changelog

## 1.2.1 - 2026-07-27

- Added raid attendance editing for linked reroll rows.
- Main contribution status now consolidates raids attended by the main and all linked rerolls.
- Reroll detail views now show their own raids, deposits, corrections, and weekly history.
- Weekly deposit corrections made from a reroll detail view now belong to that reroll.
- Expanded reroll rows now display their own raid totals, deposits, and balances.
- Weekly and deposit-history exports follow the selected reroll instead of silently exporting its main.
- Removed group deposit overrides that could hide linked reroll contributions from the main total.
- Existing group corrections are migrated to the main character while reroll deposits remain additive.
- Replaced the hidden WoW context menu for alt ranks with a visible integrated multi-select popup.
- Moved guild-rank classification to the addon options with reroll, unassigned, and main columns.
- Added native internal scrolling to the rank columns so they fit the standard WoW options window.
- Added named profile management with Default, selection, save, reset, delete, and named imports.
- Replaced the active-profile button with the standard WoW profile dropdown.
- Reorganized addon options into general settings, rank classification, then profile management, with page scrolling.
- Fixed general settings saves and ensured option changes immediately update and persist in the active profile.

## 1.2.0 - 2026-07-27

- Added a native Options > AddOns > GuildCotiz settings page.
- Added safe profile export and import for addon configuration, main/alt associations, or both.
- Profile imports show a summary and require explicit confirmation.
- Deposit, withdrawal, raid attendance, and transaction history data are never included in profiles.
- Reworked profile content selection with native vertical WoW checkboxes.

## 1.1.0 - 2026-07-26

- Added editable weekly deposit amounts in the player detail view.
- Manual corrections replace the detected guild bank total without deleting the original transactions.
- Clearing a corrected field restores the automatically detected amount.
- Weekly CSV exports identify manual corrections.
- Added the addon version to the bottom-right corner of the main window.
- Added main/alt character linking with merged contributions and expandable reroll rows.
- Added original deposit history per character group, including character, date, time, and amount.
- Improved table scrolling performance by reusing already calculated rows.
- Increased the window height and moved the version label clear of the bottom border.
- Added searchable guild-member suggestions to the main/alt manager, filtered by the `Reroll` guild rank.
- Already linked rerolls are hidden from the alt suggestions and can be unlinked directly from their expanded row.
- Polished expanded reroll rows: single-line names, wider player column, proper close icon, and cleaner version placement.
- Added reviewed main/alt suggestions based on guild notes, officer notes, and similar character names.
- Fixed the main/alt manager background so the guild table no longer shows through the dialog.
- Added live main/alt linking progress with linked, total, and remaining active guild rerolls.
- Added per-guild alt-rank configuration; all unselected ranks are treated as main ranks.
- Added ascending and descending sorting by clicking any table column header.

## 1.0.1 - 2026-07-26

- Added automatic localization based on the World of Warcraft client language.
- Added complete French and English translations.
- English is used as the fallback for all other client languages.
- Localized the interface, chat messages, status labels and CSV exports.

## 1.0.0 - 2026-07-26

- Initial public release.
- Track contribution amounts per raid attended.
- Enter raid attendance manually for each player and ISO week.
- Filter guild members by name and rank.
- Scan and deduplicate guild bank gold deposits.
- Track guild bank withdrawals in a separate view.
- Display historical balances and weekly player details.
- Export summaries, weekly history and withdrawals as CSV.
