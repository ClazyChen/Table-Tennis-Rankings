# ITTF Crawl Automation Design (AI-agent workflow)

**Date:** 2026-09-18
**Status:** Implemented
**Related:** `2026-08-11-ittf-rate-limit-resume-design.md` (superseded in parts)

## Problem

The 2026-08 crawl required manual babysitting: cookies pasted into the notebook,
manual re-runs after every 429, and manual proxy switching. ITTF 429 penalties
**escalate** (1h → 6h → 24h cooldowns), so the goal is to *never* hit 429;
checkpoint/resume is only a fallback.

## Root-cause note (2026-08 experience)

The August 429s were mostly caused by hitting deprecated endpoints: ITTF closed
the direct JSON endpoints (matches `list/31` / players `list/33` `format=json`)
and changed URLs. Human-speed paging through the browser UI does not trigger
alerts. Conclusion: use only current browser-UI HTML endpoints with human-like
pacing; no aggressive retry logic is needed.

## Design

### Entry point: `julia crawl.jl` (`--loop` for unattended)

1. **Login & cookies via Kimi WebBridge** (browser daemon at 127.0.0.1:10086):
   - Opens `results.ittf.link/index.php/events` in the user's real browser.
   - If a Joomla login form is present, fills `username`/`password` from
     `ittf_credentials.json` (gitignored), ticks "remember", submits.
   - Extracts fresh cookies (incl. the HttpOnly session cookie) via CDP
     `Storage.getCookies`, feeds them to the crawler and caches them back into
     `ittf_credentials.json`.
   - Fallback when the daemon is down: stored `"cookies"` in the credentials file.
2. **New-cycle discovery** (when no crawl is in progress, i.e. no
   `crawl_state.json` or `phase == "done"`):
   - Page through the events list **list/27 HTML**
     (`/index.php/events/list/27?...&limit27=100&limitstart27=N`, plain GET
     pagination) until a full page of already-known events.
   - Known ids come from `data/event_ids.json` (written by `post_crawl.jl`;
     fallback: full scan of `data/events/`).
   - New events are saved as the next raw batch `events/events_N.json`
     (`[[dicts]]`, isomorphic), and `crawl_state.json` is initialized with
     `phase=matches`, the new queue, and `match_files_from =
     next_match_file_num` so post-processing only merges files from this cycle.
   - Self-healing: events whose match pages were empty at crawl time never
     reach `data/events/` (the 11:0 filter drops empty events), so they are
     re-queued automatically on the next cycle. (This recovered 5 events that
     the 2026-08 crawl had silently skipped.)
3. **Matches** (list/68, unchanged) and **players** (list/60, unchanged),
   with `match_limit=100` (verified working in 2026-08; halves request count).

### Pacing (`PacingProfile`)

Human-like by default; tunable via `"pacing"` in `ittf_credentials.json`:

| Knob | Default |
|------|---------|
| `request_pause_min` / `max` | 20 / 60 s (uniform jitter) |
| `session_pages` | 20 pages per "browsing session" |
| `session_rest_min` / `max` | 600 / 1200 s between sessions |
| `daily_request_budget` | 1500 requests (persisted across restarts) |

Exhausting the daily budget throws `DailyBudgetExhausted`, checkpoints and
stops; `--loop` resumes the next morning.

### Fallback (`--loop`)

`run_crawl!` records `stop_reason` (`rate_limited` / `player_failed` /
`daily_budget` / `login_wall` / `done`) and `retry_after` in `crawl_state.json`.
In `--loop` mode `crawl.jl`:

- `login_wall` (session expired, happens roughly hourly): refresh cookies via
  WebBridge and resume immediately — no wait, no 429 risk. Handled in
  single-pass mode too (via `with_login_retry` / the loop).
- `rate_limited`: waits `max(retry_after, 3600)s` + jitter, optionally runs
  `switch_proxy_command` (credentials) to rotate the exit IP, refreshes cookies
  via WebBridge, resumes.
