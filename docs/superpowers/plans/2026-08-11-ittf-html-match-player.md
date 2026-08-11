# ITTF HTML Match/Player Fallback Implementation Plan

> **For agentic workers:** Implement task-by-task. Steps use checkbox syntax.

**Goal:** Restore ITTF match downloads via HTML-embedded Fabrik JSON, and harden player downloads with JSON-then-HTML fallback, preserving isomorphic `[[dicts]]` files.

**Architecture:** Shared `ittf_fabrik.jl` extracts Fabrik `data` from HTML; notebook download helpers call it. Match always uses HTML; player prefers `format=json` then HTML.

**Tech Stack:** Julia, HTTP.jl, JSON.jl, Gumbo.jl, Cascadia.jl

## Global Constraints

- Output JSON must remain `[[{field:value,...}]]` compatible with existing parsers.
- Do not change `convert_ittf_match` / `process_matches` / `parse_player_data` logic.
- Never persist login-wall HTML as data files.

---

### Task 1: Core extract helpers in `ittf_fabrik.jl`

**Files:** create `ittf_fabrik.jl`

- [ ] Add `looks_like_login_wall`, `extract_fabrik_list_data`, `to_ittf_list_json`
- [ ] Unit-test against saved HTML fixture (event 3480 page or minimal synthetic script snippet)

### Task 2: Match + player download API

**Files:** `ittf_fabrik.jl`

- [ ] `fetch_event_matches_html` / `download_event_matches_json`
- [ ] `try_fetch_player_format_json` / HTML fallback / `download_player_json`

### Task 3: Wire `ccelo.ipynb`

**Files:** `ccelo.ipynb`

- [ ] `include("ittf_fabrik.jl")` near cookies/download section
- [ ] Rewrite `download_matches_from_ittf` and `download_players_from_ittf`
- [ ] Update markdown docs; fix `limitstart33`

### Task 4: Verify

- [ ] Extract fixture → isomorphic keys present
- [ ] Smoke: functions load in Julia if available
