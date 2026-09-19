# events_export.jl — derive the Events web data (brackets, podiums, player
# event results) from the raw ITTF dumps and write the web bundles.
#
# Runs after export_web_data in post_crawl.jl. Reads:
#   events/events_*.json    raw event metadata (start date, organizer)
#   matches/matches_*.json  raw match rows (1.8 GB — parsed incrementally into
#   data/singles_matches_cache.json (gitignored), a compact MS/WS-only cache)
# Writes:
#   web/data/events-index.json  [[tid,name,start,end,org,weight,[ms podium],[ws podium]],...]
#   web/data/events/<tid>.json  {n,s,e,o,w,pa,MS,WS} — bracket tree (or round
#                               list fallback) + qualification list per category
#   augments web/data/history/shard-XX.json with "e": [[tid,cat,result],...]
#
# Bracket reconstruction: in a single-elimination draw every player except the
# champion loses exactly once, so each match's winner appears in exactly one
# later-round match. Following those links from the Final rebuilds the exact
# bracket tree without seeding data. Draws that violate this (group formats)
# fall back to a per-round match list.

using JSON
using Dates

# ---- compact record fields (cache + grouping) ----
# [tid, cat, stage, rcode, a, x, res, games, winner, wo, aAssoc, xAssoc]
const R_TID = 1; const R_CAT = 2; const R_STAGE = 3; const R_RND = 4
const R_A = 5;  const R_X = 6;  const R_RES = 7;  const R_GAMES = 8
const R_W = 9;  const R_WO = 10; const R_AA = 11; const R_XA = 12
# cat: 0=MS, 1=WS; stage: 0=Main Draw, 1=Qualification

# ---- round codes ----
# main draw: 0=Final 1=SemiFinal 2=QuarterFinal 3=R16 4=R32 5=R64 6=R128
# qualification: 12=QR4 13=QR8 14=QR16 15=QR32 16=QR64 (ascending toward main)
# -1 = unlabeled / group-stage / unknown
const MAIN_R_CODES = Dict(16 => 3, 32 => 4, 64 => 5, 128 => 6)
const QUAL_R_CODES = Dict(4 => 12, 8 => 13, 16 => 14, 32 => 15, 64 => 16)
const UNKNOWN_ROUNDS = Set{String}()

function round_code(r)::Int
    r === nothing && return -1
    s = string(r)
    s == "Final" && return 0
    s == "SemiFinal" && return 1
    s == "QuarterFinal" && return 2
    m = match(r"^R(\d+)$", s)
    m !== nothing && return get(MAIN_R_CODES, parse(Int, m.captures[1]), -1)
    m = match(r"^QR(\d+)$", s)
    m !== nothing && return get(QUAL_R_CODES, parse(Int, m.captures[1]), -1)
    isempty(s) || push!(UNKNOWN_ROUNDS, s)
    return -1
end

# ---- player event-result codes (stored in shard "e") ----
const RES_LABELS = ["C", "F", "SF", "QF", "R16", "R32", "R64", "R128", "Q"]

# ---------------------------------------------------------------- raw parsing

function _extract_singles!(out, path)
    data = JSON.parsefile(path)
    rows = data isa AbstractVector && !isempty(data) && data[1] isa AbstractVector ? data[1] : data
    for m in rows
        m isa AbstractDict || continue
        cat = get(m, "vw_matches___event_raw", nothing)
        (cat == "MS" || cat == "WS") || continue
        get(m, "vw_matches___player_b_id_raw", nothing) === nothing || continue
        get(m, "vw_matches___player_y_id_raw", nothing) === nothing || continue
        a = get(m, "vw_matches___player_a_id_raw", nothing)
        x = get(m, "vw_matches___player_x_id_raw", nothing)
        tid = get(m, "vw_matches___tournament_id_raw", nothing)
        (a === nothing || x === nothing || tid === nothing) && continue
        stage = get(m, "vw_matches___stage_raw", "") == "Main Draw" ? 0 : 1
        res = replace(string(get(m, "vw_matches___res_raw", "")), " - " => ":")
        games = strip(string(get(m, "vw_matches___games_raw", "")))
        w = get(m, "vw_matches___winner_raw", nothing)
        push!(out, Any[Int(tid), cat == "MS" ? 0 : 1, stage,
                       round_code(get(m, "vw_matches___round_raw", nothing)),
                       Int(a), Int(x), res, games, w === nothing ? 0 : Int(w),
                       string(get(m, "vw_matches___wo_raw", "")),
                       string(get(m, "vw_matches___assoc_a_raw", "")),
                       string(get(m, "vw_matches___assoc_x_raw", ""))])
    end
    return out
end

const SINGLES_CACHE = joinpath("data", "singles_matches_cache.json")

