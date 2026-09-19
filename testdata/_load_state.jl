include(joinpath(@__DIR__, "..", "src", "ittf_fabrik.jl"))
using .ITTFFabrik
st = load_crawl_state(joinpath(@__DIR__, "..", "crawl_state.json"))
println("event_id=$(st["event_id"]) offset=$(st["match_offset"]) file=$(st["next_match_file_num"])")
