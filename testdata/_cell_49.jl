function save_rankings(date::Date, type::String, rating::Dict{Int, Float64}, last_ranking::Dict{Int, Int}, filename::String="", count::Int=200)
    # Create directory structure
    year_dir = "history/$(year(date))"
    if !isdir(year_dir)
        mkpath(year_dir)
    end
    
    # Create filename with 2-digit month format
    month_str = lpad(month(date), 2, '0')
    output_filename = !isempty(filename) ? filename : "$(year_dir)/$(type)S-$(month_str).typ"
    
    # Filter active players
    active_players = Int[]
    for (player_id, periods) in active_periods
        # Check if player is active on the current date
        is_active = false
        for period in periods
            if period.start <= date <= period.fin
                is_active = true
                break
            end
        end
        
        if is_active && haskey(rating, player_id) && players[player_id].sex == type
            push!(active_players, player_id)
        end
    end
    
    # Sort by rating and take top 200
    sort!(active_players, by=id -> -rating[id])
    
    # Create current rankings dictionary
    current_ranking = Dict{Int, Int}()
    for (rank, player_id) in enumerate(active_players)
        current_ranking[player_id] = rank
    end
    
    # Output top-200 players
    if length(active_players) > count
        active_players = active_players[1:count]
    end
    
    # Write to file
    open(output_filename, "w") do f
        # Write template information
        if isempty(filename)
            write(f, "#import \"../../template.typ\": *\n")
        else
            write(f, "#import \"template.typ\": *\n")
        end
        write(f, "#set text(font: (\"Microsoft YaHei\"))\n\n")
        
        # Determine title
        title = type == "M" ? "Men's Singles" : "Women's Singles"
        
        # 25 players per page, 8 pages total
        for page in 1:div(count, 25)
            start_rank = (page - 1) * 25 + 1
            end_rank = min(page * 25, length(active_players))
            
            # Write table header
            write(f, "#figure(\n")
            write(f, "  caption: \"$(title) ($(start_rank) - $(end_rank))\",\n")
            write(f, "    table(\n")
            write(f, "      columns: 9,\n")
            write(f, "      [\\#], [Player],[Age], [Assoc.],  [Hand], [Grip], [Style], [Rating], [\$Delta\$],\n")
            
            # Write player information
            for i in start_rank:end_rank
                if i <= length(active_players)
                    player_id = active_players[i]
                    player = players[player_id]
                    
                    # Calculate age
                    age = year(date) - player.yob
                    
                    # Get association info
                    assoc = "?"
                    latest_date = today() + Day(1)
                    for (association, change_date) in player.history
                        if date <= change_date < latest_date
                            assoc = association
                            latest_date = change_date
                        end
                    end
                    if assoc == "?"
                        latest_date = Date(1970, 1, 1)
                        for (association, change_date) in player.history
                            if change_date > latest_date
                                assoc = association
                                latest_date = change_date
                            end
                        end 
                    end
                    
                    # Get playing hand
                    hand = player.hand == "Right-Hand" ? "#right" : 
                           player.hand == "Left-Hand" ? "#left" : "?"
                    
                    # Get grip style
                    grip = player.grip == "ShakeHand" ? "#shakehand" : 
                           player.grip == "Penhold" ? "#penhold" : "?"
                    
                    # Get playing style
                    style = player.style == "Attack" ? "#attack" : 
                            player.style == "Defence" ? "#defense" : "?"
                    
                    # Get ranking change
                    delta = haskey(last_ranking, player_id) ? 
                            "#delta($(last_ranking[player_id] - i))" : "NEW"
                    
                    # Write player row
                    write(f, "      [$(i)], [#name(\"$(player.name)\")], [#age($(age))], [#assoc(\"$(assoc)\")], ")
                    write(f, "[$(hand)], [$(grip)], [$(style)], [*$(floor(Int, rating[player_id]))*], [$(delta)],\n")
                end
            end
            
            # End table
            write(f, "    )\n")
            write(f, "  )\n")
            
            # Add page break except for the last page
            if page < div(count, 25)
                write(f, "#pagebreak()\n\n")
            end
        end
    end
    
    println("Rankings saved to file: $(output_filename)")
    
    # Return the current rankings
    return current_ranking
end