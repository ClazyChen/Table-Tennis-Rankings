using JSON
using HTTP

cd(joinpath(@__DIR__, ".."))
creds = JSON.parsefile("ittf_credentials.json")
user = string(creds["username"])
pass = string(creds["password"])

cookiejar = Dict{String,String}()

function merge_cookies!(jar, resp)
    for (k, v) in resp.headers
        if lowercase(String(k)) == "set-cookie"
            m = match(r"^([^=]+)=([^;]*)", String(v))
            m === nothing || (jar[m.captures[1]] = m.captures[2])
        end
    end
end

cookie_hdr(jar) = join(["$k=$v" for (k, v) in jar], "; ")

function header(resp, name)
    lname = lowercase(name)
    for (k, v) in resp.headers
        lowercase(String(k)) == lname && return String(v)
    end
    return nothing
end

ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
r1 = HTTP.get("https://results.ittf.link/index.php/login";
    headers=["User-Agent" => ua], status_exception=false, redirect=false)
merge_cookies!(cookiejar, r1)
html = String(r1.body)
println("GET ", r1.status, " jar=", cookiejar)

m = match(r"""<form\b[^>]*\baction=["']([^"']+)["'][^>]*\bid=["']com-users-login__form["'][^>]*>(.*?)</form>"""is, html)
@assert m !== nothing
action = m.captures[1]
form = m.captures[2]
fields = Dict{String,String}()
for inp in eachmatch(r"<input([^>]*)>", form)
    attrs = inp.captures[1]
    nm = match(r"""name=["']([^"']+)["']"""i, attrs)
    nm === nothing && continue
    name = nm.captures[1]
    val_m = match(r"""value=["']([^"']*)["']"""i, attrs)
    val = val_m === nothing ? "" : val_m.captures[1]
    ty = match(r"""type=["']([^"']+)["']"""i, attrs)
    t = ty === nothing ? "text" : lowercase(ty.captures[1])
    t in ("submit", "button") && continue
    if t == "checkbox"
        name == "remember" && (fields[name] = isempty(val) ? "yes" : val)
    else
        fields[name] = val
    end
end
fields["username"] = user
fields["password"] = pass
println("action=", action, " fields=", sort!(collect(keys(fields))))

body = join(["$(HTTP.escapeuri(k))=$(HTTP.escapeuri(v))" for (k, v) in fields], "&")
post_url = startswith(action, "http") ? action : "https://results.ittf.link" * action
r2 = HTTP.post(post_url, [
    "User-Agent" => ua,
    "Content-Type" => "application/x-www-form-urlencoded",
    "Cookie" => cookie_hdr(cookiejar),
    "Referer" => "https://results.ittf.link/index.php/login",
    "Origin" => "https://results.ittf.link",
], body; status_exception=false, redirect=false)
merge_cookies!(cookiejar, r2)
println("POST ", r2.status, " Location=", header(r2, "Location"))
println("jar after=", cookiejar)
html2 = String(r2.body)
println("body len=", sizeof(html2), " logout=", occursin("user.logout", html2), " login form=", occursin("com-users-login__form", html2))

# follow redirects manually
url = header(r2, "Location")
status = r2.status
hops = 0
while url !== nothing && status in (301, 302, 303, 307, 308) && hops < 5
    hops += 1
    abs = startswith(url, "http") ? url : "https://results.ittf.link" * url
    println("FOLLOW $status -> $abs")
    r = HTTP.get(abs; headers=["User-Agent" => ua, "Cookie" => cookie_hdr(cookiejar)], status_exception=false, redirect=false)
    merge_cookies!(cookiejar, r)
    status = r.status
    url = header(r, "Location")
    html2 = String(r.body)
    println("  got ", status, " len=", sizeof(html2), " jar=", cookiejar)
end

println("final logout=", occursin("user.logout", html2))
r3 = HTTP.get("https://results.ittf.link/index.php?option=com_fabrik&view=list&listid=27&Itemid=268&format=json&limit27=1&limitstart27=0";
    headers=["User-Agent" => ua, "Cookie" => cookie_hdr(cookiejar)], status_exception=false, redirect=false)
println("json probe ", r3.status, " ", replace(first(String(r3.body), 120), r"\s+" => " "))
