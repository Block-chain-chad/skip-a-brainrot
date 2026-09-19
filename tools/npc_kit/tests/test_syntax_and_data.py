"""Every kit file compiles under Lua 5.1 (Luau superset) and the data modules
cross-reference cleanly: recipes -> library/families/themes/packs, gesture joints
-> rig joints, amplitudes within the pack limits."""
import re

import pytest

from npc_kit.harness import SCRIPTS, all_lua_files


def test_every_file_compiles(H):
    for f in all_lua_files():
        src = f.read_text(encoding="utf-8")
        ok, err = H.lua.eval("function(src, name) local f, e = loadstring(src, '=' .. name) return f ~= nil, e end")(src, f.name)
        assert ok, f"{f.name}: {err}"


def test_every_module_requires(H):
    for dm_path, (cls, _) in SCRIPTS.items():
        if cls == "ModuleScript":
            mod = H.require(dm_path)
            assert mod is not None, dm_path


KNOWN_JOINTS = {"Root", "Waist", "Neck", "RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow", "RightWrist", "LeftWrist",
                "RightHip", "LeftHip", "RightKnee", "LeftKnee", "RightAnkle", "LeftAnkle", "Head", "WingL", "__model"}
AXES = {"swing", "spread", "twist", "bend", "turn", "tilt", "x", "y", "z", "up"}


def test_pack_gestures_reference_known_joints_and_stay_in_limits(H):
    MC = H.require("ReplicatedStorage/Modules/NpcKit/NpcMotionConfig")
    limits = MC.Limits
    for gname, g in MC.Gestures.items():
        for key in H.lua_list(g["keys"]):
            for joint, axes in key.items():
                if joint == "t":
                    continue
                assert joint in KNOWN_JOINTS, f"{gname}: unknown joint {joint}"
                for axis, v in axes.items():
                    assert axis in AXES, f"{gname}: unknown axis {axis}"
                    if joint in ("Root", "Waist", "Neck"):
                        cap = limits.spineGesture
                    elif "Shoulder" in joint:
                        cap = limits.shoulder
                    elif "Elbow" in joint:
                        cap = limits.elbow
                    elif "Wrist" in joint:
                        cap = limits.wrist
                    elif joint in ("Head", "WingL"):
                        cap = limits.spineGesture
                    else:
                        cap = limits.leg
                    if g.signature:
                        cap = max(cap, limits.signature)
                    if axis in ("x", "y", "z"):
                        cap = 1.0
                    assert abs(v) <= cap + 1e-9, f"{gname}: {joint}.{axis}={v} exceeds {cap}"
    for pname, pack in MC.Packs.items():
        for lname, layer in pack.idle.items():
            for eff in H.lua_list(layer.effects):
                assert eff.joint in KNOWN_JOINTS, f"{pname}.{lname}: unknown joint {eff.joint}"
                if layer.kind in ("sine", "snap", "const") and eff.axis in ("bend", "turn", "tilt") and eff.joint in ("Root", "Waist"):
                    assert abs(layer.amp * eff.scale) <= limits.spineIdle + 4.01, f"{pname}.{lname}: spine idle amp {layer.amp * eff.scale}"


def test_recipes_cross_reference(H):
    Lib = H.require("ReplicatedStorage/Modules/NpcKit/NpcLibrary")
    Fam = H.require("ReplicatedStorage/Modules/NpcKit/NpcFamilies")
    Themes = H.require("ReplicatedStorage/Modules/NpcKit/NpcWorldThemes")
    MC = H.require("ReplicatedStorage/Modules/NpcKit/NpcMotionConfig")
    Face = H.require("ReplicatedStorage/Modules/NpcKit/NpcFaceConfig")
    Rig = H.require("ReplicatedStorage/Modules/NpcKit/NpcRigSpec")
    for dm_path in SCRIPTS:
        if "/NpcCharacters/" not in dm_path:
            continue
        r = H.require(dm_path)
        assert r.id and r.rootName and r.tier in (1, 2, 3) and r.kind in ("human", "creature"), dm_path
        assert Themes.Themes[r.world] is not None, f"{r.id}: theme {r.world}"
        assert MC.Packs[r.pack] is not None, f"{r.id}: pack {r.pack}"
        if r.profile:
            assert MC.Packs[r.pack].profiles[r.profile] is not None, f"{r.id}: profile {r.profile}"
        if r.kind == "human":
            assert Fam.Families[r.family] is not None, f"{r.id}: family {r.family}"
            assert Rig.BodyTypes[r.bodyType] is not None, f"{r.id}: body type {r.bodyType}"
            assert Face.Expressions[r.face] is not None, f"{r.id}: face {r.face}"
            for slot in ("hair", "hat", "beard"):
                v = r[slot]
                if v:
                    assert Lib.Entries[v] is not None and Lib.Entries[v].kind in ("hair", "hat", "beard"), f"{r.id}: {slot} {v}"
            for o in H.lua_list(r.overlays or H.lua.table()):
                oid = o if isinstance(o, str) else o.id
                assert Lib.Entries[oid] is not None and Lib.Entries[oid].kind == "overlay", f"{r.id}: overlay {oid}"
            for p in H.lua_list(r.props or H.lua.table()):
                pid = p if isinstance(p, str) else p.id
                e = Lib.Entries[pid]
                assert e is not None and e.kind == "prop", f"{r.id}: prop {pid}"
                grip = (p.grip if not isinstance(p, str) else None) or e.grip
                assert Rig.Grips[grip] is not None or Lib.Entries[grip] is not None, f"{r.id}: grip {grip}"
            if r.packOverrides:
                for k in r.packOverrides.keys():
                    if "." in k:
                        head = k.split(".")[0]
                        assert head in ("idle", "gestures", "talk", "track"), f"{r.id}: override path {k}"
        else:
            assert r.species, f"{r.id}: species"
            layer = H.lua_list(r.storyLayer or H.lua.table())
            assert len(layer) <= 8, f"{r.id}: story layer > 8 parts"
            for row in layer:
                assert row.part and row.size and row.color and row.bone, f"{r.id}: story row incomplete"


def test_library_entries_are_buildable_without_meshes(H):
    Lib = H.require("ReplicatedStorage/Modules/NpcKit/NpcLibrary")
    for eid, e in Lib.Entries.items():
        if e.kind == "body":
            continue
        assert e.blockout is not None, f"{eid}: no blockout -- the Step 7 blockout build would fail"
        for spec in H.lua_list(e.blockout):
            assert spec.shape in ("Block", "Cylinder", "Ball") and spec.size is not None, f"{eid}: bad blockout part"


LUAU_ONLY = [r"\+=", r"-=", r"\*=", r"/=", r"\.\.=", r"\bcontinue\b", r"::", r"--!strict", "`"]


def test_no_luau_only_syntax_in_kit():
    """The harness runs Lua 5.1; keeping the sources in the common subset is what
    makes every test above a real test. Luau accepts all of it unchanged."""
    for f in all_lua_files():
        for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
            code = re.sub(r"--.*$", "", code)
            for pat in LUAU_ONLY:
                assert re.search(pat, code) is None, f"{f.name}:{n}: Luau-only syntax {pat!r}: {line.strip()}"
