# Brainrot Forge Conversion Implementation Plan (Phase 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 66 Part-built brainrot templates in `ReplicatedStorage.BrainrotModels` with forge-baked mesh templates of identical geometry and colour, then retire the 43 coarse plot-LOD copies.

**Architecture:** A Luau dump script exports every template's boxes (CFrame/Size/Color/Material) as JSON; `ingest_parts.py` un-poses tilted bodies; `bake_boxes.py` emits every box face not fully covered by neighbours, grouped into ≤ 12 (colour, material) roles with per-vertex colour ratios for exact shades; the existing exporter/renderer/assembler gain the few fields this needs (`COLOR_0`, per-role materials, attributes, `poseRotation`, `fx = true`, backup folder). Four import batches, each gated by a before/after sheet.

**Tech Stack:** as Phase 1 (Python 3.14 + Pillow + pytest; Roblox Studio MCP; Luau build-time modules mirrored in `game-src/`).

## Global Constraints

- Everything in the Phase-1 plan's Global Constraints still applies (anchored live edits, compile gates, commit only named paths, SessionLock ≥ 90 s between playtests, never `git add -A`).
- Exec sandbox: `loadstring(module.Source)()` in Edit mode only; Play mode needs the request-driven harness Script created in Edit mode (`ServerScriptService.__ForgeSpawnTest_DELETE_ME`, deleted afterwards).
- Roles per body ≤ 12; Neon roles ≤ 3; conversion triangle gate 12,000 per body / 4,000 per role (pack max measured 16,064).
- Geometry is lossless: every visible box face of the original is present in the mesh; only fully covered faces are dropped. Positions stay in the template's authored frame (the exporter's `roblox_forward` pre-turn + the importer's turn = identity).
- Replaced originals go to `ServerStorage.AuditBackups.BrainrotModels_PreForge_2026-09-17` (one folder); the 43 LOD copies go to `ServerStorage.AuditBackups.BrainrotModelsPlot_PreForge_2026-09-17`. `Chim` and `Maxwell` are never touched. Nothing is saved to the place by us.

## File Structure

| Path | Responsibility |
|---|---|
| `tools/brainrot_forge/studio/dump_parts.lua` | Luau (run via `execute_luau`, Edit): dumps a named group of templates as compact JSON |
| `tools/brainrot_forge/ingest_parts.py` | `Box`, `PartModel`, `load_dump()` (raw JSON or MCP wrapper), `unpose()` |
| `tools/brainrot_forge/bake_boxes.py` | face extraction + coverage cull, role clustering with vertex-colour ratios, `bake_boxes()` |
| `tools/brainrot_forge/bake.py` | `Mesh` gains optional `colors` |
| `tools/brainrot_forge/export_glb.py` | `COLOR_0` in/out; manifest extra fields |
| `tools/brainrot_forge/render.py` | per-vertex colours; `compare_sheet()` before/after |
| `tools/brainrot_forge/convert.py` + `__main__.py` | `python -m brainrot_forge convert` → 4 batches |
| `tools/brainrot_forge/tests/test_ingest_parts.py`, `test_bake_boxes.py`, `test_convert.py` (+ additions to `test_export_glb.py`, `test_render.py`) | pytest |
| `game-src/BrainrotForge.lua` → `ServerStorage.BrainrotForge` | assembler additions |
| `docs/brainrot-build-standard.md`, this plan | closeout |

---

### Task 1: Dump the 66 templates out of Studio

**Files:**
- Create: `tools/brainrot_forge/studio/dump_parts.lua`, `tools/out/convert/dump/group1..8.json` (git-ignored output).

**Interfaces:**
- Produces: JSON `[ { "name", "rarity", "world", "attrs": {k: number|string|bool}, "fx": bool, "parts": [ [px,py,pz, sx,sy,sz, "RRGGBB", "P"|"S"|"N"|<MaterialName>, [R00..R22]?] ] } ]` — the 9-number rotation only when the part is not identity-rotated. FX host parts and fully transparent parts are excluded.

- [ ] **Step 1: Write `tools/brainrot_forge/studio/dump_parts.lua`** (the `NAMES` line is replaced per group before each run)

```lua
-- Dumps a group of Part-built brainrot templates as compact JSON for tools/brainrot_forge/ingest_parts.py.
-- Run from the MCP exec (Edit mode). Outputs >= ~30 KB are persisted by the harness to a file; copy that
-- file to tools/out/convert/dump/groupN.json. Keep groups to ~9 models so every output is persisted.
local RS = game:GetService("ReplicatedStorage")
local HS = game:GetService("HttpService")
local NAMES = { "__GROUP__" }

local rarity, world = {}, {}
for _, spec in ipairs({ { "BrainrotConfig", "Valley" }, { "BrainrotConfigTundra", "Tundra" } }) do
	local src = RS.Modules[spec[1]].Source
	for name, r in src:gmatch('Name%s*=%s*"([^"]+)"%s*,%s*Rarity%s*=%s*"([^"]+)"') do
		if not rarity[name] then rarity[name] = r; world[name] = spec[2] end
	end
end
local MAT = { Plastic = "P", SmoothPlastic = "S", Neon = "N" }
local function r4(x) return math.floor(x * 10000 + 0.5) / 10000 end
local out = {}
for _, name in ipairs(NAMES) do
	local m = RS.BrainrotModels:FindFirstChild(name) or error("missing " .. name)
	local parts, fx = {}, false
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name:sub(1, 10) == "BrainrotFx" then
				fx = true
			elseif d.Transparency < 1 then
				assert(d:IsA("Part") and d.Shape == Enum.PartType.Block, name .. " has a non-block part: " .. d.Name)
				local c = { d.CFrame:GetComponents() }
				local rec = { r4(c[1]), r4(c[2]), r4(c[3]), r4(d.Size.X), r4(d.Size.Y), r4(d.Size.Z), d.Color:ToHex(), MAT[d.Material.Name] or d.Material.Name }
				local ident = math.abs(c[4] - 1) < 1e-4 and math.abs(c[8] - 1) < 1e-4 and math.abs(c[12] - 1) < 1e-4
				if not ident then rec[9] = { r4(c[4]), r4(c[5]), r4(c[6]), r4(c[7]), r4(c[8]), r4(c[9]), r4(c[10]), r4(c[11]), r4(c[12]) } end
				parts[#parts + 1] = rec
			end
		end
	end
	local attrs = {}
	for k, v in pairs(m:GetAttributes()) do
		local t = typeof(v)
		if t == "number" or t == "string" or t == "boolean" then attrs[k] = v end
	end
	out[#out + 1] = { name = name, rarity = rarity[name] or "Unknown", world = world[name] or "Unknown", attrs = attrs, fx = fx, parts = parts }
end
return HS:JSONEncode(out)
```

- [ ] **Step 2: Decide the eight groups** — the 66 names sorted alphabetically, 8–9 per group (`Chim` and `Maxwell` excluded). Get the list live:

```lua
local RS = game:GetService("ReplicatedStorage")
local names = {}
for _, m in ipairs(RS.BrainrotModels:GetChildren()) do
	if m:IsA("Model") and not m:FindFirstChildWhichIsA("MeshPart", true) and m.Name ~= "Chim" then names[#names + 1] = m.Name end
end
table.sort(names)
return #names .. "\n" .. table.concat(names, "\n")
```

Expected: 66 names (Maxwell is a MeshPart model, so it is excluded by the filter; `Chim` by name).

- [ ] **Step 3: Run the dump per group** — `execute_luau` (Edit) with `NAMES = { "<name1>", ... }` substituted; each result is large enough that the harness reports `Full output saved to: <path>`; copy that file:

```bash
mkdir -p tools/out/convert/dump
cp "<path from the tool result>" tools/out/convert/dump/group1.json
```

Repeat for groups 2–8. If a result is NOT persisted (small group), re-run with a bigger group. Verify the set:

```bash
cd tools && python - <<'EOF'
from brainrot_forge.ingest_parts import load_dump
import glob
names = []
for p in sorted(glob.glob("out/convert/dump/group*.json")):
    ms = load_dump(p); names += [m.name for m in ms]
    print(p, len(ms), "models", sum(len(m.boxes) for m in ms), "boxes")
print(len(names), "total;", len(set(names)), "unique")
EOF
```

