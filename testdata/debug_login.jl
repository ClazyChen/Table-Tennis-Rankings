include(joinpath(@__DIR__, "..", "src", "ittf_fabrik.jl"))
using .ITTFFabrik
using JSON

cd(joinpath(@__DIR__, ".."))
empty!(ITTFFabrik.SESSION.cookies)

creds = ITTFFabrik.load_credentials()
println("username_len=", length(creds.username), " password_len=", length(creds.password))

login_url = "https://results.ittf.link/index.php/login"
resp, html = ITTFFabrik.ittf_request("GET", login_url; allow_login_retry=false)
println("GET login status=", resp.status, " cookies=", ITTFFabrik.get_session_cookies())
action, fields = ITTFFabrik._extract_main_login_form(html)
fields["username"] = creds.username
fields["password"] = creds.password
get!(fields, "remember", "yes")
# also send explicit com_users fields (mod form has these)
fields["option"] = "com_users"
fields["task"] = "user.login"
println("action=", action)
println("keys=", join(sort!(collect(keys(fields))), ", "))
println("return=", get(fields, "return", ""))

using HTTP
post_url = ITTFFabrik._absolute_ittf_url(action)
body = join(["$(HTTP.escapeuri(k))=$(HTTP.escapeuri(v))" for (k, v) in fields], "&")
resp2, html2 = ITTFFabrik.ittf_request(
    "POST", post_url;
    body=body,
    headers=[
        "Content-Type" => "application/x-www-form-urlencoded",
        "Referer" => login_url,
        "Origin" => "https://results.ittf.link",
    ],
    allow_login_retry=false,
)
println("POST status=", resp2.status, " body_len=", sizeof(html2))
println("cookies after POST=", ITTFFabrik.get_session_cookies())
println("still login wall=", ITTFFabrik.looks_like_login_wall(html2))
println("title=", something(match(r"<title>(.*?)</title>"is, html2), (captures=["?"])).captures[1])
# alert messages
for m in eachmatch(r"""class=["'][^"']*alert[^"']*["'][^>]*>(.*?)</div>"""is, html2)
    s = replace(m.captures[1], r"<[^>]+>" => " ")
    s = replace(s, r"\s+" => " ")
    println("ALERT: ", strip(s)[1:min(end, 160)])
end

probe_url = "https://results.ittf.link/index.php?option=com_fabrik&view=list&listid=27&Itemid=268&format=json&limit27=1&limitstart27=0"
resp3, body3 = ITTFFabrik.ittf_request("GET", probe_url; allow_login_retry=false)
println("probe status=", resp3.status, " start=", repr(first(body3, min(120, sizeof(body3)))))
println("probe loginwall=", ITTFFabrik.looks_like_login_wall(body3))
