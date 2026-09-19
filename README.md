<h1>Table Tennis Rankings</h1>

This repository demonstrates an excellent table tennis international ranking algorithm that better reflects the actual competitive level of table tennis players compared to the simple ELO algorithm and the new ranking method used by ITTF after January 1, 2018. The algorithm uses data provided on the ITTF official website and is modified based on the ELO algorithm to make the results more consistent with the situation of table tennis.

<b>The accuracy of the models in this repository for predicting women's singles matches is >76%, and for men's singles matches is >75%</b>, far higher than the international ranking of the ITTF.

This repository provides world rankings from January 2004 to today. Earlier rankings cannot be calculated because the ITTF does not provide relevant data.
All rankings use Typst, which you can easily convert to pdf files.

There is also a bilingual (EN/CN) static website in `web/`: monthly MS/WS ranking tables plus per-player rating-history pages. It is deployed to GitHub Pages (`.github/workflows/pages.yml`); preview locally with `python -m http.server 8000 -d web`.

This repository includes men's singles ranking and women's singles ranking. You can see the changes of top players in the past twenty years: from Wang Liqin, Ma Lin, Wang Hao, Zhang Jike, Ma Long, Fan Zhendong to Wang Chuqin; from Zhang Yining, Guo Yue, Li Xiaoxia, Ding Ning, Liu Shiwen, Chen Meng to Sun Yingsha.

You are welcome to provide suggestions for improving the algorithm model or the display form of the ranking.

<h1>How to use</h1>

The code is written in Julia. The ranking algorithm and data formats are documented in `docs/algorithm.md`; the implementation lives in `src/` as plain modules.

- `julia crawl.jl` — crawl new events/matches/players from the ITTF website (requires `ittf_credentials.json`; logs in via the browser automatically; resumes from `crawl_state.json` after HTTP 429).
- `julia post_crawl.jl` — after the crawl reaches `phase == "done"`: merge into the processed data, recompute all rankings, export the web data bundles (`web/data/`), and generate the Chinese translations.
- `typst compile MS-latest.typ` — render a ranking to PDF.

<h1>Notice</h1>

**In August 2026, ITTF blocked direct access to match data via JSON format. Frequent GET-URL requests will trigger 429 rate-limit penalties.**

As a networking engineer, I fully understand many fans are dissatisfied with the current world rankings and want to scrape ITTF data for statistics, which has put heavy load on ITTF's servers.

Around the WTT Champions Yokohama 2026, I implemented certain workarounds for the 429 restrictions. However, I'm not sure whether these workarounds will survive the next update ahead of the WTT Swedish Smash 2026.

The crawler code now lives in `src/ittf_fabrik.jl` (entry point: `crawl.jl`). It is deliberately slow and conservative: on HTTP 429 it checkpoints to `crawl_state.json` and exits instead of retrying aggressively — running it carelessly will still get your IP penalized. **Rankings have been updated up to the present timestamp (WTT Champions Yokohama 2026).**

