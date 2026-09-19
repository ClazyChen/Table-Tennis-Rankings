# ITTF list/68 Match Download Design

**Date:** 2026-08-12  
**Status:** Implemented  
**Related:** `2026-08-11-ittf-rate-limit-resume-design.md`, `2026-08-11-ittf-html-match-player-design.md`

## Problem

`list/31` match pages are hard-rate-limited (immediate 429; cooldowns escalate 1h→6h→24h; IP change ineffective). Browser UI uses **`list/68`**, which still works.

## Approach

Matches crawl uses **list/68 only**:

1. **First page (offset 0):** GET  
   `/index.php/event-matches/list/68?resetfilters=1&abc={id}&vw_matches___tournament_id_raw[value][]={id}`
2. **Later pages:** POST to  
   `/index.php/event-matches/list/68?resetfilters=0&abc={id}&clearordering=0&clearfilters=0`  
   with form body from `#listform_68_com_fabrik_68` (`limit68`, `limitstart68`, tournament filter `value[1]`, CSRF token).
3. Mid-offset resume: GET once to seed form/token, then POST `limitstart68=offset` (do not treat seed GET as the saved page when offset≠0).
4. Validate every page: all `vw_matches___tournament_id_raw` equal `{id}` (guards ITTF `abc=`-only bug).
5. Parse with existing `extract_fabrik_list_data` → `[[dicts]]`.
6. No separate probe request — crawl starts with the real event’s list/68 first page (GET) then POST pages.
7. Direction B pacing + 429 save/exit unchanged.

## Fixtures

Under `docs/reference/` (Chrome view-source) and `testdata/list68_{get,post}.html` (reconstructed).
