# Instructions for coding agents

Read `DEVELOPMENT.md` before modifying GuildCotiz. It defines the architecture,
accounting rules, data-safety invariants, tests and local validation workflow.
Read `PUBLISHING.md` before changing versions, creating tags or publishing.

- A merged pull request is not a release.
- Releases are triggered only by pushing an annotated `vX.Y.Z` tag.
- Never publish a version ending in `-test`.
- Run the repository tests and release preflight before tagging.
- Never move, delete or recreate a published tag; release a new patch instead.
- Never commit CurseForge or Wago API tokens.

Use `scripts/release.ps1` for release validation and publication.