Expected: 66 total, 66 unique (this needs Task 2's `load_dump`, so run it after Task 2).

### Task 2: `ingest_parts.py` — load dumps, un-pose tilted bodies

**Files:**
- Create: `tools/brainrot_forge/ingest_parts.py`, `tools/brainrot_forge/tests/test_ingest_parts.py`

**Interfaces:**
- Produces: `Box(pos, size, color, material, rot)` (`rot` = 9-tuple row-major or `None`), `PartModel(name, rarity, world, attrs, fx, boxes, pose=None)`, `load_dump(path) -> list[PartModel]` (accepts raw JSON or the harness's `[{"type":"text","text":...}]` wrapper), `unpose(model) -> PartModel` (all boxes share one rotation → boxes rewritten in that local frame about the bbox centre, `pose` set; mixed rotations → `ValueError`), `bbox(boxes) -> (lo, hi)`.

- [ ] **Step 1: Failing tests** — `tools/brainrot_forge/tests/test_ingest_parts.py`

```python
import json
import math
import pytest
from brainrot_forge import ingest_parts as I


def dump_json(models):
    return json.dumps(models)


def test_load_dump_raw_and_wrapped(tmp_path):
    models = [{"name": "A", "rarity": "Epic", "world": "Tundra", "attrs": {"HeightScale": 1.3}, "fx": True,
               "parts": [[0, 1, 0, 2, 2, 2, "ff0000", "P"], [3, 1, 0, 1, 1, 1, "00ff00", "N", [0, 0, 1, 0, 1, 0, -1, 0, 0]]]}]
    raw = tmp_path / "raw.json"; raw.write_text(dump_json(models))
    wrapped = tmp_path / "wrapped.json"; wrapped.write_text(json.dumps([{"type": "text", "text": dump_json(models)}]))
    for p in (raw, wrapped):
        ms = I.load_dump(p)
        assert len(ms) == 1 and ms[0].name == "A" and ms[0].fx is True and ms[0].attrs == {"HeightScale": 1.3}
        b0, b1 = ms[0].boxes
        assert b0.pos == (0, 1, 0) and b0.size == (2, 2, 2) and b0.color == "#FF0000" and b0.material == "Plastic" and b0.rot is None
        assert b1.material == "Neon" and b1.rot == (0, 0, 1, 0, 1, 0, -1, 0, 0)


def test_bbox():
    boxes = [I.Box((0, 1, 0), (2, 2, 2), "#FFFFFF", "Plastic", None), I.Box((5, 0, 0), (1, 1, 1), "#FFFFFF", "Plastic", None)]
    assert I.bbox(boxes) == ((-1, -0.5, -1), (5.5, 2, 1))


def test_unpose_identity_is_noop():
    m = I.PartModel("A", "Epic", "Tundra", {}, False, [I.Box((0, 1, 0), (2, 2, 2), "#FFFFFF", "Plastic", None)])
    u = I.unpose(m)
    assert u.pose is None and u.pose_centre is None and u.boxes[0].pos == (0, 1, 0)


def test_unpose_shared_rotation():
    # every box yawed 90 degrees about Y: world = R*local + p ; R = rows (0,0,1),(0,1,0),(-1,0,0)
    R = (0, 0, 1, 0, 1, 0, -1, 0, 0)
    boxes = [I.Box((0, 0, 0), (1, 1, 3), "#FFFFFF", "Plastic", R), I.Box((2, 0, 0), (1, 1, 1), "#000000", "Plastic", R)]
    u = I.unpose(I.PartModel("T", "Epic", "Tundra", {}, False, boxes))
    assert u.pose == R and u.pose_centre is not None
    assert all(b.rot is None for b in u.boxes)
    # centre of the two boxes is (1,0,0); the second box sits +2 along world x == R * (0,0,-2)?  R^T * (1,0,0) = (0,0,-1)
    c = I.bbox(boxes)[0], I.bbox(boxes)[1]
    p0, p1 = u.boxes[0].pos, u.boxes[1].pos
    assert math.isclose(p1[2] - p0[2], -2, abs_tol=1e-6) and math.isclose(p1[0] - p0[0], 0, abs_tol=1e-6)


def test_unpose_mixed_rotations_refused():
    R = (0, 0, 1, 0, 1, 0, -1, 0, 0)
    boxes = [I.Box((0, 0, 0), (1, 1, 1), "#FFFFFF", "Plastic", R), I.Box((2, 0, 0), (1, 1, 1), "#FFFFFF", "Plastic", None)]
    with pytest.raises(ValueError, match="mixed"):
        I.unpose(I.PartModel("T", "Epic", "Tundra", {}, False, boxes))
```

Run: `cd tools && python -m pytest brainrot_forge/tests/test_ingest_parts.py -q` → `ModuleNotFoundError`.

- [ ] **Step 2: Write `tools/brainrot_forge/ingest_parts.py`**

```python
"""ingest_parts.py — the Studio dump (tools/brainrot_forge/studio/dump_parts.lua) -> PartModel.

A PartModel is a list of axis-aligned boxes in studs (the template's own frame). Three fish were
re-posed with one rigid rotation on every part; unpose() rewrites those into the shared local
frame so the bake can cull faces, and records `pose` for the assembler to re-apply.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

Vec3 = tuple[float, float, float]
Rot = tuple[float, float, float, float, float, float, float, float, float]  # row-major R00..R22
MATERIALS = {"P": "Plastic", "S": "SmoothPlastic", "N": "Neon"}


@dataclass
class Box:
    pos: Vec3
    size: Vec3
    color: str          # "#RRGGBB"
    material: str       # Roblox Material name
    rot: Rot | None     # None = identity


@dataclass
class PartModel:
    name: str
    rarity: str
    world: str
    attrs: dict
    fx: bool
    boxes: list[Box]
    pose: Rot | None = None
    pose_centre: Vec3 | None = None   # the pivot unpose() rotated about; the assembler re-poses about it


def load_dump(path: str | Path) -> list[PartModel]:
    text = Path(path).read_text(encoding="utf-8")
    data = json.loads(text)
    if data and isinstance(data[0], dict) and "type" in data[0] and "text" in data[0]:   # harness wrapper
        data = json.loads(data[0]["text"])
    models = []
    for m in data:
        boxes = []
        for p in m["parts"]:
            rot = tuple(p[8]) if len(p) > 8 and p[8] else None
            boxes.append(Box((p[0], p[1], p[2]), (p[3], p[4], p[5]), "#" + p[6].upper(), MATERIALS.get(p[7], p[7]), rot))
        models.append(PartModel(m["name"], m.get("rarity", "Unknown"), m.get("world", "Unknown"), dict(m.get("attrs", {})), bool(m.get("fx")), boxes))
    return models


def bbox(boxes: list[Box]) -> tuple[Vec3, Vec3]:
    lo = [min(b.pos[i] - b.size[i] / 2 for b in boxes) for i in range(3)]
    hi = [max(b.pos[i] + b.size[i] / 2 for b in boxes) for i in range(3)]
    return (lo[0], lo[1], lo[2]), (hi[0], hi[1], hi[2])


def _same(a: Rot, b: Rot, tol=1e-3) -> bool:
    return all(abs(x - y) <= tol for x, y in zip(a, b))


def unpose(model: PartModel) -> PartModel:
    rots = [b.rot for b in model.boxes if b.rot is not None]
    if not rots:
        return model
    if len(rots) != len(model.boxes) or not all(_same(r, rots[0]) for r in rots):
        raise ValueError(f"{model.name}: mixed rotations — cannot un-pose")
    R = rots[0]
    lo, hi = bbox(model.boxes)   # rotated boxes' AABB is only an approximation of the centre; any fixed pivot works
    c = ((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2)
    # local = R^T (p - c) + c   (row-major R: world = R * local)
    def to_local(p: Vec3) -> Vec3:
        d = (p[0] - c[0], p[1] - c[1], p[2] - c[2])
        return (R[0] * d[0] + R[3] * d[1] + R[6] * d[2] + c[0],
                R[1] * d[0] + R[4] * d[1] + R[7] * d[2] + c[1],
                R[2] * d[0] + R[5] * d[1] + R[8] * d[2] + c[2])
    boxes = [Box(to_local(b.pos), b.size, b.color, b.material, None) for b in model.boxes]
    return PartModel(model.name, model.rarity, model.world, model.attrs, model.fx, boxes, pose=R, pose_centre=c)
```

Run the tests → `5 passed`. Then run Task 1 Step 3's verification (66 total / 66 unique).

- [ ] **Step 3: Commit**

```bash
git add tools/brainrot_forge/studio/dump_parts.lua tools/brainrot_forge/ingest_parts.py tools/brainrot_forge/tests/test_ingest_parts.py
git commit -m "feat(forge): Studio part dump + ingest with un-posing for tilted bodies

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

### Task 3: `bake_boxes.py` — lossless box bake with coverage culling and colour roles

**Files:**
- Create: `tools/brainrot_forge/bake_boxes.py`, `tools/brainrot_forge/tests/test_bake_boxes.py`
- Modify: `tools/brainrot_forge/bake.py` (add `colors: list[Vec3] | None = None` to `Mesh`)

**Interfaces:**
- Produces: `bake_boxes(model: PartModel, max_roles=12, max_neon=3, exact=False, max_tris_model=12000, max_tris_role=4000) -> ConvertedModel` where `ConvertedModel` has `name, rarity, world, pitch=0.2, palette {role: rep hex}, materials {role: Material}, meshes {role: Mesh}, height_scale, width_scale, motion, material, fx (True|None), attributes, pose_rotation (9 floats|None), vertex_colors (bool), size_studs()`; also `faces(boxes) -> list[Face]`, `cull_covered(faces) -> list[Face]`, `cluster_roles(box_faces, max_roles, max_neon) -> {role: (rep, material, members)}`.

- [ ] **Step 1: Failing tests** — `tools/brainrot_forge/tests/test_bake_boxes.py`

```python
import pytest
from brainrot_forge.ingest_parts import Box, PartModel
from brainrot_forge import bake_boxes as BB


def pm(boxes, name="T", fx=False, attrs=None):
    return PartModel(name, "Epic", "Tundra", attrs or {"HeightScale": 1.3}, fx, boxes)


def test_single_box_six_faces():
    m = BB.bake_boxes(pm([Box((0, 0.5, 0), (1, 1, 1), "#FF0000", "Plastic", None)]))
    assert list(m.meshes) == ["c00"] and m.meshes["c00"].triangles == 12
    assert m.palette["c00"] == "#FF0000" and m.materials["c00"] == "Plastic" and m.meshes["c00"].colors is None


def test_shared_face_between_two_boxes_is_culled():
    boxes = [Box((0, 0.5, 0), (1, 1, 1), "#FF0000", "Plastic", None), Box((1, 0.5, 0), (1, 1, 1), "#FF0000", "Plastic", None)]
    assert BB.bake_boxes(pm(boxes)).meshes["c00"].triangles == 10 * 2


def test_face_covered_by_union_of_smaller_boxes_is_culled():
    big = Box((0, 0.5, 0), (2, 1, 2), "#FF0000", "Plastic", None)          # top face y=1 spans x,z in [-1,1]
    quads = [Box((sx * 0.5, 1.5, sz * 0.5), (1, 1, 1), "#00FF00", "Plastic", None) for sx in (-1, 1) for sz in (-1, 1)]
    m = BB.bake_boxes(pm([big] + quads))
    red = next(r for r, h in m.palette.items() if h == "#FF0000")
    assert m.meshes[red].triangles // 2 == 5, "big box keeps 5 faces: its top is fully covered by the four quads"


def test_partial_cover_keeps_face():
    big = Box((0, 0.5, 0), (2, 1, 2), "#FF0000", "Plastic", None)
    one = Box((-0.5, 1.5, -0.5), (1, 1, 1), "#00FF00", "Plastic", None)
    m = BB.bake_boxes(pm([big, one]))
    red = next(r for r, h in m.palette.items() if h == "#FF0000")
    assert m.meshes[red].triangles // 2 == 6


def test_roles_split_by_material_and_neon_is_neon():
    boxes = [Box((0, 0.5, 0), (1, 1, 1), "#FF0000", "Plastic", None), Box((3, 0.5, 0), (1, 1, 1), "#FF0000", "Neon", None)]
    m = BB.bake_boxes(pm(boxes))
    assert sorted(m.materials.values()) == ["Neon", "Plastic"] and len(m.meshes) == 2


def test_clustering_to_max_roles_with_vertex_ratios():
    boxes = [Box((i * 2, 0.5, 0), (1, 1, 1), f"#{200 - i * 10:02X}0000", "Plastic", None) for i in range(15)]
    m = BB.bake_boxes(pm(boxes), max_roles=4)
    assert len(m.meshes) == 4 and m.vertex_colors is True
    for role, mesh in m.meshes.items():
        rep = m.palette[role]
        r = int(rep[1:3], 16)
        assert mesh.colors is not None and all(0 < c[0] <= 1.0001 and c[1] == c[2] == 1.0 for c in mesh.colors)
        # representative is the per-channel max of its members, so no ratio exceeds 1
        assert max(c[0] for c in mesh.colors) <= 1.0001


def test_exact_mode_keeps_every_colour():
    boxes = [Box((i * 2, 0.5, 0), (1, 1, 1), f"#{200 - i * 10:02X}0000", "Plastic", None) for i in range(15)]
    m = BB.bake_boxes(pm(boxes), max_roles=4, exact=True)
    assert len(m.meshes) == 15 and m.vertex_colors is False


def test_neon_roles_capped():
    boxes = [Box((i * 2, 0.5, 0), (1, 1, 1), f"#00{100 + i * 20:02X}FF", "Neon", None) for i in range(6)]
    m = BB.bake_boxes(pm(boxes), max_neon=3)
    assert sum(1 for mat in m.materials.values() if mat == "Neon") == 3


def test_triangle_gate():
    boxes = [Box((i * 2, 0.5, 0), (1, 1, 1), "#FF0000", "Plastic", None) for i in range(3)]
    with pytest.raises(BB.BudgetError):
        BB.bake_boxes(pm(boxes), max_tris_model=20)


def test_metadata_flows_through():
    m = BB.bake_boxes(pm([Box((0, 0.5, 0), (1, 1, 1), "#FF0000", "Plastic", None)], fx=True, attrs={"HeightScale": 1.46, "WidthScale": 0.8, "Tier": "Secret"}))
    assert m.height_scale == 1.46 and m.width_scale == 0.8 and m.attributes["Tier"] == "Secret" and m.fx is True
    assert m.size_studs() == (1.0, 1.0, 1.0) and m.pose_rotation is None and m.pose_centre is None
```

Run → `ModuleNotFoundError`.

- [ ] **Step 2: `bake.py` — add the optional colour attribute to `Mesh`**

```python
    colors: list[Vec3] | None = None   # per-vertex multiplier over the part colour (exact / representative); None = all 1
```
(add as the last field of the `Mesh` dataclass; nothing else in `bake.py` changes.)

- [ ] **Step 3: Write `tools/brainrot_forge/bake_boxes.py`**

```python
"""bake_boxes.py — axis-aligned boxes (a Part-built brainrot) -> per-role meshes, LOSSLESS.

Every box face is emitted unless it is fully covered by coplanar, opposite-facing faces of other
boxes (union coverage on a coordinate-compressed grid — exact). Faces are grouped into roles =
(colour cluster, material): at most `max_roles` per body, at most `max_neon` Neon roles. A role's
MeshPart colour is the per-channel MAX of its member colours and each vertex carries the ratio
exact / representative as COLOR_0, so the render is exact wherever the importer keeps vertex
colours and a flat representative where it does not. exact=True disables clustering (used for the
"before" render in the approval sheets).
"""
from __future__ import annotations

from dataclasses import dataclass, field

from .bake import BudgetError, Mesh, TILE_STUDS
from .ingest_parts import Box, PartModel, Vec3, bbox

_OTHER = {0: (1, 2), 1: (2, 0), 2: (0, 1)}
EPS = 1e-4


@dataclass
class Face:
    axis: int
    sign: int
    plane: float
    u0: float
    u1: float
    v0: float
    v1: float
    color: str
    material: str


@dataclass
class ConvertedModel:
    name: str
    rarity: str
    world: str
    palette: dict[str, str]
    materials: dict[str, str]
    meshes: dict[str, Mesh]
    attributes: dict
    fx: bool | None
    pose_rotation: tuple | None
    pose_centre: Vec3 | None
    vertex_colors: bool
    bounds: tuple[Vec3, Vec3]
    pitch: float = 0.2
    motion: str = "hover"
    material: str = "Plastic"

    @property
    def height_scale(self) -> float:
        return float(self.attributes.get("HeightScale", 1))

    @property
    def width_scale(self) -> float:
        return float(self.attributes.get("WidthScale", 1))

    def size_studs(self) -> tuple[float, float, float]:
        lo, hi = self.bounds
        return tuple(round(hi[i] - lo[i], 6) for i in range(3))  # type: ignore[return-value]


def faces(boxes: list[Box]) -> list[Face]:
    out = []
    for b in boxes:
        for axis in range(3):
            ua, va = _OTHER[axis]
            u0, u1 = b.pos[ua] - b.size[ua] / 2, b.pos[ua] + b.size[ua] / 2
            v0, v1 = b.pos[va] - b.size[va] / 2, b.pos[va] + b.size[va] / 2
            for sign in (1, -1):
                plane = b.pos[axis] + sign * b.size[axis] / 2
                out.append(Face(axis, sign, round(plane, 4), round(u0, 4), round(u1, 4), round(v0, 4), round(v1, 4), b.color, b.material))
    return out


def _covered(f: Face, others: list[Face]) -> bool:
    clipped = []
    for o in others:
        u0, u1 = max(f.u0, o.u0), min(f.u1, o.u1)
        v0, v1 = max(f.v0, o.v0), min(f.v1, o.v1)
        if u1 - u0 > EPS and v1 - v0 > EPS:
            clipped.append((u0, u1, v0, v1))
    if not clipped:
        return False
    us = sorted({f.u0, f.u1, *[c[0] for c in clipped], *[c[1] for c in clipped]})
    vs = sorted({f.v0, f.v1, *[c[2] for c in clipped], *[c[3] for c in clipped]})
    for i in range(len(us) - 1):
        cu = (us[i] + us[i + 1]) / 2
        if cu < f.u0 or cu > f.u1:
            continue
        for j in range(len(vs) - 1):
            cv = (vs[j] + vs[j + 1]) / 2
            if cv < f.v0 or cv > f.v1:
                continue
            if not any(c[0] <= cu <= c[1] and c[2] <= cv <= c[3] for c in clipped):
                return False
    return True


def cull_covered(all_faces: list[Face]) -> list[Face]:
    groups: dict[tuple[int, float, int], list[Face]] = {}
    for f in all_faces:
        groups.setdefault((f.axis, f.plane, f.sign), []).append(f)
    kept = []
    for f in all_faces:
        opposite = groups.get((f.axis, f.plane, -f.sign), [])
        if not _covered(f, opposite):
            kept.append(f)
    return kept


def _rgb(h: str) -> Vec3:
    return (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16))


def _hex(rgb) -> str:
    return "#%02X%02X%02X" % tuple(int(round(c)) for c in rgb)


def cluster_roles(kept: list[Face], max_roles: int, max_neon: int, exact: bool) -> dict[str, tuple[str, str, set[str]]]:
    """-> {role: (representative hex, material, member colours)}; roles named c00, c01, ... by area."""
    area: dict[tuple[str, str], float] = {}
    for f in kept:
        area[(f.color, f.material)] = area.get((f.color, f.material), 0) + (f.u1 - f.u0) * (f.v1 - f.v0)
    keys = sorted(area, key=lambda k: -area[k])
    by_mat: dict[str, list[tuple[str, str]]] = {}
    for k in keys:
        by_mat.setdefault(k[1], []).append(k)
    clusters: list[tuple[str, str, set[str]]] = []
    if exact or len(keys) <= max_roles and sum(1 for k in keys if k[1] == "Neon") <= max_neon:
        clusters = [(k[0], k[1], {k[0]}) for k in keys]
    else:
        # budget per material: proportional to its distinct colours, at least 1, Neon capped
        budget = {}
        remaining = max_roles
        mats = sorted(by_mat, key=lambda m: -len(by_mat[m]))
        for m in mats:
            budget[m] = 1
            remaining -= 1
        for m in mats:
            want = min(len(by_mat[m]), (max_neon if m == "Neon" else max_roles)) - budget[m]
            take = max(0, min(want, remaining))
            budget[m] += take
            remaining -= take
        for m in mats:
            colours = by_mat[m]
            reps = colours[: budget[m]]
            members: dict[tuple[str, str], set[str]] = {r: {r[0]} for r in reps}
            for k in colours[budget[m]:]:
                rgb = _rgb(k[0])
                nearest = min(reps, key=lambda r: sum((a - b) ** 2 for a, b in zip(rgb, _rgb(r[0]))))
                members[nearest].add(k[0])
            for r in reps:
                mem = members[r]
                rep_rgb = tuple(max(_rgb(c)[i] for c in mem) for i in range(3))
                clusters.append((_hex(rep_rgb), m, mem))
        clusters.sort(key=lambda c: -sum(area.get((col, c[1]), 0) for col in c[2]))
    return {f"c{i:02d}": c for i, c in enumerate(clusters)}


def _quad(mesh: Mesh, f: Face, ratio: Vec3 | None) -> None:
    ua, va = _OTHER[f.axis]
    n = [0.0, 0.0, 0.0]
    n[f.axis] = float(f.sign)
    corners = []
    for (u, v) in ((f.u0, f.v0), (f.u1, f.v0), (f.u1, f.v1), (f.u0, f.v1)):
        p = [0.0, 0.0, 0.0]
        p[f.axis] = f.plane
        p[ua] = u
        p[va] = v
        corners.append(((p[0], p[1], p[2]), (round(u / TILE_STUDS, 6), round(v / TILE_STUDS, 6))))
    a, b, c = corners[0][0], corners[1][0], corners[2][0]
    ab = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
    ac = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
    cr = (ab[1] * ac[2] - ab[2] * ac[1], ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0])
    if cr[0] * n[0] + cr[1] * n[1] + cr[2] * n[2] < 0:
        corners = [corners[0], corners[3], corners[2], corners[1]]
    base = len(mesh.positions)
    for pos, uv in corners:
        mesh.positions.append(pos)
        mesh.normals.append((n[0], n[1], n[2]))
        mesh.uvs.append(uv)
        if mesh.colors is not None:
            mesh.colors.append(ratio or (1.0, 1.0, 1.0))
    mesh.indices.extend((base, base + 1, base + 2, base, base + 2, base + 3))


