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

# Save player data
save_players_to_json(players, "data/players.json")