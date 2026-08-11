# ITTF Rate-Limit Resume Crawl Design

**Date:** 2026-08-11  
**Status:** Approved  
**Related:** `2026-08-11-ittf-html-match-player-design.md`

## Problem

ITTF returns HTTP **429** under sustained crawling. The notebook download loops only used short `sleep` retries and kept progress in memory, so a mid-run failure (or kernel restart) cannot safely continue. A partial run on 2026-08-11 already wrote new files before 429.

## Goals

1. Auto-login with username/password from a gitignored credentials file; refresh session cookies.
2. On 429: persist checkpoint → wait **1 hour** by default **or** exit after saving (`exit_on_429`); then re-login and continue.
3. Pause/resume for **events**, **matches**, and **players** across multiple rounds until `phase=done`.
4. Bootstrap the first resume from **existing on-disk files** (option A: keep partial event pages, resume mid-offset).

## Non-Goals

- Browser automation / proxy pools / multi-account rotation.
- Changing rating algorithms or ITTF JSON isomorphism rules.

## Architecture

```
ittf_credentials.json          # gitignore — username/password
ittf_credentials.example.json  # committed template
crawl_state.json               # gitignore — checkpoint
ittf_fabrik.jl                 # login, HTTP wrapper, 429, checkpoint, crawl orchestration
ccelo.ipynb                    # run_crawl!(...; exit_on_429=false, wait_seconds=3600)
```

### Checkpoint fields

- `phase`: `events` | `matches` | `players` | `done`
- `event_offset`: pagination for event list JSON
- `match_event_ids`: ordered queue of tournament ids still needed
- `match_event_index` / `event_id`: current tournament
- `match_offset`: `limitstart31` for current tournament
- `pending_player_ids`: remaining player ids
- `updated_at`

### 429 path

1. Detect HTTP 429 (optional: 503 + `Retry-After`).
2. Write `crawl_state.json`.
3. If `exit_on_429`: return status to caller.
4. Else `sleep(wait_seconds)` (default 3600), `login!()`, resume same phase.

### Login

1. Read `ittf_credentials.json`.
2. GET login page → extract form tokens → POST credentials.
3. Store cookies in module session used by all requests.
4. Login wall on 200 HTML: one re-login then retry; still failing → stop (do not sleep 1h).

### Per-phase resume

| Phase | Progress | Skip if |
|-------|----------|---------|
| events | `event_offset` | already have newer event batches as configured |
| matches | `event_id` + `match_offset` + queue | empty page ends event; advance queue |
| players | `pending_player_ids` | `players/{id}.json` exists and parses |

### Bootstrap from disk (2026-08-11 partial run) — Option A

Observed:

- `events_47.json`: 19 new events (complete).
- Matches `8885`–`8921`: events through `3364` complete.
- Matches `8922`–`8930`: tournament **3366**, 9×100 = **900** matches; last page full → next **`match_offset=900`**.
- Remaining event ids after/including 3366:  
  `3366, 3492, 3319, 3392, 3449, 3363, 3318, 3305`
- Players: no new files today → after matches, build pending ids from new events’ matches.

**Action:** keep `8922`–`8930`; write initial `crawl_state.json` with `phase=matches`, `event_id=3366`, `match_offset=900`, queue as above. Do **not** re-download completed tournaments in that queue prefix.

## Notebook API

```julia
include("ittf_fabrik.jl")
using .ITTFFabrik
result = run_crawl!(; exit_on_429=false, wait_seconds=3600)
# when result.phase == :done → merge / ranking cells
```

Support `wait_seconds=2` for tests. Credentials never committed.

## Verification

1. Bad credentials → clear failure.
2. Forced 429 / short `wait_seconds` → checkpoint written → resume continues.
3. Kill process → restart `run_crawl!` resumes from `crawl_state.json`.
4. Bootstrap state matches disk (3366 @ 900).
5. Match files remain `[[dicts]]` isomorphic.
