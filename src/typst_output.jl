# typst_output.jl — render rankings as Typst files and produce the
# Chinese translations (history_CN/, *_CN.typ).
#
# Note: no `using Dates` here — Dates is already imported by the including
# script, and this file's signatures reference Main.Period (rating.jl), which
# must not be shadowed by Dates.Period. Include rating.jl before this file.

function save_rankings(date::Date, type::String, rating::Dict{Int, Float64}, last_ranking::Dict{Int, Int},
                      players::Dict{Int, Player}, active_periods::Dict{Int, Vector{Period}};
                      filename::String="", count::Int=200)
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

    # Build content then write (retry: Windows may briefly lock .typ files)
    buf = IOBuffer()
    if isempty(filename)
        write(buf, "#import \"../../template.typ\": *\n")
    else
        write(buf, "#import \"template.typ\": *\n")
    end
    write(buf, "#set text(font: (\"Microsoft YaHei\"))\n\n")

    title = type == "M" ? "Men's Singles" : "Women's Singles"

    for page in 1:div(count, 25)
        start_rank = (page - 1) * 25 + 1
        end_rank = min(page * 25, length(active_players))

        write(buf, "#figure(\n")
        write(buf, "  caption: \"$(title) ($(start_rank) - $(end_rank))\",\n")
        write(buf, "    table(\n")
        write(buf, "      columns: 9,\n")
        write(buf, "      [\\#], [Player],[Age], [Assoc.],  [Hand], [Grip], [Style], [Rating], [\$Delta\$],\n")

        for i in start_rank:end_rank
            if i <= length(active_players)
                player_id = active_players[i]
                player = players[player_id]

                age = year(date) - player.yob

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

                hand = player.hand == "Right-Hand" ? "#right" :
                       player.hand == "Left-Hand" ? "#left" : "?"

                grip = player.grip == "ShakeHand" ? "#shakehand" :
                       player.grip == "Penhold" ? "#penhold" : "?"

                style = player.style == "Attack" ? "#attack" :
                        player.style == "Defence" ? "#defense" : "?"

                delta = haskey(last_ranking, player_id) ?
                        "#delta($(last_ranking[player_id] - i))" : "NEW"

                pname = replace(player.name, "\"" => "'")
                write(buf, "      [$(i)], [#name(\"$(pname)\")], [#age($(age))], [#assoc(\"$(assoc)\")], ")
                write(buf, "[$(hand)], [$(grip)], [$(style)], [*$(floor(Int, rating[player_id]))*], [$(delta)],\n")
            end
        end

        write(buf, "    )\n")
        write(buf, "  )\n")

        if page < div(count, 25)
            write(buf, "#pagebreak()\n\n")
        end
    end

    content = String(take!(buf))
    for attempt in 1:8
        try
            open(output_filename, "w") do f
                write(f, content)
            end
            break
        catch e
            e isa SystemError || rethrow()
            attempt == 8 && rethrow()
            @warn "retry write ranking" file=output_filename attempt=attempt exception=e
            sleep(0.4 * attempt)
        end
    end

    println("Rankings saved to file: $(output_filename)")

    return current_ranking
end

# 翻译单个排名文件（英文 -> 中文）
function translate(src, dst)
    # 读取源文件内容
    text = read(src, String)

    # 定义翻译字典
    translation = Dict(
        "Player" => "运动员",
        "Assoc." => "协会",
        "Rating" => "积分",
        "template.typ" => "template_CN.typ",
        "Hand" => "手",
        "Grip" => "握拍",
        "Style" => "削球",
        "Age" => "年龄"
    )

    # 从翻译文件中读取更多翻译
    if isfile("translate.txt")
        open("translate.txt", "r") do f
            for line in eachline(f)
                words = split(line, ",")
                if length(words) >= 2
                    translation[strip(words[1])] = strip(words[2])
                end
            end
        end
    end

    # 替换文本中的单词
    for (eng, chn) in translation
        text = replace(text, eng * "]" => chn * "]")
        text = replace(text, eng * "\"" => chn * "\"")
    end

    # 写入目标文件
    write(dst, text)
end

# 翻译全部历史排名和最新排名到 history_CN/ 与 *_CN.typ
function translate_all()
    for year_dir in sort(readdir("history"))
        dir_name = joinpath("history", year_dir)
        isdir(dir_name) || continue
        cn_dir_name = joinpath("history_CN", year_dir)
        mkpath(cn_dir_name)

        # 翻译该年份下的所有文件
        for file_name in readdir(dir_name)
            file_path = joinpath(dir_name, file_name)
            cn_file_path = joinpath(cn_dir_name, file_name)
            translate(file_path, cn_file_path)
        end
        println("已翻译 $dir_name")
    end

    # 翻译最新排名文件
    for event in ["MS", "WS"]
        translate("$event-latest.typ", "$event-latest_CN.typ")
    end

    println("翻译完成")
end
