# Offline test: events list/27 HTML extraction (fixture captured via browser 2026-09-18).
include(joinpath(@__DIR__, "..", "src", "ittf_fabrik.jl"))
using .ITTFFabrik

html = read(joinpath(@__DIR__, "events27.html"), String)
rows = extract_fabrik_list_data(html; field_hint="vw_tournaments___")
@assert length(rows) == 10  # browser UI default page size
for r in rows
    @assert haskey(r, "vw_tournaments___tournament_id_raw")
    @assert haskey(r, "vw_tournaments___tournament_raw")
    @assert haskey(r, "vw_tournaments___tour_end_raw")
    @assert haskey(r, "vw_tournaments___type")
end
@assert rows[1]["vw_tournaments___tournament_id_raw"] == 3331

# URL shapes
@assert ITTFFabrik.events27_page_url(0; reset=true) ==
    "https://results.ittf.link/index.php/events/list/27?resetfilters=1&limit27=100"
@assert ITTFFabrik.events27_page_url(200) ==
    "https://results.ittf.link/index.php/events/list/27?resetfilters=0&clearordering=0&clearfilters=0&limit27=100&limitstart27=200"

println("test_events27: OK")
