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

# 应用过滤
filtered_events = filter_perfect_matches(events)
println("过滤前事件数: $(length(events))")
println("过滤后事件数: $(length(filtered_events))")
