# events_export.jl — derive the Events web data (brackets, podiums, player
# event results) from the raw ITTF dumps and write the web bundles.
#
# Runs after export_web_data in post_crawl.jl. Reads:
#   events/events_*.json    raw event metadata (start date, organizer)
#   matches/matches_*.json  raw match rows (1.8 GB — parsed incrementally into
#   data/singles_matches_cache.json (gitignored), a compact MS/WS-only cache)
# Writes:
#   web/data/events-index.json  [[tid,name,start,end,org,weight,[ms podium],[ws podium]],...]
#   web/data/events/<tid>.json  {n,s,e,o,w,pa,pr,MS,WS} — per category: bracket
#                               tree "t" (or round list fallback "r"), leftover
#                               placement/unlinked matches "x", qualification
#                               list "q", bronze (3rd place) match "b".
#                               "pr": pid => [rating, rank] entering the event
#                               (rating = series point at the event's start
#                               month; rank only for the monthly top 200, 0 =
#                               unranked)
#   augments web/data/history/shard-XX.json with "e": [[tid,cat,result],...]
#
# Bracket reconstruction: in a single-elimination draw every player except the
# champion loses exactly once, so each match's winner appears in exactly one
# later-round match. Following those links from the real Final rebuilds the
# exact bracket tree without seeding data. Draws where no unique root final
# can be determined (group formats, multi-bracket qualifiers) fall back to a
# per-round match list.

using JSON
using Dates

# ---- compact record fields (cache + grouping) ----
# [tid, cat, stage, rcode, a, x, res, games, winner, wo, aAssoc, xAssoc, mid]
const R_TID = 1; const R_CAT = 2; const R_STAGE = 3; const R_RND = 4
const R_A = 5;  const R_X = 6;  const R_RES = 7;  const R_GAMES = 8
const R_W = 9;  const R_WO = 10; const R_AA = 11; const R_XA = 12
const R_MID = 13
# cat: 0=MS, 1=WS; stage: 0=Main Draw, 1=Qualification/other, 2=Position Draw
# mid: raw match id (chronological within a tournament — used by the temporal
# reconstruction for label-less draws)

# ---- round codes ----
# main draw: 0=Final 1=SemiFinal 2=QuarterFinal 3=R16 4=R32 5=R64 6=R128 7=R256
# bare numeric labels mean "round of N" (2=Final, 4=SemiFinal, 8=QuarterFinal)
# qualification: 12=QR4 13=QR8 14=QR16 15=QR32 16=QR64 (ascending toward main)
# -1 = unlabeled / group-stage / unknown
const MAIN_R_CODES = Dict(16 => 3, 32 => 4, 64 => 5, 128 => 6, 256 => 7)
const NUM_R_CODES = Dict(2 => 0, 4 => 1, 8 => 2, 16 => 3, 32 => 4, 64 => 5, 128 => 6, 256 => 7)
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
    m = match(r"^(\d+)$", s)
    m !== nothing && return get(NUM_R_CODES, parse(Int, m.captures[1]), -1)
    isempty(s) || s == "None" || push!(UNKNOWN_ROUNDS, s)
    return -1
end

# stage: 0=main draw, 1=qualification/groups/other, 2=position draw.
# Dirty-data variants seen in the wild: "MAIN" (Small States Games 2019),
# "Main Draw - Stage 2" (Asian Cup 2018; "Stage 1" there is a pre-quarterfinal
# playoff, and "(Bronze Match)"/"(5th place)" etc. are position matches).
function stage_code(s)::Int
    (s == "Main Draw" || s == "MAIN" || s == "Main Draw - Stage 2") && return 0
    (s == "Position Draw" || startswith(s, "Main Draw -")) && return 2
    return 1
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
        stage = stage_code(string(get(m, "vw_matches___stage_raw", "")))
        res = replace(string(get(m, "vw_matches___res_raw", "")), " - " => ":")
        games = strip(string(get(m, "vw_matches___games_raw", "")))
        w = get(m, "vw_matches___winner_raw", nothing)
        push!(out, Any[Int(tid), cat == "MS" ? 0 : 1, stage,
                       round_code(get(m, "vw_matches___round_raw", nothing)),
                       Int(a), Int(x), res, games, w === nothing ? 0 : Int(w),
                       string(get(m, "vw_matches___wo_raw", "")),
                       string(get(m, "vw_matches___assoc_a_raw", "")),
                       string(get(m, "vw_matches___assoc_x_raw", "")),
                       Int(get(m, "vw_matches___id_raw", 0))])
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
        _write_json(SINGLES_CACHE, Dict("files" => sort!(collect(seen)), "matches" => records))
    end
    println("singles records: $(length(records)) ($(fresh) new match files parsed)")
    return records
