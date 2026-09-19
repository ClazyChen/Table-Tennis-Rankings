from pathlib import Path

root = Path(r"d:\Workspace\Table-Tennis-Rankings")
td = root / "testdata"

def read(n):
    return (td / f"_cell_{n}.jl").read_text(encoding="utf-8")

def cut_before(text, prefixes):
    lines = []
    for line in text.splitlines():
        if any(line.startswith(p) for p in prefixes):
            break
        lines.append(line)
    return "\n".join(lines).rstrip() + "\n"

structs = "\n".join(read(4).splitlines()[2:]).rstrip() + "\n"
cell6 = cut_before(read(6), ["# Read all events", "events = read_events"])
cell8 = cut_before(read(8), ["# Read all players", "players = read_players"])
cell13 = read(13)
cell15 = read(15).split("function process_events")[0].rstrip() + "\n"
cell19 = read(19)
cell27 = read(27)
cell33 = cut_before(read(33), ["update_player_associations(new_events"])
# Keep function body; drop trailing call / comment that starts the save-call section
cell35 = "\n".join(
    line for line in read(35).splitlines()
    if not line.startswith("save_players_to_json(players")
    and line != "# Save player data"
).rstrip() + "\n"
cell37 = cut_before(read(37), ["modified_dates = merge_events"])
cell40 = cut_before(read(40), ["save_events_to_files(events"])
cell41 = cut_before(read(41), ["# 应用过滤", "filtered_events ="])
cell45 = read(45)

active = read(47).replace(
    "function compute_active_periods(events::Dict{Date, Vector{Event}})",
    "function compute_active_periods(events::Dict{Date, Vector{Event}}, players::Dict{Int, Player})",
)
active = cut_before(active, ["active_periods = compute_active_periods"])

sr = read(49).replace(
    'function save_rankings(date::Date, type::String, rating::Dict{Int, Float64}, last_ranking::Dict{Int, Int}, filename::String="", count::Int=200)',
    "function save_rankings(date::Date, type::String, rating::Dict{Int, Float64}, last_ranking::Dict{Int, Int},\n"
    "                      players::Dict{Int, Player}, active_periods::Dict{Int, Vector{Period}};\n"
    '                      filename::String="", count::Int=200)',
)

convert_match = r'''
function convert_ittf_match(raw_match)
    player_a_id = raw_match["vw_matches___player_a_id_raw"]
    player_x_id = raw_match["vw_matches___player_x_id_raw"]
    player_a_assoc = raw_match["vw_matches___assoc_a_raw"]
    player_x_assoc = raw_match["vw_matches___assoc_x_raw"]

    if (haskey(raw_match, "vw_matches___player_b_id_raw") && !isnothing(raw_match["vw_matches___player_b_id_raw"])) ||
       (haskey(raw_match, "vw_matches___player_y_id_raw") && !isnothing(raw_match["vw_matches___player_y_id_raw"]))
        return nothing
    end
    if isnothing(player_a_id) || isnothing(player_x_id)
        return nothing
    end

    result = replace(string(raw_match["vw_matches___res_raw"]), " - " => ":")
    games = strip(replace(string(raw_match["vw_matches___games_raw"]), r"\s*0:0\s*$" => ""))
    w = result_to_weight(result)
    a_assoc = isnothing(player_a_assoc) ? "" : string(player_a_assoc)
    x_assoc = isnothing(player_x_assoc) ? "" : string(player_x_assoc)
    return Match(Int(player_a_id), Int(player_x_id), a_assoc, x_assoc, Float32(w), result, games)
end

function process_matches(new_matches_json::String, event::Event)
    data = JSON.parse(new_matches_json)
    new_match_count = 0
    for match_list in data
        for raw_match in match_list
            m = convert_ittf_match(raw_match)
            if !isnothing(m)
                push!(event.match, m)
                new_match_count += 1
            end
        end
    end
    return new_match_count
end
'''

cr = r'''
function compute_rankings(events::Dict{Date, Vector{Event}},
                          players::Dict{Int, Player},
                          active_periods::Dict{Int, Vector{Period}})
    ratings = Dict{Int, Float64}()
    last_ranking = Dict{Int, Int}()
    highest_ratings = Dict{Int, Float64}()
    start_date = Date("2004-01-01")
    end_date = today()

    all_events = Event[]
    for (_, date_events) in events
        append!(all_events, date_events)
    end
    sort!(all_events, by = e -> e.time)

    for event in all_events
        if event.time >= start_date
            ranking_m = save_rankings(start_date, "M", ratings, last_ranking, players, active_periods)
            ranking_f = save_rankings(start_date, "W", ratings, last_ranking, players, active_periods)
            empty!(last_ranking)
            for (player, rank) in ranking_m
                last_ranking[player] = rank
            end
            for (player, rank) in ranking_f
                last_ranking[player] = rank
            end
            start_date = start_date + Month(1)
            for (id, rating) in ratings
                if rating > get(highest_ratings, id, typemin(Float64))
                    highest_ratings[id] = rating
                end
            end
        end

        for m in event.match
            player1_id = m.player_a_id
            player2_id = m.player_x_id
            if !haskey(ratings, player1_id)
                ratings[player1_id] = r0
                highest_ratings[player1_id] = r0
            end
            if !haskey(ratings, player2_id)
                ratings[player2_id] = r0
                highest_ratings[player2_id] = r0
            end
            r1, r2 = update_rating(ratings[player1_id], ratings[player2_id], m.weight, event.weight, event.time)
            ratings[player1_id] = r1
            ratings[player2_id] = r2
        end
    end

    save_rankings(end_date, "M", ratings, last_ranking, players, active_periods; filename="MS-latest.typ", count=1000)
    save_rankings(end_date, "W", ratings, last_ranking, players, active_periods; filename="WS-latest.typ", count=1000)
    return sort(collect(highest_ratings), by=x -> x[2], rev=true)
end
'''

