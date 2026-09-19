# Benchmark: where does post_crawl time go? Read-only for data/ (rankings stage
# rewrites identical history files). Run from repo root: julia testdata/bench_pipeline.jl
cd(dirname(@__DIR__))
using JSON, Dates, Printf

const ROOT = pwd()
include(joinpath(ROOT, "src", "structures.jl"))
include(joinpath(ROOT, "src", "weights.jl"))
include(joinpath(ROOT, "src", "rating.jl"))
include(joinpath(ROOT, "src", "typst_output.jl"))

# --- stage 0: raw file I/O vs JSON parsing, on the 1447 date files ---
files = filter(f -> endswith(f, ".json"), readdir("data/events", join=true))
total_mb = sum(filesize.(files)) / 1e6
@printf "files: %d, total %.1f MB\n" length(files) total_mb

t_read = @elapsed (texts = [read(f, String) for f in files])
@printf "pure read (no parse):      %6.2fs\n" t_read

t_parse = @elapsed (parsed = [JSON.parse(t) for t in texts])
@printf "JSON.parse of same texts:  %6.2fs\n" t_parse

GC.gc()
t1 = @elapsed events = read_events_from_files()
@printf "read_events_from_files:    %6.2fs (%d dates)\n" t1 length(events)
# warm second run (post-compilation, page cache hot)
t1b = @elapsed events2 = read_events_from_files()
@printf "read_events (2nd run):     %6.2fs\n" t1b

t2 = @elapsed players = read_players_from_file()
@printf "read_players_from_file:    %6.2fs (%d players)\n" t2 length(players)

GC.gc()
t3 = @elapsed ap = compute_active_periods(events, players)
@printf "compute_active_periods:    %6.2fs\n" t3

t4 = @elapsed highest = compute_rankings(events, players, ap)
@printf "compute_rankings+save typ: %6.2fs\n" t4

t5 = @elapsed translate_all()
@printf "translate_all:             %6.2fs\n" t5

@printf "TOTAL (2nd-run load):      %6.2fs\n" (t1b + t2 + t3 + t4 + t5)
