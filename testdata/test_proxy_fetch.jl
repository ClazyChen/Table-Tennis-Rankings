# Live single-request check: proxy + browser-fingerprint headers + fresh cookies.
# Fetches the next pending player from crawl_state.json via list/60 and verifies
# we get real profile data (not a login wall, not a 429). Writes nothing.
const ROOT = dirname(@__DIR__)
cd(ROOT)
using JSON, HTTP

include(joinpath(ROOT, "src", "structures.jl"))
include(joinpath(ROOT, "src", "ittf_fabrik.jl"))
using .ITTFFabrik

const CREDS = JSON.parsefile(joinpath(ROOT, "ittf_credentials.json"))
const WB = "http://127.0.0.1:10086/command"

function webbridge(action::String, args::Dict=Dict())
    body = JSON.json(Dict("action" => action, "args" => args, "session" => "ittf-crawl"))
    resp = HTTP.post(WB, ["Content-Type" => "application/json"], body;
                     status_exception=false, retry=false, readtimeout=60)
    resp.status == 200 || return nothing
    d = JSON.parse(String(resp.body))
    return get(d, "ok", false) == true ? d["data"] : nothing
end
webbridge_eval(code) = (d = webbridge("evaluate", Dict("code" => code));
                        d === nothing ? nothing : get(d, "value", nothing))

set_proxy!(get(CREDS, "proxy", nothing))

# Attach a session tab first — cdp/evaluate need a current tab.
webbridge("navigate", Dict("url" => "https://results.ittf.link/index.php/events",
                           "newTab" => true, "group_title" => "ITTF 排名数据更新")) === nothing &&
    error("WebBridge unreachable — open the browser with the extension")
sleep(3)

d = webbridge("cdp", Dict("method" => "Storage.getCookies", "params" => Dict()))
d === nothing && error("WebBridge unreachable — open the browser with the extension")
cookies = Dict{String,String}()
for c in d["cookies"]
    occursin("ittf.link", string(get(c, "domain", ""))) || continue
    cookies[string(c["name"])] = string(c["value"])
end
set_session_cookies!(cookies)

ua = webbridge_eval("navigator.userAgent")
ua isa AbstractString && set_user_agent!(ua)

state = JSON.parsefile("crawl_state.json")
pending = Int[state["pending_player_ids"]...]
isempty(pending) && (println("no pending players — nothing to test"); exit(0))
pid = first(pending)
println("testing player $pid via proxy $(get_proxy()) ...")
js = download_player_json(pid)
rows = JSON.parse(js)[1]
println("OK: $(length(rows)) row(s); name=$(rows[1]["vw_profiles___name_raw"])")
println("bytes=$(sizeof(js)) — NOT written to players/ (test only)")
