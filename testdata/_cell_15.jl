function convert_ittf_event(raw_event)
    # Extract only the necessary fields from ITTF format
    id = raw_event["vw_tournaments___tournament_id_raw"]
    name = raw_event["vw_tournaments___tournament_raw"]
    time = Date(raw_event["vw_tournaments___tour_end_raw"])
    type = raw_event["vw_tournaments___type"]
    weight_ = weight(type, name)
    
    return Event(id, name, weight_, time, Match[])
end

function process_events(existing_events::Dict{Date, Vector{Event}}, new_events_json::String)
    events = Event[]
    
    data = JSON.parse(new_events_json)
    new_data = [[]]

    # ITTF format has array of arrays
    for event_list in data
        for raw_event in event_list
            # Convert and store each event immediately
            event = convert_ittf_event(raw_event)
            if !haskey(existing_events, event.time) || 
                !any(e -> e.id == event.id, existing_events[event.time])
                push!(new_data[1], raw_event)
                push!(events, event)
            end
        end
    end
    
    return events, new_data
end