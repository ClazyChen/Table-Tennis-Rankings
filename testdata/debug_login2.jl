include(joinpath(@__DIR__, "..", "src", "ittf_fabrik.jl"))
using .ITTFFabrik
using HTTP

cd(joinpath(@__DIR__, ".."))
empty!(ITTFFabrik.SESSION.cookies)

creds = ITTFFabrik.load_credentials()
login_url = "https://results.ittf.link/index.php/login"
resp, html = ITTFFabrik.ittf_request("GET", login_url; allow_login_retry=false)
action, fields = ITTFFabrik._extract_main_login_form(html)
fields["username"] = creds.username
fields["password"] = creds.password
fields["remember"] = "yes"
fields["option"] = "com_users"
fields["task"] = "user.login"
post_url = ITTFFabrik._absolute_ittf_url(action)
body = join(["$(HTTP.escapeuri(k))=$(HTTP.escapeuri(v))" for (k, v) in fields], "&")
resp2, html2 = ITTFFabrik.ittf_request(
    "POST", post_url;
    body=body,
    headers=["Content-Type" => "application/x-www-form-urlencoded", "Referer" => login_url, "Origin" => "https://results.ittf.link"],
    allow_login_retry=false,
)
println("POST status=$(resp2.status) len=$(sizeof(html2)) wall=$(ITTFFabrik.looks_like_login_wall(html2))")
println("cookies=", ITTFFabrik.get_session_cookies())

# several probes
probes = [
    "https://results.ittf.link/index.php?option=com_fabrik&view=list&listid=27&Itemid=268&format=json&limit27=1&limitstart27=0",
    "https://results.ittf.link/index.php/events",
    "https://results.ittf.link/index.php/event-matches/list/31?resetfilters=1&vw_matches___tournament_id_raw[value][]=3480&limit31=5",
    "https://www.results.ittf.link/index.php?option=com_fabrik&view=list&listid=27&Itemid=268&format=json&limit27=1&limitstart27=0",
]
for u in probes
    r, b = ITTFFabrik.ittf_request("GET", u; allow_login_retry=false)
    snip = replace(first(b, min(100, sizeof(b))), r"\s+" => " ")
    println("PROBE $(r.status) wall=$(ITTFFabrik.looks_like_login_wall(b)) json=$(startswith(strip(b), '[')) | $u")
    println("  ", snip)
end
