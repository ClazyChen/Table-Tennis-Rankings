include(joinpath(@__DIR__, "..", "src", "ittf_fabrik.jl"))
using .ITTFFabrik
using HTTP

cd(joinpath(@__DIR__, ".."))
empty!(ITTFFabrik.SESSION.cookies)
creds = ITTFFabrik.load_credentials()
_, html = ITTFFabrik.ittf_request("GET", "https://results.ittf.link/index.php/login"; allow_login_retry=false)
action, fields = ITTFFabrik._extract_main_login_form(html)
fields["username"] = creds.username
fields["password"] = creds.password
fields["remember"] = "yes"
body = join(["$(HTTP.escapeuri(k))=$(HTTP.escapeuri(v))" for (k, v) in fields], "&")
_, html2 = ITTFFabrik.ittf_request(
    "POST", ITTFFabrik._absolute_ittf_url(action);
    body=body,
    headers=["Content-Type" => "application/x-www-form-urlencoded", "Referer" => "https://results.ittf.link/index.php/login", "Origin" => "https://results.ittf.link"],
    allow_login_retry=false,
)
idx = findfirst("match", lowercase(html2))
println("find match@ ", idx)
idx2 = findfirst("password", lowercase(html2))
# show context around username/password mismatch
for pat in ["do not match", "invalid", "warning", "Username and password"]
    i = findfirst(lowercase(pat), lowercase(html2))
    if i !== nothing
        a = max(1, first(i) - 80)
        b = min(lastindex(html2), last(i) + 120)
        println("CTX[$pat]: ", replace(html2[a:b], r"\s+" => " "))
    end
end
println("Logout link=", occursin("task=user.logout", html2))
