using JSON, HTTP
function main()
  cd(joinpath(@__DIR__, ".."))
  creds = JSON.parsefile("ittf_credentials.json")
  jar = Dict("jbcookies" => "yes")
  merge!(jar, Dict{String,String}())
  function merge_cookies!(resp)
    for (k,v) in resp.headers
      if lowercase(String(k))=="set-cookie"
        m = match(r"^([^=]+)=([^;]*)", String(v)); m===nothing || (jar[m.captures[1]]=m.captures[2])
      end
    end
  end
  ch() = join(["$k=$v" for (k,v) in jar], "; ")
  ua="Mozilla/5.0"
  function gethdr(resp,n)
    for (k,v) in resp.headers; lowercase(String(k))==lowercase(n) && return String(v); end; nothing
  end
  r1=HTTP.get("https://results.ittf.link/index.php/login"; headers=["User-Agent"=>ua,"Cookie"=>ch()], status_exception=false, redirect=false)
  merge_cookies!(r1)
  html=String(r1.body)
  m=match(r"""<form\b[^>]*\baction=["']([^"']+)["'][^>]*\bid=["']com-users-login__form["'][^>]*>(.*?)</form>"""is, html)
  fields=Dict{String,String}()
  for inp in eachmatch(r"<input([^>]*)>", m.captures[2])
    attrs=inp.captures[1]
    nm=match(r"""name=["']([^"']+)["']"""i, attrs); nm===nothing && continue
    name=nm.captures[1]
    valm=match(r"""value=["']([^"']*)["']"""i, attrs)
    val=valm===nothing ? "" : valm.captures[1]
    ty=match(r"""type=["']([^"']+)["']"""i, attrs)
    t=ty===nothing ? "text" : lowercase(ty.captures[1])
    t in ("submit","button") && continue
    if t=="checkbox"; name=="remember" && (fields[name]="yes"); else; fields[name]=val; end
  end
  fields["username"]=string(creds["username"]); fields["password"]=string(creds["password"])
  body=join(["$(HTTP.escapeuri(k))=$(HTTP.escapeuri(v))" for (k,v) in fields], "&")
  r2=HTTP.post("https://results.ittf.link"*m.captures[1], ["User-Agent"=>ua,"Cookie"=>ch(),"Content-Type"=>"application/x-www-form-urlencoded","Referer"=>"https://results.ittf.link/index.php/login","Origin"=>"https://results.ittf.link"], body; status_exception=false, redirect=false)
  merge_cookies!(r2)
  println("POST ", r2.status, " loc=", gethdr(r2,"Location"), " jar=", jar)
  r3=HTTP.get(gethdr(r2,"Location"); headers=["User-Agent"=>ua,"Cookie"=>ch()], status_exception=false, redirect=false)
  merge_cookies!(r3)
  page=String(r3.body)
  println("home logout=", occursin("user.logout", page), " Login=", occursin(">Login<", page), " len=", sizeof(page))
  r4=HTTP.get("https://results.ittf.link/index.php?option=com_fabrik&view=list&listid=27&Itemid=268&format=json&limit27=1&limitstart27=0"; headers=["User-Agent"=>ua,"Cookie"=>ch()], status_exception=false, redirect=false)
  b=String(r4.body)
  println("json ", r4.status, " ", replace(first(b, min(100,sizeof(b))), r"\s+"=>" "))
end
main()