end

# Write JSON with retries: transient SystemError (EINVAL) happens on Windows
# when an antivirus/OneDrive scan briefly locks the target file (same pattern
# as the ranking writer in typst_output.jl).
function _write_json(path::AbstractString, obj)
    for attempt in 1:8
        try
            open(path, "w") do io
                JSON.print(io, obj)
            end
            return
        catch e
            e isa SystemError || rethrow()
            attempt == 8 && rethrow()
            @warn "retry write json" file=path attempt=attempt exception=e
            sleep(0.4 * attempt)
        end
    end
end

# Early ITTF dumps sometimes recorded a draw twice: a bare "3 - 0" row with no
# game scores alongside the fully-scored row (occasionally even with a wrong
# opponent id, e.g. African Championships 2010). Within one labeled round a
# player has at most one match, so keep only the best-documented row per
# (round, winner).
function drop_placeholder_dups!(rs)
    keep = Dict{Tuple{Int,Int},Int}()
    drop = Int[]
    for (i, r) in enumerate(rs)
        r[R_RND] >= 0 || continue
        key = (r[R_RND], r[R_W])
        j = get(keep, key, 0)
        if j == 0
            keep[key] = i
        else
            si = length(strip(string(rs[i][R_GAMES])))
            sj = length(strip(string(rs[j][R_GAMES])))
            keep[key] = si > sj ? i : j
            push!(drop, si > sj ? j : i)
        end
    end
    deleteat!(rs, sort!(unique!(drop)))
    return rs
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