def bake_boxes(model: PartModel, max_roles: int = 12, max_neon: int = 3, exact: bool = False,
               max_tris_model: int = 12000, max_tris_role: int = 4000) -> ConvertedModel:
    kept = cull_covered(faces(model.boxes))
    roles = cluster_roles(kept, max_roles, max_neon, exact)
    role_of: dict[tuple[str, str], str] = {}
    for role, (rep, mat, members) in roles.items():
        for col in members:
            role_of[(col, mat)] = role
    clustered = any(len(c[2]) > 1 for c in roles.values())
    meshes: dict[str, Mesh] = {}
    palette, materials = {}, {}
    for role, (rep, mat, members) in roles.items():
        meshes[role] = Mesh(role, colors=[] if clustered else None)   # uniform: every role carries ratios once any cluster exists
        palette[role] = rep
        materials[role] = mat
    for f in kept:
        role = role_of[(f.color, f.material)]
        rep = _rgb(palette[role])
        ratio = None
        if meshes[role].colors is not None:
            col = _rgb(f.color)
            ratio = tuple(min(1.0, col[i] / rep[i]) if rep[i] > 0 else 1.0 for i in range(3))
        _quad(meshes[role], f, ratio)
    total = 0
    for role, mesh in meshes.items():
        if mesh.triangles > max_tris_role:
            raise BudgetError(f"{model.name}: role {role} has {mesh.triangles} triangles > {max_tris_role}")
        total += mesh.triangles
    if total > max_tris_model:
        raise BudgetError(f"{model.name}: {total} triangles > {max_tris_model}")
    attrs = dict(model.attrs)
    return ConvertedModel(model.name, model.rarity, model.world, palette, materials, meshes, attrs,
                          True if model.fx else None, model.pose, model.pose_centre, clustered, bbox(model.boxes))
