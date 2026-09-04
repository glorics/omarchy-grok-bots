#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
bash "$root/bin/run-capped" python3 "$root/status.py" | python3 -c '
import json, sys
data = json.load(sys.stdin)
for key in ("ok", "installed", "source", "statusText", "productUrl", "signedIn", "computerLabel"):
    assert key in data, key
assert data.get("source") in ("official", "package", "path", "none"), data.get("source")
print("status.py ok · installed=%s source=%s status=%s version=%s" % (
    data.get("installed"), data.get("source"), data.get("statusText"), data.get("appVersion")))
'
got=$(python3 -c 'print("A"*300000)' | wc -c)
capped=$(set +o pipefail; GLORICS_MAX_BYTES=65536 bash "$root/bin/run-capped" python3 -c 'print("A"*300000)' 2>/dev/null | wc -c)
test "$capped" -le 65536
test "$got" -gt 65536
echo "run-capped ok · $capped bytes (limit 65536)"

start=$(date +%s)
set +o pipefail
GLORICS_MAX_SECONDS=1 bash "$root/bin/run-capped" python3 -c 'import time; time.sleep(20)' >/dev/null 2>&1 || true
set -o pipefail
elapsed=$(( $(date +%s) - start ))
test "$elapsed" -lt 5
echo "run-capped deadline ok · ${elapsed}s"

if grep -n 'capture_output=True' "$root/status.py"; then
  echo "status.py still uses capture_output=True" >&2
  exit 1
fi
if grep -nE 'LINUX_BY_VERSION|partial\.chmod|APPS\.mkdir' "$root/status.py"; then
  echo "status.py still has the old installer" >&2
  exit 1
fi
python3 - "$root" <<'PY'
import os, stat, sys, tempfile, time
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import status as grok

proc = grok.run(["python3", "-c", "print('A'*200000)"], timeout=5, max_bytes=4096)
assert len(proc.stdout.encode()) <= 4096, len(proc.stdout)
assert proc.returncode != 0
print("producer cap ok · %d bytes rc=%s" % (len(proc.stdout), proc.returncode))

survived = Path(tempfile.mkdtemp()) / "survived"
script = "import subprocess, sys, time\nsubprocess.Popen(['sleep', '20'])\ntime.sleep(20)\nopen(sys.argv[1],'w').write('alive')\n"
start = time.monotonic()
proc = grok.run(["python3", "-c", script, str(survived)], timeout=1)
assert time.monotonic() - start < 3
assert not survived.exists()
print("process group reap ok · rc=%s" % proc.returncode)

base = Path(tempfile.mkdtemp())
secret = base / "secret"
secret.mkdir()
marker = secret / "owned"
marker.write_text("keep")
os.chmod(secret, 0o755)
planted = base / "state"
planted.symlink_to(secret)
assert grok.ensure_private_dir(planted) is False
assert planted.is_symlink()
assert marker.read_text() == "keep"
assert stat.S_IMODE(secret.stat().st_mode) == 0o755
print("state dir ok · planted symlink refused")

pin = grok.PINNED_APPIMAGES["0.30.0"]
assert pin["sha256"] == "1adf717784138d8945b248001805a9ae45a77c44aeed2004d81df3a3b2f40bc2"
assert pin["bytes"] == 131344546
assert grok.pinned_artifact("0.99.0") == {}
print("pinned digest ok · 0.30.0")
PY

python3 - "$root" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
manifest = json.loads((root / "manifest.json").read_text())
assert manifest["id"] == "glorics.grok-bots", manifest["id"]
assert manifest["name"] == "Grok Bots"
roster = json.loads((root / "demo-roster.json").read_text())
assert roster["ok"] is True
assert roster["client"] == "glorics.grok-bots"
assert roster["demo"] is True
bots = roster["bots"]
assert len(bots) == 14, len(bots)
waiting = sum(1 for b in bots if b.get("waiting"))
unread_bots = sum(1 for b in bots if int(b.get("unread") or 0) > 0)
assert waiting == 1, waiting
assert unread_bots == 4, unread_bots
ids = [b["id"] for b in bots]
assert len(set(ids)) == 14
print("demo roster ok · 14 bots · 1 waiting · 4 unread")
PY
python3 "$root/inbox.py" | python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data.get("ok") is True
assert data.get("client") == "glorics.grok-bots"
assert data.get("demo") is False
bots = data.get("bots") or []
assert len(bots) <= 24
for bot in bots:
    assert bot.get("id")
    assert bot.get("name")
    assert str(bot.get("color","")).startswith("#")
print("inbox.py ok · bots=%d source=%s" % (len(bots), "yes" if data.get("sourcePath") else "none"))
'
python3 "$root/tests/unread.py"
if ! grep -q 'CountBubble' "$root/Panel.qml"; then
  echo "Panel.qml must use CountBubble on the bar" >&2
  exit 1
fi


if command -v omarchy >/dev/null; then
  omarchy plugin validate "$root"
  echo "omarchy plugin validate ok"
fi
