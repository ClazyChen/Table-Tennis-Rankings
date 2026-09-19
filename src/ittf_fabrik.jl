"""
ITTF Fabrik helpers: HTML JSON extract, cookie session, slow 429-aware crawl with checkpoints.
No automatic login — supply browser cookies manually.
Matches use list/68 (GET first page + POST pagination); never list/31.
"""
module ITTFFabrik

using HTTP
using JSON
using Gumbo
using Cascadia
using Dates

export looks_like_login_wall,
       looks_like_rate_limit_page,
       parse_retry_after_seconds,
       extract_fabrik_list_data,
       to_ittf_list_json,
       fetch_event_matches_html,
       download_event_matches_json,
       download_player_json,
       RateLimited,
       PlayerJsonFailed,
       DailyBudgetExhausted,
       LoginWall,
       PacingProfile,
       save_crawl_state,
       load_crawl_state,
       bootstrap_crawl_state_from_disk!,
       start_new_cycle!,
       fetch_events27_rows,
       run_crawl!,
       get_session_cookies,
       set_session_cookies!,
       set_proxy!,
       get_proxy,
       set_user_agent!

# Fallback UA; crawl.jl syncs the real browser UA via WebBridge at startup.
const DEFAULT_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
const ITTF_BASE = "https://results.ittf.link"
const DEFAULT_STATE_PATH = "crawl_state.json"

# Direction B defaults: slow + small pages; 429 always exits
const DEFAULT_MATCH_LIMIT = 100  # list/68 page size (100 verified working 2026-08)
# Proxy/network flakiness: more retries, longer waits
const DEFAULT_HTTP_ATTEMPTS = 10
const DEFAULT_HTTP_RETRY_BASE_SEC = 20.0

# Human-like pacing profile: jittered per-request pauses, "browsing session"
# breaks every N pages, and a daily request budget (persisted in crawl_state
# so it survives restarts). Goal: never trigger 429 — penalties escalate.
Base.@kwdef struct PacingProfile
    request_pause_min::Float64 = 20.0     # seconds between requests (jittered)
    request_pause_max::Float64 = 60.0
    session_pages::Int = 20               # pages per "browsing session"
    session_rest_min::Float64 = 600.0     # break between sessions (jittered)
    session_rest_max::Float64 = 1200.0
    daily_request_budget::Int = 1500      # hard stop for the day
end

struct RateLimited <: Exception
    retry_after::Int
    msg::String
end
Base.showerror(io::IO, e::RateLimited) = print(io, "RateLimited($(e.retry_after)s): $(e.msg)")

struct PlayerJsonFailed <: Exception
    player_id::Int
    msg::String
end
Base.showerror(io::IO, e::PlayerJsonFailed) =
    print(io, "PlayerJsonFailed(player=$(e.player_id)): $(e.msg)")

struct DailyBudgetExhausted <: Exception
    limit::Int
end
Base.showerror(io::IO, e::DailyBudgetExhausted) =
    print(io, "DailyBudgetExhausted(limit=$(e.limit))")

# Thrown when ITTF returns the login wall (session expired mid-crawl).
# The caller (crawl.jl) refreshes cookies via WebBridge and resumes.
struct LoginWall <: Exception
    msg::String
end
Base.showerror(io::IO, e::LoginWall) = print(io, "LoginWall: $(e.msg)")

struct List68Form
    action::String
    fields::Dict{String,String}
end

mutable struct Session
    cookies::Dict{String,String}
    list68_event_id::Union{Nothing,Int}
    list68_form::Union{Nothing,List68Form}
    proxy::Union{Nothing,String}
    ua::String
    browser_headers::Vector{Pair{String,String}}
end

const SESSION = Session(Dict{String,String}(), nothing, nothing, "http://127.0.0.1:7890",
                        DEFAULT_UA, Pair{String,String}[])

function get_session_cookies()
    copy(SESSION.cookies)
end

function set_session_cookies!(cookies::AbstractDict)
    empty!(SESSION.cookies)
    for (k, v) in cookies
        SESSION.cookies[string(k)] = string(v)
    end
    # helpful default used by the site's cookie banner
    get!(SESSION.cookies, "jbcookies", "yes")
    SESSION.list68_event_id = nothing
    SESSION.list68_form = nothing
    println("session cookies=$(length(SESSION.cookies)); proxy=$(repr(SESSION.proxy))")
    return SESSION.cookies
end

"""Set HTTP(S) proxy for ITTF requests, e.g. `\"http://127.0.0.1:7890\"`. Pass `nothing` to disable."""
function set_proxy!(proxy::Union{Nothing,AbstractString})
    if proxy === nothing || isempty(strip(string(proxy)))
        SESSION.proxy = nothing
    else
        SESSION.proxy = string(proxy)
    end
    println(SESSION.proxy === nothing ? "proxy: off" : "proxy: $(SESSION.proxy)")
    return SESSION.proxy
end

get_proxy() = SESSION.proxy

"""
Set the User-Agent and derive the matching browser client-hint headers
(sec-ch-ua*, Sec-Fetch-*). crawl.jl feeds this the real browser UA from
WebBridge so crawler requests carry the same fingerprint as manual browsing.
"""
function set_user_agent!(ua::AbstractString)
    SESSION.ua = string(ua)
    empty!(SESSION.browser_headers)
    m = match(r"Chrome/(\d+)", SESSION.ua)
    if m !== nothing
        v = m.captures[1]
        brands = ["\"Chromium\";v=\"$(v)\""]
        me = match(r"Edg/(\d+)", SESSION.ua)
        if me !== nothing
            push!(brands, "\"Microsoft Edge\";v=\"$(me.captures[1])\"")
        else
            push!(brands, "\"Google Chrome\";v=\"$(v)\"")
        end
        push!(brands, "\"Not-A.Brand\";v=\"99\"")
        push!(SESSION.browser_headers,
              "sec-ch-ua" => join(brands, ", "),
              "sec-ch-ua-mobile" => "?0",
              "sec-ch-ua-platform" => occursin("Mac", SESSION.ua) ? "\"macOS\"" : "\"Windows\"")
    end
    append!(SESSION.browser_headers, [
        "Accept-Language" => "en-GB,en;q=0.9",
        "Upgrade-Insecure-Requests" => "1",
        "Sec-Fetch-Dest" => "document",
        "Sec-Fetch-Mode" => "navigate",
        "Sec-Fetch-Site" => "same-origin",
    ])
    println("user-agent: $(SESSION.ua)")
    return SESSION.ua
