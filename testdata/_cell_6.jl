function read_events_from_files()
    # Create data/events directory if it doesn't exist
    if !isdir("data/events")
        mkdir("data/events")
        println("Created data/events directory")
    end
    
    # Store events in a Dict with Date keys and Vector{Event} values
    events_by_date = Dict{Date, Vector{Event}}()
    
    # Get all JSON files from data/events directory
    event_files = filter(f -> endswith(f, ".json"), readdir("data/events", join=true))
    
    for file_path in event_files
        open(file_path, "r") do file
            data = JSON.parse(read(file, String))
            
            # Process each event in the file
            for event_data in data
                if haskey(event_data, "id") && haskey(event_data, "name") && 
                   haskey(event_data, "weight") && haskey(event_data, "time") && 
                   haskey(event_data, "match")
                    
                    # Parse match data
                    matches = Match[]
                    for match_data in event_data["match"]
                        if haskey(match_data, "player_a_id") && haskey(match_data, "player_x_id") &&
                           haskey(match_data, "player_a_assoc") && haskey(match_data, "player_x_assoc") &&
                           haskey(match_data, "weight") && haskey(match_data, "result") && 
                           haskey(match_data, "games")
                            
                            push!(matches, Match(
                                match_data["player_a_id"],
                                match_data["player_x_id"],
                                match_data["player_a_assoc"],
                                match_data["player_x_assoc"],
                                match_data["weight"],
                                match_data["result"],
                                match_data["games"]
                            ))
                        end
                    end
                    
                    # Create event object
                    event_date = Date(event_data["time"], "yyyymmdd")
                    event = Event(
                        event_data["id"],
                        event_data["name"],
                        event_data["weight"],
                        event_date,
                        matches
                    )
                    
                    # Add to date-indexed dictionary
                    if !haskey(events_by_date, event_date)
                        events_by_date[event_date] = Event[]
                    end
                    push!(events_by_date[event_date], event)
                end
            end
        end
    end
    
    return events_by_date
end

# Read all events
events = read_events_from_files()
println("Read events for $(length(events)) dates from data/events directory")