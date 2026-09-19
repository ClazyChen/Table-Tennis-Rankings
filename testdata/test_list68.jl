# Offline tests for list/68 URL + form helpers (no network).
include(joinpath(@__DIR__, "..", "src", "ittf_fabrik.jl"))
using .ITTFFabrik

const GET_HTML = read(joinpath(@__DIR__, "list68_get.html"), String)
const POST_HTML = read(joinpath(@__DIR__, "list68_post.html"), String)

# --- URLs ---
u0 = ITTFFabrik.list68_first_url(3494)
@assert occursin("/event-matches/list/68?", u0)
@assert occursin("resetfilters=1", u0)
@assert occursin("abc=3494", u0)
@assert occursin("vw_matches___tournament_id_raw", u0)
@assert occursin("3494", u0)
@assert !occursin("/list/31", u0)

u1 = ITTFFabrik.list68_post_url(3494)
@assert occursin("resetfilters=0", u1)
@assert occursin("abc=3494", u1)
@assert occursin("clearordering=0", u1)
@assert occursin("clearfilters=0", u1)
@assert !occursin("/list/31", u1)

# --- form extract from GET fixture ---
form = ITTFFabrik.extract_list68_form(GET_HTML)
@assert form.action isa AbstractString
@assert occursin("list/68", form.action)
@assert form.fields["limitstart68"] == "0"
@assert form.fields["limit68"] == "50"
@assert form.fields["listid"] == "68"
@assert form.fields["fabrik___filter[list_68_com_fabrik_68][value][1]"] == "3494"
@assert any(length(k) == 32 && all(isxdigit, k) for k in keys(form.fields))

# --- build POST body for page 2 ---
body = ITTFFabrik.build_list68_post_body(form.fields; event_id=3494, limit=50, offset=50)
@assert occursin("limitstart68=50", body)
@assert occursin("limit68=50", body)
@assert occursin("listid=68", body)
# value[1] encoded
@assert occursin("3494", body)
@assert !occursin("ids%5B", body)
@assert !occursin("ids[", body)
println("post body bytes=", sizeof(body))

# --- POST fixture data ---
rows0 = extract_fabrik_list_data(GET_HTML; field_hint="vw_matches___")
rows1 = extract_fabrik_list_data(POST_HTML; field_hint="vw_matches___")
@assert length(rows0) == 50
@assert length(rows1) == 50
@assert all(r -> r["vw_matches___tournament_id_raw"] == 3494, rows0)
@assert all(r -> r["vw_matches___tournament_id_raw"] == 3494, rows1)
form1 = ITTFFabrik.extract_list68_form(POST_HTML)
@assert form1.fields["limitstart68"] == "50"

println("test_list68: OK")
