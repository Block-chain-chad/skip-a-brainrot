"""Stage the module sources the data-safety harness loads, next to the bridge so Studio can GET them.

    python tools/studio-bridge/data-safety/stage.py            # stage both variants
    python tools/studio-bridge/data-safety/stage.py --live-ref a2eaf34

live = the byte-exact pre-hotfix mirror (git ref, default a2eaf34 = the live sync the hotfix was built on)
new  = the working tree
Output: tools/studio-bridge/data-safety/stage/{live,new}/{SessionLock,PlayerDataManager}.lua
"""
import os, subprocess, sys

HERE = os.path.abspath(os.path.dirname(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
FILES = ["Modules/SessionLock.lua", "Modules/PlayerDataManager.lua"]
BASE = "game-src/place-full/ServerScriptService/"

live_ref = "a2eaf34"
if "--live-ref" in sys.argv:
    live_ref = sys.argv[sys.argv.index("--live-ref") + 1]

for variant in ("live", "new"):
    out_dir = os.path.join(HERE, "stage", variant)
    os.makedirs(out_dir, exist_ok=True)
    for f in FILES:
        if variant == "live":
            data = subprocess.check_output(["git", "-C", REPO, "show", f"{live_ref}:{BASE}{f}"])
        else:
            with open(os.path.join(REPO, BASE, f), "rb") as fh:
                data = fh.read()
        target = os.path.join(out_dir, os.path.basename(f))
        with open(target, "wb") as fh:
            fh.write(data)
        print(f"{variant:4} {os.path.basename(f):22} {len(data):6} bytes")
