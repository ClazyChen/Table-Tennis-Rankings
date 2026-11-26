# Annual score web bundles. This is a display-layer aggregation of the monthly
# rating series; it does not modify or replay the main ranking algorithm.

const ANNUAL_TOP_N = 200

annual_score(adjusted_rating::Real) = clamp(90.0 + (adjusted_rating - 3000.0) / 20.0, 0.0, 100.0)

function annual_played_months(events::Dict{Date,Vector{Event}})
    played = Dict{Int,Set{Int}}()
    for dated_events in values(events), event in dated_events, match in event.match
        mi = month_index(event.time)
        for pid in (match.player_a_id, match.player_x_id)
            push!(get!(() -> Set{Int}(), played, pid), mi)
        end
    end
    return played
end

function annual_rating_values(c::WebExportCollector, valid_months::Set{Int})
    result = Dict{Int,Dict{Int,Int}}()
    for (pid, series) in c.series
        values = Dict{Int,Int}()
        for point in series
            mi, rating = point
            mi in valid_months && (values[mi] = rating)
        end
        if !isempty(series) && haskey(c.final_ratings, pid)
            last_mi, last_rating = series[end]
            final = floor(Int, c.final_ratings[pid])
            if final != last_rating && last_mi + 1 in valid_months
                values[last_mi + 1] = final
            end
        end
        result[pid] = values
    end
    return result
end

function annual_active_ids(c::WebExportCollector)
    return Set{Int}(row[2] for rows in values(c.latest_rows) for row in rows)
end

function write_annual_period(c::WebExportCollector, players::Dict{Int,Player},
                             rating_values::Dict{Int,Dict{Int,Int}},
                             played::Dict{Int,Set{Int}}, active_ids::Set{Int},
                             period::String, sample_months::Vector{Int},
                             played_months::Vector{Int}, add_current::Bool,
                             as_of::Date, out_dir::AbstractString)
    for (gender, key) in (("M", "MS"), ("W", "WS"))
        candidates = []
        for (pid, player) in players
            player.sex == gender || continue
            months = get(played, pid, nothing)
            months === nothing && continue
            played_count = count(mi -> mi in months, played_months)
            played_count > 0 || continue

            values = get(rating_values, pid, Dict{Int,Int}())
            samples = Int[]
            for mi in sample_months
                haskey(values, mi) && push!(samples, values[mi])
            end
            if add_current && pid in active_ids && haskey(c.final_ratings, pid)
                push!(samples, floor(Int, c.final_ratings[pid]))
            end
            isempty(samples) && continue

            average = sum(samples) / length(samples)
            penalty = 100 * max(0, 3 - played_count)
            adjusted = average - penalty
            push!(candidates, (pid=pid, average=average, penalty=penalty,
                               adjusted=adjusted, played=played_count))
        end
        sort!(candidates, by=x -> (-x.adjusted, -x.average, x.pid))

        rows = Any[]
        for (rank, item) in enumerate(candidates[1:min(ANNUAL_TOP_N, length(candidates))])
            player = players[item.pid]
            push!(rows, Any[
                rank,
                item.pid,
                round(annual_score(item.adjusted); digits=1),
                item.played,
                year(as_of) - player.yob,
                player_assoc_on_date(player, as_of),
                round(item.average; digits=1),
                item.penalty,
            ])
        end
        open(joinpath(out_dir, "$(key)-$(period).json"), "w") do io
            JSON.print(io, rows)
        end
    end
end

function export_annual_web_data(c::WebExportCollector,
                                events::Dict{Date,Vector{Event}},
                                players::Dict{Int,Player};
                                out_dir::AbstractString="web/data",
                                as_of::Date=today())
    annual_dir = joinpath(out_dir, "annual")
    mkpath(annual_dir)
    isempty(c.months) && error("Cannot export annual scores without monthly snapshots")

    valid_months = Set(month_index(Date(ym * "-01")) for ym in c.months)
    rating_values = annual_rating_values(c, valid_months)
    played = annual_played_months(events)
    active_ids = annual_active_ids(c)

    first_year = year(Date(first(c.months) * "-01"))
    last_complete_year = year(as_of) - 1
    current_mi = month_index(as_of)
    years = collect(first_year:last_complete_year)

    for y in years
        sample_months = [month_index(Date(y, m, 1)) + 1 for m in 1:12]
        played_months = [month_index(Date(y, m, 1)) for m in 1:12]
        write_annual_period(c, players, rating_values, played, active_ids,
                            string(y), sample_months, played_months, false,
                            Date(y, 12, 31), annual_dir)
    end

    write_annual_period(c, players, rating_values, played, active_ids,
                        "current", collect(current_mi - 10:current_mi),
                        collect(current_mi - 11:current_mi), true, as_of, annual_dir)

    open(joinpath(out_dir, "annual-index.json"), "w") do io
        JSON.print(io, Dict("years" => years, "generated" => string(as_of)))
    end
    println("annual web export: $(length(years)) calendar years + rolling current, " *
            "top $ANNUAL_TOP_N → $annual_dir")
end