# Bracket reconstruction tolerant of dirty labels. In a single-elimination draw
# every player except the champion loses exactly once, so each match's winner
# appears in exactly one later-round match; following those links from the
# Final rebuilds the bracket without seeding data.
#
# Root selection: the real Final is the unique "Final"-labeled match whose two
# players each won a semifinal (a lone Final is accepted as-is; when several
# candidates remain — placement finals of cup formats — the one with the
# largest linked subtree wins). Matches that cannot be linked or do not hang
# off the root (placement games, mislabeled sub-event finals, unlabeled rows)
# are NOT fatal: they are split out as leftovers.
#
# ms = main-draw records of one (tid, cat). Returns
#   (tree, tree_idx, leftover_idx, sf_losers)
# where tree is nested [a,x,res,winner,feederA,feederX,games,wo] (feeder =
# subtree or nothing), or nothing when no unique root final exists.
# `career` maps pid => total singles matches in the database, used to break
# ties between parallel draws (see below).
function build_tree(ms, career)
    labeled = [i for i in eachindex(ms) if ms[i][R_RND] >= 0]
    finals = [i for i in labeled if ms[i][R_RND] == 0]
    isempty(finals) && return nothing
    sf_winners = Set(ms[i][R_W] for i in labeled if ms[i][R_RND] == 1)

    plays = Dict{Int,Vector{Int}}()
    for i in labeled
        push!(get!(plays, ms[i][R_A], Int[]), i)
        push!(get!(plays, ms[i][R_X], Int[]), i)
    end
    # candidate parents of match i = matches in the closest later round its
    # winner plays in
    function candidates(i)
        m = ms[i]
        w = m[R_W]
        (w == m[R_A] || w == m[R_X]) || return Int[]
        nxt = [j for j in get(plays, w, Int[]) if j != i && ms[j][R_RND] >= 0 && ms[j][R_RND] < m[R_RND]]
        isempty(nxt) && return Int[]
        best = maximum(ms[j][R_RND] for j in nxt)
        [j for j in nxt if ms[j][R_RND] == best]
    end
    # first pass: unambiguous links only
    parent = Dict{Int,Int}()
    for i in labeled
        cand = candidates(i)
        length(cand) == 1 && (parent[i] = cand[1])
    end
    children_of = Dict{Int,Vector{Int}}()
    function rebuild_children!()
        empty!(children_of)
        for (i, p) in parent
            push!(get!(children_of, p, Int[]), i)
        end
    end
    rebuild_children!()
    function reachable_from(root)
        seen = Set{Int}()
        stack = [root]
        while !isempty(stack)
            i = pop!(stack)
            i in seen && continue
            push!(seen, i)
            append!(stack, get(children_of, i, Int[]))
        end
        seen
    end

    root = nothing
    if length(finals) == 1
        f = ms[finals[1]]
        # accept a lone final when at least one finalist won a semifinal. The
        # other finalist may have advanced through an unrecorded walkover
        # (early ITTF data often lacks retired matches entirely, e.g. WU Yang's
        # semifinal at China Open 2013). Reject only when semifinals exist and
        # neither finalist won one (i.e. it is a stray placement final).
        if isempty(sf_winners) || f[R_A] in sf_winners || f[R_X] in sf_winners
            root = finals[1]
        end
    else
        cands = [i for i in finals if ms[i][R_A] in sf_winners && ms[i][R_X] in sf_winners]
        if isempty(cands)
            # walkover finals: only one finalist won a semifinal
            cands = [i for i in finals if ms[i][R_A] in sf_winners || ms[i][R_X] in sf_winners]
        end
        if length(cands) > 1
            sizes = [length(reachable_from(c)) for c in cands]
            best = maximum(sizes)
            tied = cands[sizes .== best]
            if length(tied) > 1
                # parallel draws under one event label (e.g. Belarus Open 2010
                # ran a national and an international draw side by side, all
                # rounds labeled identically): prefer the draw with the
                # stronger field, proxied by total career matches of its
                # connected player set
                uf = Dict{Int,Int}()
                function uf_find(x)
                    while get(uf, x, x) != x
                        uf[x] = uf_find(uf[x])
                        x = uf[x]
                    end
                    x
                end
                for i in labeled
                    a, x = ms[i][R_A], ms[i][R_X]
                    uf[a] = uf_find(a); uf[x] = uf_find(x)
                    uf[uf_find(a)] = uf_find(x)
                end
                comp_score = Dict{Int,Int}()
                for i in labeled
                    r = uf_find(ms[i][R_A])
                    comp_score[r] = get(comp_score, r, 0) +
                                    get(career, ms[i][R_A], 0) + get(career, ms[i][R_X], 0)
                end
                scores = [comp_score[uf_find(ms[c][R_A])] for c in tied]
                best2 = maximum(scores)
                count(==(best2), scores) == 1 || return nothing
                root = tied[argmax(scores)]
            else
                root = tied[1]
            end
        elseif length(cands) == 1
            root = cands[1]
        end
    end
    root === nothing && return nothing

    # second pass, to a fixpoint: an ambiguous match links to the unique
    # candidate that is already part of the tree (e.g. a quarterfinal whose
    # winner plays both the real semifinal and a mislabeled bronze "semifinal")
    while true
        seen = reachable_from(root)
        progress = false
        for i in labeled
            (i == root || haskey(parent, i) || i in seen) && continue
            linked = [j for j in candidates(i) if j in seen]
            if length(linked) == 1
                parent[i] = linked[1]
                progress = true
            end
        end
        progress || break
        rebuild_children!()
    end

    seen = reachable_from(root)
    leftover = [i for i in eachindex(ms) if !(i in seen)]
    # losers of the two matches feeding the final (normally the semifinals; the
    # label may be wrong in dirty data, e.g. an SF mislabeled as QuarterFinal)
    sf_losers = Int[]
    for j in get(children_of, root, Int[])
        j in seen || continue
        m = ms[j]
        push!(sf_losers, m[R_W] == m[R_A] ? m[R_X] : m[R_A])
    end

    function emit(i)
        m = ms[i]
        feeder(pid) = begin
            for j in get(children_of, i, Int[])
                (j in seen && ms[j][R_W] == pid) && return emit(j)
            end
            nothing
        end
        Any[m[R_A], m[R_X], m[R_RES], m[R_W], feeder(m[R_A]), feeder(m[R_X]),
            m[R_GAMES], m[R_WO]]
    end
    return (emit(root), sort!(collect(seen)), leftover, sf_losers)