end

function looks_like_login_wall(body::AbstractString)::Bool
    b = lowercase(body)
    has_login = occursin("mod-login", b) ||
                occursin("already have an account", b) ||
                occursin("click here to register", b) ||
                occursin("com-users-login", b) ||
                (occursin("please click", b) && occursin("to login", b))
    # Only real list payloads count — echoing vw_profiles___ in a guest page must NOT.
    has_data = occursin("\"data\":[[", body) || occursin("fabrik_row", b)
    return has_login && !has_data
end

function looks_like_rate_limit_page(body::AbstractString)::Bool
    b = lowercase(body)
    return occursin("429", b) && occursin("too many requests", b)
end

function parse_retry_after_seconds(body::AbstractString; header_value=nothing, default::Int=3600)::Int
    if header_value !== nothing
        hv = strip(string(header_value))
        if occursin(r"^\d+$", hv)
            return max(1, parse(Int, hv))
        end
    end
    m = match(r"var\s+remaining\s*=\s*(\d+)", body)
    m !== nothing && return max(1, parse(Int, m.captures[1]))
    m = match(r"about\s+(\d+)\s+hours?", lowercase(body))
    m !== nothing && return max(1, parse(Int, m.captures[1]) * 3600)
    m = match(r"about\s+(\d+)\s+minutes?", lowercase(body))
    m !== nothing && return max(1, parse(Int, m.captures[1]) * 60)
    return default
end

function _extract_json_object(text::AbstractString, start::Int)::String
    @assert text[start] == '{'
    depth = 0
    in_str = false
    escape = false
    i = start
    n = lastindex(text)
    while i <= n
        c = text[i]
        if in_str
            if escape
                escape = false
            elseif c == '\\'
                escape = true
            elseif c == '"'
                in_str = false
            end
        else
            if c == '"'
                in_str = true
            elseif c == '{'
                depth += 1
            elseif c == '}'
                depth -= 1
                if depth == 0
                    return text[start:i]
                end
            end
        end
        i = nextind(text, i)
    end
    error("Unbalanced JSON object starting at position $start")
end

function _script_texts(html::AbstractString)::Vector{String}
    doc = parsehtml(html)
    texts = String[]
    for node in eachmatch(Selector("script"), doc.root)
        t = Gumbo.text(node)
        isempty(strip(t)) || push!(texts, t)
    end
    if isempty(texts) || !any(t -> occursin("\"data\":[[", t), texts)
        for m in eachmatch(r"<script[^>]*>(.*?)</script>"s, html)
            push!(texts, m.captures[1])
        end
    end
    return texts
end

function extract_fabrik_list_data(html::AbstractString; field_hint::AbstractString="vw_")::Vector{Dict{String,Any}}
    looks_like_login_wall(html) && error("ITTF login wall detected; refresh COOKIES in the notebook and retry")
    looks_like_rate_limit_page(html) && throw(RateLimited(parse_retry_after_seconds(html), "429 page body"))

    candidates = String[]
    for t in _script_texts(html)
        if occursin("\"data\":[[", t) && occursin(field_hint, t)
            push!(candidates, t)
        end
    end
    if isempty(candidates)
        looks_like_login_wall(html) && error("ITTF login wall detected; refresh COOKIES in the notebook and retry")
        # True empty list (or guest shell without rows). Avoid treating login walls as empty.
        if occursin("\"data\":[[]]", html) || occursin("\"data\":[]", html)
            return Dict{String,Any}[]
        end
        if !occursin("\"data\":[[", html) && !occursin("fabrik_row", html)
            return Dict{String,Any}[]
        end
        if occursin(r">\s*No records\s*<", html) && !occursin("\"data\":[[{", html)
            return Dict{String,Any}[]
        end
        error("No Fabrik embedded list data found in HTML")
    end

    script = argmax(sizeof, candidates)
    anchor = findfirst("\"limitLength\"", script)
    data_idx = findfirst("\"data\":[[", script)
    (anchor === nothing || data_idx === nothing) && error("Fabrik list payload missing limitLength/data")

    search_from = first(anchor)
    obj = nothing
    for back in 0:8000
        pos = search_from - back
        pos < 1 && break
        script[pos] != '{' && continue
        try
            js = _extract_json_object(script, pos)
            parsed = JSON.parse(js)
            if parsed isa AbstractDict && haskey(parsed, "data") && haskey(parsed, "limitLength")
                obj = parsed
                break
            end
        catch
            continue
        end
    end
    obj === nothing && error("Failed to parse Fabrik list options JSON")

    rows = Dict{String,Any}[]
    data = obj["data"]
    data isa AbstractVector || error("Unexpected Fabrik data shape")
    for group in data
        group isa AbstractVector || continue
        for row in group
            if row isa AbstractDict && haskey(row, "data") && row["data"] isa AbstractDict
                push!(rows, Dict{String,Any}(row["data"]))
            elseif row isa AbstractDict
                push!(rows, Dict{String,Any}(row))
            end
        end
    end
    return rows
end

function to_ittf_list_json(rows::Vector{<:AbstractDict})::String
    JSON.json([rows])
end

function _cookie_header(cookies::AbstractDict)::String
    join(["$k=$v" for (k, v) in cookies], "; ")
end