# Incremental parse of matches/matches_*.json. Match files are append-only
# (new crawl batches get new numbers), so only unseen filenames are parsed.
function load_singles_records()
    files = sort!(filter(f -> endswith(f, ".json"), readdir("matches"; join=true)))
    seen = Set{String}()
    records = Any[]
    if isfile(SINGLES_CACHE)
        c = JSON.parsefile(SINGLES_CACHE)
        union!(seen, get(c, "files", Any[]))
        append!(records, get(c, "matches", Any[]))
    end
    fresh = 0
    for f in files
        f in seen && continue
        _extract_singles!(records, f)
        push!(seen, f)
        fresh += 1
    end
    if fresh > 0
        mkpath(dirname(SINGLES_CACHE))
        open(SINGLES_CACHE, "w") do io
            JSON.print(io, Dict("files" => sort!(collect(seen)), "matches" => records))
        end
    end
    println("singles records: $(length(records)) ($(fresh) new match files parsed)")
    return records
end

# tid => (start::String, org::String) from raw event batches
function load_raw_event_meta()
    meta = Dict{Int,Tuple{String,String}}()
    isdir("events") || return meta
    for f in filter(f -> endswith(f, ".json"), readdir("events"; join=true))
        data = JSON.parsefile(f)
        rows = data isa AbstractVector && !isempty(data) && data[1] isa AbstractVector ? data[1] : data
        for e in rows
            e isa AbstractDict || continue
            tid = get(e, "vw_tournaments___tournament_id_raw", nothing)
            tid === nothing && continue
            start = get(e, "vw_tournaments___tour_start_raw", nothing)
            org = get(e, "vw_tournaments___organizer", nothing)
            meta[Int(tid)] = (start === nothing ? "" : string(start),
                              org === nothing ? "" : string(org))
        end
    end
    return meta
end

# ---------------------------------------------------------------- bracket tree

# ms = main-draw records of one (tid, cat). Returns a nested tree
# [a, x, res, winner, feederA, feederX, games, wo] (feeder = subtree or
# nothing), or nothing when the draw is not a clean single elimination.
function build_tree(ms)
    count(m -> m[R_RND] == 0, ms) == 1 || return nothing
    any(m -> m[R_RND] < 0, ms) && return nothing
    plays = Dict{Int,Vector{Int}}()
    for (i, m) in enumerate(ms)
        push!(get!(plays, m[R_A], Int[]), i)
        push!(get!(plays, m[R_X], Int[]), i)
    end
    final_idx = findfirst(m -> m[R_RND] == 0, ms)
    parent = fill(-1, length(ms))
    for (i, m) in enumerate(ms)
        i == final_idx && continue
        w = m[R_W]
        (w == m[R_A] || w == m[R_X]) || return nothing
        # the winner's next match = the unique match in the closest later round
        nxt = [j for j in get(plays, w, Int[]) if j != i && ms[j][R_RND] < m[R_RND]]
        isempty(nxt) && return nothing
        best = maximum(ms[j][R_RND] for j in nxt)
        cand = [j for j in nxt if ms[j][R_RND] == best]
        length(cand) == 1 || return nothing
        parent[i] = cand[1]
    end
    children_of = Dict{Int,Vector{Int}}()
    for (i, p) in enumerate(parent)
        p > 0 && push!(get!(children_of, p, Int[]), i)
    end
    # every match must hang off the final (no orphaned subtrees)
    seen = Set{Int}()
    stack = [final_idx]
    while !isempty(stack)
        i = pop!(stack)
        i in seen && continue
        push!(seen, i)
        append!(stack, get(children_of, i, Int[]))
    end
    length(seen) == length(ms) || return nothing

    function emit(i)
        m = ms[i]
        feeder(pid) = begin
            for j in get(children_of, i, Int[])
                ms[j][R_W] == pid && return emit(j)
            end
            nothing
        end
        Any[m[R_A], m[R_X], m[R_RES], m[R_W], feeder(m[R_A]), feeder(m[R_X]),
            m[R_GAMES], m[R_WO]]
    end
    return emit(final_idx)
end

# (champion, runner-up, sf1, sf2); 0-filled when missing
function podium_of(ms)
    f = filter(m -> m[R_RND] == 0, ms)
    isempty(f) && return [0, 0, 0, 0]
    f = f[1]
    champ = f[R_W]
    runner = f[R_A] == champ ? f[R_X] : f[R_A]
    sf_losers = [m[R_W] == m[R_A] ? m[R_X] : m[R_A] for m in ms if m[R_RND] == 1]
    return [champ, runner, get(sf_losers, 1, 0), get(sf_losers, 2, 0)]
end

# fallback payload for non-knockout draws: rounds grouped by code (desc)
function rounds_list(ms)
    out = Any[]
    for code in sort!(unique(m[R_RND] for m in ms); rev=true)
        rows = [Any[m[R_A], m[R_X], m[R_RES], m[R_W], m[R_GAMES], m[R_WO]]
                for m in ms if m[R_RND] == code]
        push!(out, Any[code, rows])
    end
    return out
end

# ---------------------------------------------------------------- export

