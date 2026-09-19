# ittf_convert.jl — convert raw ITTF Fabrik JSON (events/matches/players)
# into the core structures, and load freshly crawled batches from disk.
#
# Raw ITTF format field reference: see docs/algorithm.md.

using JSON
using Dates

function convert_ittf_event(raw_event)
    # Extract only the necessary fields from ITTF format
    id = raw_event["vw_tournaments___tournament_id_raw"]
    name = raw_event["vw_tournaments___tournament_raw"]
    time = Date(raw_event["vw_tournaments___tour_end_raw"])
    type = raw_event["vw_tournaments___type"]
    weight_ = weight(type, name)

    return Event(id, name, weight_, time, Match[])
end

# Parse a raw events JSON string; returns (events, new_data) where new_data
# keeps only the raw rows not already present in existing_events.
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

function convert_ittf_match(raw_match)
    player_a_id = raw_match["vw_matches___player_a_id_raw"]
    player_x_id = raw_match["vw_matches___player_x_id_raw"]
    player_a_assoc = raw_match["vw_matches___assoc_a_raw"]
    player_x_assoc = raw_match["vw_matches___assoc_x_raw"]

    if (haskey(raw_match, "vw_matches___player_b_id_raw") && !isnothing(raw_match["vw_matches___player_b_id_raw"])) ||
       (haskey(raw_match, "vw_matches___player_y_id_raw") && !isnothing(raw_match["vw_matches___player_y_id_raw"]))
        return nothing
    end
    if isnothing(player_a_id) || isnothing(player_x_id)
        return nothing
    end

    result = replace(string(raw_match["vw_matches___res_raw"]), " - " => ":")
    games = strip(replace(string(raw_match["vw_matches___games_raw"]), r"\s*0:0\s*$" => ""))
    w = result_to_weight(result)
    a_assoc = isnothing(player_a_assoc) ? "" : string(player_a_assoc)
    x_assoc = isnothing(player_x_assoc) ? "" : string(player_x_assoc)
    return Match(Int(player_a_id), Int(player_x_id), a_assoc, x_assoc, Float32(w), result, games)
end

function process_matches(new_matches_json::String, event::Event)
    data = JSON.parse(new_matches_json)
    new_match_count = 0
    for match_list in data
        for raw_match in match_list
            m = convert_ittf_match(raw_match)
            if !isnothing(m)
                push!(event.match, m)
                new_match_count += 1
            end
        end
    end
    return new_match_count
end

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
    # ITTF wraps profile values in <span class='notranslate'>…</span> (since ~2025);
    # strip the tags so the regexes below see plain text
    profile = replace(profile, r"</?span[^>]*>" => "")

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
    if yob_match === nothing
        yob_match = match(r"Birth Year:\s*(\d+)", profile)
    end
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

# --- Loading freshly crawled data (written by ITTFFabrik.run_crawl!) ---

function load_events_batch(batch::AbstractString)::Vector{Event}
    isfile(batch) || error("Missing event batch: $batch")
    raw = JSON.parsefile(batch)
    rows = raw isa AbstractVector && !isempty(raw) && raw[1] isa AbstractVector ? raw[1] : raw
    out = Event[]
    for r in rows
        push!(out, convert_ittf_event(r))
    end
    println("Loaded $(length(out)) events from $batch")
    return out
end

function load_crawled_matches_into_new_events!(new_events::Vector{Event};
                                              from_file::Int, to_file::Int)
    by_id = Dict{Int,Event}(Int(e.id) => e for e in new_events)
    for e in new_events
        empty!(e.match)
    end
    loaded_files = 0
    loaded_matches = 0
    skipped = 0
    for n in from_file:to_file
        path = joinpath("matches", "matches_$(n).json")
        isfile(path) || continue
        txt = read(path, String)
        data = JSON.parse(txt)
        rows = (data isa AbstractVector && !isempty(data) && data[1] isa AbstractVector) ? data[1] : data
        isempty(rows) && continue
        tid = Int(rows[1]["vw_matches___tournament_id_raw"])
        if !haskey(by_id, tid)
            skipped += 1
            continue
        end
        loaded_matches += process_matches(txt, by_id[tid])
        loaded_files += 1
    end
    println("Matches: files=$(loaded_files) ($from_file-$to_file), singles=$(loaded_matches), skipped=$skipped")
    println("Events with matches: $(count(e -> !isempty(e.match), new_events)) / $(length(new_events))")
    return loaded_matches
end

function load_new_players_from_disk(new_events::Vector{Event}, existing::Dict{Int,Player})::Vector{Player}
    ids = Set{Int}()
    for ev in new_events, m in ev.match
        push!(ids, Int(m.player_a_id))
        push!(ids, Int(m.player_x_id))
    end
    out = Player[]
    missing = Int[]
    for id in sort!(collect(ids))
        haskey(existing, id) && continue
        path = joinpath("players", "$(id).json")
        if !isfile(path) || filesize(path) < 20
            push!(missing, id)
            continue
        end
        pl = parse_player_data(read(path, String))
        if pl === nothing
            push!(missing, id)
            continue
        end
        push!(out, pl)
    end
    println("New players from disk: $(length(out)); missing files/parse: $(length(missing))")
    isempty(missing) || println("Missing examples: ", missing[1:min(10, end)])
    return out
end

function merge_players!(existing::Dict{Int,Player}, new_players::Vector{Player})
    added = 0
    for pl in new_players
        if haskey(existing, pl.id)
            @warn "player already exists, skip" id=pl.id name=pl.name
        else
            existing[pl.id] = pl
            added += 1
        end
    end
    println("Merged players: +$added → total $(length(existing))")
end

# Repair players whose profile fields were parsed from a changed ITTF HTML
# layout (values wrapped in <span class='notranslate'>, leaving raw HTML in
# hand/grip/style). Re-parses the raw dumps on disk; event-derived association
# history is preserved.
function repair_malformed_profiles!(players::Dict{Int,Player})
    bad = [p for p in values(players)
           if occursin('<', p.hand) || occursin('<', p.grip) || occursin('<', p.style)]
    fixed = 0
    for p in bad
        path = joinpath("players", "$(p.id).json")
        isfile(path) || continue
        pl = parse_player_data(read(path, String))
        pl === nothing && continue
        players[p.id] = Player(pl.id, pl.name, pl.sex, p.history,
                               pl.yob == 0 ? p.yob : pl.yob, pl.hand, pl.style, pl.grip)
        fixed += 1
    end
    println("Repaired malformed profiles: $fixed / $(length(bad))")
    return fixed
end