function _merge_set_cookies!(cookies::Dict{String,String}, resp)
    if hasproperty(resp, :cookies) && resp.cookies !== nothing
        for c in resp.cookies
            cookies[string(c.name)] = string(c.value)
        end
    end
    for (k, v) in resp.headers
        if lowercase(String(k)) == "set-cookie"
            m = match(r"^([^=]+)=([^;]*)", String(v))
            if m !== nothing
                cookies[m.captures[1]] = m.captures[2]
            end
        end
    end
    return cookies
end

function _header_value(resp, name::AbstractString)
    lname = lowercase(name)
    for (k, v) in resp.headers
        if lowercase(String(k)) == lname
            return String(v)
        end
    end
    return nothing
end

function _absolute_ittf_url(path_or_url::AbstractString)::String
    if startswith(path_or_url, "http://") || startswith(path_or_url, "https://")
        return replace(path_or_url, "https://www.results.ittf.link" => ITTF_BASE)
    end
    startswith(path_or_url, "/") && return ITTF_BASE * path_or_url
    return ITTF_BASE * "/" * path_or_url
end

"""HTTP helper using SESSION cookies. Throws RateLimited on 429. No auto-login."""
function ittf_request(method::AbstractString, url::AbstractString;
                      body=nothing, headers=Pair{String,String}[], timeout=60,
                      redirect::Bool=true, max_redirects::Int=8)
    isempty(SESSION.cookies) && error("SESSION cookies empty — set COOKIES via set_session_cookies! first")

    current_url = url
    current_method = uppercase(method)
    current_body = body
    redirects_left = max_redirects
    hdrs_extra = collect(headers)
    proxy = SESSION.proxy

    while true
        hdrs = [
            "User-Agent" => SESSION.ua,
            "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Cookie" => _cookie_header(SESSION.cookies),
        ]
        append!(hdrs, SESSION.browser_headers)
        append!(hdrs, hdrs_extra)

        resp = _http_exchange(current_method, current_url, hdrs, current_body; timeout=timeout, proxy=proxy)
        _merge_set_cookies!(SESSION.cookies, resp)
        text = String(resp.body)

        if resp.status == 429 || looks_like_rate_limit_page(text)
            ra = parse_retry_after_seconds(text; header_value=_header_value(resp, "Retry-After"))
            throw(RateLimited(ra, "HTTP $(resp.status) from $current_url"))
        end

        if redirect && resp.status in (301, 302, 303, 307, 308) && redirects_left > 0
            loc = _header_value(resp, "Location")
            loc === nothing && error("Redirect without Location from $current_url")
            current_url = _absolute_ittf_url(loc)
            if resp.status in (301, 302, 303) || current_method == "POST"
                current_method = "GET"
                current_body = nothing
                hdrs_extra = filter(p -> lowercase(first(p)) != "content-type", hdrs_extra)
            end
            redirects_left -= 1
            continue
        end

        if looks_like_login_wall(text) && resp.status == 200
            throw(LoginWall("ITTF login wall at $current_url — refresh cookies via WebBridge"))
        end

        return resp, text
    end
end

function _is_transient_http_error(e)::Bool
    e isa EOFError && return true
    # TCP-level failures (network blip, brief server-side drop): retryable
    if e isa HTTP.ConnectError
        msg = sprint(showerror, e)
        return occursin("ETIMEDOUT", msg) || occursin("ECONNRESET", msg) ||
               occursin("timed out", lowercase(msg))
    end
    if e isa HTTP.RequestError
        u = try
            e.error
        catch
            nothing
        end
        u isa EOFError && return true
        msg = sprint(showerror, e)
        return occursin("EOFError", msg) || occursin("Connection reset", msg) ||
               occursin("timed out", lowercase(msg)) || occursin("ECONNRESET", msg)
    end
    return false
end

"""One GET/POST with retries for proxy/EOF drops (long backoff)."""
function _http_exchange(method::AbstractString, url::AbstractString, hdrs, body;
                        timeout::Int, proxy::Union{Nothing,String},
                        attempts::Int=DEFAULT_HTTP_ATTEMPTS,
                        retry_base_sec::Float64=DEFAULT_HTTP_RETRY_BASE_SEC)
    local last_err
    for attempt in 1:attempts
        try
            if uppercase(method) == "GET"
                return if proxy === nothing
                    HTTP.get(url, hdrs; status_exception=false, readtimeout=timeout,
                             connecttimeout=30, redirect=false, retry=false)
                else
                    HTTP.get(url, hdrs; status_exception=false, readtimeout=timeout,
                             connecttimeout=30, redirect=false, retry=false, proxy=proxy)
                end
            elseif uppercase(method) == "POST"
                payload = body === nothing ? UInt8[] : body
                return if proxy === nothing
                    HTTP.post(url, hdrs, payload; status_exception=false, readtimeout=timeout,
                              connecttimeout=30, redirect=false, retry=false)
                else
                    HTTP.post(url, hdrs, payload; status_exception=false, readtimeout=timeout,
                              connecttimeout=30, redirect=false, retry=false, proxy=proxy)
                end
            else
                error("Unsupported method $method")
            end
        catch e
            last_err = e
            if _is_transient_http_error(e) && attempt < attempts
                wait_s = retry_base_sec * attempt   # 20s, 40s, 60s, ...
                println("transient HTTP error on $method $url (attempt $attempt/$attempts): $(typeof(e)); sleep $(wait_s)s then retry...")
                sleep(wait_s)
                continue
            end
            rethrow(e)
        end
    end
    throw(last_err)
end

# Note: Fabrik keeps list pagination state server-side per user/session, and it
# bleeds across events (a previous event's limitstart68 can land this GET on a
# middle page — or beyond the end, yielding "No records"). Always pin
# limitstart68=0 on the first page.
function list68_first_url(event_id::Integer)::String
    string(
        ITTF_BASE,
        "/index.php/event-matches/list/68?",
        "resetfilters=1",
        "&abc=$(event_id)",
        "&vw_matches___tournament_id_raw[value][]=$(event_id)",
        "&limitstart68=0",
    )
end

