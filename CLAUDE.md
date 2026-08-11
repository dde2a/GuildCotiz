# Claude Code project instructions

Before making changes, read:

1. `DEVELOPMENT.md` for architecture, accounting rules, data invariants, tests
   and the local WoW validation workflow.
2. `PUBLISHING.md` before changing versions, creating tags or publishing.

Non-negotiable rules:

- A season/rate change must preserve all deposits, attendance, debts and credits.
- Historical weeks must use the rate effective for each week.
- Main totals merge linked alts; an alt detail view stays character-specific.
- Keep SavedVariables migrations idempotent and backward compatible.
- Keep French and English locale keys synchronized.
- Develop in the repository, use `-test` for in-game builds, run all tests and
  wait for the maintainer's in-game validation before publishing.
- A merged pull request is not a release. Only an annotated `vX.Y.Z` tag triggers
  packaging. Never rewrite release tags or commit API tokens.

Use `scripts/release.ps1` only after following the checklist in `PUBLISHING.md`.
