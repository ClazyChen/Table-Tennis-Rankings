# web_export.jl — emit compact JSON bundles for the static web frontend into
# web/data/. Data is collected during the compute_rankings replay via the
# on_month/on_latest callbacks (zero extra replay cost), then written by
# export_web_data. Bundles are loaded on demand by the frontend:
#   index.json            month list + generation info
#   latest.json           full active ranking (MS/WS) as of today
#   rankings/MS-YYYY-MM.json, rankings/WS-YYYY-MM.json
#                         monthly top-200 rows [rank,id,rating,delta,age,assoc]
#   history/shard-XX.json player meta + rating series, sharded by id % 64
#   search.json           [id, name, cnName] for the search box
#   flags/<ASSOC>.png     association flags referenced by the data

using JSON
using Dates
using Printf

mutable struct WebExportCollector
    months::Vector{String}
    month_rows::Dict{String,Vector{Any}}      # "MS-2004-01" => rows
    series::Dict{Int,Vector{Vector{Int}}}     # player_id => [[monthidx, rating], ...]
    prev_rank::Dict{String,Dict{Int,Int}}     # "M"/"W" => previous month ranking
    latest_rows::Dict{String,Vector{Any}}     # "MS"/"WS" => rows (full active list)
    final_ratings::Dict{Int,Float64}          # every player's rating after the last replayed event
    WebExportCollector() = new(String[], Dict{String,Vector{Any}}(),
                               Dict{Int,Vector{Vector{Int}}}(),
                               Dict("M" => Dict{Int,Int}(), "W" => Dict{Int,Int}()),
                               Dict{String,Vector{Any}}(), Dict{Int,Float64}())
end

month_index(date::Date) = (year(date) - 2004) * 12 + month(date) - 1
_ym(date::Date) = Dates.format(date, "yyyy-mm")

function _is_active_on(periods::Vector{Period}, date::Date)::Bool
    for p in periods
        p.start <= date <= p.fin && return true
    end
    return false
end

# One ranking row per player:
#   [rank, id, rating, delta, age, assoc, hand, grip, style]
# delta = previous month's rank minus current rank (positive = climbed), or "NEW".
# hand/grip/style are compact codes: L/R/?, S(hakehand)/P(enhold)/?, A(ttack)/D(efence)/?.
function _attr_codes(player::Player)
    hand = player.hand == "Left-Hand" ? "L" : player.hand == "Right-Hand" ? "R" : "?"
    grip = player.grip == "ShakeHand" ? "S" : player.grip == "Penhold" ? "P" : "?"
    style = player.style == "Attack" ? "A" : player.style == "Defence" ? "D" : "?"
    return hand, grip, style
end

function _web_rows(date::Date, ids::Vector{Int}, ratings::Dict{Int,Float64},
                   prev_ranking::Dict{Int,Int}, players::Dict{Int,Player}; count::Int)
    rows = Any[]
    n = min(count, length(ids))
    for i in 1:n
        pid = ids[i]
        player = players[pid]
        delta = haskey(prev_ranking, pid) ? prev_ranking[pid] - i : "NEW"
        hand, grip, style = _attr_codes(player)
        push!(rows, Any[i, pid, floor(Int, ratings[pid]), delta,
                        year(date) - player.yob, player_assoc_on_date(player, date),
                        hand, grip, style])
    end
    return rows
end

function collect_month!(c::WebExportCollector, date::Date, ratings::Dict{Int,Float64},
                        ranking_m::Dict{Int,Int}, ranking_f::Dict{Int,Int},
                        players::Dict{Int,Player}, active_periods::Dict{Int,Vector{Period}})
    ym = _ym(date)
    for (t, rmap) in (("M", ranking_m), ("W", ranking_f))
        ids = ranked_active_players(date, t, ratings, players, active_periods)
        c.month_rows["$(t)S-$(ym)"] = _web_rows(date, ids, ratings, c.prev_rank[t], players; count=200)
        c.prev_rank[t] = rmap
    end
    # Rating series point for every active player (both genders).
    mi = month_index(date)
    for (pid, periods) in active_periods
        if _is_active_on(periods, date) && haskey(ratings, pid)
            push!(get!(c.series, pid, Vector{Int}[]), Int[mi, floor(Int, ratings[pid])])
        end
    end
    push!(c.months, ym)
    return c