function list68_post_url(event_id::Integer)::String
    string(
        ITTF_BASE,
        "/index.php/event-matches/list/68?",
        "resetfilters=0",
        "&abc=$(event_id)",
        "&clearordering=0",
        "&clearfilters=0",
    )
end

function _gumbo_attr(node, key::AbstractString, default="")::String
    attrs = node.attributes
    haskey(attrs, key) ? string(attrs[key]) : string(default)
end

function _list68_keep_field(name::AbstractString)::Bool
    # Row checkboxes / bulk actions — browser pagination POST does not send these.
    startswith(name, "ids[") && return false
    name in ("checkAll", "fabrik_listplugin_name", "fabrik_listplugin_renderOrder",
             "fabrik_listplugin_options") && return false
    return true
end

"""Parse the Fabrik list form `#listform_68_com_fabrik_68` from a list/68 HTML page."""
function extract_list68_form(html::AbstractString)::List68Form
    doc = parsehtml(html)
    nodes = collect(eachmatch(Selector("form#listform_68_com_fabrik_68"), doc.root))
    isempty(nodes) && error("list/68 form #listform_68_com_fabrik_68 not found")
    form = first(nodes)
    action = _gumbo_attr(form, "action", "")
    isempty(action) && error("list/68 form missing action")
    fields = Dict{String,String}()

    for inp in eachmatch(Selector("input"), form)
        name = _gumbo_attr(inp, "name", "")
        isempty(name) && continue
        !_list68_keep_field(name) && continue
        typ = lowercase(_gumbo_attr(inp, "type", "text"))
        typ in ("submit", "button", "image", "checkbox") && continue
        fields[name] = _gumbo_attr(inp, "value", "")
    end

    for sel in eachmatch(Selector("select"), form)
        name = _gumbo_attr(sel, "name", "")
        isempty(name) && continue
        !_list68_keep_field(name) && continue
        chosen = ""
        for opt in eachmatch(Selector("option"), sel)
            attrs = opt.attributes
            if haskey(attrs, "selected")
                chosen = _gumbo_attr(opt, "value", strip(Gumbo.text(opt)))
                break
            end
        end
        if isempty(chosen)
            opts = collect(eachmatch(Selector("option"), sel))
            if !isempty(opts)
                chosen = _gumbo_attr(first(opts), "value", strip(Gumbo.text(first(opts))))
            end
        end
        fields[name] = chosen
    end

    for ta in eachmatch(Selector("textarea"), form)
        name = _gumbo_attr(ta, "name", "")
        isempty(name) && continue
        !_list68_keep_field(name) && continue
        fields[name] = strip(Gumbo.text(ta))
    end

    return List68Form(action, fields)
end

function build_list68_post_body(fields::AbstractDict;
                                event_id::Integer,
                                limit::Integer,
                                offset::Integer)::String
    f = Dict{String,String}()
    for (k, v) in fields
        ks = string(k)
        _list68_keep_field(ks) || continue
        f[ks] = string(v)
    end
    f["limit68"] = string(limit)
    f["limitstart68"] = string(offset)
    f["listid"] = "68"
    f["view"] = get(f, "view", "list")
    f["option"] = get(f, "option", "com_fabrik")
    f["format"] = "html"
    f["incfilters"] = get(f, "incfilters", "1")
    f["task"] = get(f, "task", "")
    f["fabrik___filter[list_68_com_fabrik_68][value][1]"] = string(event_id)
    if !haskey(f, "fabrik_referrer") || isempty(f["fabrik_referrer"])
        f["fabrik_referrer"] = "/index.php/event-matches/list/68?resetfilters=0&abc=$(event_id)&clearordering=0&clearfilters=0"
    end
    return join([HTTP.escapeuri(k) * "=" * HTTP.escapeuri(v) for (k, v) in f], "&")
end

function _validate_list68_rows!(html::AbstractString, event_id::Integer)
    rows = extract_fabrik_list_data(html; field_hint="vw_matches___")
    isempty(rows) && return rows
    for r in rows
        tid = r["vw_matches___tournament_id_raw"]
        Int(tid) == Int(event_id) || error(
            "list/68 tournament mismatch: expected $(event_id), got $(tid) (ITTF abc-only bug or wrong filter)"
        )
    end
    return rows
end

function _cache_list68_form!(html::AbstractString, event_id::Integer)
    SESSION.list68_form = extract_list68_form(html)
    SESSION.list68_event_id = Int(event_id)
    return SESSION.list68_form
end

"""Parse the Fabrik footer "Page X of Y Total: Z" → (x, y, z), or nothing."""
function _list_page_info(html::AbstractString)
    m = match(r"Page\s+(\d+)\s+of\s+(\d+)\s+Total:\s*(\d+)", html)
    m === nothing && return nothing
    return (parse(Int, m.captures[1]), parse(Int, m.captures[2]), parse(Int, m.captures[3]))
end