function export_events_web(events::Dict{Date,Vector{Event}}, players::Dict{Int,Player};
                           out_dir::AbstractString="web/data")
    mkpath(joinpath(out_dir, "events"))

    # processed event lookup: tid => (name, weight, end date)
    ev_info = Dict{Int,Tuple{String,Float64,Date}}()
    for evs in values(events), e in evs
        ev_info[Int(e.id)] = (e.name, Float64(e.weight), e.time)
    end
    raw_meta = load_raw_event_meta()

    records = load_singles_records()

    # group by (tid, cat), dedupe identical rows
    groups = Dict{Tuple{Int,Int},Vector{Any}}()
    seen_row = Set{UInt}()
    for r in records
        key = (r[R_TID], r[R_CAT])
        h = hash((key, r[R_STAGE], r[R_RND], r[R_A], r[R_X], r[R_RES]))
        h in seen_row && continue
        push!(seen_row, h)
        push!(get!(groups, key, Any[]), r)
    end

    tids = sort!(unique(k[1] for k in keys(groups)))
    index_rows = Any[]
    results = Dict{Int,Vector{Any}}()   # pid => [[tid,cat,rescode],...]
    n_tree = n_fallback = 0

    for tid in tids
        haskey(ev_info, tid) || continue
        name, wt, end_date = ev_info[tid]
        start_s, org = get(raw_meta, tid, ("", ""))
        detail = Dict{String,Any}("n" => name,
                                  "s" => isempty(start_s) ? string(end_date) : start_s,
                                  "e" => string(end_date),
                                  "o" => org, "w" => wt)
        pa = Dict{Int,String}()
        podiums = Dict{Int,Any}()

        for cat in (0, 1)
            rs = get(groups, (tid, cat), nothing)
            rs === nothing && continue
            for r in rs
                pa[r[R_A]] = r[R_AA]
                pa[r[R_X]] = r[R_XA]
            end
            main = filter(r -> r[R_STAGE] == 0, rs)
            qual = filter(r -> r[R_STAGE] == 1, rs)

            payload = Dict{String,Any}()
            if !isempty(main)
                tree = build_tree(main)
                if tree === nothing
                    payload["r"] = rounds_list(main)
                    n_fallback += 1
                else
                    payload["t"] = tree
                    n_tree += 1
                end
                podiums[cat] = podium_of(main)
            end
            if !isempty(qual)
                payload["q"] = [Any[m[R_A], m[R_X], m[R_RES], m[R_W], m[R_RND], m[R_GAMES], m[R_WO]]
                                for m in sort!(qual; by=m -> -m[R_RND])]
            end
            detail[cat == 0 ? "MS" : "WS"] = payload

            # player results
            pids = unique!(sort!(vcat([r[R_A] for r in rs], [r[R_X] for r in rs])))
            for pid in pids
                mine_main = filter(r -> (r[R_A] == pid || r[R_X] == pid), main)
                res = nothing
                if !isempty(mine_main)
                    if all(r -> r[R_RND] >= 0, mine_main)
                        best = minimum(r[R_RND] for r in mine_main)
                        if best == 0
                            fm = first(filter(r -> r[R_RND] == 0, mine_main))
                            res = fm[R_W] == pid ? 0 : 1
                        else
                            res = best + 1
                        end
                    end
                elseif any(r -> r[R_A] == pid || r[R_X] == pid, qual)
                    res = 8   # qualification only
                end
                res === nothing && continue
                push!(get!(results, pid, Any[]), Any[tid, cat, res])
            end
        end

        detail["pa"] = Dict(string(k) => v for (k, v) in pa if !isempty(v))
        open(joinpath(out_dir, "events", "$(tid).json"), "w") do io
            JSON.print(io, detail)
        end
        push!(index_rows, Any[tid, name, detail["s"], detail["e"], org, wt,
                              get(podiums, 0, [0, 0, 0, 0]),
                              get(podiums, 1, [0, 0, 0, 0])])
    end

    sort!(index_rows; by=r -> r[4], rev=true)
    open(joinpath(out_dir, "events-index.json"), "w") do io
        JSON.print(io, index_rows)
    end

    # augment history shards with player event results
    n_res = 0
    for shard_path in filter(f -> endswith(f, ".json"),
                             readdir(joinpath(out_dir, "history"); join=true))
        shard = JSON.parsefile(shard_path)
        changed = false
        for (pid_s, entry) in shard
            pid = parse(Int, pid_s)
            rs = get(results, pid, nothing)
            rs === nothing && continue
            sort!(rs; by=r -> r[1], rev=true)
            entry["e"] = rs
            changed = true
            n_res += 1
        end
        if changed
            open(shard_path, "w") do io
                JSON.print(io, shard)
            end
        end
    end

    println("events export: $(length(tids)) events (tree=$n_tree, fallback=$n_fallback), " *
            "$(length(index_rows)) indexed, player results for $(n_res) players → $out_dir")
    isempty(UNKNOWN_ROUNDS) ||
        println("  unknown round labels (→ fallback): ", join(collect(UNKNOWN_ROUNDS), ", "))
    return nothing
end