end

# ---- temporal reconstruction for label-less draws ----
# Some events (e.g. Finlandia Open 2021) carry no round labels at all, but
# match ids are chronological within a tournament. The bracket is then
# recoverable from time: a match's feeders are the two players' immediately
# preceding matches (if they won them), and the root is the last match of the
# unique unbeaten player (the champion). Consolation/placement games hang off
# losers, never off the champion's path, so they stay out of the tree. Returns
# (tree, tree_records, leftover_records, sf_losers) where tree_records are
# COPIES with R_RND set to the depth from the final (0=Final), or nothing when
# the draw has no unique unbeaten player (multi-bracket qualifiers, fragmented
# data) or no matches at all.
function build_tree_temporal(ms)
    played = [i for i in eachindex(ms)
              if ms[i][R_W] != 0 &&
                 !(string(ms[i][R_RES]) == "0:0" && isempty(strip(string(ms[i][R_GAMES]))))]
    isempty(played) && return nothing
    losses = Dict{Int,Int}()
    players = Set{Int}()
    for i in played
        m = ms[i]
        l = m[R_W] == m[R_A] ? m[R_X] : m[R_A]
        losses[l] = get(losses, l, 0) + 1
        push!(players, m[R_A]); push!(players, m[R_X])
    end
    unbeaten = [p for p in players if get(losses, p, 0) == 0]
    length(unbeaten) == 1 || return nothing

    seq = Dict{Int,Vector{Int}}()
    for i in played
        push!(get!(seq, ms[i][R_A], Int[]), i)
        push!(get!(seq, ms[i][R_X], Int[]), i)
    end
    for v in values(seq)
        sort!(v; by=i -> ms[i][R_MID])
    end

    root = last(seq[unbeaten[1]])
    depth_of = Dict{Int,Int}()
    visited = Set{Int}()
    function emit(i, d)
        i in visited && return nothing
        push!(visited, i)
        depth_of[i] = d
        m = ms[i]
        feeder(pid) = begin
            k = findfirst(==(i), seq[pid])
            (k === nothing || k == 1) && return nothing
            j = seq[pid][k-1]
            ms[j][R_W] == pid || return nothing
            emit(j, d + 1)
        end
        Any[m[R_A], m[R_X], m[R_RES], m[R_W], feeder(m[R_A]), feeder(m[R_X]),
            m[R_GAMES], m[R_WO]]
    end
    tree = emit(root, 0)
    tree === nothing && return nothing

    tree_recs = [begin
                     r = copy(ms[i])
                     r[R_RND] = depth_of[i]
                     r
                 end for i in sort!(collect(visited))]
    leftover = [ms[i] for i in played if !(i in visited)]
    sf_losers = Int[]
    for pid in (ms[root][R_A], ms[root][R_X])
        s = seq[pid]
        length(s) < 2 && continue
        j = s[end-1]
        ms[j][R_W] == pid || continue
        push!(sf_losers, ms[j][R_A] == pid ? ms[j][R_X] : ms[j][R_A])
    end
    return (tree, tree_recs, leftover, sf_losers)
end

# ---- bronze (3rd-place) match ----
# A match between the losers of the two semifinals that feed the final. It is
# not part of the knockout path and shows up in the raw data under all sorts of
# labels: a second Main-Draw "Final" (Beijing 2008), a third "SemiFinal" (World
# Cup 2011), a "Position Draw" row (Paris 2024), "(Bronze Match)" (Asian Cup
# 2018). Detect it after the tree is built, from any stage, by the
# semifinal-loser rule. `pool` = candidate records (leftovers + non-main rows).
function find_bronze(pool, sf_losers)
    length(sf_losers) == 2 || return nothing
    losers = Set(sf_losers)
    cands = [r for r in pool
             if r[R_A] in losers && r[R_X] in losers &&
                (r[R_STAGE] == 2 || r[R_RND] == 0 || r[R_RND] == 1)]
    length(cands) == 1 || return nothing
    return cands[1]
