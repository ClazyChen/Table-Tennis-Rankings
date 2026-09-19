# parse-only smoke check
src = read("post_crawl.jl", String)
Meta.parseall(src)
println("PARSE_OK bytes=$(sizeof(src))")
