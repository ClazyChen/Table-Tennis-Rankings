include(joinpath(@__DIR__, "..", "src", "ittf_fabrik.jl"))
using .ITTFFabrik
using HTTP

cd(joinpath(@__DIR__, ".."))
empty!(ITTFFabrik.SESSION.cookies)
creds = ITTFFabrik.load_credentials()
println("username=", repr(creds.username))  # ok to print username for debug

login_url = "https://results.ittf.link/index.php/login"
_, html = ITTFFabrik.ittf_request("GET", login_url; allow_login_retry=false)
println("session before=", ITTFFabrik.get_session_cookies())
action, fields = ITTFFabrik._extract_main_login_form(html)
fields["username"] = creds.username
fields["password"] = creds.password
fields["remember"] = "yes"
# try WITHOUT extra option/task first (as main form)
# fields["option"] = "com_users"
# fields["task"] = "user.login"
post_url = ITTFFabrik._absolute_ittf_url(action)
body = join(["$(HTTP.escapeuri(k))=$(HTTP.escapeuri(v))" for (k, v) in fields], "&")
_, html2 = ITTFFabrik.ittf_request(
    "POST", post_url;
    body=body,
    headers=["Content-Type" => "application/x-www-form-urlencoded", "Referer" => login_url, "Origin" => "https://results.ittf.link"],
    allow_login_retry=false,
)
println("session after=", ITTFFabrik.get_session_cookies())
println("has Logout=", occursin("Logout", html2) || occursin("log out", lowercase(html2)))
println("has Log in menu=", occursin(">Login<", html2) || occursin(">Log in<", html2))
println("invalid pwd=", occursin("do not match", lowercase(html2)) || occursin("invalid", lowercase(html2)))
# extract system messages
for m in eachmatch(r"""id=["']system-message["'][^>]*>(.*?)</div>\s*</div>"""is, html2)
    s = replace(m.captures[1], r"<[^>]+>" => " ")
    println("MSG: ", replace(strip(s), r"\s+" => " ")[1:min(end, 200)])
end
for m in eachmatch(r"""class=["'][^"']*alert-[^"']*["'][^>]*>(.*?)</div>"""is, html2)
    s = replace(m.captures[1], r"<[^>]+>" => " ")
    s = replace(strip(s), r"\s+" => " ")
    isempty(s) || println("ALERT: ", s[1:min(end, 200)])
end
# check event-matches for embedded data
_, mh = ITTFFabrik.ittf_request("GET", "https://results.ittf.link/index.php/event-matches/list/31?resetfilters=1&vw_matches___tournament_id_raw%5Bvalue%5D%5B%5D=3480&limit31=5"; allow_login_retry=false)
println("matches has data=", occursin("\"data\":[[", mh), " fabrik_row=", occursin("fabrik_row", mh), " len=", sizeof(mh))
