import json
from pathlib import Path

path = Path(r"d:\Workspace\Table-Tennis-Rankings\ccelo.ipynb")
nb = json.loads(path.read_text(encoding="utf-8"))

nb["cells"][10]["source"] = [
    "### 2.1 Credentials, session, and crawl resume\n",
    "**Warning:** Put your ITTF account in gitignored `ittf_credentials.json` (see `ittf_credentials.example.json`).\n",
    "\n",
    "**Note (2026-08):**\n",
    "- Match `format=json` is blocked (403); HTML + embedded Fabrik data is used.\n",
    "- Sustained crawling hits **429**; use `run_crawl!` with checkpoint `crawl_state.json`.\n",
    "- After a partial run, `bootstrap_crawl_state_from_disk!` resumes at event **3366** / offset **900** (option A).\n",
    "- On 429: saves checkpoint, sleeps using server countdown (or `wait_seconds`), re-logins, continues; or `exit_on_429=true` to stop after saving.\n",
]

nb["cells"][11]["source"] = [
    "using HTTP\n",
    "\n",
    "include(\"ittf_fabrik.jl\")\n",
    "using .ITTFFabrik\n",
    "\n",
    "# Optional: seed cookies manually; login!() will refresh from ittf_credentials.json\n",
    "const COOKIES = Dict{String,String}()\n",
    "\n",
    "# First-time resume after the 2026-08-11 429 interruption (keeps matches_8922-8930)\n",
    "bootstrap_crawl_state_from_disk!(; force=false)\n",
    "\n",
    "println(\"ITTFFabrik loaded. Create ittf_credentials.json then run the crawl cell.\")",
]

# Insert guidance before match download: replace match download cell to call run_crawl for matches+players
nb["cells"][22]["source"] = [
    "#### 2.3.3 Download matches (and later players) with 429-aware resume\n",
    "\n",
    "Prefer `run_crawl!` below instead of one-shot loops. It continues from `crawl_state.json`.\n",
    "\n",
    "- Default: sleep using the site's 429 countdown, re-login, continue.\n",
    "- `exit_on_429=true`: only save checkpoint and return (re-run later).\n",
]

nb["cells"][23]["source"] = [
    "# 429-aware multi-round crawl (matches → players). Requires ittf_credentials.json\n",
    "# After phase == \"done\", run merge / convert cells as usual (re-load new files if needed).\n",
    "\n",
    "crawl_state = run_crawl!(;\n",
    "    exit_on_429 = false,   # set true to stop after checkpoint instead of sleeping\n",
    "    wait_seconds = 3600,   # fallback if 429 page has no countdown\n",
    "    request_pause = 0.75,\n",
    "    bootstrap = true,\n",
    ")\n",
    "\n",
    "println(\"crawl phase=$(crawl_state[\\\"phase\\\"])\")\n",
    "println(\"If phase is not done, re-run this cell later (after wait / with fresh login).\")\n",
]

# Soften players cell: skip if crawl already handled players
nb["cells"][28]["source"] = [
    "#### 2.4.3 Download players\n",
    "\n",
    "If you used `run_crawl!`, players are already downloaded when `phase=done`.  \n",
    "This cell remains for manual / legacy one-shot downloads of `new_player_ids` only.\n",
]

nb["cells"][29]["source"] = [
    "function download_players_from_ittf(player_ids::Set{Int})\n",
    "    isdir(\"players\") || mkdir(\"players\")\n",
    "    players = Vector{Player}()\n",
    "    success_count = 0\n",
    "    failure_count = 0\n",
    "\n",
    "    for player_id in player_ids\n",
    "        while true\n",
    "            try\n",
    "                player_json = download_player_json(player_id, get_session_cookies())\n",
    "                player = parse_player_data(player_json)\n",
    "                if player === nothing\n",
    "                    println(\"Invalid player $(player_id)\")\n",
    "                    break\n",
    "                end\n",
    "                push!(players, player)\n",
    "                open(\"players/$(player_id).json\", \"w\") do io\n",
    "                    write(io, player_json)\n",
    "                end\n",
    "                success_count += 1\n",
    "                println(\"Downloaded player: $(player.name)\")\n",
    "                break\n",
    "            catch e\n",
    "                if e isa RateLimited\n",
    "                    println(\"429 while fetching players: $(e). Save state / wait / re-run run_crawl!.\")\n",
    "                    rethrow(e)\n",
    "                end\n",
    "                failure_count += 1\n",
    "                println(\"Error when fetching player #$(player_id): $e\")\n",
    "                sleep(10)\n",
    "            end\n",
    "        end\n",
    "        sleep(0.2)\n",
    "    end\n",
    "\n",
    "    println(\"Failed to fetch $(failure_count) players\")\n",
    "    return players\n",
    "end\n",
    "\n",
    "# Skip if run_crawl! already finished players\n",
    "st = load_crawl_state()\n",
    "if st !== nothing && string(get(st, \"phase\", \"\")) == \"done\"\n",
    "    println(\"crawl_state phase=done → skip legacy player download loop\")\n",
    "    new_players = Player[]\n",
    "else\n",
    "    new_players = download_players_from_ittf(new_player_ids)\n",
    "    println(\"Downloaded $(length(new_players)) players\")\n",
    "end",
]

for i in (11, 23, 29):
    nb["cells"][i]["outputs"] = []
    nb["cells"][i]["execution_count"] = None

path.write_text(json.dumps(nb, ensure_ascii=False, indent=1), encoding="utf-8")
print("notebook patched")
