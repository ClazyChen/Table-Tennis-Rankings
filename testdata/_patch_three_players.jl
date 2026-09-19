# Parse manually saved list/60 HTML (decoded) → players/*.json → merge → rankings → CN translate
const ROOT = dirname(@__DIR__)
cd(ROOT)

include(joinpath(ROOT, "src", "ittf_fabrik.jl"))
using .ITTFFabrik

# Load pipeline without auto-running main
const POST_CRAWL_AS_LIBRARY = true
include(joinpath(ROOT, "post_crawl.jl"))

const IDS = [221811, 224464, 225728]

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
            src = "$dir_name/$file_name"
            dst = "$cn_dir_name/$file_name"
            translate(src, dst)
        end
        println("translated history/$year → history_CN/$year")
    end
    for event in ["MS", "WS"]
        translate("$event-latest.typ", "$event-latest_CN.typ")
        println("translated $event-latest.typ")
    end
    println("翻译完成")
end

function main_patch()
    println("== Parse decoded HTML → players/{id}.json ==")
    isdir("players") || mkpath("players")
    for id in IDS
        html_path = joinpath("testdata", "player_$(id)_decoded.html")
        isfile(html_path) || error("Missing $html_path — decode view-source first")
        html = read(html_path, String)
        rows = extract_fabrik_list_data(html; field_hint="vw_profiles___")
        isempty(rows) && error("No profile rows for $id")
        tid = Int(rows[1]["vw_profiles___player_id_raw"])
        tid == id || error("id mismatch: want $id got $tid")
        js = to_ittf_list_json(rows)
        out = joinpath("players", "$(id).json")
        open(out, "w") do io
            write(io, js)
        end
        name = get(rows[1], "vw_profiles___name_raw", "?")
        println("  $id → $out ($(sizeof(js)) bytes) $name")
    end

    println("\n== Merge into data/players.json ==")
    players = read_players_from_file()
    added = Player[]
    for id in IDS
        pl = parse_player_data(read(joinpath("players", "$(id).json"), String))
        pl === nothing && error("parse_player_data failed for $id")
        push!(added, pl)
        println("  parsed $(pl.id) $(pl.name) $(pl.sex) yob=$(pl.yob)")
    end
    merge_players!(players, added)

    println("\n== Update associations from all events ==")
    events = read_events_from_files()
    flat = Event[]
    for (_, es) in events
        append!(flat, es)
    end
    update_player_associations(flat, players)
    save_players_to_json(players, "data/players.json")

    println("\n== Recompute rankings ==")
    active_periods = compute_active_periods(events, players)
    println("active_periods players=$(length(active_periods))")
    highest = compute_rankings(events, players, active_periods)
    println("Top highest:")
    for (id, r) in highest[1:min(5, end)]
        name = haskey(players, id) ? players[id].name : "?"
        println("  $id $name $(round(r; digits=1))")
    end

    println("\n== Chinese translation ==")
    translate_rankings!()
    println("DONE")
end

main_patch()
