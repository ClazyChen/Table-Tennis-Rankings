function convert_ittf_match(raw_match)
    # Extract player IDs
    player_a_id = raw_match["vw_matches___player_a_id_raw"]
    player_x_id = raw_match["vw_matches___player_x_id_raw"]

    # Extract player Assocs
    player_a_assoc = raw_match["vw_matches___assoc_a_raw"]
    player_x_assoc = raw_match["vw_matches___assoc_x_raw"]
    
    # Skip if not single match (player_b or player_y exists)
    if haskey(raw_match, "vw_matches___player_b_id_raw") && 
        !isnothing(raw_match["vw_matches___player_b_id_raw"]) ||
        haskey(raw_match, "vw_matches___player_y_id_raw") && 
        !isnothing(raw_match["vw_matches___player_y_id_raw"])
        return nothing
    end
    
    # Check null values (withdraw)
    if isnothing(player_a_id) || isnothing(player_x_id)
        return nothing
    end
    
    # Convert result from "A - X" to "A:X" format
    result = replace(raw_match["vw_matches___res_raw"], " - " => ":")
        
    # Get games result, remove possible "0:0" or space suffix
    games = strip(replace(raw_match["vw_matches___games_raw"], r"\s*0:0\s*$" => ""))

    # Compute the weight by result
    weight = result_to_weight(result)

    return Match(player_a_id, player_x_id, player_a_assoc, player_x_assoc, weight, result, games)
end

function process_matches(new_matches_json::String, event::Event)    
    data = JSON.parse(new_matches_json)
    
    new_match_count = 0

    # ITTF format has array of arrays
    for match_list in data
        for raw_match in match_list
            match = convert_ittf_match(raw_match)
            # Only add valid single matches
            if !isnothing(match)
                push!(event.match, match)
                new_match_count += 1
            end
        end
    end

    return new_match_count
end