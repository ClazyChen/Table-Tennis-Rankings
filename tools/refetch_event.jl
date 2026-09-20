#!/usr/bin/env julia
# tools/refetch_event.jl — re-download events' matches from ITTF (list/68)
# and patch both stores in place:
#   matches/matches_<N>.json   (raw dumps for that event, all pages rewritten)
#   data/events/<date>.json    (processed store: the event's match list rebuilt)
#
# Usage (repo root):
#   julia tools/refetch_event.jl <tid>=<f1,f2,...> [<tid>=<f1,...> ...]
# where f1,f2,... are the existing matches_*.json file numbers holding that
# event's pages (used for overwrite-in-place; extra pages get fresh numbers,
# surplus old files are deleted).
#
# Safety: an event is skipped (nothing written) when the fresh data would
# *remove* any previously known match id. Human-like pacing between requests.
#
# Afterwards delete data/singles_matches_cache.json and run `julia post_crawl.jl`
# to recompute rankings and regenerate all outputs.
#
# Login/cookies via Kimi WebBridge, same as crawl.jl (helpers copied here so the
# crawler entry point stays untouched).

using JSON
using Dates
using HTTP

const REPO_DIR = dirname(@__DIR__)
const CREDENTIALS_PATH = joinpath(REPO_DIR, "ittf_credentials.json")
const WEBBRIDGE_URL = "http://127.0.0.1:10086/command"
const WEBBRIDGE_SESSION = "ittf-crawl"

include(joinpath(REPO_DIR, "src", "structures.jl"))
include(joinpath(REPO_DIR, "src", "weights.jl"))
include(joinpath(REPO_DIR, "src", "ittf_convert.jl"))
include(joinpath(REPO_DIR, "src", "ittf_fabrik.jl"))
using .ITTFFabrik

# ---------------------------------------------------------------- credentials

function load_credentials()
    isfile(CREDENTIALS_PATH) ||
        error("Missing $CREDENTIALS_PATH — see the comment at the top of crawl.jl")
    return JSON.parsefile(CREDENTIALS_PATH)
end

function save_cookies_to_credentials!(cookies::Dict{String,String})
    creds = load_credentials()
    creds["cookies"] = cookies
    open(CREDENTIALS_PATH, "w") do io
        JSON.print(io, creds, 2)
    end
end

# ------------------------------------------------------------------ webbridge

function webbridge(action::String, args::Dict=Dict())
    body = JSON.json(Dict("action" => action, "args" => args, "session" => WEBBRIDGE_SESSION))
    local resp
    try
        resp = HTTP.post(WEBBRIDGE_URL, ["Content-Type" => "application/json"], body;
                         status_exception=false, retry=false, readtimeout=60)
    catch e
        return nothing   # daemon not reachable
    end
    resp.status == 200 || return nothing
    d = JSON.parse(String(resp.body))
    return get(d, "ok", false) == true ? d["data"] : nothing
end

webbridge_available() = webbridge("list_tabs") !== nothing

function webbridge_eval(code::AbstractString)
    d = webbridge("evaluate", Dict("code" => code))
    d === nothing && return nothing
    return get(d, "value", nothing)
end

function webbridge_ensure_login!(creds)::Bool
    webbridge("navigate", Dict("url" => "https://results.ittf.link/index.php/events",
                               "newTab" => true, "group_title" => "ITTF 排名数据更新"))
    sleep(3)
    has_login_form = webbridge_eval(
        "(() => !!document.querySelector('form input[name=\"username\"]'))()")
    if has_login_form != true
        println("webbridge: already logged in")
        return true
    end

    username = string(get(creds, "username", ""))
    password = string(get(creds, "password", ""))
    (isempty(username) || isempty(password)) &&
        error("ITTF login required but username/password missing in ittf_credentials.json")

    println("webbridge: logging in as $username ...")
    webbridge("fill", Dict("selector" => "form input[name=\"username\"]", "value" => username))
    webbridge("fill", Dict("selector" => "form input[name=\"password\"]", "value" => password))
    webbridge_eval(
        "(() => { const r = document.querySelector('form input[name=\"remember\"]'); if (r && !r.checked) r.click(); return true; })()")
    webbridge_eval(
        "(() => { const f = document.querySelector('form input[name=\"username\"]').form; const b = f.querySelector('button[type=\"submit\"], input[type=\"submit\"]'); b.click(); return true; })()")
    sleep(5)

    still_form = webbridge_eval(
        "(() => !!document.querySelector('form input[name=\"username\"]'))()")
    if still_form == true
        error("ITTF login failed — check username/password in ittf_credentials.json")
    end
    println("webbridge: login OK")
    return true