```

Run → `10 passed`. If `test_face_covered_by_union_of_smaller_boxes_is_culled` fails, check the plane rounding (`round(plane, 4)`) — both faces must land on the identical key.

- [ ] **Step 4: Commit**

```bash
git add tools/brainrot_forge/bake.py tools/brainrot_forge/bake_boxes.py tools/brainrot_forge/tests/test_bake_boxes.py
git commit -m "feat(forge): lossless box bake with coverage culling, colour clustering and vertex-colour ratios

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

### Task 4: Exporter, manifest and renderer extensions (`COLOR_0`, extra fields, before/after sheets)

**Files:**
- Modify: `tools/brainrot_forge/export_glb.py`, `tools/brainrot_forge/render.py`, `tools/brainrot_forge/tests/test_export_glb.py`, `tools/brainrot_forge/tests/test_render.py`

**Interfaces:**
- `write_glb`: a mesh with `colors` gets a `COLOR_0` (VEC3 float) attribute; `read_glb` returns `"colors"` (list or `None`).
- `build_manifest`: per model also `attributes` (dict or `{}`), `materials` (`{role: Material}`; defaults to every role = `model.material`), `poseRotation` (9 floats or null), `poseCentre` ([x,y,z] or null), `vertexColors` (bool). `fx` may be `true` (use the existing `BrainrotFX` recipe), a list, or null.
- `render.compare_sheet(pairs, out_dir, prefix, per_sheet=6) -> list[Path]` where `pairs = [(before_model, before_meshes, after_model, after_meshes)]`; each row = before (exact colours) | after (representative colours, i.e. the worst case) | after at pad distance.

- [ ] **Step 1: Failing tests** — append to `tests/test_export_glb.py`:

```python
def test_color0_round_trip_and_manifest_extras(tmp_path):
    from brainrot_forge.bake import Mesh
    m = cube("V")
    meshes = bake(m)
    mesh = meshes["body"]
    mesh.colors = [(1.0, 0.5, 0.25)] * len(mesh.positions)
    path = tmp_path / "vc.glb"
    G.write_glb(path, [(m, meshes)], roblox_forward=False)
    node = G.read_glb(path)["V__body"]
    assert node["colors"] == [(1.0, 0.5, 0.25)] * len(mesh.positions)
    plain = tmp_path / "plain.glb"
    G.write_glb(plain, batch_of(cube()), roblox_forward=False)
    assert G.read_glb(plain)["T__body"]["colors"] is None

    class Converted:  # the ConvertedModel shape, minimal
        name = "Conv"; rarity = "Secret"; world = "Tundra"; pitch = 0.2; motion = "hover"; material = "Plastic"
        palette = {"c00": "#FF0000"}; materials = {"c00": "Neon"}; attributes = {"Tier": "Secret", "HeightScale": 1.46}
        fx = True; pose_rotation = (0, 0, 1, 0, 1, 0, -1, 0, 0); pose_centre = (1.0, 2.0, 3.0); vertex_colors = True
        height_scale = 1.46; width_scale = 1.0
        def size_studs(self): return (1.0, 1.0, 1.0)
    cm = Converted()
    man = G.build_manifest([(cm, {"c00": mesh})])
    e = man["models"]["Conv"]
    assert e["materials"] == {"c00": "Neon"} and e["attributes"]["Tier"] == "Secret" and e["fx"] is True
    assert e["poseRotation"] == [0, 0, 1, 0, 1, 0, -1, 0, 0] and e["poseCentre"] == [1.0, 2.0, 3.0] and e["vertexColors"] is True
    pilot = G.build_manifest(batch_of(cube()))["models"]["T"]
    assert pilot["materials"] == {"body": "Plastic"} and pilot["attributes"] == {} and pilot["poseRotation"] is None and pilot["vertexColors"] is False
```

Append to `tests/test_render.py`:

```python
def test_vertex_colours_darken_and_compare_sheet(tmp_path):
    m, meshes = sample()
    dark = {k: v for k, v in meshes.items()}
    from brainrot_forge.bake import Mesh
    body = meshes["body"]
    darker = Mesh("body", list(body.positions), list(body.normals), list(body.uvs), list(body.indices), [(0.5, 0.5, 0.5)] * len(body.positions))
    dark["body"] = darker
    bright = list(R.render_model(m, meshes, size=128).get_flattened_data())
    dim = list(R.render_model(m, dark, size=128).get_flattened_data())
    assert sum(p[0] for p in dim) < sum(p[0] for p in bright) * 0.8
    paths = R.compare_sheet([(m, meshes, m, dark)], tmp_path, "batch1", per_sheet=6)
    assert [p.name for p in paths] == ["batch1_sheet1.png"] and paths[0].stat().st_size > 0
```

Run both files → the new tests fail (`KeyError: 'colors'`, `AttributeError: compare_sheet`).

- [ ] **Step 2: `export_glb.py` changes**

In `write_glb`, after `t_blob`/before `i_blob`, add:
```python
            c_blob = b"".join(struct.pack("<3f", *c) for c in mesh.colors) if mesh.colors is not None else None
```
and after `a_uv`:
```python
            attributes = {"POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv}
            if c_blob is not None:
                attributes["COLOR_0"] = accessor(view(c_blob, _ARRAY_BUFFER), _FLOAT, len(mesh.colors), "VEC3")
```
and use `"attributes": attributes` in the primitive. In `read_glb`, set `"colors": read(prim["attributes"]["COLOR_0"]) if "COLOR_0" in prim["attributes"] else None`. In `build_manifest`, extend the per-model dict:
```python
            "attributes": dict(getattr(model, "attributes", {}) or {}),
            "materials": dict(getattr(model, "materials", None) or {role: model.material for role in role_meshes}),
            "poseRotation": list(model.pose_rotation) if getattr(model, "pose_rotation", None) else None,
            "poseCentre": list(model.pose_centre) if getattr(model, "pose_centre", None) else None,
            "vertexColors": bool(getattr(model, "vertex_colors", False)),
```