load_helpers = r'''
function load_events_batch(batch::AbstractString)::Vector{Event}
    isfile(batch) || error("Missing event batch: $batch")
    raw = JSON.parsefile(batch)
    rows = raw isa AbstractVector && !isempty(raw) && raw[1] isa AbstractVector ? raw[1] : raw
    out = Event[]
    for r in rows
        push!(out, convert_ittf_event(r))
    end
    println("Loaded $(length(out)) events from $batch")
    return out
end

function load_crawled_matches_into_new_events!(new_events::Vector{Event};
                                              from_file::Int=8885,
                                              to_file::Int)
    by_id = Dict{Int,Event}(Int(e.id) => e for e in new_events)
    for e in new_events
        empty!(e.match)
    end
    loaded_files = 0
    loaded_matches = 0
    skipped = 0
    for n in from_file:to_file
        path = joinpath("matches", "matches_$(n).json")
        isfile(path) || continue
        txt = read(path, String)
        data = JSON.parse(txt)
        rows = (data isa AbstractVector && !isempty(data) && data[1] isa AbstractVector) ? data[1] : data
        isempty(rows) && continue
        tid = Int(rows[1]["vw_matches___tournament_id_raw"])
        if !haskey(by_id, tid)
            skipped += 1
            continue
        end
        loaded_matches += process_matches(txt, by_id[tid])
        loaded_files += 1
    end
    println("Matches: files=$(loaded_files) ($from_file-$to_file), singles=$(loaded_matches), skipped=$skipped")
    println("Events with matches: $(count(e -> !isempty(e.match), new_events)) / $(length(new_events))")
    return loaded_matches
end

function load_new_players_from_disk(new_events::Vector{Event}, existing::Dict{Int,Player})::Vector{Player}
    ids = Set{Int}()
    for ev in new_events, m in ev.match
        push!(ids, Int(m.player_a_id))
        push!(ids, Int(m.player_x_id))
    end
    out = Player[]
    missing = Int[]
    for id in sort!(collect(ids))
        haskey(existing, id) && continue
        path = joinpath("players", "$(id).json")
        if !isfile(path) || filesize(path) < 20
            push!(missing, id)
            continue
        end
        pl = parse_player_data(read(path, String))
        if pl === nothing
            push!(missing, id)
            continue
        end
        push!(out, pl)
    end
    println("New players from disk: $(length(out)); missing files/parse: $(length(missing))")
    isempty(missing) || println("Missing examples: ", missing[1:min(10, end)])
    return out
end

function merge_players!(existing::Dict{Int,Player}, new_players::Vector{Player})
    added = 0
    for pl in new_players
        if haskey(existing, pl.id)
            @warn "player already exists, skip" id=pl.id name=pl.name
        else
            existing[pl.id] = pl
            added += 1
        end
    end
    println("Merged players: +$added → total $(length(existing))")
end
'''

header = '''#!/usr/bin/env julia
# post_crawl.jl — finish pipeline after run_crawl! phase=done
#
# Usage (repo root):
#   julia post_crawl.jl
#   julia post_crawl.jl --skip-ranking
#
# Requires: crawl_state.json phase=done, events batch, matches_8885.., players/*.json,
#           data/events/*.json, data/players.json

using JSON
using Dates
using Distributions

const SKIP_RANKING = "--skip-ranking" in ARGS

'''

main = r'''
function main()
    cd(@__DIR__)
    println("cwd=", pwd())

    st_path = "crawl_state.json"
    isfile(st_path) || error("Missing $st_path")
    st = Dict{String,Any}(string(k) => v for (k, v) in pairs(JSON.parsefile(st_path)))
    phase = string(get(st, "phase", "?"))
    phase == "done" || error("crawl phase=$phase (want done)")

    batch = string(get(st, "events_batch_file", "events/events_47.json"))
    from_file = 8885
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
end

main()
'''

parts = [
    header,
    structs,
    cell6,
    cell8,
    cell13,
    cell15,
    cell19,
    convert_match,
    cell27,
    cell33,
    cell35,
    cell37,
    cell40,
    cell41,
    cell45,
    active,
    sr,
    cr,
    load_helpers,
    main,
]

out = root / "post_crawl.jl"
text = "\n".join(parts)
out.write_text(text, encoding="utf-8")
print("wrote", out, "bytes", out.stat().st_size, "lines", text.count("\n") + 1)