end

# (champion, runner-up, third, fourth) from the built tree; 0-filled when
# missing. third/fourth are the bronze-match players when there is one,
# otherwise the semifinal losers.
function podium_of_tree(tree, sf_losers, bronze)
    champ = tree[4]
    champ == 0 && return [0, 0, 0, 0]
    runner = tree[1] == champ ? tree[2] : tree[1]
    if bronze !== nothing
        bw = bronze[R_W]
        bl = bronze[R_A] == bw ? bronze[R_X] : bronze[R_A]
        return [champ, runner, bw, bl]
    end
    return [champ, runner, get(sf_losers, 1, 0), get(sf_losers, 2, 0)]
end

# fallback podium for non-knockout draws (first labeled Final, if any)
function podium_of(ms)
    f = filter(m -> m[R_RND] == 0, ms)
    isempty(f) && return [0, 0, 0, 0]
    f = f[1]
    champ = f[R_W]
    runner = f[R_A] == champ ? f[R_X] : f[R_A]
    sf_losers = [m[R_W] == m[R_A] ? m[R_X] : m[R_A] for m in ms if m[R_RND] == 1]
    return [champ, runner, get(sf_losers, 1, 0), get(sf_losers, 2, 0)]
end

# Neutral athletes ("AIN" in the raw match rows) are shown with their true
# association when the player profile knows one (ITTF keeps the real
# nationality in the profile even while match rows say AIN).
function _true_assoc(players::Dict{Int,Player}, pid::Int, assoc::String)::String
    assoc == "AIN" || return assoc
    p = get(players, pid, nothing)
    p === nothing && return assoc
    best, bdate = assoc, Date(0)
    for (a, d) in p.history
        if d > bdate
            best, bdate = a, d
        end
    end
    return best
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

# Player rating series from the web history shards (pid => [[monthidx, rating], ...]
# ascending). monthidx = (year-2004)*12 + month-1; the point at monthidx m is the
# rating at the *start* of month m (snapshot written before that month's events),
# i.e. exactly the rating a player carries into an event held in month m.
_month_index(d::Date) = (year(d) - 2004) * 12 + month(d) - 1

function _load_rating_series(out_dir::AbstractString)::Dict{Int,Vector{Vector{Int}}}
    dir = joinpath(out_dir, "history")
    series = Dict{Int,Vector{Vector{Int}}}()
    isdir(dir) || return series
    for f in filter(f -> startswith(f, "shard-") && endswith(f, ".json"), readdir(dir))
        shard = JSON.parsefile(joinpath(dir, f))
        for (pid_s, entry) in shard
            s = get(entry, "s", nothing)
            isempty(s) && continue
            series[parse(Int, pid_s)] = [Int[p[1], p[2]] for p in s]
        end
    end
    return series
end

# Rating at the start of month mi: last series point at or before mi.
function _rating_at(series::Vector{Vector{Int}}, mi::Int)::Union{Int,Nothing}
    lo, hi = 1, length(series)
    series[1][1] > mi && return nothing
    while lo < hi
        mid = (lo + hi + 1) ÷ 2
        series[mid][1] <= mi ? (lo = mid) : (hi = mid - 1)
    end
    return series[lo][2]
end

# id => rank maps from the monthly top-200 files, loaded lazily per (cat, ym).
function _rank_map!(cache::Dict{Tuple{Int,String},Dict{Int,Int}}, out_dir::AbstractString,
                    cat::Int, ym::String)::Dict{Int,Int}
    get!(cache, (cat, ym)) do
        path = joinpath(out_dir, "rankings", "$(cat == 0 ? "MS" : "WS")-$(ym).json")
        m = Dict{Int,Int}()
        if isfile(path)
            for row in JSON.parsefile(path)
                m[Int(row[2])] = Int(row[1])
            end
        end
        m
    end
