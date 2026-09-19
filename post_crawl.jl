#!/usr/bin/env julia
# post_crawl.jl — finish pipeline after `julia crawl.jl` reaches phase=done.
#
# Usage (repo root):
#   julia post_crawl.jl
#   julia post_crawl.jl --skip-ranking
#
# Requires: crawl_state.json phase=done, events batch, matches_*.json,
#           players/*.json, data/events/*.json, data/players.json

using JSON
using Dates

const SKIP_RANKING = "--skip-ranking" in ARGS

include(joinpath(@__DIR__, "src", "structures.jl"))
include(joinpath(@__DIR__, "src", "weights.jl"))
include(joinpath(@__DIR__, "src", "ittf_convert.jl"))
# rating.jl defines `Period` (shadowing Dates.Period); it must be included
# before typst_output.jl so save_rankings' signature binds the right type.
include(joinpath(@__DIR__, "src", "rating.jl"))
include(joinpath(@__DIR__, "src", "typst_output.jl"))

function main()
    cd(@__DIR__)
    println("cwd=", pwd())

    st_path = "crawl_state.json"
    isfile(st_path) || error("Missing $st_path")
    st = Dict{String,Any}(string(k) => v for (k, v) in pairs(JSON.parsefile(st_path)))
    phase = string(get(st, "phase", "?"))
    phase == "done" || error("crawl phase=$phase (want done)")

    batch = string(get(st, "events_batch_file", "events/events_47.json"))
    from_file = Int(get(st, "match_files_from", 8885))
    to_file = Int(st["next_match_file_num"]) - 1
    println("batch=$batch matches=$from_file:$to_file")

    println("\n== Load existing data ==")
    events = read_events_from_files()
    players = read_players_from_file()
    println("Existing dates=$(length(events)), players=$(length(players))")

    println("\n== Build new_events / new_players from crawl files ==")
    new_events = load_events_batch(batch)
    load_crawled_matches_into_new_events!(new_events; from_file=from_file, to_file=to_file)
    new_players = load_new_players_from_disk(new_events, players)
    isempty(new_events) && error("new_events is empty")
    println("new_events=$(length(new_events)), new_players=$(length(new_players))")

    println("\n== Merge & save players ==")
    merge_players!(players, new_players)
    update_player_associations(new_events, players)
    println("Associations updated from new_events")
    save_players_to_json(players, "data/players.json")

    println("\n== Merge events, filter, save ==")
    modified_dates = merge_events(events, new_events)
    println("modified_dates=$(length(modified_dates))")
    events = filter_perfect_matches(events)
    println("After filter: dates=$(length(events))")
    save_events_to_files(events, union(modified_dates, Set(keys(events))))
    save_event_ids_index(events)

    if SKIP_RANKING
        println("\n== Skip ranking (--skip-ranking) ==")
        return
    end

    println("\n== Rankings ==")
    active_periods = compute_active_periods(events, players)
    println("active_periods players=$(length(active_periods))")
    highest = compute_rankings(events, players, active_periods)
    println("Done. Top highest ratings:")
    for (id, r) in highest[1:min(10, end)]
        name = haskey(players, id) ? players[id].name : "?"
        println("  $id $name $(round(r; digits=1))")
    end

    println("\n== Translate to Chinese ==")
    translate_all()
end

if !(@isdefined(POST_CRAWL_AS_LIBRARY) && POST_CRAWL_AS_LIBRARY)
    main()
end
