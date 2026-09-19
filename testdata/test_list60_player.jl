# Offline: list/60 player HTML → isomorphic [[dicts]] for parse_player_data
include(joinpath(@__DIR__, "..", "src", "ittf_fabrik.jl"))
using .ITTFFabrik
using JSON

html = read(joinpath(@__DIR__, "list60_player.html"), String)
rows = extract_fabrik_list_data(html; field_hint="vw_profiles___")
@assert length(rows) == 1
r = rows[1]
@assert r["vw_profiles___player_id_raw"] == 121558
@assert haskey(r, "vw_profiles___profile_raw")
@assert haskey(r, "vw_profiles___name_raw")
@assert haskey(r, "vw_profiles___gender_raw")
@assert haskey(r, "vw_profiles___player_id")
js = to_ittf_list_json(rows)
@assert startswith(js, "[[")
data = JSON.parse(js)
@assert data[1][1]["vw_profiles___player_id_raw"] == 121558

u = ITTFFabrik.list60_player_url(121558)
@assert occursin("/player-profile/list/60?", u)
@assert occursin("resetfilters=1", u)
@assert occursin("vw_profiles___player_id_raw[value][]=121558", u)   # array-style, like list/68
@assert !occursin("vw_profiles___Name_raw=", u)
@assert !occursin("listid=33", u)
@assert !occursin("format=json", u)

@assert ITTFFabrik._player_name_raw_from_match("GAZVODA Neza (SLO)") == "GAZVODA Neza"
@assert ITTFFabrik._player_name_raw_from_match("XIANG Peng") == "XIANG Peng"

println("test_list60_player: OK")
