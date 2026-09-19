# rating.jl — the modified-ELO rating core.
#
# Classic ELO plus two sigmoid-based modifications ("long jump" and
# "centripetal force"), plus active-period tracking. Full math spec and
# parameter table: docs/algorithm.md.

using Dates

# Parameters
const W = 50.0
const D1 = 1000.0
const D2 = 1000.0
const D3 = 250.0
const r0 = 1500.0
const rc = 3000.0
const α = 0.25
const β = 0

const date_0 = Date("2004-01-01")
const date_1 = Date("2010-01-01")

function update_rating(r1::Float64, r2::Float64, wm::Float32, we::Float32, date::Date)
    a1 = wm > 0.0 ? 1.0 : (wm < 0.0 ? 0.0 : 0.5)
    wm = abs(wm)
    if date < date_0
        wm *= 2
    end
    if date < date_1
        wm *= 2
    end

    # Calculate opponent's result
    a2 = 1.0 - a1

    # Step 1: Calculate ELO expectation
    e1 = 1.0 / (1.0 + 10.0^((r1 - r2) / D1))
    e2 = 1.0 / (1.0 + 10.0^((r2 - r1) / D1))

    # Step 2: Calculate raw rating delta
    Δ1 = wm * we * W * (a1 - e1)
    Δ2 = wm * we * W * (a2 - e2)

    # Step 3: Centripetal force (based on default and ceiling ratings)
    if Δ1 < 0
        Δ1_prime = Δ1 * (2.0 / (1.0 + 10.0^(-(r1 - r0) / D2)))
    else
        Δ1_prime = Δ1 * (2.0 / (1.0 + 10.0^((r1 - rc) / D2)))
    end

    if Δ2 < 0
        Δ2_prime = Δ2 * (2.0 / (1.0 + 10.0^(-(r2 - r0) / D2)))
    else
        Δ2_prime = Δ2 * (2.0 / (1.0 + 10.0^((r2 - rc) / D2)))
    end

    # Step 4: Centripetal force (based on opponent's rating)
    if Δ1 < 0
        Δ1_dprime = Δ1_prime * (2.0 / (1.0 + 10.0^(-(r1 - r2) / D3)))
    else
        Δ1_dprime = Δ1_prime * (2.0 / (1.0 + 10.0^((r1 - r2) / D3)))
    end

    if Δ2 < 0
        Δ2_dprime = Δ2_prime * (2.0 / (1.0 + 10.0^(-(r2 - r1) / D3)))
    else
        Δ2_dprime = Δ2_prime * (2.0 / (1.0 + 10.0^((r2 - r1) / D3)))
    end

    # Step 5: Result of centripetal force
    r1_prime = r1 + Δ1_dprime
    r2_prime = r2 + Δ2_dprime

    # Step 6: Long jump
    if r1 < r1_prime && r1_prime < r2
        r1_prime = r1_prime + α * (r2 - r1_prime)
    elseif r1 > r1_prime && r1_prime > r2
        r1_prime = r1_prime + β * (r2 - r1_prime)
    end

    if r2 < r2_prime && r2_prime < r1
        r2_prime = r2_prime + α * (r1 - r2_prime)
    elseif r2 > r2_prime && r2_prime > r1
        r2_prime = r2_prime + β * (r1 - r2_prime)
    end

    return r1_prime, r2_prime
end

struct Period
    start::Date
    fin::Date
end

function compute_active_periods(events::Dict{Date, Vector{Event}}, players::Dict{Int, Player})
    # Initialize dictionary to store active periods for each player
    active_periods = Dict{Int, Vector{Period}}()

    # Track the last match date for each player
    last_match_date = Dict{Int, Date}()

    # Process all events in chronological order
    sorted_dates = sort(collect(keys(events)))

    for date in sorted_dates
        for event in events[date]
            for match in event.match
                for player_id in [match.player_a_id, match.player_x_id]
                    if haskey(players, player_id)
                        update_player_period(player_id, date, active_periods, last_match_date)
                    end
                end
            end
        end
    end

    # Close any open active periods
    current_date = Dates.today()
    for (player_id, last_date) in last_match_date
        if haskey(active_periods, player_id) && length(active_periods[player_id]) > 0
            last_period = active_periods[player_id][end]
            if last_period.fin == Date(9999, 12, 31)  # If period is still open
                if Dates.value(current_date - last_date) <= 365
                    active_periods[player_id][end] = Period(last_period.start, current_date)
                else
                    active_periods[player_id][end] = Period(last_period.start, last_date)
                end
            end
        end
    end

    return active_periods
end

function update_player_period(player_id::Int, date::Date,
                             active_periods::Dict{Int, Vector{Period}},
                             last_match_date::Dict{Int, Date})
    # Initialize active period record for new players
    if !haskey(active_periods, player_id)
        active_periods[player_id] = [Period(date, Date(9999, 12, 31))]
        last_match_date[player_id] = date
        return
    end

    # Get player's last match date
    last_date = last_match_date[player_id]

    # If more than 1000 days have passed, start a new active period
    if Dates.value(date - last_date) > 1000
        # Close the previous active period
        if length(active_periods[player_id]) > 0 && active_periods[player_id][end].fin == Date(9999, 12, 31)
            active_periods[player_id][end] = Period(active_periods[player_id][end].start, last_date)
        end

        # Start a new active period
        push!(active_periods[player_id], Period(date, Date(9999, 12, 31)))
    end

    # Update the last match date
    last_match_date[player_id] = date
end

# Replay all events chronologically, writing a monthly snapshot before each
# month's events, and finally MS/WS-latest.typ (top 1000).
# Returns the all-time highest rating per player, sorted descending.
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
