# ITTF Rate-Limit Resume Crawl Design

**Date:** 2026-08-11  
**Status:** Approved (revised: cookie-only + direction B)  
**Related:** `2026-08-11-ittf-html-match-player-design.md`

## Problem

ITTF returns HTTP **429** under sustained crawling. The notebook download loops only used short `sleep` retries and kept progress in memory, so a mid-run failure (or kernel restart) cannot safely continue. A partial run on 2026-08-11 already wrote new files before 429.

## Goals

1. **Manual one-time cookies** from a logged-in browser (no automatic login / no password file in the crawl path).
2. **Direction B pacing:** long pause between requests, smaller match pages, periodic batch rest; on **429 save checkpoint and exit** (caller waits / changes IP, then re-runs).
3. Pause/resume for **matches** and **players** until `phase=done` (events already completed for the 2026-08-11 partial run).
4. Bootstrap the first resume from **existing on-disk files** (option A: keep partial event pages, resume mid-offset).

## Non-Goals

- Automatic username/password login (removed — unreliable against ITTF/Joomla session).
- In-process sleep-for-hours on 429 / auto re-login loops.
- Browser automation / proxy pools / multi-account rotation.
- Changing rating algorithms or ITTF JSON isomorphism rules.

## Architecture

```
crawl_state.json               # checkpoint (may be tracked for resume bootstrap)
ittf_fabrik.jl                 # cookie session, HTTP wrapper, 429 exit, crawl orchestration
ccelo.ipynb                    # COOKIES cell → set_session_cookies! then run_crawl!(...)
```

### Checkpoint fields

- `phase`: `events` | `matches` | `players` | `done`
- `event_offset`: pagination for event list JSON (legacy / unused if events done)
- `match_event_ids`: ordered queue of tournament ids still needed
- `match_event_index` / `event_id`: current tournament
- `match_offset`: `limitstart68` for current tournament (list/68; never list/31)
- `next_match_file_num`: next `matches_N.json`
- `pending_player_ids`: remaining player ids
- `updated_at`

### Defaults (direction B)

| Knob | Default |
|------|---------|
| `request_pause` | 8 s |
| `match_limit` | 50 |
| `batch_every` | 5 pages |
| `batch_rest` | 180 s |

### 429 path

1. Detect HTTP 429 or 429 HTML body (`too many requests` / `var remaining = …`).
2. Write `crawl_state.json`.
3. **Return** to caller (no sleep, no re-login).
4. Operator waits and/or **changes exit IP**, refreshes cookies if login wall, re-runs `run_crawl!`.

### Session

1. Paste cookies into notebook `COOKIES` cell.
2. `set_session_cookies!(COOKIES)` → module `SESSION`.
3. Crawl starts directly on list/68 for the checkpoint event (no separate probe).
4. Login wall on 200 HTML → hard error (refresh cookies); do not treat as 429 wait.

### Per-phase resume

| Phase | Progress | Skip if |
|-------|----------|---------|
| matches | `event_id` + `match_offset` + queue | empty page ends event; advance queue |
| players | `pending_player_ids` | `players/{id}.json` exists and parses |

### Bootstrap from disk (2026-08-11 partial run) — Option A

Observed:

- `events_47.json`: 19 new events (complete).
- Matches `8885`–`8921`: events through `3364` complete.
- Matches `8922`–`8930`: tournament **3366**, 9×100 = **900** matches; last page full → next **`match_offset=900`**.
- Remaining event ids after/including 3366:  
  `3366, 3492, 3319, 3392, 3449, 3363, 3318, 3305`
- Players: no new files that day → after matches, build pending ids from new events’ matches.

**Action:** keep `8922`–`8930`; write initial `crawl_state.json` with `phase=matches`, `event_id=3366`, `match_offset=900`, queue as above. Do **not** re-download completed tournaments in that queue prefix.

## Notebook API

```julia
include("ittf_fabrik.jl")
using .ITTFFabrik
set_session_cookies!(COOKIES)
bootstrap_crawl_state_from_disk!(; force=false)
result = run_crawl!()           # 429 → saves and returns
# when result["phase"] == "done" → merge / ranking cells
```

Never commit real cookies from the notebook.

## Verification

1. Missing/bad cookies → login-wall / empty SESSION failure on first real request.
2. Forced 429 → checkpoint written → process exits; re-run continues.
3. Kill process → restart `run_crawl!` resumes from `crawl_state.json`.
4. Bootstrap state matches disk (3366 @ 900).
5. Match files remain `[[dicts]]` isomorphic.
