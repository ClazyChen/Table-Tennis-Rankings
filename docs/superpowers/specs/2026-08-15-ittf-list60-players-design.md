# ITTF list/60 Player Download Design

**Date:** 2026-08-15  
**Status:** Implemented  
**Related:** `2026-08-12-ittf-list68-matches-design.md`

## Problem

Player crawl via `listid=33&format=json` hits 429 (same class of machine-friendly endpoint as matches `list/31`).

## Approach

Use the browser profile UI:

`GET /index.php/player-profile/list/60?resetfilters=1&vw_profiles___player_id_raw={id}`

Embedded Fabrik `"data":[[{data:{vw_profiles___…}}]]` includes fields required by `parse_player_data` (`profile_raw`, `name_raw`, `gender_raw`, `player_id`, `player_id_raw`). Existing `extract_fabrik_list_data` → `to_ittf_list_json` yields isomorphic `[[dicts]]`.

## Behavior

- No `list/33` JSON and no other HTML fallbacks.
- Validate `player_id_raw` matches requested id.
- On 429 / extract failure: save `crawl_state.json` and exit (`RateLimited` / `PlayerJsonFailed`); keep current id in `pending_player_ids`.

## Fixture

`docs/reference/view-source_…player-profile_list_60…121558.html` → `testdata/list60_player.html`.
