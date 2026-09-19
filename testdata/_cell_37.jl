# Merge new events into existing events and return modified dates
function merge_events(events::Dict{Date, Vector{Event}}, new_events::Vector{Event})
    # Track modified dates
    modified_dates = Set{Date}()
    
    # Merge new events
    for new_event in new_events
        date = new_event.time
        
        # Record this date as modified
        push!(modified_dates, date)
        
        # If this date doesn't exist yet, create a new entry
        if !haskey(events, date)
            events[date] = Event[]
        end
        
        # Check if an event with the same ID already exists
        existing_index = findfirst(e -> e.id == new_event.id, events[date])
        
        if existing_index !== nothing
            # Update existing event
            events[date][existing_index] = new_event
        else
            # Add new event
            push!(events[date], new_event)
        end
    end
    
    return modified_dates
end

modified_dates = merge_events(events, new_events)
println("Number of modified dates: $(length(modified_dates))")
println("Total number of events organized by date: $(length(events))")