include(joinpath(@__DIR__, "..", "src", "ittf_fabrik.jl"))
using .ITTFFabrik
using HTTP
using JSON

cd(joinpath(@__DIR__, ".."))
raw = read("ittf_credentials.json", String)
println("credentials file bytes=", sizeof(raw))
println("has BOM=", startswith(raw, "\ufeff"))
data = JSON.parse(raw)
println("keys=", join(keys(data), ","))
u = string(data["username"])
p = string(data["password"])
println("user=", repr(u), " pass_len=", length(p), " pass_codepoints=", length(collect(p)))
println("pass has whitespace around=", p != strip(p))

empty!(ITTFFabrik.SESSION.cookies)
_, html = ITTFFabrik.ittf_request("GET", "https://results.ittf.link/index.php/login"; allow_login_retry=false)
action, fields = ITTFFabrik._extract_main_login_form(html)
fields["username"] = u
fields["password"] = p
fields["remember"] = "yes"
body = join(["$(HTTP.escapeuri(k))=$(HTTP.escapeuri(v))" for (k, v) in fields], "&")
println("body_len=", length(body))
println("body contains username=", occursin(HTTP.escapeuri(u), body))
println("body contains escaped password=", occursin(HTTP.escapeuri(p), body))
# count password= occurrences
println("password= count=", count("password=", body))
