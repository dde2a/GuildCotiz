# Claude Code project instructions

The canonical build and deployment procedure is in `PUBLISHING.md`. Read it
before changing versions, creating tags or publishing GuildCotiz.

A pull-request merge does not deploy the addon. A release requires an annotated
`vX.Y.Z` tag pushed to GitHub. Use `scripts/release.ps1` for preflight checks and
publication. Never publish `-test` versions, rewrite release tags or commit API
tokens.