"""Fetch one matches page via list/68: GET when offset==0 (or to seed form), else POST."""
function fetch_event_matches_html(event_id::Integer; limit::Integer=DEFAULT_MATCH_LIMIT, offset::Integer=0,
                                  cookies::Union{Nothing,AbstractDict}=nothing)::String
    cookies !== nothing && set_session_cookies!(cookies)

    need_seed = SESSION.list68_form === nothing || SESSION.list68_event_id != Int(event_id)
    if offset == 0 || need_seed
        resp, html0 = ittf_request("GET", list68_first_url(event_id))
        if resp.status in (403, 404)
            # Fabrik form/CSRF tokens are bound to the session; a 403/404 here
            # almost always means the session expired under us.
            throw(LoginWall("list/68 GET failed: HTTP $(resp.status) for event $event_id (stale session?)"))
        end
        resp.status == 200 || error("Match list/68 GET failed: HTTP $(resp.status)")
        _cache_list68_form!(html0, event_id)
        if offset == 0
            _validate_list68_rows!(html0, event_id)
            # Guard against server-side pagination-state bleed: the first page
            # of an event must be page 1, and an empty page 1 with a non-zero
            # footer total means we were served a stale offset — never treat
            # that as "event complete".
            info = _list_page_info(html0)
            if info !== nothing && info[1] != 1
                error("list/68 pagination bleed for event $event_id: first GET landed on " *
                      "page $(info[1]) of $(info[2]) (total $(info[3]))")
            end
            if info !== nothing && info[3] > 0 &&
               isempty(extract_fabrik_list_data(html0; field_hint="vw_matches___"))
                error("list/68 page 1 of event $event_id has no rows but footer total is " *
                      "$(info[3]) — refusing to mark the event complete")
            end
            return html0
        end
    end

    form = SESSION.list68_form
    form === nothing && error("list/68 form cache empty")
    post_url = list68_post_url(event_id)
    body = build_list68_post_body(form.fields; event_id=event_id, limit=limit, offset=offset)
    referer = offset == 0 ? list68_first_url(event_id) : post_url
    resp, html = ittf_request(
        "POST",
        post_url;
        body=body,
        headers=[
            "Content-Type" => "application/x-www-form-urlencoded",
            "Origin" => ITTF_BASE,
            "Referer" => referer,
        ],
    )
    if resp.status in (403, 404)
        throw(LoginWall("list/68 POST failed: HTTP $(resp.status) for event $event_id (stale session token?)"))
    end
    resp.status == 200 || error("Match list/68 POST failed: HTTP $(resp.status)")
    _cache_list68_form!(html, event_id)
    _validate_list68_rows!(html, event_id)
    return html
end

function fetch_event_matches_html(event_id::Integer, cookies::AbstractDict; limit::Integer=DEFAULT_MATCH_LIMIT, offset::Integer=0)
    fetch_event_matches_html(event_id; limit=limit, offset=offset, cookies=cookies)
end

function download_event_matches_json(event_id::Integer; limit::Integer=DEFAULT_MATCH_LIMIT, offset::Integer=0,
                                     cookies::Union{Nothing,AbstractDict}=nothing)::String
    html = fetch_event_matches_html(event_id; limit=limit, offset=offset, cookies=cookies)
    rows = extract_fabrik_list_data(html; field_hint="vw_matches___")
    to_ittf_list_json(rows)
end

function download_event_matches_json(event_id::Integer, cookies::AbstractDict; limit::Integer=DEFAULT_MATCH_LIMIT, offset::Integer=0)
    download_event_matches_json(event_id; limit=limit, offset=offset, cookies=cookies)
end

# --- events list (list/27, HTML; the JSON variant is blocked) ---

const DEFAULT_EVENTS_LIMIT = 100

function events27_page_url(offset::Integer=0; limit::Integer=DEFAULT_EVENTS_LIMIT, reset::Bool=false)::String
    if reset
        return "$ITTF_BASE/index.php/events/list/27?resetfilters=1&limit27=$limit"
    else
        return "$ITTF_BASE/index.php/events/list/27?resetfilters=0&clearordering=0&clearfilters=0&limit27=$limit&limitstart27=$offset"
    end
end

"""Fetch one events page via list/27 (plain GET pagination) and return raw rows."""
function fetch_events27_rows(; offset::Integer=0, limit::Integer=DEFAULT_EVENTS_LIMIT)
    url = events27_page_url(offset; limit=limit, reset=(offset == 0))
    resp, html = ittf_request("GET", url)
    resp.status == 200 || error("Events list/27 GET failed: HTTP $(resp.status)")
    return extract_fabrik_list_data(html; field_hint="vw_tournaments___")
end

function _next_events_file_num(events_dir::AbstractString="events")
    n = 0
    while isfile(joinpath(events_dir, "events_$(n).json"))
        n += 1
    end
    return n
end

"""
Start a new incremental crawl cycle: page through the events list (list/27),
keep events whose id is not in `known_ids`, save them as the next raw events
batch file, and set crawl_state to phase=matches with the new queue.

`match_files_from` records the first matches_N.json file of this cycle so that
post-processing only merges files written by this cycle.
"""
function start_new_cycle!(known_ids::Set{Int}; state_path::AbstractString=DEFAULT_STATE_PATH,
                          events_dir::AbstractString="events", matches_dir::AbstractString="matches",
                          pacing::PacingProfile=PacingProfile(),
                          events_limit::Integer=DEFAULT_EVENTS_LIMIT,
                          max_pages::Integer=20)
    isdir(events_dir) || mkpath(events_dir)
    state = Dict{String,Any}()
    new_rows = Any[]
    seen_new = Set{Int}()

    for page in 0:(max_pages - 1)
        offset = page * events_limit
        println("events: fetching list/27 offset=$offset limit=$events_limit")
        rows = fetch_events27_rows(; offset=offset, limit=events_limit)
        isempty(rows) && (println("events: empty page, stop"); break)

        n_known = 0
        for r in rows
            id = Int(r["vw_tournaments___tournament_id_raw"])
            if id in known_ids || id in seen_new
                n_known += 1
            else
                push!(seen_new, id)
                push!(new_rows, r)
            end
        end
        println("events: page had $(length(rows)) rows, $(n_known) already known, $(length(new_rows)) new so far")
        # stop once a page is entirely known events (list is newest-first)
        n_known == length(rows) && break
        _pace!(state; pacing=pacing)
    end

    st = default_state()
    if isempty(new_rows)
        st["phase"] = "done"
        st["stop_reason"] = "done"
        save_crawl_state(st; path=state_path)
        println("no new events — nothing to crawl")
        return st
    end

    # newest-first in the list; crawl oldest-first so match files follow chronology
    reverse!(new_rows)
    batch_file = joinpath(events_dir, "events_$(_next_events_file_num(events_dir)).json")
    open(batch_file, "w") do io
        JSON.print(io, Any[new_rows])   # [[dicts]] — isomorphic with raw ITTF dumps
    end

    next_file = _next_match_file_num(matches_dir)
    st["phase"] = "matches"
    st["match_event_ids"] = [Int(r["vw_tournaments___tournament_id_raw"]) for r in new_rows]
    st["match_event_index"] = 1
    st["event_id"] = st["match_event_ids"][1]
    st["match_offset"] = 0
    st["next_match_file_num"] = next_file
    st["match_files_from"] = next_file
    st["events_batch_file"] = batch_file
    st["pending_player_ids"] = Int[]
    st["stop_reason"] = nothing
    save_crawl_state(st; path=state_path)
    println("new cycle: $(length(new_rows)) events → $batch_file; matches from file #$next_file")
    return st
