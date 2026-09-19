# ELO Rating Algorithm and Data Formats

*Extracted from the original `ccelo.ipynb` notebook. This document describes the data
formats and the ranking algorithm; the code lives in `src/` and the pipeline entry
points are `crawl.jl` and `post_crawl.jl`.*

## ITTF raw formats

### event.json
Each `event.json` is formatted as `[[dicts]]`, where in each dict:
- `vw_tournaments___id_raw` -> uid
- `vw_tournaments___tournament_id_raw` -> id
- `vw_tournaments___yr_raw` -> year
- `vw_tournaments___tournament_raw` -> name
- `vw_tournaments___type` -> type
- `vw_tournaments___kind` -> kind
- `vw_tournaments___organizer` -> organizer
- `vw_tournaments___tour_start_raw` -> start (YYYY-MM-DD)
- `vw_tournaments___tour_end_raw` -> end (YYYY-MM-DD)

### match.json
Each `match.json` is formatted as `[[dicts]]`, where in each dict:
- `vw_matches___id_raw` -> id
- `vw_matches___tournament_id_raw` -> event_id
- `vw_matches___tournament_id` -> event_name (ITTF's terrible naming)
- `vw_matches___player_a_id_raw` -> player_a_id
- `vw_matches___name_a_raw` -> player_a_name (can also be looked up with id)
- `vm_matches___assoc_a` -> player_a_assoc (when this event took place)
- `vm_matches___player_b` -> for MD, WD, XD, the partner of player_a
- `vm_matches___player_x` -> the opponent of player_a
- `vm_matches___player_y` -> for MD, WD, XD, the partner of player_x
- `vm_matches___stage_raw` -> Qualification, R32, R16, QF, SF, F
- `vm_matches___res_raw` -> the result of the match, formatted "A - X"
- `vm_matches___games_raw` -> the results of each game, formatted "A-X A-X A-X" (may have 0:0 or space suffix)

### player.json
Each `player.json` is formatted as `[[dicts]]`, where in each dict:
- `vw_profiles___player_id_raw` -> id
- `vw_profiles___player_id` -> "name (assoc)"
- `vw_profiles___name_raw` -> "name (#id)"
- `vm_profiles___gender_raw` -> M / W
- `vm_profiles___assoc_raw` -> association (at present)
- `vm_profiles___profile_raw` -> HTML snippet parsed for YoB, hand, style, grip,
  e.g. `"<img src='.../flags/USA.png' ...><br/>MA: USA<br/>Gender: Male<br/>YoB: 1991<br/>Style: Left-Hand Attack (ShakeHand)<br/>..."`

## Downloading ITTF files

Downloading the full ITTF dataset (>1 GB) takes time; you only need it to build a
different ranking. To consume this project's output, the processed format in `data/`
is enough.

To crawl:
- Log in to the ITTF website in your browser, then export your cookies into
  `ittf_credentials.json` (gitignored — see `crawl.jl` for the format).
- Run `julia crawl.jl`. Matches are fetched via the Fabrik **list/68** endpoint
  (GET first page, POST pagination; **never list/31**), players via **list/60**
  (**never list/33**). Match `format=json` is blocked (403), so the crawler fetches
  HTML and extracts the embedded Fabrik data into the same `[[dicts]]` shape.
- Pacing is deliberately slow: ~8 s between requests, page size 50, ~3 min rest
  every 5 pages. On HTTP 429 the crawler saves `crawl_state.json` and exits;
  wait or change exit IP, then re-run `julia crawl.jl` to resume.
- Set `"proxy"` in `ittf_credentials.json` when Clash/V2 is on — Julia does not
  follow the browser proxy.

## Processed format ("my format")

All redundant ITTF fields are removed. The processed data lives in two places:
matches grouped by end-date in `data/events/YYYYMMDD.json`, and all players in a
single `data/players.json`.

Only singles matches (MS/WS) are recorded: the algorithm is not suitable for
doubles. Table tennis differs from badminton in that two strong players can always
form a strong pair even without having played together — e.g. SUN Yingsha and
KUAI Man could beat many pairs, yet that pair has no ELO rating at all.

### format of events
- `id`
- `name`
- `weight` (from the category)
- `time` (the end-date in YYYYMMDD, same as the filename)
- `match` (list)
  - `player_a_id`
  - `player_x_id`
  - `weight` (computed from the result)
  - `result` (in "A:X")
  - `games` (in "a:x a:x a:x")

The algorithm does not take per-game results into account: table tennis is an
11-point game, and at 6:0 / 7:0 many players "abandon" the game to conserve
stamina or play more aggressively to probe the opponent. An 11:1 does not imply
a huge strength gap.

### format of players
- `id`
- `name`
- `sex` (M/W)
- `history` (list) (for players who changed association, like ZHU Yuling)
  - `until`
  - `assoc`
- `yob` (year of birth)
- `hand` (left or right)
- `style` (attack or defence)
- `grip` (shakehand or penhold)

### Performance note (measured 2026-09-19, `testdata/bench_pipeline.jl`)

The per-date file split is NOT a bottleneck: reading all ~1450 files (167 MB)
takes 0.4 s, parsing 1.5 s, building structs 3.1 s; a full `post_crawl.jl` run
is dominated by Julia startup/JIT (~30 s) and the CN translation step (~7 s).
Incremental updates only rewrite the files of modified dates, so the format
stays as-is. Web-friendly exports are a separate concern (Phase D).

## Directory structure

Raw ITTF files (not uploaded to GitHub):
- events: `events/events_xxx.json` (`xxx = 0, 1, 2, ...`)
- matches: `matches/matches_xxx.json`
- players: `players/[playerid].json`

Processed files:
- events (with matches): `data/events/YYYYMMDD.json`
- players: `data/players.json`

## Workflow

1. Load local processed files.
2. Update data (crawl the ITTF website — `julia crawl.jl`).
3. Merge and store (`julia post_crawl.jl`).
4. Run the algorithm to generate rankings, then translate to Chinese.

If you do not want to update data (e.g. you use your own data instead of ITTF
data), skip steps 2–3.

## Event weights

The **weight** of an event is computed from its type. Major events are more
intense and receive greater attention from players — many use regular WTT events
as practice while giving their all in majors. ITTF/WTT points also matter. The
weights below balance both aspects. (Due to limited understanding of historical
events, these weights may not be sufficiently reasonable and may be optimized in
the future.)

| Event Type                          | Weight |
| ----------------------------------- | ------ |
| Olympic Games                       |   3.0  |
| World Championships                 |   2.5  |
| World Cup                           |   2.0  |
| Asian/European Games                |   1.6  |
| Asian/European Championships        |   1.5  |
| Asian/European (Top-16) Cup         |   1.5  |
| ITTF/WTT Finals                     |   1.5  |
| WTT Grand Smash                     |   1.4  |
| WTT Champions & ITTF Platinum Open  |   1.3  |
| WTT Star Contender & ITTF Open      |   1.2  |
| WTT Contender & ITTF Challenge Plus |   1.1  |
| WTT Feeder & ITTF Challenge         |   1.0  |

The full dispatch logic (including youth-event reductions and special cases)
lives in `src/weights.jl`.

## Match weights

The **weight** of a match is computed from the number of games won by each
player, via a normal distribution (`1 - 2·cdf(Normal(0, 2/√w), -(w-l)/2)`).
Approximate values:

| W / L |   3  |   2  |   1  |   0  |
| ----- | ---- | ---- | ---- | ---- |
|   4   | 0.38 | 0.68 | 0.87 | 0.95 |
|   3   |      | 0.33 | 0.61 | 0.81 |
|   2   |      |      | 0.28 | 0.52 |
|   1   |      |      |      | 0.20 |

## The ranking algorithm

This algorithm is based on classic ELO with two modifications, both implemented
with sigmoid-like functions.

Table tennis has its uniqueness compared to other rated sports such as tennis
and chess. One main challenge is that WTT events lack sufficient influence:
some players do not regard them as their most important professional activity,
since they can compete in high-level domestic events in China, Japan, and
elsewhere. Some players barely participate in open events yet maintain a very
high level through in-team training. For example, FAN Siqi entered only one WTT
event (China Smash) in 2024, but there she defeated WANG Yidi, CHENG I-Ching,
and MORI Sakura. Another challenge is the extreme dominance of top players:
during peak periods they enter many events with win rates above 90%, so their
ratings inflate; when their level declines with age or injury, they play fewer
events and the rating does not drop fast enough. (WTT's one-year point expiry
mitigates the latter; it would be better still if WTT could encourage top
players to attend more events.)

**The first modification is "long jump".** In classic ELO, a lower-rated player
(e.g. HARIMOTO Tomokazu) beating a much higher-rated one (e.g. MA Long) gains
only a limited number of points, so a talented newcomer stays ranked below their
publicly recognized level for a long time. An extreme case is KIM Kum Yong, who
beat SUN Yingsha, WANG Yidi, and HARIMOTO Miwa at the Asian Championships but
stayed low in the WTT ranking because she played no WTT events. The long jump
lets such players converge quickly, with a magnitude depending on the opponent's
current rating. It occasionally inflates some players (e.g. TANAKA Yuta), but
since KIM Kum Yong-like situations occur more often, the benefits outweigh the
drawbacks.

**The second modification is "centripetal force".** A higher-rated player finds
it harder to gain points and easier to lose them, especially when losing to a
much lower-rated opponent. This reins in top-player inflation and lets ratings
"fall to earth" when performance declines. It also balances the positive-sum
point changes introduced by the long jump with a negative-sum factor.

The algorithm predicts match outcomes after 2018-01-01 with about **76%**
accuracy, versus about 66% for WTT's point rules. *Note:* predictive accuracy is
not the sole criterion for a ranking system — some higher-accuracy variants
cause drastic ranking fluctuations that make the ranking useless as a reference,
so they are not valid ranking algorithms.

### update_rating

Inputs:
- $r_1$: rating of player 1 before the match.
- $r_2$: rating of player 2 before the match.
- $w_m$: weight of the match.
- $w_e$: weight of the event.

Outputs:
- $r'_1$, $r'_2$: ratings after the match.

Algorithm (take $r_1 \to r'_1$ as an example):

1. ELO expectation $e_1 = \frac{1}{1 + 10^{(r_1 - r_2)/D_1}}$.
2. Raw delta $\Delta_1 = w_m \times w_e \times W \times (a_1 - e_1)$, where $a_1$
   is 1 when player 1 wins and 0 when player 1 loses.
3. Centripetal force:
   - If $a_1 = 0$, $\Delta'_1 = \Delta_1 \times \frac{2}{1 + 10^{-(r_1 - r_0)/D_2}}$ ($r_0$ = default rating).
   - If $a_1 = 1$, $\Delta'_1 = \Delta_1 \times \frac{2}{1 + 10^{(r_1 - r_c)/D_2}}$ ($r_c$ = ceiling rating).
4. Centripetal force (by opponent):
   - If $a_1 = 0$, $\Delta''_1 = \Delta'_1 \times \frac{2}{1 + 10^{-(r_1 - r_2)/D_3}}$.
   - If $a_1 = 1$, $\Delta''_1 = \Delta'_1 \times \frac{2}{1 + 10^{(r_1 - r_2)/D_3}}$.
5. Result: $r'_1 = r_1 + \Delta''_1$.
6. Long jump (no "long fall", i.e. $\beta = 0$):
   - If $r_1 < r'_1 < r_2$, $r'_1 = r'_1 + \alpha \times (r_2 - r'_1)$.
   - If $r_1 > r'_1 > r_2$, $r'_1 = r'_1 + \beta \times (r_2 - r'_1)$.

Parameters (fine-tuned on ITTF/WTT data):

|  $W$  |  $D_1$  |  $D_2$  |  $D_3$  |  $r_0$  |  $r_c$  |  $\alpha$  |  $\beta$  |
| ----- | ------- | ------- | ------- | ------- | ------- | ---------- | --------- |
|   50  |  1000   |  1000   |   250   |  1500   |  3000   |    0.25    |    0      |

Match weights are doubled for matches before 2004-01-01, and doubled again
before 2010-01-01 (`date_0`/`date_1` in `src/rating.jl`).

### Active periods

A player who has not played any ITTF/WTT event for at least 1,000 days is deemed
inactive for that period. Inactive players do not appear in the output rankings.

### Typst output

Rankings are rendered as Typst files: monthly snapshots in
`history/YYYY/{MS,WS}-MM.typ` (top 200, 25 players per page) and current
top-1000 lists in `MS-latest.typ` / `WS-latest.typ`. Templates live in
`template.typ` / `template_CN.typ`; Step 4.5 (`translate_all()`) produces the
Chinese versions in `history_CN/` and `*_CN.typ` using `translate.txt`.
