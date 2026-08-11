# ITTF Match/Player HTML Fallback Design

**Date:** 2026-08-11  
**Status:** Approved  
**Scope:** Restore match (and resilient player) downloads for `ccelo.ipynb` after ITTF blocked match `format=json`.

## Problem

- Event list `format=json` still works when the user is logged in.
- Match list `format=json` / `format=csv` / `format=raw` (including Fabrik AJAX `list.view`) returns **403 Forbidden** even with a valid session.
- Match HTML list pages remain reachable, e.g.  
  `/index.php/event-matches/list/31?resetfilters=1&vw_matches___tournament_id_raw[value][]={id}&limit31=100&limitstart31={offset}`.
- Those HTML pages embed the full Fabrik list payload (including `*_raw` fields) inside a `<script>` as `"data":[[{ "data": { ...fields }, ...}, ...]]`.
- Player `format=json` (listid=33) is **not** hard-blocked with 403; it works when authenticated. When the session is missing/expired it still returns HTTP 200 with a small login/register HTML body — easy to mis-save as JSON.
- Player HTML surfaces exist (`/index.php/players-profiles`, `player-profile/list/60`, classic `listid=33` HTML) and should support the same embedded-`data` extraction when logged in.

## Goals

1. Download matches again and write `matches/matches_N.json` **isomorphic** to historical ITTF files: `[[{ vw_matches___…, … }]]`.
2. Keep `convert_ittf_match` / `process_matches` / `parse_player_data` unchanged.
3. Put fetch/parse logic in a standalone Julia module included by the notebook.
4. Player download: prefer JSON; validate response; fall back to HTML extraction with the same `[[dicts]]` shape.
5. Allow Gumbo (and Cascadia if useful) as dependencies.

## Non-Goals

- Reviving blocked match `format=json`.
- Browser automation.
- Changing event download (still JSON) beyond documenting login-wall detection if touched.
- Changing rating/ranking algorithms.

## Architecture

```
ccelo.ipynb
  COOKIES, download_matches_from_ittf, download_players_from_ittf
       │
       └─ include("ittf_fabrik.jl")
              ├─ looks_like_login_wall(body)::Bool
              ├─ extract_fabrik_list_data(html)::Vector{Dict}
              ├─ to_ittf_list_json(rows)::String   # "[[{...},...]]"
              ├─ fetch_event_matches_page(event_id; offset, limit, cookies)
              ├─ download_event_matches_json(event_id; …)::String
              ├─ fetch_player_json(player_id; cookies)           # try format=json
              └─ download_player_json(player_id; cookies)::String # JSON or HTML fallback
```

### Match path

1. GET event-matches HTML with cookies + browser User-Agent.
2. Gumbo: find `<script>` whose text contains `"data":[[` and `vw_matches___`.
3. Locate the JSON object that contains both `limitLength` and `data`; parse with Julia JSON.
4. Flatten each row’s `row["data"]` into a dict.
5. Serialize as `[[flat_rows...]]`.
6. Notebook pagination: `limit=100`, `offset += 100` until zero rows; save files; call existing `process_matches`.

### Player path

1. GET listid=33 `format=json` (fix `limitstart33`, not `limitstart27`).
2. If body is JSON (`application/json` or parses as array-of-arrays with profile fields) → save as-is.
3. If login wall / non-JSON / unusable → GET HTML filtered by player id, extract + flatten to the same `[[dicts]]` shape expected by `parse_player_data`.
4. Notebook keeps writing `players/{id}.json` and calling `parse_player_data`.

## Error handling

- HTTP errors and extract failures: throw or signal failure so notebook retry loops (`sleep(10)`) still work.
- Never write login-wall HTML into `matches_*.json` / `players/*.json`.
- Empty match page → end pagination for that event.

## Verification

1. Event 3480: ~93 matches; keys include `vw_matches___player_a_id_raw`, `vw_matches___res_raw`, etc.
2. Run existing `process_matches` on extracted JSON.
3. With valid cookies: player JSON success path for a known id.
4. Without cookies / forced HTML: login detection or HTML extract path does not corrupt files.
5. Optional: compare key sets with an old `matches_*.json` for the same tournament if available locally.

## Files

| File | Change |
|------|--------|
| `ittf_fabrik.jl` | New module (shared extract + match/player download helpers) |
| `ccelo.ipynb` | `include`; rewrite match/player download cells; doc note; fix `limitstart33` |
| `docs/superpowers/specs/2026-08-11-ittf-html-match-player-design.md` | This spec |