end

function list60_player_url(player_id::Integer)::String
    # Array-style filter param, same shape as list/68's
    # vw_matches___tournament_id_raw[value][]= — matches experience suggests
    # the rate limiter is less sensitive to this form.
    string(
        ITTF_BASE,
        "/index.php/player-profile/list/60?",
        "resetfilters=1",
        "&vw_profiles___player_id_raw[value][]=$(player_id)",
    )
end

"""Strip trailing (ASSOC) from match name fields → profile Name_raw."""
function _player_name_raw_from_match(s::AbstractString)::String
    t = strip(s)
    isempty(t) && return ""
    m = match(r"^(.*?)\s*\([^)]*\)\s*$", t)
    return m === nothing ? t : strip(m.captures[1])
end

function _collect_player_names_from_match_files(file_nums::AbstractRange; matches_dir="matches")
    names = Dict{Int,String}()
    pairs = (
        ("vw_matches___player_a_id_raw", "vw_matches___name_a_raw"),
        ("vw_matches___player_x_id_raw", "vw_matches___name_x_raw"),
        ("vw_matches___player_b_id_raw", "vw_matches___name_b_raw"),
        ("vw_matches___player_y_id_raw", "vw_matches___name_y_raw"),
    )
    for n in file_nums
        path = joinpath(matches_dir, "matches_$(n).json")
        isfile(path) || continue
        for r in _parse_ittf_rows(path)
            for (idk, namek) in pairs
                idv = get(r, idk, nothing)
                nv = get(r, namek, nothing)
                (idv isa Integer || (idv isa Real && idv == floor(idv))) || continue
                nv isa AbstractString || continue
                nm = _player_name_raw_from_match(nv)
                isempty(nm) && continue
                names[Int(idv)] = nm
            end
        end
    end
    return names
end

const LAST_PLAYER_FAIL_HTML = joinpath("testdata", "last_player_fail.html")

function _dump_player_fail_html!(player_id::Integer, url::AbstractString, html::AbstractString)
    try
        isdir("testdata") || mkpath("testdata")
        open(LAST_PLAYER_FAIL_HTML, "w") do io
            println(io, "<!-- player_id=$player_id -->")
            println(io, "<!-- url=$url -->")
            println(io, "<!-- bytes=$(sizeof(html)) saved=$(Dates.now()) -->")
            write(io, html)
        end
        println("wrote failing HTML to $LAST_PLAYER_FAIL_HTML ($(sizeof(html)) bytes)")
    catch e
        @warn "failed to dump player HTML" exception=e
    end
end

"""Download one player via browser list/60 HTML. No id-only retry."""
function download_player_json(player_id::Integer; cookies::Union{Nothing,AbstractDict}=nothing)::String
    cookies !== nothing && set_session_cookies!(cookies)
    url = list60_player_url(player_id)
    resp, html = ittf_request("GET", url)
    if resp.status != 200
        _dump_player_fail_html!(player_id, url, html)
        throw(PlayerJsonFailed(Int(player_id), "list/60 HTTP $(resp.status) url=$(url)"))
    end
    if looks_like_login_wall(html)
        _dump_player_fail_html!(player_id, url, html)
        throw(PlayerJsonFailed(Int(player_id),
            "login wall (guest HTML) — session cookie missing/expired; paste fresh COOKIES from a logged-in browser"))
    end
    local rows
    try
        rows = extract_fabrik_list_data(html; field_hint="vw_profiles___")
    catch e
        e isa RateLimited && rethrow(e)
        _dump_player_fail_html!(player_id, url, html)
        snippet = replace(first(html, min(120, sizeof(html))), r"\s+" => " ")
        throw(PlayerJsonFailed(Int(player_id), "list/60 extract failed: $(typeof(e)); body≈$(repr(snippet))"))
    end
    if isempty(rows)
        _dump_player_fail_html!(player_id, url, html)
        throw(PlayerJsonFailed(Int(player_id), "list/60 returned 0 profile rows url=$(url)"))
    end
    tid = rows[1]["vw_profiles___player_id_raw"]
    if Int(tid) != Int(player_id)
        _dump_player_fail_html!(player_id, url, html)
        throw(PlayerJsonFailed(Int(player_id), "list/60 player id mismatch: got $(tid)"))
    end
    return to_ittf_list_json(rows)
end

function download_player_json(player_id::Integer, cookies::AbstractDict)
    download_player_json(player_id; cookies=cookies)
end

# -------------------- crawl state --------------------

function default_state()
    Dict{String,Any}(
        "phase" => "matches",
        "event_offset" => 0,
        "match_event_ids" => Int[],
        "match_event_index" => 1,
        "event_id" => nothing,
        "match_offset" => 0,
        "pending_player_ids" => Int[],
        "next_match_file_num" => 0,
        "events_batch_file" => nothing,
        "pages_since_rest" => 0,
        "updated_at" => string(now()),
    )
end

function save_crawl_state(state::AbstractDict; path::AbstractString=DEFAULT_STATE_PATH)
    state = Dict{String,Any}(state)
    state["updated_at"] = string(now())
    open(path, "w") do io
        JSON.print(io, state, 2)
    end
    return path
end

function load_crawl_state(path::AbstractString=DEFAULT_STATE_PATH)
    isfile(path) || return nothing
    # JSON.jl may return JSON.Object; crawl helpers mutate a plain Dict.
    raw = JSON.parsefile(path)
    return Dict{String,Any}(string(k) => v for (k, v) in pairs(raw))
