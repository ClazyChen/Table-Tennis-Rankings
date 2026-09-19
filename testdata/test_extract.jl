include(joinpath(@__DIR__, "..", "src", "ittf_fabrik.jl"))
using .ITTFFabrik
using JSON

html = read(joinpath(@__DIR__, "synthetic_matches.html"), String)
rows = extract_fabrik_list_data(html; field_hint="vw_matches___")
@assert length(rows) == 1
@assert rows[1]["vw_matches___player_a_id_raw"] == 10
@assert rows[1]["vw_matches___res_raw"] == "3 - 1"
js = to_ittf_list_json(rows)
@assert JSON.parse(js)[1][1]["vw_matches___tournament_id_raw"] == 3480
@assert looks_like_login_wall("<p>Click here to register.</p><a href='/login'>please click</a> to login")
println("synthetic OK")

fixture = joinpath(@__DIR__, "event_3480_matches.html")
if isfile(fixture)
    rows = extract_fabrik_list_data(read(fixture, String); field_hint="vw_matches___")
    @assert length(rows) == 93
    println("fixture 3480 OK rows=$(length(rows))")
else
    println("skip large fixture")
end
