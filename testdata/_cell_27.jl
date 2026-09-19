function parse_player_data(new_player_json::String)
    # Parse the JSON string
    data = JSON.parse(new_player_json)

    # Get player basic information
    # Get player profile information
    local profile
    try
        profile = data[1][1]["vw_profiles___profile_raw"]
    catch e
        return nothing
    end
    
    # Parse name and association (remove ID and association)
    name_with_id = data[1][1]["vw_profiles___name_raw"]
    name_match = match(r"^(.*?)\s*\(.*?\)$", name_with_id)
    name = name_match === nothing ? name_with_id : name_match.captures[1]
    
    # Parse sex
    sex = data[1][1]["vw_profiles___gender_raw"]

    # Parse association information
    assoc = nothing
    # Extract association from profile
    assoc_match = match(r"<img src='.*?/flags/([A-Z]{3})\.png'", profile)
    if assoc_match !== nothing
        assoc = assoc_match.captures[1]
    end
    
    # If the above method fails, try to extract from player_id
    if assoc === nothing
        # Match the content in the last parentheses
        assoc_match = match(r"\(([^()]*)\)[^()]*$", data[1][1]["vw_profiles___player_id"])
        if assoc_match !== nothing
            assoc = assoc_match.captures[1]
        end
    end
    
    # Use regular expressions to parse other fields
    yob_match = match(r"YoB:\s*(\d+)", profile)
    yob = yob_match === nothing ? nothing : parse(Int, yob_match.captures[1])

    # If yob is not found, compute it with age
    if yob === nothing
        age_match = match(r"Age:\s*(\d+)", profile)
        if age_match !== nothing
            age = parse(Int, age_match.captures[1])
            current_year = year(today())
            yob = current_year - age
        end
    end
    
    # Match handedness, could be Left-Hand, Right-Hand or Unknown Handness
    hand_match = match(r"Style:\s*(.*?Hand\w*)", profile)
    hand = hand_match === nothing ? nothing : hand_match.captures[1]
    
    # Match playing style, in the Style tag, after handedness and before parentheses
    style_match = match(r"Style:\s*.*?Hand\w*\s+(.*?)\s*\(", profile)
    style = style_match === nothing ? nothing : strip(style_match.captures[1])
    
    # Match grip style, in the Style tag, inside parentheses
    grip_match = match(r"Style:.*?\((.*?)\)", profile)
    grip = grip_match === nothing ? nothing : strip(grip_match.captures[1])
    
    # Create player history record, add current association to today's date by default
    history = Dict{String, Date}()
    if assoc !== nothing
        history[assoc] = today()
    end
    
    # Get player ID from the data
    player_id = data[1][1]["vw_profiles___player_id_raw"]
    
    # Create player data object
    player_data = Player(
        player_id,
        name,
        sex === nothing ? "U" : sex,
        history,  # History record containing default association information
        yob === nothing ? 0 : yob,
        hand === nothing ? "Unknown Handness" : hand,
        style === nothing ? "Unknown Style" : style,
        grip === nothing ? "Unknown Grip" : grip
    )
    
    return player_data
end