end

function _next_match_file_num(matches_dir::AbstractString="matches")
    n = 0
    while isfile(joinpath(matches_dir, "matches_$(n).json"))
        n += 1
    end
    return n
end

function _parse_ittf_rows(path::AbstractString)
    data = JSON.parsefile(path)
    if data isa AbstractVector && !isempty(data) && data[1] isa AbstractVector
        return data[1]
    elseif data isa AbstractVector
        return data
    end
    return Any[]
end

function _parse_ittf_rows_from_string(s::AbstractString)
    data = JSON.parse(s)
    if data isa AbstractVector && !isempty(data) && data[1] isa AbstractVector
        return data[1]
    elseif data isa AbstractVector
        return data
    end
    return Any[]
end

"""
Bootstrap checkpoint from the 2026-08-11 partial run (option A):
keep matches for event 3366 pages already downloaded; resume at offset 900.
"""
function bootstrap_crawl_state_from_disk!(; state_path::AbstractString=DEFAULT_STATE_PATH,
                                          events_batch::AbstractString="events/events_47.json",
                                          force::Bool=false)
    if isfile(state_path) && !force
        st = load_crawl_state(state_path)
        # keep progress, but refresh next file index from disk
        st["next_match_file_num"] = _next_match_file_num()
        save_crawl_state(st; path=state_path)
        println("bootstrap: existing $state_path kept (phase=$(get(st, "phase", "?"))). Use force=true to overwrite.")
        return st
    end

    isfile(events_batch) || error("Missing $events_batch for bootstrap")
    rows = _parse_ittf_rows(events_batch)
    all_ids = Int[r["vw_tournaments___tournament_id_raw"] for r in rows]
    start = findfirst(==(3366), all_ids)
    start === nothing && error("tournament 3366 not found in $events_batch")
    queue = all_ids[start:end]

    st = default_state()
    st["phase"] = "matches"
    st["match_event_ids"] = queue
    st["match_event_index"] = 1
    st["event_id"] = 3366
    st["match_offset"] = 900
    st["next_match_file_num"] = _next_match_file_num()
    st["events_batch_file"] = events_batch
    st["pending_player_ids"] = Int[]
    st["note"] = "Bootstrapped option A: resume event 3366 at offset 900; files matches_8922-8930 kept"
    save_crawl_state(st; path=state_path)
    println("bootstrap: wrote $state_path phase=matches event_id=3366 offset=900 queue=$(length(queue)) next_file=$(st["next_match_file_num"])")
    return st
end

function _pace!(state::AbstractDict; pacing::PacingProfile)
    pause = pacing.request_pause_min +
            rand() * max(0.0, pacing.request_pause_max - pacing.request_pause_min)
    sleep(pause)

    # Daily budget bookkeeping (persisted in crawl_state.json → survives restarts)
    today_str = Dates.format(Dates.today(), "yyyy-mm-dd")
    if get(state, "requests_day", nothing) != today_str
        state["requests_day"] = today_str
        state["requests_today"] = 0
    end
    state["requests_today"] = Int(get(state, "requests_today", 0)) + 1
    if pacing.daily_request_budget > 0 &&
       Int(state["requests_today"]) > pacing.daily_request_budget
        throw(DailyBudgetExhausted(pacing.daily_request_budget))
    end

    n = Int(get(state, "pages_since_rest", 0)) + 1
    state["pages_since_rest"] = n
    if pacing.session_pages > 0 && n >= pacing.session_pages
        rest = pacing.session_rest_min +
               rand() * max(0.0, pacing.session_rest_max - pacing.session_rest_min)
        println("session rest $(round(Int, rest))s after $(n) pages...")
        sleep(rest)
        state["pages_since_rest"] = 0
    end
end

function _save_match_page!(json_text::AbstractString, state::AbstractDict; matches_dir::AbstractString="matches")
    isdir(matches_dir) || mkpath(matches_dir)
    n = Int(state["next_match_file_num"])
    path = joinpath(matches_dir, "matches_$(n).json")
    open(path, "w") do io
        write(io, json_text)
    end
    state["next_match_file_num"] = n + 1
    println("saved $path")
    return path
end

function _collect_player_ids_from_match_files(file_nums::AbstractRange; matches_dir="matches")
    ids = Set{Int}()
    for n in file_nums
        path = joinpath(matches_dir, "matches_$(n).json")
        isfile(path) || continue
        for r in _parse_ittf_rows(path)
            for k in ("vw_matches___player_a_id_raw", "vw_matches___player_x_id_raw",
                      "vw_matches___player_b_id_raw", "vw_matches___player_y_id_raw")
                v = get(r, k, nothing)
                if v isa Integer
                    push!(ids, Int(v))
                elseif v isa Real && v == floor(v)
                    push!(ids, Int(v))
                end
            end
        end
    end
    return ids
end

