#!/usr/bin/env julia
# crawl.jl — crawl new events/matches/players from the ITTF results site.
#
# Usage (repo root):
#   julia crawl.jl           # single pass; stops on 429 / budget / done
#   julia crawl.jl --loop    # unattended: waits out 429/budget, resumes automatically
#
# Requires ittf_credentials.json (gitignored) in the repo root:
#   {
#     "username": "...",                 # ITTF account (used for WebBridge auto-login)
#     "password": "...",
#     "proxy": "http://127.0.0.1:7890",  # proxy for Julia HTTP requests; null to disable
#     "cookies": { "<name>": "<value>", ... },  # fallback / cache; refreshed automatically
#     "switch_proxy_command": "bash command to rotate exit IP",   # optional, --loop only
#     "pacing": { "request_pause_min": 20, ... }                  # optional PacingProfile overrides
#   }
#
# Login & cookies are managed through Kimi WebBridge (browser daemon at
# 127.0.0.1:10086): the script logs in via the real browser if needed and
# extracts the fresh session cookies (incl. HttpOnly) over CDP. The browser
# must be running with the WebBridge extension; without the daemon the script
# falls back to the stored "cookies".
#
# 429 policy: ITTF penalties escalate, so pacing is tuned to never hit one.
# If it still happens, the crawler checkpoints to crawl_state.json and stops;
# --loop then waits the full server-suggested Retry-After before resuming.
# When the state reaches phase "done", run `julia post_crawl.jl`.

using JSON
using Dates
using HTTP

const REPO_DIR = @__DIR__
const CREDENTIALS_PATH = joinpath(REPO_DIR, "ittf_credentials.json")
const WEBBRIDGE_URL = "http://127.0.0.1:10086/command"
const WEBBRIDGE_SESSION = "ittf-crawl"
const LOOP_MODE = "--loop" in ARGS

include(joinpath(REPO_DIR, "src", "structures.jl"))
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

# Log in via the real browser if the events page shows a login form.
# Returns true when the browser session is logged in.
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

# Extract fresh ITTF cookies (incl. HttpOnly session cookie) via CDP.
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

# --------------------------------------------------------------------- pacing

function build_pacing(creds)::PacingProfile
    over = get(creds, "pacing", nothing)
    over === nothing && return PacingProfile()
    kwargs = Dict{Symbol,Any}()
    for f in fieldnames(PacingProfile)
        k = string(f)
        haskey(over, k) || continue
        v = over[k]
        kwargs[f] = fieldtype(PacingProfile, f) <: AbstractFloat ? Float64(v) : Int(v)
    end
    return PacingProfile(; kwargs...)
end

# ----------------------------------------------------------------------- main

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

# Run f(); on an expired ITTF session, refresh cookies via WebBridge and retry.
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

function wait_for_retry(state)::Float64
    reason = string(get(state, "stop_reason", ""))
    if reason == "rate_limited"
        ra = Float64(get(state, "retry_after", 3600))
        wait = max(ra, 3600.0) + rand() * 600.0   # at least 1h, plus jitter
    elseif reason == "daily_budget"
        # sleep until 06:00 local next day, plus jitter
        now_dt = now()
        tomorrow = Date(now_dt) + Day(1)
        target = DateTime(tomorrow) + Hour(6)
        wait = Dates.value(target - now_dt) / 1000 + rand() * 1800.0
    elseif reason == "player_failed"
        wait = 1800.0 + rand() * 600.0
    else
        wait = 3600.0
    end
    println("stop_reason=$reason — waiting $(round(Int, wait))s before resume")
    return wait
end

function main()
    cd(REPO_DIR)
    creds = load_credentials()

    # Julia HTTP traffic goes through the configured proxy (browser does not).
    set_proxy!(get(creds, "proxy", nothing))

    # Fresh cookies via WebBridge (auto-login if needed); fall back to stored.
    if webbridge_available()
        webbridge_ensure_login!(creds)
        # Match the crawler's request fingerprint to the real browser: the
        # rate limiter treats the outdated/static UA + missing client hints
        # as a bot and gives it a much smaller budget.
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
        isempty(stored) && error("No cookies available and WebBridge is down — open the browser with the WebBridge extension")
        set_session_cookies!(stored)
    end

    pacing = build_pacing(creds)
    println("pacing: $(pacing.request_pause_min)-$(pacing.request_pause_max)s per request, " *
            "rest every $(pacing.session_pages) pages, daily budget $(pacing.daily_request_budget)")

    # Start a new incremental cycle when there is no crawl in progress
    existing = load_crawl_state()
    if existing === nothing || string(get(existing, "phase", "")) == "done"
        println("no crawl in progress — discovering new events via list/27 ...")
        known = known_event_ids()
        println("known events: $(length(known))")
        with_login_retry(creds) do
            start_new_cycle!(known; pacing=pacing)
        end
    end

    switch_cmd = get(creds, "switch_proxy_command", nothing)

    consecutive_login_walls = 0
    consecutive_errors = 0
    cooldown = false
    while true
        local state
        try
            state = run_crawl!(; pacing=pacing)
        catch e
            # Unexpected (e.g. network) error: run_crawl! already checkpointed.
            LOOP_MODE || rethrow()
            consecutive_errors += 1
            consecutive_errors > 5 && rethrow()
            wait = 600.0 * consecutive_errors + rand() * 300.0
            @warn "run_crawl! crashed; waiting $(round(Int, wait))s then resuming ($consecutive_errors/5)" exception=e
            sleep(wait)
            continue
        end
        consecutive_errors = 0
        reason = string(get(state, "stop_reason", ""))
        phase = string(get(state, "phase", "?"))

        if phase == "done" || reason == "done"
            println("crawl phase=done — run `julia post_crawl.jl` next")
            break
        end

        # Session expired mid-crawl: refreshing cookies is cheap and carries no
        # 429 risk, so do it in both single-pass and --loop mode.
        if reason == "login_wall"
            consecutive_login_walls += 1
            consecutive_login_walls > 3 &&
                error("3 consecutive login walls — cookie refresh is not helping; check WebBridge login")
            refresh_cookies!(creds)
            continue
        end
        consecutive_login_walls = 0

        if !LOOP_MODE
            println("Stopped (reason=$reason). Re-run `julia crawl.jl` to resume, or use --loop for unattended mode.")
            break
        end

        wait = wait_for_retry(state)
        if reason == "rate_limited"
            if switch_cmd !== nothing
                println("rotating exit IP: $switch_cmd")
                try run(Cmd(["bash", "-c", string(switch_cmd)])) catch e; @warn "switch_proxy_command failed" exception=e end
            end
            # Penalties escalate (1h → 6h → 24h): after any 429, run the rest
            # of this crawl at half speed.
            if !cooldown
                cooldown = true
                pacing = PacingProfile(
                    request_pause_min = pacing.request_pause_min * 2,
                    request_pause_max = pacing.request_pause_max * 2,
                    session_pages = max(5, pacing.session_pages ÷ 2),
                    session_rest_min = pacing.session_rest_min,
                    session_rest_max = pacing.session_rest_max,
                    daily_request_budget = pacing.daily_request_budget,
                )
                println("429 cooldown: pacing slowed to $(pacing.request_pause_min)-$(pacing.request_pause_max)s for the rest of this run")
            end
        end
        sleep(wait)
        # After a long wait the session is surely dead — refresh before resuming.
        if reason in ("rate_limited", "daily_budget") && webbridge_available()
            try refresh_cookies!(creds) catch e; @warn "cookie refresh failed" exception=e end
        end
    end
end

main()
