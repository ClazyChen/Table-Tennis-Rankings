import json
from pathlib import Path

path = Path(r"d:\Workspace\Table-Tennis-Rankings\ccelo.ipynb")
nb = json.loads(path.read_text(encoding="utf-8"))
nb["cells"][23]["source"] = [
    "# 429-aware multi-round crawl (matches -> players). Requires ittf_credentials.json\n",
    "# After phase == \"done\", run merge / convert cells as usual (re-load new files if needed).\n",
    "\n",
    "crawl_state = run_crawl!(\n",
    "    exit_on_429 = false,   # set true to stop after checkpoint instead of sleeping\n",
    "    wait_seconds = 3600,   # fallback if 429 page has no countdown\n",
    "    request_pause = 0.75,\n",
    "    bootstrap = true,\n",
    ")\n",
    "\n",
    "phase = string(get(crawl_state, \"phase\", \"?\"))\n",
    "println(\"crawl phase=$phase\")\n",
    "println(\"If phase is not done, re-run this cell later (after wait / with fresh login).\")\n",
]
nb["cells"][23]["outputs"] = []
nb["cells"][23]["execution_count"] = None
path.write_text(json.dumps(nb, ensure_ascii=False, indent=1), encoding="utf-8")
print("fixed cell 23")
print("".join(nb["cells"][23]["source"]))