- [ ] **Step 3: `render.py` changes**

In `_triangles`, apply per-vertex ratios:
```python
        for i in range(0, len(mesh.indices), 3):
            ids = mesh.indices[i:i + 3]
            colour = rgb
            if mesh.colors is not None:
                k = mesh.colors[ids[0]]
                colour = (rgb[0] * k[0], rgb[1] * k[1], rgb[2] * k[2])
            yield [mesh.positions[j] for j in ids], mesh.normals[ids[0]], colour
```
Add:
```python
def compare_sheet(pairs, out_dir, prefix: str, per_sheet: int = 6) -> list[Path]:
    """Rows of before (exact colours) | after (representative colours) | after at pad distance."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    paths: list[Path] = []
    for s in range(0, len(pairs), per_sheet):
        chunk = pairs[s:s + per_sheet]
        sheet = Image.new("RGB", (300 + 300 + 220, 300 * len(chunk)), SKY)
        d = ImageDraw.Draw(sheet)
        for i, (bm, bk, am, ak) in enumerate(chunk):
            y = 300 * i
            sheet.paste(render_model(bm, bk, 300), (0, y))
            sheet.paste(render_model(am, ak, 300), (300, y))
            sheet.paste(render_plot_tile(am, ak), (610, y + 50))
            d.text((6, y + 4), f"{am.name}: BEFORE (parts, exact)", fill=(20, 20, 30))
            d.text((306, y + 4), "AFTER (mesh, flat colours = worst case)", fill=(20, 20, 30))
            d.text((614, y + 30), "pad distance", fill=(20, 20, 30))
        p = out_dir / f"{prefix}_sheet{s // per_sheet + 1}.png"
        sheet.save(p)
        paths.append(p)
    return paths
```

Run the full suite → all green (`50 + 1 + 1 + 5 + 10 = 67 passed`).

- [ ] **Step 4: Commit**

```bash
git add tools/brainrot_forge/export_glb.py tools/brainrot_forge/render.py tools/brainrot_forge/tests/test_export_glb.py tools/brainrot_forge/tests/test_render.py
git commit -m "feat(forge): COLOR_0 export/import, manifest extras (materials/attributes/pose/vertexColors), before-after sheets

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

### Task 5: `convert.py` + CLI — dumps → four batches with sheets and a vertex-colour probe

**Files:**
- Create: `tools/brainrot_forge/convert.py`, `tools/brainrot_forge/tests/test_convert.py`
- Modify: `tools/brainrot_forge/__main__.py` (add the `convert` sub-command)

**Interfaces:**
- `convert.load_models(dump_dir) -> list[PartModel]` (all `group*.json`, sorted by name), `convert.probe() -> ConvertedModel` named `__ForgeProbe_VertexColor` (one role `probe`, rep `#FFFFFF`, 6 face colours as ratios), `convert.convert_all(dump_dir, out_dir, batches=4) -> list[dict]` (per-model rows: name, batch, boxes, roles, triangles, vertexColors, posed, fx), writing `convert_batch<i>.glb`, `manifest_batch<i>.json`, `previews/batch<i>_sheet<k>.png`; CLI `python -m brainrot_forge convert [--dump out/convert/dump] [--out out/convert] [--batches 4]`.

- [ ] **Step 1: Failing test** — `tools/brainrot_forge/tests/test_convert.py`

```python
import json
from brainrot_forge import convert as C


def write_fake_dump(tmp_path):
    grad = {"name": "Grad Fish", "rarity": "Rare", "world": "Tundra", "attrs": {"HeightScale": 1.25, "Tier": "Rare"}, "fx": False,
            "parts": [[i * 1.0, 0.5, 0, 1, 1, 1, "%02X4040" % (255 - i * 12), "P"] for i in range(15)]}
    R = [0, 0, 1, 0, 1, 0, -1, 0, 0]
    tilted = {"name": "Tilted Ray", "rarity": "Epic", "world": "Tundra", "attrs": {"HeightScale": 1.3}, "fx": True,
              "parts": [[0, 0.5, 0, 1, 1, 3, "3060A0", "P", R], [0, 1.5, 0, 1, 1, 1, "FFFFFF", "N", R]]}
    plain = {"name": "Plain Cube", "rarity": "Common", "world": "Valley", "attrs": {}, "fx": False,
             "parts": [[0, 0.5, 0, 1, 1, 1, "A0A0A0", "P"]]}
    d = tmp_path / "dump"; d.mkdir()
    (d / "group1.json").write_text(json.dumps([grad, tilted]))
    (d / "group2.json").write_text(json.dumps([{"type": "text", "text": json.dumps([plain])}]))
    return d


def test_convert_all_writes_batches_with_probe(tmp_path):
    d = write_fake_dump(tmp_path)
    out = tmp_path / "out"
    rows = C.convert_all(d, out, batches=2)
    assert [r["name"] for r in rows] == ["Grad Fish", "Plain Cube", "Tilted Ray"]
    m1 = json.loads((out / "manifest_batch1.json").read_text())
    m2 = json.loads((out / "manifest_batch2.json").read_text())
    assert "__ForgeProbe_VertexColor" in m1["models"] and "__ForgeProbe_VertexColor" not in m2["models"]
    assert m1["robloxForward"] is True
    grad = m1["models"]["Grad Fish"]
    assert grad["vertexColors"] is True and len(grad["parts"]) == 12 and grad["attributes"]["Tier"] == "Rare"
    tilted = m2["models"]["Tilted Ray"]
    assert tilted["poseRotation"] == [0, 0, 1, 0, 1, 0, -1, 0, 0] and tilted["poseCentre"] is not None and tilted["fx"] is True
    assert sorted(tilted["materials"].values()) == ["Neon", "Plastic"]
    assert (out / "convert_batch1.glb").stat().st_size > 0 and (out / "convert_batch2.glb").stat().st_size > 0
    assert (out / "previews" / "batch1_sheet1.png").exists() and (out / "previews" / "batch2_sheet1.png").exists()
    assert {r["batch"] for r in rows} == {1, 2}
```

Run → `ModuleNotFoundError`.

- [ ] **Step 2: Write `tools/brainrot_forge/convert.py`**

```python
"""convert.py — Studio part dumps -> forge batches (glb + manifest + before/after sheets).

Batch 1 also carries __ForgeProbe_VertexColor: a unit cube whose six faces differ only by COLOR_0.
After the import, BrainrotForge's probe check reads that mesh back with CreateEditableMeshAsync
(allowed: we uploaded it) to learn whether Roblox kept vertex colours. Either way the exported
bodies are correct: exact shades if kept, flat representatives (the sheets' AFTER column) if not.
"""
from __future__ import annotations

import glob
import json
from pathlib import Path

from .bake import Mesh
from .bake_boxes import ConvertedModel, bake_boxes
from .export_glb import build_manifest, write_glb
from .ingest_parts import PartModel, load_dump, unpose
from .render import compare_sheet

PROBE_NAME = "__ForgeProbe_VertexColor"


def load_models(dump_dir: str | Path) -> list[PartModel]:
    models: list[PartModel] = []
    for p in sorted(glob.glob(str(Path(dump_dir) / "group*.json"))):
        models.extend(load_dump(p))
    models.sort(key=lambda m: m.name)
    return models


def probe() -> ConvertedModel:
    mesh = Mesh("probe", colors=[])
    faces = [  # axis, sign, ratio
        (2, -1, (1.0, 0.0, 0.0)), (2, 1, (0.0, 1.0, 0.0)), (0, 1, (0.0, 0.0, 1.0)),
        (0, -1, (1.0, 1.0, 0.0)), (1, 1, (0.0, 1.0, 1.0)), (1, -1, (1.0, 0.0, 1.0)),
    ]
    other = {0: (1, 2), 1: (2, 0), 2: (0, 1)}
    for axis, sign, ratio in faces:
        ua, va = other[axis]
        n = [0.0, 0.0, 0.0]; n[axis] = float(sign)
        corners = []
        for (u, v) in ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)):
            p = [0.0, 0.0, 0.0]; p[axis] = 1.0 if sign > 0 else 0.0; p[ua] = u; p[va] = v
            corners.append((p[0], p[1], p[2]))
        a, b, c = corners[0], corners[1], corners[2]
        ab = (b[0] - a[0], b[1] - a[1], b[2] - a[2]); ac = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        cr = (ab[1] * ac[2] - ab[2] * ac[1], ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0])
        if cr[0] * n[0] + cr[1] * n[1] + cr[2] * n[2] < 0:
            corners = [corners[0], corners[3], corners[2], corners[1]]
        base = len(mesh.positions)
        for pos in corners:
            mesh.positions.append(pos); mesh.normals.append((n[0], n[1], n[2])); mesh.uvs.append((0.0, 0.0)); mesh.colors.append(ratio)
        mesh.indices.extend((base, base + 1, base + 2, base, base + 2, base + 3))
    return ConvertedModel(PROBE_NAME, "Common", "Probe", {"probe": "#FFFFFF"}, {"probe": "SmoothPlastic"}, {"probe": mesh},
                          {}, None, None, None, True, ((0, 0, 0), (1, 1, 1)))


def _chunks(items, n):
    size = -(-len(items) // n)
    return [items[i:i + size] for i in range(0, len(items), size)]


def convert_all(dump_dir: str | Path, out_dir: str | Path, batches: int = 4) -> list[dict]:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    models = [unpose(m) for m in load_models(dump_dir)]
    rows: list[dict] = []
    for bi, chunk in enumerate(_chunks(models, batches), 1):
        after = [bake_boxes(m) for m in chunk]
        before = [bake_boxes(m, exact=True) for m in chunk]
        batch = [(cm, cm.meshes) for cm in after]
        if bi == 1:
            pr = probe()
            batch.insert(0, (pr, pr.meshes))
        write_glb(out / f"convert_batch{bi}.glb", batch)
        (out / f"manifest_batch{bi}.json").write_text(json.dumps(build_manifest(batch), indent=2))
        compare_sheet([(b, b.meshes, a, a.meshes) for b, a in zip(before, after)], out / "previews", f"batch{bi}")
        for m, cm in zip(chunk, after):
            rows.append({"name": m.name, "batch": bi, "boxes": len(m.boxes), "roles": len(cm.meshes),
                         "triangles": sum(x.triangles for x in cm.meshes.values()), "vertexColors": cm.vertex_colors,
                         "posed": cm.pose_rotation is not None, "fx": bool(cm.fx)})
    return rows
```

