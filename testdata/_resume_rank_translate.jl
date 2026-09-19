# Resume: rankings + CN translate (players already merged)
const ROOT = dirname(@__DIR__)
cd(ROOT)
const POST_CRAWL_AS_LIBRARY = true
include(joinpath(ROOT, "post_crawl.jl"))

function translate_rankings!()
    function translate(src, dst)
        text = read(src, String)
        translation = Dict(
            "Player" => "运动员",
            "Assoc." => "协会",
            "Rating" => "积分",
            "template.typ" => "template_CN.typ",
            "Hand" => "手",
            "Grip" => "握拍",
            "Style" => "削球",
            "Age" => "年龄",
        )
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
        for (eng, chn) in translation
            text = replace(text, eng * "]" => chn * "]")
            text = replace(text, eng * "\"" => chn * "\"")
        end
        write(dst, text)
    end

    isdir("history_CN") || mkpath("history_CN")
    for year in 2004:year(today())
        dir_name = "history/$year"
        cn_dir_name = "history_CN/$year"
        isdir(dir_name) || continue
        isdir(cn_dir_name) || mkpath(cn_dir_name)
        for file_name in readdir(dir_name)
            endswith(file_name, ".typ") || continue
            translate("$dir_name/$file_name", "$cn_dir_name/$file_name")
        end
        println("translated history/$year → history_CN/$year")
    end
    for event in ["MS", "WS"]
        translate("$event-latest.typ", "$event-latest_CN.typ")
        println("translated $event-latest.typ")
    end
    println("翻译完成")
end

println("cwd=", pwd())
players = read_players_from_file()
events = read_events_from_files()
println("players=$(length(players)) dates=$(length(events))")
for id in (221811, 224464, 225728)
    haskey(players, id) || error("missing player $id in data/players.json")
    println("  ok $id $(players[id].name)")
end

active_periods = compute_active_periods(events, players)
highest = compute_rankings(events, players, active_periods)
println("Top highest:")
for (id, r) in highest[1:min(5, end)]
    println("  $id $(players[id].name) $(round(r; digits=1))")
end

translate_rankings!()
println("DONE")