end

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
    rating_series = _load_rating_series(out_dir)
    rank_cache = Dict{Tuple{Int,String},Dict{Int,Int}}()

    # career match counts (used to rank parallel draws in build_tree)
    career = Dict{Int,Int}()
    for r in records
        career[r[R_A]] = get(career, r[R_A], 0) + 1
        career[r[R_X]] = get(career, r[R_X], 0) + 1
    end

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
        pid_cat = Dict{Int,Int}()
        podiums = Dict{Int,Any}()

        for cat in (0, 1)
            rs = get(groups, (tid, cat), nothing)
            rs === nothing && continue
            drop_placeholder_dups!(rs)
            for r in rs
                pa[r[R_A]] = _true_assoc(players, r[R_A], r[R_AA])
                pa[r[R_X]] = _true_assoc(players, r[R_X], r[R_XA])
                pid_cat[r[R_A]] = cat
                pid_cat[r[R_X]] = cat
            end
            main = filter(r -> r[R_STAGE] == 0, rs)
            qual = filter(r -> r[R_STAGE] != 0, rs)

            payload = Dict{String,Any}()
            result_pool = main   # matches that count toward player results
            if !isempty(main)
                built = build_tree(main, career)
                tree = nothing; sf_losers = Int[]
                if built !== nothing
                    t, tree_idx, leftover_idx, sf_losers = built
                    tree = t
                    result_pool = main[tree_idx]
                    leftover = main[leftover_idx]
                else
                    tb = build_tree_temporal(main)
                    if tb !== nothing
                        tree, result_pool, leftover, sf_losers = tb
                    end
                end
                if tree === nothing
                    payload["r"] = rounds_list(main)
                    podiums[cat] = podium_of(main)
                    n_fallback += 1
                else
                    bronze = find_bronze(vcat(leftover, qual), sf_losers)
                    if bronze !== nothing
                        filter!(r -> r !== bronze, qual)
                        filter!(r -> r !== bronze, leftover)
                        payload["b"] = Any[bronze[R_A], bronze[R_X], bronze[R_RES],
                                           bronze[R_W], bronze[R_GAMES], bronze[R_WO]]
                    end
                    payload["t"] = tree
                    isempty(leftover) || (payload["x"] = rounds_list(leftover))
                    podiums[cat] = podium_of_tree(tree, sf_losers, bronze)
                    n_tree += 1
                end
            end
            if !isempty(qual)
                payload["q"] = [Any[m[R_A], m[R_X], m[R_RES], m[R_W], m[R_RND], m[R_GAMES], m[R_WO]]
                                for m in sort!(qual; by=m -> -m[R_RND])]
            end
            detail[cat == 0 ? "MS" : "WS"] = payload

            # player results (placement/leftover matches do not count)
            pids = unique!(sort!(vcat([r[R_A] for r in rs], [r[R_X] for r in rs])))
            for pid in pids
                mine_main = filter(r -> (r[R_A] == pid || r[R_X] == pid), result_pool)
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

        # entering-the-event rating & rank (month of the event start); rank is
        # only known for the monthly top 200, 0 = unranked
        start_date = try Date(detail["s"]) catch; end_date end
        mi = _month_index(start_date)
        ym = Dates.format(start_date, "yyyy-mm")
        pr = Dict{String,Any}()
        if mi >= 0
            for (pid, cat) in pid_cat
                s = get(rating_series, pid, nothing)
                s === nothing && continue
                r = _rating_at(s, mi)
                r === nothing && continue
                rank = get(_rank_map!(rank_cache, out_dir, cat, ym), pid, 0)
                pr[string(pid)] = Any[r, rank]
            end
        end
        isempty(pr) || (detail["pr"] = pr)
        _write_json(joinpath(out_dir, "events", "$(tid).json"), detail)
        push!(index_rows, Any[tid, name, detail["s"], detail["e"], org, wt,
                              get(podiums, 0, [0, 0, 0, 0]),
                              get(podiums, 1, [0, 0, 0, 0])])
    end

    sort!(index_rows; by=r -> r[4], rev=true)
    _write_json(joinpath(out_dir, "events-index.json"), index_rows)

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
            _write_json(shard_path, shard)
        end
    end

    println("events export: $(length(tids)) events (tree=$n_tree, fallback=$n_fallback), " *
            "$(length(index_rows)) indexed, player results for $(n_res) players → $out_dir")
    isempty(UNKNOWN_ROUNDS) ||
        println("  unknown round labels (→ fallback): ", join(collect(UNKNOWN_ROUNDS), ", "))
    return nothing
end
