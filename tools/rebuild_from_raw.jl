#!/usr/bin/env julia
# rebuild_from_raw.jl — rebuild the processed format (data/) entirely from
# the raw ITTF dumps (events/, matches/, players/). One-off utility; not
# part of the normal update workflow.
#
# Usage (repo root):
#   julia tools/rebuild_from_raw.jl

using JSON
using Dates

const REPO_ROOT = dirname(@__DIR__)

include(joinpath(REPO_ROOT, "src", "structures.jl"))
include(joinpath(REPO_ROOT, "src", "weights.jl"))
include(joinpath(REPO_ROOT, "src", "ittf_convert.jl"))

function read_all_players()
    players_dict = Dict{Int64, Player}()

    # 遍历players文件夹下的所有JSON文件
    for file in readdir("players")
        if endswith(file, ".json")
            try
                # 读取JSON文件内容
                player_json = read("players/$file", String)
                # 解析玩家数据
                player = parse_player_data(player_json)
                if player !== nothing
                # 将成功解析的Player添加到字典中
                    players_dict[player.id] = player
                end
            catch e
                println("处理文件 $file 时出错: $e")
            end
        end
    end

    println("成功加载 $(length(players_dict)) 名玩家数据")
    return players_dict
end

function load_events_from_files()
    events_dir = "events"
    events_by_id = Dict{Int, Event}()
    empty_events = Dict{Date, Vector{Event}}()

    file_num = 0
    while isfile(joinpath(events_dir, "events_$(file_num).json"))
        file_path = joinpath(events_dir, "events_$(file_num).json")

        open(file_path, "r") do file
            json_data = read(file, String)
            events, _ = process_events(empty_events, json_data)

            for event in events
                events_by_id[event.id] = event
            end
        end

        file_num += 1
    end

    println("总共加载了 $(length(events_by_id)) 个赛事")
    return events_by_id
end

function load_matches_into_events(events_dict)
    matches_dir = "matches"
    new_match_count = 0

    file_num = 0
    while isfile(joinpath(matches_dir, "matches_$(file_num).json"))
        file_path = joinpath(matches_dir, "matches_$(file_num).json")

        try
            open(file_path, "r") do file
                matches_data = JSON.parse(file)

                # ITTF格式是数组的数组
                for match_list in matches_data
                    for raw_match in match_list
                        event_id = raw_match["vw_matches___tournament_id_raw"]

                        match = convert_ittf_match(raw_match)

                        # 只添加有效的单打比赛
                        if !isnothing(match)
                            push!(events_dict[event_id].match, match)
                            new_match_count += 1
                        end
                    end
                end
            end
            println("已读取 $(file_path)，当前比赛数 $(new_match_count)")
            file_num += 1
        catch e
            println("处理比赛文件 matches_$(file_num).json 时出错: $e")
            file_num += 1
        end
    end

    println("成功加载了 $(new_match_count) 场比赛到赛事中")
    return events_dict
end

cd(REPO_ROOT)
players = read_all_players()
events_dict = load_events_from_files()
events_dict = load_matches_into_events(events_dict)
println("Rebuild loaded. Merge/save intentionally left to the caller — this script only loads.")
