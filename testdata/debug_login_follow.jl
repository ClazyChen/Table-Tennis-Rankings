using JSON
using HTTP

function main()
    cd(joinpath(@__DIR__, ".."))
    creds = JSON.parsefile("ittf_credentials.json")
    user = string(creds["username"])
    pass = string(creds["password"])
    jar = Dict{String,String}()

    function merge_cookies!(resp)
        for (k, v) in resp.headers
            if lowercase(String(k)) == "set-cookie"
                m = match(r"^([^=]+)=([^;]*)", String(v))
                m === nothing || (jar[m.captures[1]] = m.captures[2])
            end
        end
    end
    cookie_hdr() = join(["$k=$v" for (k, v) in jar], "; ")
    function gethdr(resp, name)
        for (k, v) in resp.headers
            lowercase(String(k)) == lowercase(name) && return String(v)
        end
        nothing
    end

    ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    function req(method, url; body=nothing)
        headers = ["User-Agent" => ua, "Cookie" => cookie_hdr()]
        resp = if method == "GET"
            HTTP.get(url; headers=headers, status_exception=false, redirect=false)
        else
            push!(headers, "Content-Type" => "application/x-www-form-urlencoded")
            push!(headers, "Referer" => "https://results.ittf.link/index.php/login")
            push!(headers, "Origin" => "https://results.ittf.link")
            HTTP.post(url, headers, body; status_exception=false, redirect=false)
        end
        merge_cookies!(resp)
        return resp
    end

    r1 = req("GET", "https://results.ittf.link/index.php/login")
    html = String(r1.body)
    m = match(r"""<form\b[^>]*\baction=["']([^"']+)["'][^>]*\bid=["']com-users-login__form["'][^>]*>(.*?)</form>"""is, html)
    action, form = m.captures[1], m.captures[2]
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
            name == "remember" && (fields[name] = "yes")
        else
            fields[name] = val
        end
    end
    fields["username"] = user
    fields["password"] = pass
    body = join(["$(HTTP.escapeuri(k))=$(HTTP.escapeuri(v))" for (k, v) in fields], "&")
    r2 = req("POST", "https://results.ittf.link" * action; body=body)
    println("POST ", r2.status, " loc=", gethdr(r2, "Location"), " jar=", jar)

    url = gethdr(r2, "Location")
    page = String(r2.body)
    hops = 0
    while url !== nothing && hops < 5
        hops += 1
        abs = startswith(url, "http") ? url : "https://results.ittf.link" * (startswith(url, "/") ? url : "/" * url)
        println("FOLLOW ", abs)
        r = req("GET", abs)
        page = String(r.body)
        println("  status=", r.status, " logout=", occursin("user.logout", page), " Login=", occursin(">Login<", page), " len=", sizeof(page))
        url = r.status in (301, 302, 303, 307, 308) ? gethdr(r, "Location") : nothing
    end

    println("cookie header=", cookie_hdr())
    for u in [
        "https://results.ittf.link/index.php?option=com_users&view=profile",
        "https://results.ittf.link/index.php/players-profiles",
        "https://results.ittf.link/index.php?option=com_fabrik&view=list&listid=27&Itemid=268&format=json&limit27=1&limitstart27=0",
        "https://results.ittf.link/index.php/event-matches/list/31?resetfilters=1&vw_matches___tournament_id_raw%5Bvalue%5D%5B%5D=3480&limit31=5",
    ]
        r = req("GET", u)
        b = String(r.body)
        println("GET ", r.status, " len=", sizeof(b), " wall_reg=", occursin("Click", b) && occursin("register", lowercase(b)))
        println("  ", u)
        println("  snip=", replace(first(b, min(160, sizeof(b))), r"\s+" => " "))
        if occursin("fabrik_row", b)
            println("  has fabrik_row")
        end
        if occursin("\"data\":[[", b)
            println("  has embedded data")
        end
    end
end

main()
