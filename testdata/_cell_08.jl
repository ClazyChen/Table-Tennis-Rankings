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

# Read all players
players = read_players_from_file()
println("Read $(length(players)) players from data/players.json file")