- `daily_budget`: sleeps until 06:00 next day + jitter.
- `player_failed`: waits ~30 min + jitter.

Single-pass mode (no `--loop`) keeps the old checkpoint-and-exit behavior
(except for login walls, which are always auto-refreshed).

## Field findings (2026-09-18)

1. **Session cookies expire after roughly an hour.** The browser stays logged
   in (remember-me), so WebBridge can always mint a fresh session cookie.
   Reactive refresh on `LoginWall` is sufficient.
2. **Fabrik pagination state bleeds across events server-side.** A previous
   event's `limitstart68` can land a new event's first GET on a middle page —
   or beyond its end ("No records"), which the old code treated as "event
   complete", silently dropping the event. (This is why 5 events from the
   2026-08 cycle never made it into `data/events`.) Fixes: `limitstart68=0` is
   pinned on every first-page GET, and `fetch_event_matches_html` validates the
   "Page X of Y Total: Z" footer at offset 0 (page must be 1; empty rows with
   Total > 0 is an error, never "complete").
3. `abc={event_id}` on list/68 URLs appears to be required for access (URLs
   without it bounce to a login-wall-like template page) — keep it.

## Field findings (2026-09-19): the 429 limiter

1. **The limiter discriminates by client fingerprint, not just IP/account.**
   Manual browsing from the same account and same home IP never hit 429 while
   the crawler did. The crawler's tells were: a static 2023-era Chrome/120 UA,
   no client-hint/Sec-Fetch/Accept-Language headers, `Connection: close`, and
   an extra `vw_profiles___Name_raw` filter param that manual profile browsing
   does not send. Fixes: crawl.jl syncs `navigator.userAgent` from the real
   browser via WebBridge (`set_user_agent!` derives matching `sec-ch-ua*`
   brands, incl. Microsoft Edge), browser-like headers are sent on every
   request, `Connection: close` is gone, and list/60 URLs no longer carry the
   Name param.
2. **Once flagged, pacing cannot save you.** After a 429, resuming from the
   same identity (even after the full Retry-After, even at half speed)
   re-tripped 429 quickly with an escalated penalty — the strike state does
   not fully reset. The escape hatch is a *new identity*: route Julia traffic
   through a proxy (`"proxy": "http://127.0.0.1:7897"` in
   `ittf_credentials.json`) whose exit IP has no strike history. Verified:
   session cookies are not IP-bound (browser on home IP + crawler via proxy
   exit works, no login wall).
3. Pacing still matters as prevention on the fresh identity; the
   wait-Retry-After path in `--loop` remains only as a last-resort fallback.
4. **The penalty is per exit IP, not per account.** With the proxy +
   fingerprint fixes live, the crawler still tripped 429 after ~8 requests
   (twice; 1h → 6h ladder restarted on the new IP). Two probes during the
   penalty window settled it: the real browser (same exit IP, system proxy
   on) saw the same 429 page, and a *guest* curl with no cookies through the
   proxy also got 429 + Retry-After. So a flagged IP is blocked regardless of
   login state. A fresh exit node (not a fresh account) is the reset button;
   shared VPN exits may arrive pre-polluted. Do not probe during a penalty —
   requests appear to extend it.
5. **list/60 now uses the array-style filter** `vw_profiles___player_id_raw[value][]=<id>`
   (same shape as list/68's tournament filter). The plain `=<id>` form also
   worked, but the matches crawl has a long track record of the array form
   being unproblematic, so we standardized on it (user's call, 2026-09-19).

## Non-goals

- No in-process immediate retry on 429 (penalties escalate — wait fully).
- No proxy pools / multi-account rotation beyond the optional switch hook.

## Verification

- Offline: `testdata/test_events27.jl` (fixture `testdata/events27.html`,
  captured via browser 2026-09-18), plus the existing list/68, list/60,
  extract, bootstrap suites.
- Live smoke test 2026-09-18: login check, cookie refresh (5 ITTF cookies),
  events discovery (26 new events → `events_48.json`), matches crawl started.
