function compute_rankings()
    # 初始化玩家评分字典
    ratings = Dict{Int, Float64}()
    
    # 初始化上次排名字典
    last_ranking = Dict{Int, Int}()

    # 记录历史最高分
    highest_ratings = Dict{Int, Float64}()
    
    # 设置开始日期和结束日期
    start_date = Date("2004-01-01")
    end_date = today()
    
    # 获取所有事件并按日期排序
    all_events = Event[]
    for (date, date_events) in events
        for event in date_events
            push!(all_events, event)
        end
    end
    
    # 按日期排序
    sort!(all_events, by = e -> e.time)
    
    # 当前月份
    current_month = Month(0)
    
    # 遍历每个事件
    for event in all_events
        # 检查是否需要保存排名（每月一次）
        if event.time >= start_date
            ranking_m = save_rankings(start_date, "M", ratings, last_ranking)
            ranking_f = save_rankings(start_date, "W", ratings, last_ranking)
            # 清空并重新创建last_ranking
            empty!(last_ranking)
            
            # 合并男女排名为新的last_ranking
            for (player, rank) in ranking_m
                last_ranking[player] = rank
            end
            
            for (player, rank) in ranking_f
                last_ranking[player] = rank
            end
            
            # 更新start_date到下个月的第一天
            start_date = start_date + Month(1)

            # 更新历史最高分
            for (id, rating) in ratings
                if ratings[id] > highest_ratings[id]
                    highest_ratings[id] = ratings[id]
                end
            end
        end

        # 处理事件中的每场比赛
        for match in event.match
            # 获取玩家ID
            player1_id = match.player_a_id
            player2_id = match.player_x_id
            
            # 如果是新玩家，初始化评分
            if !haskey(ratings, player1_id)
                ratings[player1_id] = r0
                highest_ratings[player1_id] = r0
            end
            
            if !haskey(ratings, player2_id)
                ratings[player2_id] = r0
                highest_ratings[player2_id] = r0
            end
            
            # 更新评分
            r1, r2 = update_rating(ratings[player1_id], ratings[player2_id], match.weight, event.weight, event.time)
            ratings[player1_id] = r1
            ratings[player2_id] = r2
        end
    end

    save_rankings(end_date, "M", ratings, last_ranking, "MS-latest.typ", 1000)
    save_rankings(end_date, "W", ratings, last_ranking, "WS-latest.typ", 1000)

    # 返回按照最高分排序的字典
    sorted_highest_ratings = sort(collect(highest_ratings), by=x->x[2], rev=true)
    sorted_highest_ratings
end