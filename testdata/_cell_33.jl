function update_player_associations(events::Vector{Event}, players::Dict{Int, Player})
    
    # Map deprecated association codes to correct ones
    assoc_mapping = Dict(
        "BLZ" => "BIZ",
        "ROM" => "ROU",
        "SIN" => "SGP",
        "SRL" => "SRI"
    )
    
    # Function to process association information for a single player
    function process_player_assoc(player_id, assoc, event_date)
        if !haskey(players, player_id) || assoc === nothing
            return
        end
        
        # Skip AIN association
        if assoc == "AIN"
            return
        end
        
        # Handle association code mapping
        if haskey(assoc_mapping, assoc)
            assoc = assoc_mapping[assoc]
        end
        
        player = players[player_id]
        # Only update if the association doesn't exist or the new date is later
        if !haskey(player.history, assoc) || event_date > player.history[assoc]
            player.history[assoc] = event_date
        end
    end
    
    # Iterate through all events and matches
    for event in events
        event_date = event.time
        for match in event.match
            process_player_assoc(match.player_a_id, match.player_a_assoc, event_date)
            process_player_assoc(match.player_x_id, match.player_x_assoc, event_date)
        end
    end
    
end

# Update players' association history
update_player_associations(new_events, players)
println("The associations are updated.")