Add to `__main__.py` (a `convert` sub-parser and branch):
```python
    c = sub.add_parser("convert")
    c.add_argument("--dump", default="out/convert/dump")
    c.add_argument("--out", default="out/convert")
    c.add_argument("--batches", type=int, default=4)
    ...
    if a.cmd == "convert":
        from .convert import convert_all
        rows = convert_all(a.dump, a.out, a.batches)
        print(f"{'name':<34} {'batch':>5} {'boxes':>6} {'roles':>5} {'triangles':>9} {'vcol':>5} {'posed':>5} {'fx':>3}")
        for r in rows:
            print(f"{r['name']:<34} {r['batch']:>5} {r['boxes']:>6} {r['roles']:>5} {r['triangles']:>9} {str(r['vertexColors']):>5} {str(r['posed']):>5} {str(r['fx']):>3}")
        return 0
```

Run the suite → all green. Then the real run:

```bash
cd tools && python -m brainrot_forge convert
```

Expected: 66 rows, 4 batches (~17 each), no `BudgetError`; `out/convert/previews/batch1_sheet1..3.png` etc. If a body trips the 12,000 / 4,000 triangle gate, raise the gate for that run (`bake_boxes(..., max_tris_model=...)` via a `--max-tris` flag) and record the number — do not drop geometry.

- [ ] **Step 3: Commit**

```bash
git add tools/brainrot_forge/convert.py tools/brainrot_forge/__main__.py tools/brainrot_forge/tests/test_convert.py
git commit -m "feat(forge): convert command — part dumps to four import batches with before/after sheets and a vertex-colour probe

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

### Task 6: Assembler additions (per-role material, attributes, pose, `fx = true`, backup folder, probe skip)

**Files:**
- Modify: `game-src/BrainrotForge.lua` and `ServerStorage.BrainrotForge` (identical edits, anchored on the current text).

**Interfaces:**
- `M.Assemble(root, manifestJson, opts)` gains `opts.backupFolder` (name of a folder under `ServerStorage.AuditBackups`; replaced originals move there keeping their names) and skips manifest entries whose name starts with `__ForgeProbe`. `M.AssembleOne` reads `entry.materials[role]` (`"Plastic"` → tile, `"Neon"`, `"SmoothPlastic"`, any other Material name), sets every `entry.attributes` key, applies `entry.poseRotation` about `entry.poseCentre`, and treats `entry.fx == true` as "apply the existing recipe".

- [ ] **Step 1: Edit the mirror** (`game-src/BrainrotForge.lua`) — four anchored replacements:

(a) material per role — replace
```lua
		if tile then
			p.Material = Enum.Material.Plastic       -- BrainrotTile.BaseMaterial; a variant is ignored on any other Material
			p.MaterialVariant = M.TILE_VARIANT
		else
			p.Material = Enum.Material.SmoothPlastic
			p.MaterialVariant = ""
		end
```
with
```lua
		local matName = (entry.materials and entry.materials[role]) or (entry.material == "SmoothPlastic" and "SmoothPlastic") or "Plastic"
		if matName == "Plastic" and tile then
			p.Material = Enum.Material.Plastic       -- BrainrotTile.BaseMaterial; a variant is ignored on any other Material
			p.MaterialVariant = M.TILE_VARIANT
		else
			local okM = pcall(function() p.Material = Enum.Material[matName] end)
			if not okM then p.Material = Enum.Material.SmoothPlastic end
			p.MaterialVariant = ""
		end
```

(b) pose — replace
```lua
	local cf, size = model:GetBoundingBox()
	local rootPart = Instance.new("Part")
