# structures.jl — core data structures and processed-data ("my format") I/O.
#
# Processed format (committed to git):
#   data/events/YYYYMMDD.json — events with their matches, one file per end-date
#   data/players.json         — single array of all players
#
# See docs/algorithm.md for the format specification.

using JSON
using Dates

struct Match
    player_a_id::Int
    player_x_id::Int
    player_a_assoc::String
    player_x_assoc::String
    weight::Float32
    result::String
    games::String
end

struct Event
    id::Int
    name::String
    weight::Float32
    time::Date
    match::Vector{Match}
end

struct Player
    id::Int
    name::String
    sex::String
    history::Dict{String, Date}
    yob::Int
    hand::String
    style::String
    grip::String
end

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

# Read Player information
function read_players_from_file(file_path::String = "data/players.json")
    players_dict = Dict{Int, Player}()

    if isfile(file_path)
        open(file_path, "r") do file
            player_data = JSON.parse(file)

            for player in player_data
                # Process association information
                associations = Dict{String, Date}()
                if haskey(player, "history")
                    for (assoc, date_str) in player["history"]
                        associations[assoc] = Date(date_str)
                    end
                end

                # Create Player object and add to dictionary with player_id as key
                player_id = player["id"]
                players_dict[player_id] = Player(
                    player_id,
                    player["name"],
                    get(player, "sex", "U"),
                    associations,
                    get(player, "yob", 0),
                    get(player, "hand", "Unknown Handness"),
                    get(player, "style", "Unknown Style"),
                    get(player, "grip", "Unknown Grip")
                )
            end
        end
    else
        println("Warning: Player data file $file_path not found")
    end

    return players_dict
end

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

# Save player data to JSON file
function save_players_to_json(players, filename)
    # Create directory if it doesn't exist
    dir_path = dirname(filename)
    if !isdir(dir_path)
        mkpath(dir_path)
    end

    # Convert player data to serializable format
    serializable_players = []
    for (id, player) in players
        player_dict = Dict(
            "id" => player.id,
            "name" => player.name,
            "sex" => player.sex,
            "history" => Dict(assoc => string(date) for (assoc, date) in player.history),
            "yob" => player.yob,
            "hand" => player.hand,
            "style" => player.style,
            "grip" => player.grip
        )
        push!(serializable_players, player_dict)
    end

    # Write to JSON file
    open(filename, "w") do io
        JSON.print(io, serializable_players)
    end

    println("Saved data for $(length(players)) players to $filename")
end

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

# 过滤掉所有比赛都是11:0或0:11的比赛
function filter_perfect_matches(events_dict::Dict{Date, Vector{Event}})
    filtered_events = Dict{Date, Vector{Event}}()

    for (event_date, events) in events_dict
        for event in events
            # 如果有比赛每一场都是11:0或0:11，则从事件中删除
            filtered_matches = []
            for match in event.match
                all_perfect_matches = true
                games = split(match.games, " ")
                for game in games
                    if !(game == "11:0" || game == "0:11")
                        all_perfect_matches = false
                        break
                    end
                end
                if !all_perfect_matches
                    push!(filtered_matches, match)
                end
            end
            if !isempty(filtered_matches)
                # 创建新的事件对象，使用过滤后的比赛列表
                filtered_event = Event(
                    event.id,
                    event.name,
                    event.weight,
                    event.time,
                    filtered_matches
                )

                # 如果该日期尚未在字典中，创建一个新的空数组
                if !haskey(filtered_events, event_date)
                    filtered_events[event_date] = Event[]
                end

                # 将过滤后的事件添加到对应日期的数组中
                push!(filtered_events[event_date], filtered_event)
            end
        end
    end

    return filtered_events
end

# --- event id index (fast path for starting a new crawl cycle) ---

const EVENT_IDS_INDEX = "data/event_ids.json"

# Set of event ids already in the processed store. Uses the index file when
# available; otherwise scans all processed event files (slow, one-off).
function known_event_ids()::Set{Int}
    if isfile(EVENT_IDS_INDEX)
        return Set{Int}(JSON.parsefile(EVENT_IDS_INDEX))
    end
    ids = Set{Int}()
    isdir("data/events") || return ids
    for file_path in filter(f -> endswith(f, ".json"), readdir("data/events", join=true))
        for event_data in JSON.parse(read(file_path, String))
            haskey(event_data, "id") && push!(ids, Int(event_data["id"]))
        end
    end
    return ids
end

function save_event_ids_index(events::Dict{Date, Vector{Event}})
    ids = sort!(collect(Set{Int}(e.id for evs in values(events) for e in evs)))
    mkpath(dirname(EVENT_IDS_INDEX))
    open(EVENT_IDS_INDEX, "w") do io
        JSON.print(io, ids)
    end
    println("Saved $(length(ids)) event ids to $EVENT_IDS_INDEX")
end
