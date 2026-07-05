
## GBrain Configuration (configured by /setup-gbrain)
- Mode: local-stdio
- Engine: pglite
- Config file: ~/.gbrain/config.json (mode 0600)
- Setup date: 2026-07-06
- MCP registered: yes (user scope, `mcp__gbrain__*` tools after session restart)
- Artifacts sync: artifacts-only → https://github.com/karannarwani01/gstack-artifacts-user (private)
- Current repo policy: read-write
- Embeddings: NOT configured (no OPENAI_API_KEY/VOYAGE_API_KEY/ZEROENTROPY_API_KEY).
  Keyword search works; semantic search activates when a key is set, then run
  `gbrain embed --stale`.
- Known issue: transcript ingest stages 26 files but `gbrain import` picks up 0
  on Windows (path bug in staging handoff) — transcripts not yet brain-searchable.

## GBrain Search Guidance (configured by /setup-gbrain)
<!-- gstack-gbrain-search-guidance:start -->
GBrain is set up on this machine (keyword mode until an embedding key is added).
Prefer `gbrain search "<terms>"` for past plans/decisions/learnings in ~/.gstack.
Durable decisions: log with `gstack-decision-log`, resurface with
`gstack-decision-search`. Grep remains right for exact strings in code.
<!-- gstack-gbrain-search-guidance:end -->
