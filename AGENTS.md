# AGENTS.md — Table Tennis Rankings

## Project overview

This repository computes an alternative world ranking for table tennis singles (men's and
women's), based on match data scraped from the ITTF results site (`https://results.ittf.link`).
The algorithm is a heavily modified ELO that the author claims predicts match outcomes with
>75% accuracy, better than the official ITTF ranking. Monthly rankings are produced from
January 2004 to the present (earlier data is not available from ITTF) and rendered as
Typst documents (then compiled to PDF).

There is no library or service here — the deliverables are the ranking files themselves:
`history/YYYY/{MS,WS}-MM.typ` (monthly top-200 snapshots), `history_CN/` (Chinese versions),
and `MS-latest.typ` / `WS-latest.typ` (current top-1000) plus their compiled PDFs at the
repository root.

## Technology stack

- **Julia** is the main language (Julia 1.12). Dependencies: `HTTP`, `JSON`,
  `Gumbo`, `Cascadia` (HTML parsing), `Distributions`, plus stdlib `Dates`.
  **There is no `Project.toml`/`Manifest.toml`** — packages are installed into the global
  Julia environment (see `testdata/_install_deps.jl`: `Pkg.add(["Gumbo", "Cascadia", "JSON", "HTTP"])`).
- **Typst** renders rankings to PDF (`typst compile MS-latest.typ` etc.). Templates
  `template.typ` / `template_CN.typ` define colored helpers (`#age`, `#delta`, `#assoc`, ...)
  and embed flag images from `data/flags/<ASSOC>.png`.
- **Python** appears only in ad-hoc tooling under `testdata/` (e.g. notebook patching,
  fixture decoding); the product code is Julia.

## Code organization

The former Jupyter notebook (`ccelo.ipynb`) has been split into plain Julia modules
under `src/`; its explanatory markdown now lives in `docs/algorithm.md`.

- `src/structures.jl` — `Match`/`Event`/`Player` structs, processed-data I/O
  (`read_events_from_files`, `read_players_from_file`, `save_*`), merging,
  association-history updates, and the 11:0/0:11 filter.
- `src/weights.jl` — event weights (`match_weight`/`weight` dispatch) and match
  weights (`WEIGHT_MAP` via normal-CDF, `result_to_weight`).
- `src/ittf_convert.jl` — raw ITTF JSON → structs (`convert_ittf_event/match`,
  `parse_player_data`) and loading freshly crawled batches
  (`load_events_batch`, `load_crawled_matches_into_new_events!`,
  `load_new_players_from_disk`, `merge_players!`).
- `src/rating.jl` — the algorithm core: constants, `update_rating`, `Period`,
  `compute_active_periods`, `compute_rankings`. **Include order matters**:
  `rating.jl` (which defines `Period`, shadowing `Dates.Period`) must be included
  before `src/typst_output.jl`.
- `src/typst_output.jl` — `ranked_active_players`/`player_assoc_on_date` (shared with
  the web exporter), `save_rankings` (Typst writer) and
  `translate`/`translate_all` (Chinese versions, uses `translate.txt`).
- `src/web_export.jl` — collects monthly ranking rows and per-player rating series
  during the `compute_rankings` replay (via its `on_month`/`on_latest` callbacks) and
  writes the compact JSON bundles for the static site into `web/data/`
  (`index.json`, `latest.json`, `rankings/MS|WS-YYYY-MM.json`,
  `history/shard-XX.json` by `id % 64`, `search.json`, `flags/`). Each shard entry's
  series ends with a final-rating point (so the chart endpoint matches the player's
  current/final rating, including retired players) and its meta carries that final
  rating as the last field.
- `src/ittf_fabrik.jl` — module `ITTFFabrik`: the ITTF crawler. Session cookies come
  from the browser via Kimi WebBridge (auto-login with `ittf_credentials.json`
  username/password; fallback to its stored `"cookies"`), HTTP proxy via
  `set_proxy!` (off by default). Matches use the Fabrik **list/68** endpoint
  (GET first page, POST pagination, page size 100; **never list/31**). Players
  use **list/60** (`/index.php/player-profile/list/60?...vw_profiles___player_id_raw=<id>`;
  **never list/33**). Events are discovered via **list/27 HTML**
  (`/index.php/events/list/27?...&limitstart27=N`, plain GET pagination; the JSON
  variant is blocked). Pacing is human-like by design (`PacingProfile`: jittered
  20–60 s pauses, a 10–20 min rest every 20 pages, daily request budget persisted
  in `crawl_state.json`) because **ITTF 429 penalties escalate** — the goal is to
  never hit one. On 429 / budget / failure it checkpoints `stop_reason` +
  `retry_after` into `crawl_state.json` and exits.
- `crawl.jl` — one-command crawl entry: WebBridge login + cookie refresh, then
  (when no crawl is in progress) `start_new_cycle!` pages list/27 and diffs
  against `data/event_ids.json` to queue only new events, then `run_crawl!`.
  `--loop` = unattended mode: waits out 429 (`retry_after`, ≥1 h + jitter,
  optional `switch_proxy_command`) and daily budgets, then resumes.
- `post_crawl.jl` — standalone post-processing script, run after the crawl reaches
  `phase == "done"`: `julia post_crawl.jl` (or `--skip-ranking`). It merges the freshly
  crawled events/matches/players into the processed store (only `matches_N.json`
  files from `match_files_from` onward), filters events where every match
  is 11:0 / 0:11, updates association history, recomputes all rankings, writes the
  `.typ` outputs, refreshes `data/event_ids.json`, exports the web data bundles
  (`web/data/`), and regenerates the Chinese translations (`history_CN/`, `*_CN.typ`).
- `tools/rebuild_from_raw.jl` — one-off utility: reload everything from the raw
  ITTF dumps (the former notebook appendix).
- `template.typ`, `template_CN.typ` — Typst templates imported by every generated ranking.
- `translate.txt` — comma-separated `English name, 中文名` mapping used by the `translate()`
  function to produce the `history_CN/` and `*_CN.typ` files.
- `docs/algorithm.md` — the ranking-algorithm and data-format documentation
  (extracted from the old notebook).
- `docs/superpowers/specs/` — design documents for the 2026 rate-limit-resilient crawl
  (list/68 matches, list/60 players, 429 pause/resume). Read these before touching the crawler.
- `docs/reference/` — saved ITTF HTML pages used as offline fixtures.
- `testdata/` — offline assertion scripts (`test_*.jl`, see Testing) with their HTML
  fixtures, plus `testdata/_install_deps.jl` (installs the Julia dependencies) and
  `bench_pipeline.jl` (pipeline read/parse benchmark). `test_login.jl` is a live-network
  smoke test for the crawler login (not part of the offline suite).
- `web/` — the static ranking site (zero-dependency vanilla JS: `index.html`, `app.js`,
  `style.css`; hash routing `#/MS|WS/YYYY-MM`, `#/player/<id>`; EN/CN toggle; Typst color
  palette for hand/grip/style/age; month timeline slider + big side prev/next buttons;
  "back to rankings" returns to the source ranking via `sessionStorage`). `web/data/`
  is generated by `post_crawl.jl` (do not hand-edit). **Live at
  https://clazychen.github.io/Table-Tennis-Rankings/**: deployed by
  `.github/workflows/pages.yml` on every push touching `web/**` (Pages source =
  GitHub Actions, already configured in the repo settings).

## Data layout

Two formats coexist:

- **Raw ITTF format** (gitignored due to size — do not commit): `events/events_N.json`
  (event batches), `matches/matches_N.json` (~9000 files, one batch of match pages each),
  `players/<player_id>.json` (~32000 files).
- **Processed format** (committed): `data/events/YYYYMMDD.json` (events with their matches,
  one file per day), `data/players.json` (single array of all players with id, name, sex,
  yob, hand, grip, style, association `history`), `data/flags/*.png`.
  `data/event_ids.json` (gitignored, derived) caches the known event-id set for
  crawl-cycle discovery; `post_crawl.jl` rewrites it after each merge.

`crawl_state.json` is the crawler checkpoint (gitignored): tracks current event id/offset,
match file numbering (`next_match_file_num`, `match_files_from`), pending player ids,
`phase`, `stop_reason`/`retry_after`, and daily-budget counters. Rankings are only
recomputed when `phase == "done"`.

## The ranking algorithm

Full math spec: `docs/algorithm.md`. Implemented in `src/rating.jl`
(`update_rating`, constants `W=50, D1=D2=1000, D3=250, r0=1500 (initial),
rc=3000 (ceiling), α=0.25, β=0`). On top of classic ELO it adds:

- event weight (`match_weight` dispatch on event type/name, e.g. Olympic Games = 3.0) and
  match weight derived from the game score (`WEIGHT_MAP`); weights are doubled for matches
  before 2004-01-01 and again before 2010-01-01;
- "centripetal force" steps that dampen rating changes near the floor/ceiling and relative
  to the opponent's rating;
- a "long jump" step (α/β) when a result would cross the opponent's rating.

`compute_rankings` replays all events chronologically, writing a monthly snapshot
(`history/YYYY/{MS,WS}-MM.typ`, top 200 active players) before each month's events, and
finally `MS-latest.typ` / `WS-latest.typ` (top 1000). Player "active periods"
(`compute_active_periods`) gate who appears in a snapshot.

## Build and test commands

There is no build system and no formal test suite.

- Full pipeline: `julia crawl.jl` (crawl; requires `ittf_credentials.json`, may take
  days due to deliberate pacing; re-run to resume after 429), then
  `julia post_crawl.jl` from the repo root (`--skip-ranking` to only merge data).
- Offline tests (no network): `julia testdata/test_list68.jl`,
  `julia testdata/test_list60_player.jl`, `julia testdata/test_extract.jl`,
  `julia testdata/test_crawl_bootstrap.jl`, `julia testdata/test_events27.jl`.
  These are plain `@assert` scripts that parse HTML fixtures from `testdata/`
  and `docs/reference/`; a clean exit with no assertion error means pass.
- Compile a ranking PDF: `typst compile MS-latest.typ` (needs the flag PNGs in `data/flags/`
  and a font setup providing Cascadia Mono / Microsoft YaHei).
- Preview the website locally: `python -m http.server 8000 -d web` → `http://localhost:8000`.

## Development conventions

- Comments and documentation are primarily in English; a few Chinese comments exist
  (e.g. the translate step and the 11:0 filter). Match the surrounding style.
- The crawler is deliberately conservative: ITTF 429 penalties escalate, so pacing aims to
  *never* trigger one (human-like jitter, session breaks, daily budget). On 429 always
  checkpoint-and-exit; unattended resume (`crawl.jl --loop`) waits the full server-suggested
  `Retry-After` before continuing — never retry immediately.
- Git history shows ranking-update commits with short date messages (e.g. `260707`).

## Security considerations

- **Never commit credentials or crawl state**: `ittf_credentials.json` (now including the
  ITTF username/password for WebBridge auto-login) and `crawl_state.json` are gitignored;
  cookies are refreshed into `ittf_credentials.json` automatically by `crawl.jl`.
- Raw scrape directories (`events/`, `matches/`, `players/`, `data/*.json`) are gitignored
  because of size, not secrecy — but do not force-add them.
- ITTF actively rate-limits (HTTP 429) with escalating penalties. The crawler uses only
  current browser-UI HTML endpoints (events list/27, matches list/68, players list/60)
  with human-like pacing; treat any 429 as a signal to slow down, not to retry.