end

function collect_latest!(c::WebExportCollector, date::Date, ratings::Dict{Int,Float64},
                         ranking_m::Dict{Int,Int}, ranking_f::Dict{Int,Int},
                         players::Dict{Int,Player}, active_periods::Dict{Int,Vector{Period}})
    for (t, rmap) in (("M", ranking_m), ("W", ranking_f))
        ids = ranked_active_players(date, t, ratings, players, active_periods)
        c.latest_rows["$(t)S"] = _web_rows(date, ids, ratings, c.prev_rank[t], players; count=length(ids))
    end
    c.final_ratings = copy(ratings)
    return c
end

# translate.txt: "EN name, 中文名" per line (same parsing as translate()).
function _load_cn_names(path::AbstractString="translate.txt")::Dict{String,String}
    d = Dict{String,String}()
    isfile(path) || return d
    for line in eachline(path)
        words = split(line, ",")
        length(words) >= 2 || continue
        d[strip(words[1])] = strip(words[2])
    end
    return d
end

function export_web_data(c::WebExportCollector, players::Dict{Int,Player}, highest;
                         out_dir::AbstractString="web/data")
    mkpath(joinpath(out_dir, "rankings"))
    mkpath(joinpath(out_dir, "history"))
    mkpath(joinpath(out_dir, "flags"))

    for (key, rows) in c.month_rows
        open(joinpath(out_dir, "rankings", "$(key).json"), "w") do io
            JSON.print(io, rows)
        end
    end

    open(joinpath(out_dir, "latest.json"), "w") do io
        JSON.print(io, c.latest_rows)
    end

    peak = Dict{Int,Float64}(highest)
    cn = _load_cn_names()

    n_shards = 64
    shards = [Dict{String,Any}() for _ in 1:n_shards]
    assocs_used = Set{String}()
    for (pid, series) in c.series
        player = players[pid]
        cur_assoc = player_assoc_on_date(player, today())
        push!(assocs_used, cur_assoc)
        for a in keys(player.history)
            push!(assocs_used, a)
        end
        # Final point: rating after the player's last match, placed one month
        # after their last monthly snapshot, so the chart endpoint matches the
        # displayed "current rating" (including retired players).
        last_mi, last_r = series[end]
        final = haskey(c.final_ratings, pid) ? floor(Int, c.final_ratings[pid]) : last_r
        final != last_r && push!(series, Int[last_mi + 1, final])
        meta = Any[player.name, get(cn, player.name, player.name), player.sex, player.yob,
                   player.hand, player.grip, player.style, cur_assoc,
                   floor(Int, get(peak, pid, 0.0)), final]
        shards[pid % n_shards + 1][string(pid)] = Dict("m" => meta, "s" => series)
    end
    for (i, shard) in enumerate(shards)
        open(joinpath(out_dir, "history", @sprintf("shard-%02d.json", i - 1)), "w") do io
            JSON.print(io, shard)
        end
    end

    search = [Any[pid, players[pid].name, get(cn, players[pid].name, players[pid].name)]
              for pid in sort!(collect(keys(c.series)))]
    open(joinpath(out_dir, "search.json"), "w") do io
        JSON.print(io, search)
    end

    open(joinpath(out_dir, "index.json"), "w") do io
        JSON.print(io, Dict("months" => c.months, "generated" => string(today()),
                            "players" => length(c.series)))
    end

    n_flags = 0
    for a in assocs_used
        src = joinpath("data", "flags", "$(a).png")
        isfile(src) || continue
        cp(src, joinpath(out_dir, "flags", "$(a).png"); force=true)
        n_flags += 1
    end

    println("web export: $(length(c.month_rows)) month files, $(length(c.series)) players, " *
            "$(n_shards) shards, $(n_flags) flags → $out_dir")
end
