include(joinpath(@__DIR__, "..", "src", "ittf_fabrik.jl"))
using .ITTFFabrik
using JSON

# offline extract still works
html = read(joinpath(@__DIR__, "synthetic_matches.html"), String)
rows = extract_fabrik_list_data(html; field_hint="vw_matches___")
@assert length(rows) == 1

# retry-after parsing
body = """Try again in <strong>about 49 minutes</strong>
<script>var remaining = 2901;</script>"""
@assert parse_retry_after_seconds(body) == 2901
@assert looks_like_rate_limit_page("<h1>429</h1><p>Too many requests — we're temporarily limiting")

# bootstrap — write to a temp state file (never clobber the real crawl_state.json)
cd(joinpath(@__DIR__, ".."))
tmp_state = tempname() * ".json"
st = bootstrap_crawl_state_from_disk!(; state_path=tmp_state, force=true)
@assert st["phase"] == "matches"
@assert st["event_id"] == 3366
@assert st["match_offset"] == 900
@assert st["match_event_ids"][1] == 3366
@assert length(st["match_event_ids"]) == 8
rm(tmp_state; force=true)
println("bootstrap OK: ", st["note"])
println("next_match_file_num=", st["next_match_file_num"])
println("ALL OK")
