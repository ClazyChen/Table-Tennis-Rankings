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
# pull warning/error texts
open(joinpath(@__DIR__, "login_post_snip.txt"), "w") do io
    # write only message areas
    for m in eachmatch(r"""<div[^>]*class=["'][^"']*(?:alert|error|warning|message)[^"']*["'][^>]*>(.*?)</div>"""is, html2)
        s = replace(m.captures[1], r"<[^>]+>" => " ")
        s = replace(strip(s), r"\s+" => " ")
        isempty(s) && continue
        println(io, s[1:min(end, 300)])
        println("MSG:", s[1:min(end, 300)])
    end
end
