function save_events_to_files(events_data::Dict{Date, Vector{Event}}, modified_dates::Set{Date})
    # Create necessary directories if they don't exist
    mkpath("data")
    mkpath("data/events")

    # Only save files for dates in modified_dates
    saved_count = 0
    for date in modified_dates
        if haskey(events_data, date)
            date_events = events_data[date]
            
            # Convert Event structs to dictionaries
            events_dict = []
            for event in date_events
                event_dict = Dict(
                    "id" => event.id,
                    "name" => event.name,
                    "weight" => event.weight,
                    "time" => Dates.format(event.time, "yyyymmdd"),
                    "match" => [
                        Dict(
                            "player_a_id" => m.player_a_id,
                            "player_x_id" => m.player_x_id,
                            "player_a_assoc" => m.player_a_assoc,
                            "player_x_assoc" => m.player_x_assoc,
                            "weight" => m.weight,
                            "result" => m.result,
                            "games" => m.games
                        ) for m in event.match
                    ]
                )
                push!(events_dict, event_dict)
            end

            # Write to JSON file with date as filename
            open("data/events/$date.json", "w") do f
                JSON.print(f, events_dict, 2)
            end
            
            saved_count += 1
        end
    end
    
    println("Successfully saved $(saved_count) modified date files to data/events/")
end

save_events_to_files(events, modified_dates)