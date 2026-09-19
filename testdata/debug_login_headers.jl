using JSON
using HTTP

function main()
    cd(joinpath(@__DIR__, ".."))
    creds = JSON.parsefile("ittf_credentials.json")
    jar = Dict{String,String}("jbcookies" => "yes")
    ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    function merge!(resp)
        println("--- headers status=$(resp.status) ---")
        for (k, v) in resp.headers
            ks = String(k)
            if lowercase(ks) in ("set-cookie", "location", "content-type")
                println(ks, ": ", String(v)[1:min(end, 120)])
            end
            if lowercase(ks) == "set-cookie"
                m = match(r"^([^=]+)=([^;]*)", String(v))
                m === nothing || (jar[m.captures[1]] = m.captures[2])
            end
        end
    end
    ch() = join(["$k=$v" for (k, v) in jar], "; ")

    r1 = HTTP.get("https://results.ittf.link/index.php/login"; headers=["User-Agent"=>ua, "Cookie"=>ch()], status_exception=false, redirect=false)
    merge!(r1)
    html = String(r1.body)
    println("login page len=", sizeof(html), " has form=", occursin("com-users-login__form", html), " is429=", occursin("429", html))
    occursin("com-users-login__form", html) || return
    m = match(r"""<form\b[^>]*\baction=["']([^"']+)["'][^>]*\bid=["']com-users-login__form["'][^>]*>(.*?)</form>"""is, html)
    fields = Dict{String,String}()
    for inp in eachmatch(r"<input([^>]*)>", m.captures[2])
        attrs = inp.captures[1]
        nm = match(r"""name=["']([^"']+)["']"""i, attrs); nm === nothing && continue
        name = nm.captures[1]
        valm = match(r"""value=["']([^"']*)["']"""i, attrs)
        val = valm === nothing ? "" : valm.captures[1]
        ty = match(r"""type=["']([^"']+)["']"""i, attrs)
        t = ty === nothing ? "text" : lowercase(ty.captures[1])
        t in ("submit", "button") && continue
        if t == "checkbox"
            name == "remember" && (fields[name] = "yes")
        else
            fields[name] = val
        end
    end
    fields["username"] = string(creds["username"])
    fields["password"] = string(creds["password"])
    body = join(["$(HTTP.escapeuri(k))=$(HTTP.escapeuri(v))" for (k, v) in fields], "&")
    println("post body length=", length(body), " field keys=", sort(collect(keys(fields))))
    r2 = HTTP.post("https://results.ittf.link" * m.captures[1],
        ["User-Agent"=>ua, "Cookie"=>ch(), "Content-Type"=>"application/x-www-form-urlencoded",
         "Referer"=>"https://results.ittf.link/index.php/login", "Origin"=>"https://results.ittf.link"],
        body; status_exception=false, redirect=false)
    merge!(r2)
    println("jar=", jar)
end
main()
