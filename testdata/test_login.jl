include(joinpath(@__DIR__, "..", "src", "ittf_fabrik.jl"))
using .ITTFFabrik

cd(joinpath(@__DIR__, ".."))
empty!(ITTFFabrik.SESSION.cookies)
login!()
println("cookies=", join(keys(get_session_cookies()), ", "))
println("LIVE LOGIN OK")