end

function webbridge_cookies()::Union{Nothing,Dict{String,String}}
    d = webbridge("cdp", Dict("method" => "Storage.getCookies", "params" => Dict()))
    d === nothing && return nothing
    list = get(d, "cookies", nothing)
    list === nothing && return nothing
    cookies = Dict{String,String}()
    for c in list
        domain = string(get(c, "domain", ""))
        occursin("ittf.link", domain) || continue
        cookies[string(c["name"])] = string(c["value"])
    end
    return isempty(cookies) ? nothing : cookies
end

function refresh_cookies!(creds)
    webbridge_available() ||
        error("login/session refresh needs WebBridge — open the browser with the WebBridge extension")
    webbridge_ensure_login!(creds)
    fresh = webbridge_cookies()
    fresh === nothing && error("WebBridge returned no ITTF cookies after login")
    set_session_cookies!(fresh)
    save_cookies_to_credentials!(fresh)
    println("cookies refreshed via WebBridge ($(length(fresh)) entries)")
end

function with_login_retry(f, creds)
    while true
        try
            return f()
        catch e
            e isa LoginWall || rethrow()
            println("session expired — refreshing via WebBridge ...")
            refresh_cookies!(creds)
        end
    end
end

# ----------------------------------------------------------------------- fetch

pace() = sleep(20 + rand() * 20)

"""Fetch every list/68 page of an event; returns Vector of page row-vectors."""
function fetch_all_pages(event_id::Integer)
    pages = Vector{Any}[]
    offset = 0
    while true
        offset > 0 && pace()
        html = fetch_event_matches_html(event_id; offset=offset)
        rows = extract_fabrik_list_data(html; field_hint="vw_matches___")
        push!(pages, rows)
        length(rows) < ITTFFabrik.DEFAULT_MATCH_LIMIT && break
        offset += ITTFFabrik.DEFAULT_MATCH_LIMIT
    end
    return pages
end

function backup(path::AbstractString)
    dir = joinpath("testdata", "_bak_refetch")
    mkpath(dir)
    cp(path, joinpath(dir, basename(path)); force=true)
end

function next_free_match_num()::Int
    mx = 0
    for f in readdir("matches")
        m = match(r"^matches_(\d+)\.json$", f)
        m === nothing && continue
        mx = max(mx, parse(Int, m[1]))
    end
    return mx + 1
end

# ----------------------------------------------------------------------- main

