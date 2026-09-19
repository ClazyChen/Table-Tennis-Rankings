struct Period
    start::Date
    fin::Date
end

function compute_active_periods(events::Dict{Date, Vector{Event}})
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

active_periods = compute_active_periods(events)
println("Calculated $(length(active_periods)) players' active periods")