"""
Slow crawl with checkpoints. On 429: save state and return (no sleep / no re-login).
Supply cookies via set_session_cookies!(COOKIES) before calling.

Pacing is human-like by design (see PacingProfile): jittered pauses, session
breaks, daily budget. ITTF 429 penalties escalate, so the goal is to never hit
one; the checkpoint/return path is only a fallback.

On return, `state["stop_reason"]` tells the caller why we stopped:
  "done" | "rate_limited" | "player_failed" | "daily_budget"
`state["retry_after"]` holds the server-suggested wait (seconds) when known.
"""
function run_crawl!(; state_path::AbstractString=DEFAULT_STATE_PATH,
                    pacing::PacingProfile=PacingProfile(),
                    match_limit::Int=DEFAULT_MATCH_LIMIT,
                    bootstrap::Bool=true,
                    probe::Bool=false)  # ignored; kept so old callers do not error
    probe && @warn "probe= is ignored; crawl starts directly on list/68"
    if bootstrap
        bootstrap_crawl_state_from_disk!(; state_path=state_path, force=false)
    end
    state = load_crawl_state(state_path)
    state === nothing && error("No crawl state at $state_path")

    isempty(SESSION.cookies) && error("No cookies in SESSION — refresh cookies first (crawl.jl does this via WebBridge)")

    state["stop_reason"] = nothing
    try
        while true
            phase = string(get(state, "phase", "done"))
            if phase == "done"
                println("crawl already done")
                state["stop_reason"] = "done"
                save_crawl_state(state; path=state_path)
                return state
            end

            if phase == "matches"
                _crawl_matches_phase!(state; state_path=state_path, pacing=pacing,
                                      match_limit=match_limit)
            elseif phase == "players"
                _crawl_players_phase!(state; state_path=state_path, pacing=pacing)
            elseif phase == "events"
                @warn "events phase not implemented in run_crawl!; marking matches"
                state["phase"] = "matches"
                save_crawl_state(state; path=state_path)
            else
                error("Unknown phase: $phase")
            end

            save_crawl_state(state; path=state_path)
            if string(state["phase"]) == "done"
                state["stop_reason"] = "done"
                save_crawl_state(state; path=state_path)
                return state
            end
        end
    catch e
        if e isa RateLimited
            state["stop_reason"] = "rate_limited"
            state["retry_after"] = e.retry_after
            save_crawl_state(state; path=state_path)
            mins = round(e.retry_after / 60; digits=1)
            println("429 — checkpoint saved to $state_path")
            println("Server suggested wait ≈ $(e.retry_after)s (~$(mins) min). Stop requests, change IP if needed, then re-run.")
            return state
        elseif e isa PlayerJsonFailed
            state["stop_reason"] = "player_failed"
            save_crawl_state(state; path=state_path)
            println("player list/60 HTML failed — checkpoint saved to $state_path")
            println(e)
            println("Wait / change IP, then re-run.")
            return state
        elseif e isa DailyBudgetExhausted
            state["stop_reason"] = "daily_budget"
            save_crawl_state(state; path=state_path)
            println("daily request budget ($(e.limit)) exhausted — checkpoint saved to $state_path")
            return state
        elseif e isa LoginWall
            state["stop_reason"] = "login_wall"
            save_crawl_state(state; path=state_path)
            println("login wall (session expired) — checkpoint saved to $state_path")
            return state
        end
        save_crawl_state(state; path=state_path)
        rethrow(e)
    end
end

function _crawl_matches_phase!(state::AbstractDict; state_path::AbstractString,
                               pacing::PacingProfile, match_limit::Int)
    ids = [Int(x) for x in state["match_event_ids"]]
    idx = Int(get(state, "match_event_index", 1))
    offset = Int(get(state, "match_offset", 0))
    isempty(ids) && (state["phase"] = "players"; return)

    while idx <= length(ids)
        event_id = ids[idx]
        state["match_event_index"] = idx
        state["event_id"] = event_id
        state["match_offset"] = offset
        save_crawl_state(state; path=state_path)

        println("matches: event=$event_id offset=$offset limit=$match_limit")
        json_text = download_event_matches_json(event_id; limit=match_limit, offset=offset)
        rows = _parse_ittf_rows_from_string(json_text)
        if isempty(rows)
            println("matches: event=$event_id complete")
            idx += 1
            offset = 0
            state["match_event_index"] = idx
            state["match_offset"] = 0
            state["event_id"] = idx <= length(ids) ? ids[idx] : nothing
            save_crawl_state(state; path=state_path)
            _pace!(state; pacing=pacing)
            continue
        end

        _save_match_page!(json_text, state)
        offset += match_limit
        state["match_offset"] = offset
        save_crawl_state(state; path=state_path)
        _pace!(state; pacing=pacing)
    end

    if isempty(get(state, "pending_player_ids", Int[]))
        start_n = Int(get(state, "match_files_from", 8885))
        end_n = Int(state["next_match_file_num"]) - 1
        ids_set = _collect_player_ids_from_match_files(start_n:end_n)
        pending = Int[]
        for id in sort!(collect(ids_set))
            path = joinpath("players", "$(id).json")
            if !isfile(path) || filesize(path) < 20
                push!(pending, id)
            end
        end
        state["pending_player_ids"] = pending
        println("players queued: $(length(pending)) (missing/empty profiles)")
    end
    state["phase"] = "players"
    state["event_id"] = nothing
    state["match_offset"] = 0
    save_crawl_state(state; path=state_path)
end

function _crawl_players_phase!(state::AbstractDict; state_path::AbstractString, pacing::PacingProfile)
    pending = [Int(x) for x in get(state, "pending_player_ids", Int[])]
    isdir("players") || mkpath("players")
    start_n = Int(get(state, "match_files_from", 8885))
    end_n = Int(get(state, "next_match_file_num", _next_match_file_num())) - 1
    name_map = _collect_player_names_from_match_files(start_n:end_n)
    println("player name map from matches_$(start_n)–$(end_n): $(length(name_map)) ids")
    while !isempty(pending)
        pid = first(pending)
        state["pending_player_ids"] = pending
        save_crawl_state(state; path=state_path)
        out = joinpath("players", "$(pid).json")
        if isfile(out) && filesize(out) >= 20
            popfirst!(pending)
            state["pending_player_ids"] = pending
            save_crawl_state(state; path=state_path)
            continue
        end
        pname = get(name_map, pid, nothing)
        label = pname === nothing ? "(no name)" : string(pname)
        println("player $pid $label ...")
        # Keep pid in pending until success (429 / fail → resume same id).
        js = download_player_json(pid)
        open(out, "w") do io
            write(io, js)
        end
        popfirst!(pending)
        state["pending_player_ids"] = pending
        save_crawl_state(state; path=state_path)
        _pace!(state; pacing=pacing)
    end
    state["pending_player_ids"] = Int[]
    state["phase"] = "done"
    save_crawl_state(state; path=state_path)
    println("crawl phase=done")
end

# Populate default browser headers so non-crawl.jl users get them too.
set_user_agent!(DEFAULT_UA)

end # module