function refetch_event!(events, creds, event_id::Int, file_nums::Vector{Int})
    println("\n=== event $event_id (files $(join(file_nums, ","))) ===")
    raw_paths = [joinpath("matches", "matches_$(n).json") for n in file_nums]
    for p in raw_paths
        isfile(p) || (println("  ! missing $p — skipped"); return false)
    end

    pages = with_login_retry(creds) do
        fetch_all_pages(event_id)
    end
    rows = reduce(vcat, pages)
    tids = unique(Int(r["vw_matches___tournament_id_raw"]) for r in rows)
    tids == [event_id] && !isempty(rows) ||
        (println("  ! tournament mismatch/empty: $tids — skipped"); return false)
    println("  fetched $(length(rows)) rows in $(length(pages)) page(s)")

    old_rows = mapreduce(f -> reduce(vcat, JSON.parsefile(f)), vcat, raw_paths)
    old_ids = Set(Int(r["vw_matches___id_raw"]) for r in old_rows)
    new_ids = Set(Int(r["vw_matches___id_raw"]) for r in rows)
    added = setdiff(new_ids, old_ids)
    removed = setdiff(old_ids, new_ids)
    println("  added: $(length(added)), removed: $(length(removed))")
    if !isempty(removed)
        println("  !! fresh data would remove $(length(removed)) match ids — skipped (needs manual review)")
        return false
    end
    isempty(added) && isempty(setdiff(old_ids, new_ids)) && length(old_rows) == length(rows) &&
        println("  (content ids unchanged; rewriting anyway)")
    byid = Dict(Int(r["vw_matches___id_raw"]) => r for r in rows)
    for id in sort!(collect(added))
        r = byid[id]
        println("    + ", r["vw_matches___round_raw"], " | ",
                r["vw_matches___name_a_raw"], " vs ", r["vw_matches___name_x_raw"],
                " ", r["vw_matches___res_raw"], " ", r["vw_matches___games_raw"])
    end

    # Rewrite the raw dumps: overwrite old files in order, extra pages get fresh
    # file numbers, surplus old files are deleted.
    for p in raw_paths
        backup(p)
    end
    fresh = next_free_match_num()
    n_common = min(length(pages), length(raw_paths))
    for i in 1:n_common
        open(raw_paths[i], "w") do io
            write(io, JSON.json([pages[i]]))
        end
    end
    for i in (n_common + 1):length(pages)   # more pages than before
        p = joinpath("matches", "matches_$(fresh).json")
        open(p, "w") do io
            write(io, JSON.json([pages[i]]))
        end
        println("  + new raw file $p")
        fresh += 1
    end
    for i in (n_common + 1):length(raw_paths)   # fewer pages than before
        rm(raw_paths[i])
        println("  - deleted stale raw file $(raw_paths[i])")
    end
    println("  raw dumps rewritten")

    # Patch the processed store: rebuild the event's match list from the new raw.
    txt = JSON.json([rows])
    local target_date = nothing
    for (date, evs) in events
        for ev in evs
            if Int(ev.id) == event_id
                empty!(ev.match)
                n = process_matches(txt, ev)
                println("  processed store: event $event_id ($date) rebuilt with $n singles matches")
                target_date = date
            end
        end
    end
    if target_date === nothing
        println("  ! event $event_id not found in processed store — raw patched only")
        return true
    end
    backup(joinpath("data", "events", "$(target_date).json"))
    save_events_to_files(events, Set([target_date]))
    println("  data/events/$(target_date).json saved")
    return true
end

function main()
    cd(REPO_DIR)
    isempty(ARGS) && error("Usage: julia tools/refetch_event.jl <tid>=<f1,f2,...> [...]")

    creds = load_credentials()
    set_proxy!(get(creds, "proxy", nothing))

    if webbridge_available()
        webbridge_ensure_login!(creds)
        ua = webbridge_eval("navigator.userAgent")
        if ua isa AbstractString && !isempty(ua)
            set_user_agent!(ua)
        end
        cookies = webbridge_cookies()
        if cookies !== nothing
            set_session_cookies!(cookies)
            save_cookies_to_credentials!(cookies)
            println("cookies refreshed via WebBridge ($(length(cookies)) entries)")
        else
            @warn "WebBridge returned no ITTF cookies; falling back to stored cookies"
            set_session_cookies!(Dict{String,String}(string(k) => string(v) for (k, v) in get(creds, "cookies", Dict())))
        end
    else
        @warn "WebBridge daemon not reachable; using stored cookies from ittf_credentials.json"
        stored = Dict{String,String}(string(k) => string(v) for (k, v) in get(creds, "cookies", Dict()))
        isempty(stored) && error("No cookies available and WebBridge is down")
        set_session_cookies!(stored)
    end

    events = read_events_from_files()
    ok = 0
    skipped = String[]
    for (i, spec) in enumerate(ARGS)
        i > 1 && pace()
        m = match(r"^(\d+)=([\d,]+)$", spec)
        m === nothing && (println("! bad spec $spec — skipped"); continue)
        tid = parse(Int, m[1])
        file_nums = parse.(Int, split(m[2], ","))
        try
            refetch_event!(events, creds, tid, file_nums) && (ok += 1)
        catch e
            println("  !! event $tid failed: $(typeof(e)) — skipped")
            println(sprint(showerror, e))
            for (i, frame) in enumerate(stacktrace(catch_backtrace()))
                i > 6 && break
                println("    ", frame)
            end
            push!(skipped, spec)
        end
    end
    println("\nDone: $ok/$(length(ARGS)) events refetched", isempty(skipped) ? "" : "; failed: $(join(skipped, " "))")
    println("Next: rm data/singles_matches_cache.json && julia post_crawl.jl")
end

main()
