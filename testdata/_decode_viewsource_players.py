from pathlib import Path
import html as H
import re
import json

ref = Path(r"d:/Workspace/Table-Tennis-Rankings/docs/reference")
out_dir = Path(r"d:/Workspace/Table-Tennis-Rankings/testdata")
ids = [221811, 224464, 225728]

for pid in ids:
    files = list(ref.glob(f"*player_id_raw={pid}*.html"))
    if not files:
        raise SystemExit(f"missing html for {pid}")
    raw = files[0].read_text(encoding="utf-8", errors="replace")
    parts = re.findall(r'class="line-content">(.*?)</td>', raw, flags=re.S)
    if not parts:
        raise SystemExit(f"no line-content in {files[0].name}")
    joined = "".join(parts)
    joined = re.sub(r"<[^>]+>", "", joined)
    decoded = H.unescape(joined)
    out = out_dir / f"player_{pid}_decoded.html"
    out.write_text(decoded, encoding="utf-8")
    print(pid, "parts", len(parts), "decoded_bytes", len(decoded),
          "data", '"data":[[' in decoded, "profiles", "vw_profiles___" in decoded,
          "->", out.name)
