"""Static lint for game-src/npc-kit (no Studio):
  1. every .lua compiles under Lua 5.1 (Luau accepts the same text unchanged)
  2. no Luau-only syntax (keeps the harness honest)
  3. forbidden APIs per file (runtime never scans/creates/animates on the server, etc.)
  4. header comment present
  5. data cross-references (recipes <-> library/families/themes/packs) via the harness

    cd tools && python -m npc_kit.lint
"""
from __future__ import annotations

import re
import sys

from npc_kit.harness import KIT, Harness, all_lua_files

LUAU_ONLY = [r"\+=", r"-=", r"\*=", r"/=", r"\.\.=", r"\bcontinue\b", r"::", r"--!strict", "`"]
FORBIDDEN = {
    "NpcLife.lua": [
        (r"math\.random", "driver must be deterministic (hashes only)"),
        (r"Instance\.new", "runtime driver never creates instances"),
        (r"\.Transform\s*=", "Transform belongs to the Animator; the driver writes C0"),
        (r"workspace:GetDescendants|Workspace:GetDescendants", "never scan the workspace"),
        (r"FireServer|InvokeServer", "the driver never talks to the server"),
    ],
    "NpcLifeClient.client.lua": [
        (r"GetDescendants", "no scans in the client wiring"),
        (r"math\.random", "deterministic only"),
    ],
    "NpcForge.lua": [
        (r"\.MeshId\s*=", "MeshId is not scriptable; meshes come from Import 3D"),
        (r"\.Transform\s*=", "no Transform writes"),
    ],
    "*": [
        (r"DataStoreService|TeleportService|MarketplaceService", "the kit never touches these"),
        (r"MerchantDialog\s*=\s*require|require\([^)]*MerchantDialog", "locked UI module must not be required by the kit"),
    ],
}
# Drop-in replacements for LIVE scripts that already require the locked UI module: they are
# the glue between the live prompt/remotes and MerchantDialog, not kit runtime. Everything
# else in the kit (driver, forge, data) stays barred from it.
LIVE_DROP_INS = {"GianlucaClient.client.lua": {"locked UI module must not be required by the kit"}}


def strip(line: str) -> str:
    code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
    code = re.sub(r"'(?:[^'\\]|\\.)*'", "''", code)
    return re.sub(r"--.*$", "", code)


def main() -> int:
    H = Harness()
    problems: list[str] = []
    files = all_lua_files()
    compile_fn = H.lua.eval("function(src, name) local f, e = loadstring(src, '=' .. name) return f ~= nil, e end")
    for f in files:
        src = f.read_text(encoding="utf-8")
        rel = f.relative_to(KIT).as_posix()
        ok, err = compile_fn(src, f.name)
        if not ok:
            problems.append(f"{rel}: does not compile: {err}")
        if not src.lstrip().startswith("--"):
            problems.append(f"{rel}: missing header comment")
        lines = re.sub(r"--\[(=*)\[.*?\]\]", "", src, flags=re.S).splitlines()
        for n, line in enumerate(lines, 1):
            code = strip(line)
            for pat in LUAU_ONLY:
                if re.search(pat, code):
                    problems.append(f"{rel}:{n}: Luau-only syntax {pat!r}")
            for pat, why in FORBIDDEN.get(f.name, []) + FORBIDDEN["*"]:
                if re.search(pat, code) and why not in LIVE_DROP_INS.get(f.name, set()):
                    problems.append(f"{rel}:{n}: forbidden ({why}): {line.strip()[:80]}")
        if f.name == "NpcLife.lua":
            scans = sum(1 for line in lines if "GetDescendants" in strip(line))
            if scans != 1:
                problems.append(f"{rel}: expected exactly one GetDescendants (adopt-time), found {scans}")
        if f.name == "NpcLifeClient.client.lua":
            hb = sum(1 for line in lines if "Heartbeat:Connect" in strip(line))
            if hb != 1:
                problems.append(f"{rel}: expected exactly one Heartbeat connection, found {hb}")

    # data cross-references (same checks the tests run, as a lint pass)
    try:
        from npc_kit.tests import test_syntax_and_data as T
        T.test_pack_gestures_reference_known_joints_and_stay_in_limits(H)
        T.test_recipes_cross_reference(H)
        T.test_library_entries_are_buildable_without_meshes(H)
    except AssertionError as e:
        problems.append(f"data: {e}")

    print(f"npc_kit lint: {len(files)} files")
    for p in problems:
        print("  FAIL", p)
    if not problems:
        print("  OK: compile, syntax subset, forbidden APIs, headers, data cross-references")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