```
with
```lua
	if entry.poseRotation and entry.poseCentre then
		-- re-apply the rigid rotation unpose() removed for the bake, about the same pivot
		local r, c = entry.poseRotation, entry.poseCentre
		local R = CFrame.new(0, 0, 0, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
		local pose = CFrame.new(c[1], c[2], c[3]) * R * CFrame.new(-c[1], -c[2], -c[3])
		for _, p in ipairs(model:GetChildren()) do
			if p:IsA("BasePart") then p.CFrame = pose * p.CFrame end
		end
	end
	local cf, size = model:GetBoundingBox()
	local rootPart = Instance.new("Part")
```

(c) attributes — replace
```lua
	model:SetAttribute("HeightScale", entry.heightScale or 1)
	model:SetAttribute("WidthScale", entry.widthScale or 1)
```
with
```lua
	for k, v in pairs(entry.attributes or {}) do model:SetAttribute(k, v) end
	model:SetAttribute("HeightScale", entry.heightScale or 1)
	model:SetAttribute("WidthScale", entry.widthScale or 1)
```

(d) backup folder + probe skip — in `M.Assemble` replace
```lua
	for _, name in ipairs(names) do
		local entry = manifest.models[name]
		local existing = folder:FindFirstChild(name)
		if existing and not opts.replace then
```
with
```lua
	for _, name in ipairs(names) do
		local entry = manifest.models[name]
		local existing = folder:FindFirstChild(name)
		if name:sub(1, 12) == "__ForgeProbe" then
			print("BrainrotForge: probe " .. name .. " left in the import group (not a template)")
		elseif existing and not opts.replace then
```
and replace
```lua
				if existing then
					local backups = ServerStorage:FindFirstChild(M.BACKUP_FOLDER) or Instance.new("Folder")
					backups.Name = M.BACKUP_FOLDER
					backups.Parent = ServerStorage
					existing.Name = ("BrainrotForge_%s_%s"):format(name, os.date("%Y-%m-%d"))
					existing.Parent = backups
				end
```
with
```lua
				if existing then
					local backups = ServerStorage:FindFirstChild(M.BACKUP_FOLDER) or Instance.new("Folder")
					backups.Name = M.BACKUP_FOLDER
					backups.Parent = ServerStorage
					if given.backupFolder then
						local sub = backups:FindFirstChild(given.backupFolder) or Instance.new("Folder")
						sub.Name = given.backupFolder
						sub.Parent = backups
						existing.Parent = sub            -- keeps its own name inside the batch folder
					else
						existing.Name = ("BrainrotForge_%s_%s"):format(name, os.date("%Y-%m-%d"))
						existing.Parent = backups
					end
				end
```
(`given` is the raw opts table already captured at the top of `Assemble`.)

- [ ] **Step 2: Apply the same four edits live** with `multi_edit` on `game.ServerStorage.BrainrotForge` (same `old_string`/`new_string` pairs), then byte-parity: `return #game.ServerStorage.BrainrotForge.Source` must equal `wc -c game-src/BrainrotForge.lua`.

- [ ] **Step 3: Synthetic test (`execute_luau`, Edit)**

```lua
local RS, SS = game:GetService("ReplicatedStorage"), game:GetService("ServerStorage")
local HS = game:GetService("HttpService")
local F = loadstring(SS.BrainrotForge.Source)()
local root = Instance.new("Model"); root.Name = "__ForgeTest_AuxScene"; root.Parent = workspace
local function fake(name, size, pos)
	local p = Instance.new("Part"); p.Name = name; p.Size = size; p.Position = pos; p.Anchored = false; p.Parent = root; return p
end
fake("Forge Test__body", Vector3.new(4, 6, 2), Vector3.new(0, 3, 0)); fake("Forge Test__glow", Vector3.new(1, 1, 0.2), Vector3.new(1, 5, -1.1))
fake("__ForgeProbe_VertexColor__probe", Vector3.new(1, 1, 1), Vector3.new(10, 0.5, 0))
local manifest = [[{"version":1,"pitch":0.2,"robloxForward":true,"models":{
"Forge Test":{"rarity":"Secret","world":"Tundra","roles":{"body":"#3060A0","glow":"#FFFFFF"},"materials":{"body":"Plastic","glow":"Neon"},"parts":["Forge Test__body","Forge Test__glow"],"heightScale":1.2,"widthScale":1,"motion":"hover","material":"Plastic","fx":null,"attributes":{"Tier":"Secret","PaletteV3":"ice","HeightScale":1.2},"poseRotation":[0,0,1,0,1,0,-1,0,0],"poseCentre":[0,3,0],"vertexColors":true,"bbox":[4,6,2.1],"triangles":{"body":12,"glow":12},"totalTriangles":24},
"__ForgeProbe_VertexColor":{"rarity":"Common","world":"Probe","roles":{"probe":"#FFFFFF"},"materials":{"probe":"SmoothPlastic"},"parts":["__ForgeProbe_VertexColor__probe"],"heightScale":1,"widthScale":1,"motion":"hover","material":"Plastic","fx":null,"attributes":{},"poseRotation":null,"poseCentre":null,"vertexColors":true,"bbox":[1,1,1],"triangles":{"probe":12},"totalTriangles":12}}}]]
local models, errors = F.Assemble(root, manifest, { tile = true, backupFolder = "__ForgeTest_Backup" })
local m = models["Forge Test"]
assert(m and next(errors) == nil, HS:JSONEncode(errors))
assert(not models["__ForgeProbe_VertexColor"] and root:FindFirstChild("__ForgeProbe_VertexColor__probe"), "probe must be skipped and left in place")
assert(m.body.Material == Enum.Material.Plastic and m.body.MaterialVariant == "BrainrotTile", "body tile")
assert(m.glow.Material == Enum.Material.Neon and m.glow.MaterialVariant == "", "glow neon")
assert(m:GetAttribute("Tier") == "Secret" and m:GetAttribute("PaletteV3") == "ice" and m:GetAttribute("HeightScale") == 1.2, "attributes")
-- pose: a 90-degree yaw about (0,3,0) moves the glow from (1,5,-1.1) to (-1.1,5,-1)
local g = m.glow.Position
assert(math.abs(g.X - -1.1) < 0.01 and math.abs(g.Z - -1) < 0.01, "pose not applied: " .. tostring(g))
-- replace into the batch backup folder, keeping the original's name
fake("Forge Test__body", Vector3.new(4, 6, 2), Vector3.new(0, 3, 0)); fake("Forge Test__glow", Vector3.new(1, 1, 0.2), Vector3.new(1, 5, -1.1))
local m2 = F.Assemble(root, manifest, { tile = true, replace = true, backupFolder = "__ForgeTest_Backup" })["Forge Test"]
local sub = SS.AuditBackups:FindFirstChild("__ForgeTest_Backup")
assert(m2 and sub and sub:FindFirstChild("Forge Test") == m, "backup folder should hold the original under its own name")
m2:Destroy(); root:Destroy(); sub:Destroy()
assert(not RS.BrainrotModels:FindFirstChild("Forge Test"))
return "OK"
```

Expected `"OK"`; `search_game_tree` for `Forge Test` / `ForgeTest` finds nothing afterwards.

- [ ] **Step 4: Commit**

```bash
git add game-src/BrainrotForge.lua
git commit -m "feat(studio): BrainrotForge per-role materials, attributes, pose re-apply, batch backup folder, probe skip

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

### Task 7: The four import batches (gate → import → assemble → verify), one at a time

Repeat for `i = 1..4`:

- [ ] **Step 1: USER GATE** — send `tools/out/convert/previews/batch<i>_sheet*.png` (`SendUserFile`, render). The AFTER column is the worst case (flat representative colours). Wait for approval; a rejected body is fixed by raising its role budget for that body (`bake_boxes(m, max_roles=...)` with a per-name override in `convert.py`) and re-running `convert`.

- [ ] **Step 2: USER STEP** — File → Import (Ctrl+M) → `C:\Users\m\Coding\skip-a-brainrot\tools\out\convert\convert_batch<i>.glb` → defaults → Import. The group lands as `Workspace.convert_batch<i>`.

- [ ] **Step 3: Sanity (`execute_luau`)** — count `MeshPart`s under `Workspace.convert_batch<i>` (must equal the manifest's total parts, +1 for the probe in batch 1), every `MeshId ~= ""`.

- [ ] **Step 4 (batch 1 only): vertex-colour probe**

```lua
local AS = game:GetService("AssetService")
local probe
for _, d in ipairs(workspace.convert_batch1:GetDescendants()) do if d:IsA("MeshPart") and d.Name == "__ForgeProbe_VertexColor__probe" then probe = d end end
assert(probe, "probe mesh missing")
local ok, res = pcall(function()
	local em = AS:CreateEditableMeshAsync(Content.fromUri(probe.MeshId))
	local n = #em:GetColors()
	em:Destroy()
	return n
end)
return ("probe MeshId=%s colourCount=%s (%s)"):format(probe.MeshId, tostring(res), ok and "ok" or "ERR")
```

Record the result in the execution log: `colourCount > 0` → the importer keeps `COLOR_0` (gradient bodies render exactly); `0` or an error → flat representatives (the approved worst case).

- [ ] **Step 5: Assemble (`execute_luau`)** — manifest pasted inside `[==[ ... ]==]`:

```lua
local SS = game:GetService("ServerStorage")
local MANIFEST = [==[<contents of tools/out/convert/manifest_batch<i>.json>]==]
local F = loadstring(SS.BrainrotForge.Source)()
local models, errors = F.Assemble(workspace["convert_batch<i>"], MANIFEST, { tile = true, replace = true, backupFolder = "BrainrotModels_PreForge_2026-09-17" })
local n = 0 for _ in pairs(models) do n += 1 end
return game:GetService("HttpService"):JSONEncode({ assembled = n, errors = errors })
```

Expected: `assembled` = the batch's model count, `errors = {}`, every review printed `[PASS]`.

- [ ] **Step 6: Verify the batch (`execute_luau`)** — for every name in the manifest: budget verdict, bbox of the new template vs its backup within 2 % on each axis, `MeshParts == #roles`, all `MeshId ~= ""`, `HeightScale` equal to the backup's:

```lua
local RS, SS = game:GetService("ReplicatedStorage"), game:GetService("ServerStorage")
local HS = game:GetService("HttpService")
local B = loadstring(SS.BrainrotBudget.Source)()
local backup = SS.AuditBackups["BrainrotModels_PreForge_2026-09-17"]
local NAMES = { "<names of this batch>" }
local out, bad = {}, 0
for _, n in ipairs(NAMES) do
	local m, old = RS.BrainrotModels:FindFirstChild(n), backup:FindFirstChild(n)
	assert(m and old, n)
	local _, s1 = m:GetBoundingBox(); local _, s0 = old:GetBoundingBox()
	local dev = math.max(math.abs(s1.X - s0.X) / s0.X, math.abs(s1.Y - s0.Y) / s0.Y, math.abs(s1.Z - s0.Z) / s0.Z)
	local meshes, blank = 0, 0
	for _, d in ipairs(m:GetDescendants()) do if d:IsA("MeshPart") then meshes += 1 if d.MeshId == "" then blank += 1 end end end
	local v = B.compare(m).verdict
	if v ~= "PASS" or dev > 0.02 or blank > 0 or m:GetAttribute("HeightScale") ~= old:GetAttribute("HeightScale") then bad += 1 end
	out[#out + 1] = ("%-32s %s bboxDev=%.3f meshes=%d blank=%d hs=%s"):format(n, v, dev, meshes, blank, tostring(m:GetAttribute("HeightScale")))
end
return ("bad=%d\n"):format(bad) .. table.concat(out, "\n")
```

Expected `bad=0`. Note: hidden FX hosts sit inside the bbox, so bbox parity is exact for bodies with effects too. Then delete `Workspace.convert_batch<i>` (batch 1: after the probe check).

### Task 8: Retire the plot LODs, Play spot check, triangles

- [ ] **Step 1: Retire the 43 LOD copies (`execute_luau`, Edit)** — only after all four batches report `bad=0`:

```lua
local RS, SS = game:GetService("ReplicatedStorage"), game:GetService("ServerStorage")
local backups = SS:FindFirstChild("AuditBackups")
local sub = Instance.new("Folder"); sub.Name = "BrainrotModelsPlot_PreForge_2026-09-17"; sub.Parent = backups
local n = 0
for _, m in ipairs(RS.BrainrotModelsPlot:GetChildren()) do m.Parent = sub; n += 1 end
return ("moved %d LOD models; BrainrotModelsPlot now has %d children (spawner falls through to BrainrotModels)"):format(n, #RS.BrainrotModelsPlot:GetChildren())
```

Expected: moved 43, 0 left. (`BrainrotSpawner.templateFor` treats an empty folder as a miss — verified in its source.)

- [ ] **Step 2: Play spot check** — re-create the request-driven harness from the Phase-1 log (Edit mode `multi_edit`, className Script) with specs `{ "Valanga Ruggente" }, { "Inverno Eterno" }, { "Orcarella Bibitona" }, { "Narvalino Trapanino" }, { "Secret Pete" }, { "Aurora Serpentina", "Golden" }`; wait ≥ 90 s since the last playtest; Play; request the free Tundra plot farthest from the character; park the character 55 studs outside that camp; run the Phase-1 client check (blank MeshIds = 0, welds, tags, tile, sizes vs HeightScale) and the LOD probe on Inverno Eterno; stop Play; delete the harness.

- [ ] **Step 3: Triangles (Studio in the foreground)** — `BrainrotBudget.triangles` twice (warm-up) on Valanga Ruggente, Inverno Eterno, Orcarella Bibitona, Narvalino Trapanino, Secret Pete, Aurora Serpentina; expected within ±15 % of the Part-built numbers where measured (Valanga 8,196) — lossless geometry means the same triangles in ~10 draw calls instead of ~1,100 instances.

### Task 9: Closeout

- [ ] Studio cleanup: no `convert_batch*`, `__Forge*` objects left; `BrainrotModels` count still 218; `BrainrotModelsPlot` empty; two backup folders populated (66 + 43).
- [ ] Docs: `docs/brainrot-build-standard.md` §1.2/§1.3 — add a line that the 66 voxel originals are now forge meshes (Part-built population 0; `Chim` primitive and `Maxwell` static mesh remain), §4 add the converted samples; `game-src/README.md` one line; this plan's execution log (probe result, per-batch `bad=0` outputs, spot check, triangle table, objects touched, "UNSAVED until the owner saves").
- [ ] Commit docs; update memory notes (`skip-rocks-brainrot-construction-audit`: conversion done; gotchas learned).
- [ ] Report to the user: what changed, the probe outcome, the two backup folders, the save reminder, and that the owner's "authored everywhere" now costs pack-level instances on every plot.

---

## Self-review

- **Spec coverage:** dump channel (Task 1) → ingest/unpose (2) → lossless bake + clustering + vertex ratios (3) → COLOR_0/manifest/sheets (4) → batches + probe (5) → assembler fields + backup folder (6) → gated imports + parity checks (7) → LOD retirement, Play, triangles (8) → docs/log (9). Chim/Maxwell exclusion is in the group query (Task 1 Step 2).
- **Placeholders:** the only substitutions are the per-batch name lists and manifest pastes, each produced by an earlier step.
- **Type consistency:** `PartModel.pose`/`pose_centre` → `ConvertedModel.pose_rotation`/`pose_centre` → manifest `poseRotation`/`poseCentre` → assembler `entry.poseRotation`/`entry.poseCentre`; `materials {role: name}` and `attributes` use the same keys end to end; role names `cNN` are the same in palette, materials, meshes and part names.
---

## Execution log (2026-09-17/18, inline execution)

### Deviations from the plan as written (all resolved)
- **65, not 66:** the "66 voxel" population counted `Chim` (34 primitive parts, excluded by design). 65 Part-built bodies were dumped (20 groups, 20,095 parts) and converted.
- **Dump channel:** `execute_luau` results under ~50 KB are not persisted and over 100 KB are truncated, so each group call is padded to exactly 98,000 chars; the persisted file is raw text or the `[{"type":"text","text":...}]` wrapper, and `load_dump` accepts both.
- **Un-pose math sign:** the plan's `test_unpose_shared_rotation` expected `R^T (2,0,0) = (0,0,-2)`; it is `(0,0,+2)`. Fixed in the test (round-trip assertion added), implementation unchanged.
- **Per-role triangle gate raised 4,000 → 5,000 for the run** (`--max-tris-role 5000`, the plan's own remedy): Fanghetto Palunko (4,288), Iglu Mangione (4,846), Inverno Eterno (4,546), Kraken Congelato (4,266) and Valanga Ruggente (4,246) each have one colour carrying most of the body. Whole-body totals 460–9,934, all under the 12,000 gate. No geometry dropped.
- **Contact sheets' AFTER column** renders with `COLOR_0` stripped (`render._flat`) so it is the true worst case; the first cut had applied the ratios and looked identical to BEFORE.
- **Posed bodies (Focarella, Martellone, Narvalino, Pippo Olivardino):** re-applying the rotation in the assembler left the RootPart tilted (a fresh `Model`'s pivot takes its first part's orientation; `GetBoundingBox` follows it) — Focarella's box read +51 % in Y, the axis the spawner scales by. Fixed twice over: `bake_boxes.repose()` bakes the tilt into the vertices after the un-tilted bake (MeshParts land unrotated with the exact AABB of the tilted body; manifests carry `poseRotation: null`), and `BrainrotForge.AssembleOne` resets `model.WorldPivot` to identity before building the RootPart. Focarella was re-done in batch 2 (`convert --move "Focarella Ballonzolo=2"`; the interim template was deleted before assembly, the original stayed in the backup folder).
- **Invisible-scaffold cap 3 → 4** in `BrainrotBudget.RANGES` and the standard §2.1: RootPart + the three `BrainrotFX` hosts is 4 on Balena Polare, Balenone, Martellone, Nave Rompighiaccio, Orcarella, Squalone — exactly what their originals had; the old cap contradicted §2.4 (pack p90 is 6).
- **Secret Pete's skull:** the original carried a hand-authored sparkle `ParticleEmitter` and a `PointLight` on its `skull` part, outside `BrainrotFX`. The emitter was cloned onto an invisible `BrainrotFxSkull` host at the skull's position (emitters 7/7 again); the **PointLight was not carried over** — lights are forbidden by the standard (§2.1/§3) and were the owner's "super laggy" class. No other original had anything outside geometry + FX hosts (scanned: emitters, lights, beams, trails, decals, textures, guis, sounds, scripts, attachments, constraints, tags, part attributes, semi-transparent/reflective/non-block parts — none).
- `FxVersion` is not copied from the dump's attributes (BrainrotFX.apply sets it).
- **Gate reading:** the spec's "PASS on all 66" is read as "no FAIL" — bodies with 12 MeshParts or any Neon grade WARN by construction (PASS is ≤ 11 parts and 0 Neon; Aurora Serpentina's original had 679 Neon parts). Final: 8 PASS, 57 WARN, 0 FAIL.
- Batches 3 and 4 were imported by the user before their sheets were reviewed; both were assembled and verified, and the sheets remain in `tools/out/convert/previews/` for the look check (any body can be reverted from the backup folder).
- The plan's "search_game_tree for residue" step is useless (the tool dumps the tree); residue was checked with an `execute_luau` name sweep instead.

### Task 1 — dumps
20 groups → `tools/out/convert/dump/group01..20.json`, 65 models, 65 unique, 20,095 parts (Plastic 18,368 / Neon 1,727; 94 distinct part sizes). Four bodies carry one shared rotation on every part: Focarella 40°, Martellone 42°, Narvalino 48° (about X) and Pippo Olivardino (180° about Y).

### Tasks 2–6 — pipeline
Suite: **74 passed** (`tools/`: `python -m pytest brainrot_forge -q`). `python -m brainrot_forge convert --max-tris-role 5000 --move "Focarella Ballonzolo=2"` → 4 batches (17 + probe / 18 / 17 / 14 bodies; 113 + 1 / 141 / 146 / 102 MeshParts; 3.9 / 4.2 / 3.4 / 3.0 MB), 12 sheets. Dry-run profile: faces kept 230–4,967 per body; 25 bodies needed colour clustering (15–64 shades → 12 roles). Assembler edits applied to the mirror and live (`BrainrotForge` 9,162 bytes, byte parity; synthetic test `OK`).

### Task 7 — the four batches
- **Vertex-colour probe (batch 1):** `CreateEditableMeshAsync` on our own `__ForgeProbe_VertexColor__probe` upload → **24 colours, 6 distinct face colours, values exact** (1,0,0 / 0,1,0 / …). **Roblox's Import 3D keeps `COLOR_0`**, so clustered bodies render their exact shades; the sheets' flat AFTER column was only the worst case.
- Batch 1: 125/125 meshes, assembled 17, errors {}, **bad=0** (2 PASS / 15 WARN); Focarella at dev 0.099 was excluded and re-done in batch 2.
- Batch 2: 141/141, assembled 18, errors {}, **bad=0** (2 PASS / 16 WARN); Focarella now dev 0.000.
- Batch 3: 146/146, assembled 17, errors {}, **bad=0** (2 PASS / 15 WARN).
- Batch 4: 102/102, assembled 14, errors {}, **bad=0** after the Secret Pete skull emitter was carried over (2 PASS / 12 WARN).
- Every body: bounding box within 0.000 of its original on all three axes, RootPart upright, `HeightScale`/`Tier` equal, blank MeshIds 0, FX emitter count equal to the original's, tile on every Plastic role, Neon on every Neon role.

### Task 8 — LODs, Play, triangles
- 43 LOD models moved to `ServerStorage.AuditBackups.BrainrotModelsPlot_PreForge_2026-09-17` (every LOD name verified to have a mesh template first); `BrainrotModelsPlot` = 0 children; `BrainrotSpawner.templateFor` falls through to `BrainrotModels`.
- Play round (Plot7, unclaimed Tundra plot 11,523 studs from the spawn; character parked 55 studs outside the camp): all six spawned through the real `BrainrotSpawner.Spawn`. Client DataModel: blankMeshIds 0 on all six; root anchored + every other part unanchored and welded (welds == unanchored); `BrainrotBody` tag; Motion hover; tiles on Plastic roles, Neon on Neon roles; heights at the spawner's fit Valanga 8.2 / Inverno 9.0 / Orcarella 6.1 / Narvalino 7.6 / Secret Pete 8.3 (width-capped 9.5, as before) / Golden Aurora 8.2 (= 6 × HeightScale within 0.1); `MutationBody` tag + 1 emitter on the Golden. LOD probe on Inverno Eterno: FAR (110 studs) blanked 4/7 parts, emitters 0 on; NEAR (25 studs) blanked 0/7, emitters 6 on. Console: no errors.
- Triangles: **NOT measured** — `BrainrotBudget.triangles` returned `nil` on all six samples because Studio's render counters are frozen unless Studio is the visible window, and the owner did not bring it forward before the session ended. The standard §4 therefore still carries only the pilot and pre-conversion voxel numbers. Geometry is lossless, so the triangle count per body is unchanged by construction (only the draw calls drop, from ~N parts to 2–12); the measurement is a sanity check, not a gate. Re-run: focus the Studio viewport, then `BrainrotBudget.triangles` twice (warm-up) on Valanga Ruggente, Inverno Eterno, Orcarella Bibitona, Narvalino Trapanino, Secret Pete, Aurora Serpentina.

### Studio objects touched (ALL UNSAVED until the owner saves the place)
- Replaced: 65 templates in `ReplicatedStorage.BrainrotModels` (originals → `ServerStorage.AuditBackups.BrainrotModels_PreForge_2026-09-17`, 65 models, names kept). 514 MeshAssets uploaded to the user's account (501 in use; the probe cube and Focarella's first pass are unused).
- Moved: 43 models `ReplicatedStorage.BrainrotModelsPlot` → `ServerStorage.AuditBackups.BrainrotModelsPlot_PreForge_2026-09-17`.
- Edited: `ServerStorage.BrainrotForge` (per-role materials, attributes, pose, backup folder, probe skip, pivot reset), `ServerStorage.BrainrotBudget` (invisibleParts max 4).
- Removed after use: `Workspace.convert_batch1..4`, `ServerStorage.__ForgeDumpSrc_DELETE_ME`, `ServerScriptService.__ForgeSpawnTest_DELETE_ME`. `BrainrotModels` count 218 before and after; `Chim` and `Maxwell` untouched.
