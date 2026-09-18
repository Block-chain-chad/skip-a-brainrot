# Brainrot Forge Pilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Brainrot Forge (voxel design → per-colour baked meshes → one `.glb` → Studio assembler + budget gate) and ship three original Frozen Tundra brainrots through it, verified in-game.

**Architecture:** A stdlib-plus-Pillow Python package under `tools/brainrot_forge/` turns deterministic design scripts into a batch `.glb` + `manifest.json` + preview PNGs; the user imports the `.glb` once via File > Import 3D; two build-time Luau modules in `ServerStorage` (`BrainrotForge`, `BrainrotBudget`) assemble the templates to the content-drop contract and gate them against the measured pack baseline. Game code is untouched except two recipe rows in `BrainrotFX` and three `Weight = 0` roster rows.

**Tech Stack:** Python 3.14, Pillow 12, pytest; Roblox Studio via the `roblox-studio` MCP (`execute_luau`, `multi_edit`, `script_read`, `script_grep`); Luau ModuleScripts mirrored in `game-src/`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-09-17-brainrot-forge-pilot-design.md`; standard: `docs/brainrot-build-standard.md`. Budgets per template (standard §2.1): BaseParts ≤ 20, visible parts ≤ 14, MeshParts ≤ 14, descendants ≤ 80, ParticleEmitters ≤ 8, particles alive ≤ 100, SurfaceAppearance ≤ 1, Neon ≤ 3, beams ≤ 2, **0** trails/lights/highlights/unions/scripts/Motor6D/bones/constraints/humanoids/sounds/guis.
- Bake pre-gate: ≤ 10 roles, ≤ 8,000 triangles per model, ≤ 2,000 per role. Design gate: height 25–45 voxels at pitch 0.2 studs, one role ≥ 40 % of cells, eyes present.
- Lattice: integer cells, y up, feet at y = 0, x/z centred on 0, **front = −Z**. UVs: `u = a / 2`, `v = b / 2` in studs (BrainrotTile: 2 cells per texture, StudsPerTile 2).
- Studio: Model name == config `Name` exactly; parent `ReplicatedStorage.BrainrotModels`; invisible `RootPart` as PrimaryPart; attributes `HeightScale` (Tundra ladder: Epic 1.30 / Legendary 1.36 / Secret 1.46), `WidthScale`; tiled parts `Material = Plastic` + `MaterialVariant = "BrainrotTile"`, untiled `SmoothPlastic`; never write `RenderFidelity`; `CollisionFidelity = Box`; `Anchored = true`, `CanCollide/CanQuery/CanTouch = false`, `CastShadow = false`.
- Roster rows: `{ Name, Rarity, CashPerSecond, Weight = 0, Origin = "Forge" }` — Guantone Brontolone Epic 108000, Alce Lampadario Legendary 230000, Nonno Ghiacciaio Secret 900000 (+ `Motion = "shiver"`).
- Studio edits are anchored on a **fresh `script_read`** of the live script, never on the `game-src` mirror; every edited module is compile-gated with `loadstring(script.Source)`. The place is Team Create and UNSAVED until the owner saves — never claim a Studio change is persisted.
- Git: the branch carries another session's uncommitted edits. Every commit stages **only the paths named in its step** (`git add <paths>`, never `git add -A`). Commit messages end with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- Python commands run from `tools/` (`cd tools`), tests via `python -m pytest brainrot_forge/tests -q`.
- Never write credentials, never call `PDM.Load`, wait ≥ 90 s between Studio playtests (SessionLock), and never call `git add -A`.

## File Structure

| Path | Responsibility |
|---|---|
| `tools/brainrot_forge/__init__.py` | package marker, `__version__` |
| `tools/brainrot_forge/voxel.py` | `VoxelModel` — the design representation, shape helpers, `validate()` |
| `tools/brainrot_forge/bake.py` | exposed-face extraction, greedy rectangles, `Mesh` per role, triangle gate |
| `tools/brainrot_forge/export_glb.py` | glTF 2.0 binary writer, `read_glb` (tests/ingest), manifest builder |
| `tools/brainrot_forge/render.py` | Pillow software renderer: close-up + plot-distance previews, contact sheet |
| `tools/brainrot_forge/designs/__init__.py` | `DESIGNS` registry (`name -> build()`) |
| `tools/brainrot_forge/designs/guantone_brontolone.py` | Epic pilot design |
| `tools/brainrot_forge/designs/alce_lampadario.py` | Legendary pilot design |
| `tools/brainrot_forge/designs/nonno_ghiacciaio.py` | Secret pilot design |
| `tools/brainrot_forge/__main__.py` | CLI: `python -m brainrot_forge build pilot` → `out/pilot/` |
| `tools/brainrot_forge/tests/test_*.py` | pytest suites per module |
| `game-src/BrainrotBudget.lua` | mirror of `ServerStorage.BrainrotBudget` (build-time gate) |
| `game-src/BrainrotForge.lua` | mirror of `ServerStorage.BrainrotForge` (build-time assembler) |
| `game-src/BrainrotFX.lua` | existing mirror; + 2 recipe rows |
| `game-src/place-full/ReplicatedStorage/Modules/BrainrotConfigTundra.lua` | re-mirrored after the roster edit |
| `docs/brainrot-build-standard.md` | §4 filled with measured triangle counts at the end |

---

### Task 1: Package scaffold + `VoxelModel`

**Files:**
- Create: `tools/brainrot_forge/__init__.py`, `tools/brainrot_forge/voxel.py`, `tools/brainrot_forge/tests/__init__.py`, `tools/brainrot_forge/tests/test_voxel.py`, `tools/README.md`

**Interfaces:**
- Produces: `VoxelModel(name, rarity, world="Tundra", pitch=0.2)` with `.role(name, hex)`, `.set(x,y,z,role)`, `.box(x0,x1,y0,y1,z0,z1,role)`, `.stepped_ellipsoid(cx,cy,cz,rx,ry,rz,role)`, `.cylinder_y(cx,cz,r,y0,y1,role)`, `.carve(x0,x1,y0,y1,z0,z1)`, `.keep_above(y_min)`, `.mirror_x()`, `.eyes(centers, z, size, pupil, gaze=(0,0))`, `.bounds() -> ((minx,miny,minz),(maxx,maxy,maxz))`, `.size_voxels()`, `.size_studs()`, `.count_by_role()`, `.front_z()`, `.validate() -> list[str]`; fields `cells: dict[(x,y,z) -> role]`, `palette: dict[role -> "#RRGGBB"]`, `motion`, `fx`, `height_scale`, `width_scale`, `material`. Constants `RARITIES`, `MAX_ROLES = 10`, `MIN_HEIGHT = 25`, `MAX_HEIGHT = 45`, `MIN_BODY_SHARE = 0.40`.

- [ ] **Step 1: Install pytest and create the package skeleton**

```bash
python -m pip install pytest
mkdir -p tools/brainrot_forge/tests tools/brainrot_forge/designs
printf '"""Brainrot Forge: voxel design -> baked per-colour meshes -> .glb for File > Import 3D."""\n__version__ = "0.1.0"\n' > tools/brainrot_forge/__init__.py
: > tools/brainrot_forge/tests/__init__.py
```

`tools/README.md`:
```markdown
# tools/

`brainrot_forge/` — the Brainrot Forge. Run everything from this folder:

    cd tools
    python -m pytest brainrot_forge/tests -q
    python -m brainrot_forge build pilot      # -> out/pilot/{pilot_batch.glb, manifest.json, previews/}

Design rules and budgets: ../docs/brainrot-build-standard.md. Pipeline: ../docs/superpowers/specs/2026-09-17-brainrot-forge-pilot-design.md.
```

- [ ] **Step 2: Write the failing tests** — `tools/brainrot_forge/tests/test_voxel.py`

```python
import pytest
from brainrot_forge.voxel import VoxelModel, MAX_ROLES


def make():
    m = VoxelModel("Test Thing", "Epic")
    m.role("body", "#C0392B").role("eye", "#F5F5F5").role("pupil", "#141218")
    return m


def test_box_fills_inclusive_ranges():
    m = make()
    m.box(-1, 1, 0, 2, -1, 1, "body")
    assert len(m.cells) == 3 * 3 * 3
    assert m.cells[(1, 2, 1)] == "body"


def test_set_rejects_unknown_role():
    m = make()
    with pytest.raises(KeyError):
        m.set(0, 0, 0, "nope")


def test_carve_removes_cells():
    m = make()
    m.box(0, 2, 0, 2, 0, 2, "body")
    m.carve(1, 1, 0, 2, 0, 2)
    assert len(m.cells) == 27 - 9
    assert (1, 1, 1) not in m.cells


def test_stepped_ellipsoid_is_symmetric_and_bounded():
    m = make()
    m.stepped_ellipsoid(0, 5, 0, 4, 3, 2, "body")
    for (x, y, z) in m.cells:
        assert (-x, y, z) in m.cells and (x, y, -z) in m.cells
        assert -4 <= x <= 4 and 2 <= y <= 8 and -2 <= z <= 2
    assert (0, 5, 0) in m.cells and (4, 5, 0) in m.cells and (0, 8, 0) in m.cells
    assert (4, 8, 2) not in m.cells


def test_mirror_x_copies_positive_side():
    m = make()
    m.box(1, 3, 0, 0, 0, 0, "body")
    m.mirror_x()
    assert (-1, 0, 0) in m.cells and (-3, 0, 0) in m.cells and len(m.cells) == 6


def test_keep_above_drops_low_cells():
    m = make()
    m.box(0, 0, -2, 2, 0, 0, "body")
    m.keep_above(0)
    assert min(y for (_, y, _) in m.cells) == 0 and len(m.cells) == 3


def test_eyes_paint_front_layer_with_pupil_inside():
    m = make()
    m.box(-4, 4, 0, 8, -2, 2, "body")
    m.eyes([(-2, 5), (2, 5)], z=-2, size=3, pupil=1)
    assert m.cells[(-2, 5, -2)] == "pupil" and m.cells[(2, 5, -2)] == "pupil"
    assert m.cells[(-3, 6, -2)] == "eye" and m.cells[(3, 4, -2)] == "eye"
    assert m.cells[(-2, 5, -1)] == "body"          # only the front layer is painted
    assert m.count_by_role()["eye"] == 2 * (9 - 1)


def test_eyes_gaze_offsets_pupil():
    m = make()
    m.box(-4, 4, 0, 8, -2, 2, "body")
    m.eyes([(0, 5)], z=-2, size=3, pupil=1, gaze=(1, 0))
    assert m.cells[(1, 5, -2)] == "pupil" and m.cells[(0, 5, -2)] == "eye"


def test_measurements():
    m = make()
    m.box(-2, 2, 0, 9, -1, 1, "body")
    assert m.bounds() == ((-2, 0, -1), (2, 9, 1))
    assert m.size_voxels() == (5, 10, 3)
    assert m.size_studs() == (1.0, 2.0, 0.6)
    assert m.front_z() == -1


def test_validate_passes_a_sound_model():
    m = make()
    m.box(-5, 5, 0, 29, -3, 3, "body")
    m.eyes([(-2, 20), (2, 20)], z=-3, size=3, pupil=1)
    assert m.validate() == []


def test_validate_reports_each_problem():
    m = make()
    m.box(0, 0, 0, 5, 0, 0, "body")                 # too short, no eyes
    problems = m.validate()
    assert any("height" in p for p in problems)
    assert any("eyes" in p for p in problems)
    for i in range(MAX_ROLES + 1):
        m.role(f"r{i}", "#000000")
    assert any("roles" in p for p in m.validate())
    m2 = VoxelModel("X", "Divine")
    assert any("rarity" in p for p in m2.validate())
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd tools && python -m pytest brainrot_forge/tests/test_voxel.py -q`
Expected: collection error `ModuleNotFoundError: No module named 'brainrot_forge.voxel'`.

- [ ] **Step 4: Write `tools/brainrot_forge/voxel.py`**

```python
"""VoxelModel: the design representation for the Brainrot Forge.

Integer lattice, y up, feet at y = 0, x/z centred on 0, FRONT = -Z (the side
BrainrotThumb.DEFAULT_DIR = (0.9, 0.45, -1) looks at). One cell = `pitch` studs
(0.2 like the game's existing voxel set). Colours are ROLES ("body", "eye", ...)
mapped to a hex palette; the bake turns each role into one MeshPart, so a role
is a MeshPart and MutationFX recolours it as one part (exactly like the pack).
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Iterable

Cell = tuple[int, int, int]

RARITIES = ("Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret", "God")
MAX_ROLES = 10          # standard §2.1: MeshParts <= 14 incl. eyes; 10 colour roles is the design gate
MIN_HEIGHT = 25         # voxels at pitch 0.2 = 5 studs (the existing set is 2.2-9 studs)
MAX_HEIGHT = 45         # 9 studs
MIN_BODY_SHARE = 0.40   # one role must be the body, not confetti
_HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")


def _rng(a: int, b: int) -> range:
    return range(min(a, b), max(a, b) + 1)


@dataclass
class VoxelModel:
    name: str
    rarity: str
    world: str = "Tundra"
    pitch: float = 0.2
    cells: dict[Cell, str] = field(default_factory=dict)
    palette: dict[str, str] = field(default_factory=dict)
    motion: str = "hover"
    fx: list[dict] | None = None        # BrainrotFX recipe rows: {"kit": str, "color": [r,g,b], ...}
    height_scale: float = 1.0
    width_scale: float = 1.0
    material: str = "Plastic"           # "Plastic" (tiled) or "SmoothPlastic"

    # ---------------------------------------------------------------- painting
    def role(self, role: str, hex_color: str) -> "VoxelModel":
        if not _HEX.match(hex_color):
            raise ValueError(f"{role}: colour must be #RRGGBB, got {hex_color!r}")
        self.palette[role] = hex_color.upper()
        return self

    def set(self, x: int, y: int, z: int, role: str) -> None:
        if role not in self.palette:
            raise KeyError(f"role {role!r} is not in the palette; call .role() first")
        self.cells[(int(x), int(y), int(z))] = role

    def box(self, x0, x1, y0, y1, z0, z1, role: str) -> "VoxelModel":
        for x in _rng(x0, x1):
            for y in _rng(y0, y1):
                for z in _rng(z0, z1):
                    self.set(x, y, z, role)
        return self

    def stepped_ellipsoid(self, cx, cy, cz, rx, ry, rz, role: str) -> "VoxelModel":
        """Cells whose centre lies inside the ellipsoid; the integer lattice makes it terraced."""
        for x in _rng(cx - rx, cx + rx):
            for y in _rng(cy - ry, cy + ry):
                for z in _rng(cz - rz, cz + rz):
                    if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 + ((z - cz) / rz) ** 2 <= 1.0:
                        self.set(x, y, z, role)
        return self

    def cylinder_y(self, cx, cz, r, y0, y1, role: str) -> "VoxelModel":
        for x in _rng(cx - r, cx + r):
            for z in _rng(cz - r, cz + r):
                if ((x - cx) / r) ** 2 + ((z - cz) / r) ** 2 <= 1.0:
                    for y in _rng(y0, y1):
                        self.set(x, y, z, role)
        return self

    def carve(self, x0, x1, y0, y1, z0, z1) -> "VoxelModel":
        for x in _rng(x0, x1):
            for y in _rng(y0, y1):
                for z in _rng(z0, z1):
                    self.cells.pop((x, y, z), None)
        return self

    def keep_above(self, y_min: int) -> "VoxelModel":
        self.cells = {c: r for c, r in self.cells.items() if c[1] >= y_min}
        return self

    def mirror_x(self) -> "VoxelModel":
        """Copy every cell with x > 0 onto -x (x = 0 stays). Use for symmetric bodies."""
        for (x, y, z), r in list(self.cells.items()):
            if x > 0:
                self.cells[(-x, y, z)] = r
        return self

    def eyes(self, centers: Iterable[tuple[int, int]], z: int, size: int, pupil: int,
             gaze: tuple[int, int] = (0, 0), eye_role: str = "eye", pupil_role: str = "pupil") -> "VoxelModel":
        """Paint cube eyes INTO the front layer z (VoxelFace rules: cubes, sized off the head,
        never proud stickers). Only cells that already exist are painted, so eyes never float."""
        if eye_role not in self.palette:
            self.role(eye_role, "#F5F5F5")
        if pupil_role not in self.palette:
            self.role(pupil_role, "#141218")
        h = size // 2
        ph = pupil // 2
        for (cx, cy) in centers:
            for x in _rng(cx - h, cx - h + size - 1):
                for y in _rng(cy - h, cy - h + size - 1):
                    if (x, y, z) in self.cells:
                        self.cells[(x, y, z)] = eye_role
            px, py = cx + gaze[0], cy + gaze[1]
            for x in _rng(px - ph, px - ph + pupil - 1):
                for y in _rng(py - ph, py - ph + pupil - 1):
                    if (x, y, z) in self.cells:
                        self.cells[(x, y, z)] = pupil_role
        return self

    # --------------------------------------------------------------- measuring
    def bounds(self) -> tuple[Cell, Cell]:
        if not self.cells:
            raise ValueError("empty model")
        xs = [c[0] for c in self.cells]; ys = [c[1] for c in self.cells]; zs = [c[2] for c in self.cells]
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))

    def size_voxels(self) -> tuple[int, int, int]:
        lo, hi = self.bounds()
        return (hi[0] - lo[0] + 1, hi[1] - lo[1] + 1, hi[2] - lo[2] + 1)

    def size_studs(self) -> tuple[float, float, float]:
        w, h, d = self.size_voxels()
        return (round(w * self.pitch, 6), round(h * self.pitch, 6), round(d * self.pitch, 6))

    def count_by_role(self) -> dict[str, int]:
        out: dict[str, int] = {}
        for r in self.cells.values():
            out[r] = out.get(r, 0) + 1
        return out

    def front_z(self) -> int:
        return self.bounds()[0][2]

    # -------------------------------------------------------------- the gate
    def validate(self) -> list[str]:
        problems: list[str] = []
        if not self.name.strip():
            problems.append("name is empty")
        if self.rarity not in RARITIES:
            problems.append(f"rarity {self.rarity!r} is not one of {RARITIES}")
        if self.pitch <= 0:
            problems.append("pitch must be > 0")
        if not self.cells:
            problems.append("model has no cells")
            return problems
        used = self.count_by_role()
        if len(self.palette) > MAX_ROLES:
            problems.append(f"too many roles: {len(self.palette)} > {MAX_ROLES}")
        for r in used:
            if r not in self.palette:
                problems.append(f"role {r!r} used but not in palette")
        _, h, _ = self.size_voxels()
        if not (MIN_HEIGHT <= h <= MAX_HEIGHT):
            problems.append(f"height {h} voxels outside {MIN_HEIGHT}-{MAX_HEIGHT}")
        if max(used.values()) / len(self.cells) < MIN_BODY_SHARE:
            problems.append(f"no body: largest role covers {max(used.values()) / len(self.cells):.0%} < {MIN_BODY_SHARE:.0%}")
        if used.get("eye", 0) == 0 or used.get("pupil", 0) == 0:
            problems.append("no eyes: paint some with .eyes()")
        if self.bounds()[0][1] != 0:
            problems.append(f"feet must sit at y = 0 (lowest cell is y = {self.bounds()[0][1]})")
        return problems
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd tools && python -m pytest brainrot_forge/tests/test_voxel.py -q`
Expected: `11 passed`.

- [ ] **Step 6: Commit**

```bash
git add tools/README.md tools/brainrot_forge/__init__.py tools/brainrot_forge/voxel.py tools/brainrot_forge/tests/__init__.py tools/brainrot_forge/tests/test_voxel.py
git commit -m "feat(forge): VoxelModel design representation with shape helpers and design gate

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

### Task 2: The bake — exposed faces, greedy rectangles, one `Mesh` per role

**Files:**
- Create: `tools/brainrot_forge/bake.py`, `tools/brainrot_forge/tests/test_bake.py`

**Interfaces:**
- Consumes: `VoxelModel` (Task 1) — `.cells`, `.pitch`, `.palette`.
- Produces: `Mesh(role, positions, normals, uvs, indices)` with `.triangles`, `.bounds()`; `exposed_faces(cells) -> dict[(axis, sign, slice, role) -> set[(u, v)]]`; `greedy_rects(grid) -> list[(u0, v0, w, h)]`; `bake(model) -> dict[role, Mesh]` (raises `BudgetError`); `triangle_report(meshes) -> dict[role, int]`; constants `TILE_STUDS = 2.0`, `MAX_TRIS_MODEL = 8000`, `MAX_TRIS_ROLE = 2000`.

- [ ] **Step 1: Write the failing tests** — `tools/brainrot_forge/tests/test_bake.py`

```python
import pytest
from brainrot_forge.voxel import VoxelModel
from brainrot_forge import bake as B


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def model(*cells, role="body"):
    m = VoxelModel("T", "Epic").role("body", "#FF0000").role("eye", "#FFFFFF")
    for c in cells:
        m.set(*c, role)
    return m


def assert_ccw(mesh):
    for i in range(0, len(mesh.indices), 3):
        a, b, c = (mesh.positions[mesh.indices[i + k]] for k in range(3))
        n = mesh.normals[mesh.indices[i]]
        assert dot(cross(sub(b, a), sub(c, a)), n) > 0, "triangle winds clockwise against its normal"


def test_single_cube_is_six_quads():
    meshes = B.bake(model((0, 0, 0)))
    assert list(meshes) == ["body"]
    m = meshes["body"]
    assert m.triangles == 12 and len(m.positions) == 24 and len(m.normals) == 24 and len(m.uvs) == 24
    assert m.bounds() == ((0.0, 0.0, 0.0), (0.2, 0.2, 0.2))
    assert sorted(set(m.normals)) == sorted({(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)})
    assert_ccw(m)


def test_slab_merges_coplanar_faces():
    m = B.bake(model((0, 0, 0), (1, 0, 0), (0, 1, 0), (1, 1, 0)))["body"]
    assert m.triangles == 12          # 6 rectangles, not 16 unit faces
    assert m.bounds() == ((0.0, 0.0, 0.0), (0.4, 0.4, 0.2))
    assert_ccw(m)


def test_interior_faces_are_not_emitted():
    faces = B.exposed_faces({(0, 0, 0): "body", (1, 0, 0): "body", (0, 1, 0): "body"})
    assert sum(len(g) for g in faces.values()) == 3 * 6 - 2 * 2


def test_faces_between_two_roles_are_not_emitted():
    faces = B.exposed_faces({(0, 0, 0): "body", (1, 0, 0): "eye"})
    assert sum(len(g) for g in faces.values()) == 10


def test_two_roles_give_two_meshes_without_shared_faces():
    m = model((0, 0, 0))
    m.set(1, 0, 0, "eye")
    meshes = B.bake(m)
    assert set(meshes) == {"body", "eye"}
    assert meshes["body"].triangles == 10 and meshes["eye"].triangles == 10


def test_greedy_rects_full_grid_is_one_rect():
    grid = {(u, v) for u in range(3) for v in range(2)}
    assert B.greedy_rects(grid) == [(0, 0, 3, 2)]


def test_greedy_rects_cover_exactly_once():
    grid = {(u, v) for u in range(4) for v in range(3)} - {(1, 1)}
    rects = B.greedy_rects(grid)
    covered = [(u0 + i, v0 + j) for (u0, v0, w, h) in rects for i in range(w) for j in range(h)]
    assert sorted(covered) == sorted(grid)
    assert len(covered) == len(set(covered))


def test_uvs_are_planar_in_studs_over_tile():
    m = B.bake(model((0, 0, 0), (1, 0, 0)))["body"]
    front = {m.uvs[i] for i in range(len(m.normals)) if m.normals[i] == (0, 0, -1)}
    assert front == {(0.0, 0.0), (0.2, 0.0), (0.2, 0.1), (0.0, 0.1)}


def test_triangle_report_and_budget_gate(monkeypatch):
    m = model((0, 0, 0))
    assert B.triangle_report(B.bake(m)) == {"body": 12}
    monkeypatch.setattr(B, "MAX_TRIS_MODEL", 6)
    with pytest.raises(B.BudgetError, match="triangles"):
        B.bake(m)


def test_role_gate():
    m = model((0, 0, 0))
    for i in range(11):
        m.role(f"r{i}", "#010101")
        m.set(i + 2, 0, 0, f"r{i}")
    with pytest.raises(B.BudgetError, match="roles"):
        B.bake(m)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd tools && python -m pytest brainrot_forge/tests/test_bake.py -q`
Expected: `ModuleNotFoundError: No module named 'brainrot_forge.bake'`.

- [ ] **Step 3: Write `tools/brainrot_forge/bake.py`**

```python
"""bake.py — voxel cells -> flat-shaded meshes, ONE PER COLOUR ROLE.

Only faces exposed to air are emitted (a face against any other cell, same role
or not, is interior). Coplanar same-role faces are greedy-merged into rectangles;
each rectangle becomes 4 unshared vertices with one flat normal and 2 triangles,
so the voxel steps stay crisp. UVs are planar in studs / TILE_STUDS: the owner's
MaterialService.BrainrotTile holds 2 cells per texture at StudsPerTile 2, so this
makes the tile 1.0 stud on a mesh exactly as it is on a Part-built body.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from .voxel import MAX_ROLES, Cell, VoxelModel

TILE_STUDS = 2.0
MAX_TRIS_MODEL = 8000
MAX_TRIS_ROLE = 2000

Vec3 = tuple[float, float, float]
FaceKey = tuple[int, int, int, str]  # (axis, sign, slice index, role)

_OTHER = {0: (1, 2), 1: (2, 0), 2: (0, 1)}  # axis -> (u axis, v axis)
_DIRS = ((0, 1), (0, -1), (1, 1), (1, -1), (2, 1), (2, -1))


class BudgetError(ValueError):
    """The design is over the bake budget; nothing was exported."""


@dataclass
class Mesh:
    role: str
    positions: list[Vec3] = field(default_factory=list)
    normals: list[Vec3] = field(default_factory=list)
    uvs: list[tuple[float, float]] = field(default_factory=list)
    indices: list[int] = field(default_factory=list)

    @property
    def triangles(self) -> int:
        return len(self.indices) // 3

    def bounds(self) -> tuple[Vec3, Vec3]:
        xs = [p[0] for p in self.positions]; ys = [p[1] for p in self.positions]; zs = [p[2] for p in self.positions]
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))


def exposed_faces(cells: dict[Cell, str]) -> dict[FaceKey, set[tuple[int, int]]]:
    out: dict[FaceKey, set[tuple[int, int]]] = {}
    for (x, y, z), role in cells.items():
        c = (x, y, z)
        for axis, sign in _DIRS:
            n = list(c)
            n[axis] += sign
            if tuple(n) in cells:
                continue
            ua, va = _OTHER[axis]
            out.setdefault((axis, sign, c[axis], role), set()).add((c[ua], c[va]))
    return out


def greedy_rects(grid: set[tuple[int, int]]) -> list[tuple[int, int, int, int]]:
    """Merge unit cells into maximal rectangles: grow along u, then along v while
    every cell of the next row is free. Deterministic (sorted scan)."""
    remaining = set(grid)
    rects: list[tuple[int, int, int, int]] = []
    for (u0, v0) in sorted(grid):
        if (u0, v0) not in remaining:
            continue
        w = 1
        while (u0 + w, v0) in remaining:
            w += 1
        h = 1
        while all((u0 + i, v0 + h) in remaining for i in range(w)):
            h += 1
        for i in range(w):
            for j in range(h):
                remaining.discard((u0 + i, v0 + j))
        rects.append((u0, v0, w, h))
    return rects


def _cross(a: Vec3, b: Vec3) -> Vec3:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dot(a: Vec3, b: Vec3) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _sub(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _quad(mesh: Mesh, axis: int, sign: int, k: int, rect: tuple[int, int, int, int], pitch: float) -> None:
    u0, v0, w, h = rect
    ua, va = _OTHER[axis]
    plane = (k + (1 if sign > 0 else 0)) * pitch
    uA, uB = u0 * pitch, (u0 + w) * pitch
    vA, vB = v0 * pitch, (v0 + h) * pitch
    normal = [0.0, 0.0, 0.0]
    normal[axis] = float(sign)
    n: Vec3 = (normal[0], normal[1], normal[2])
    corners = []
    for (u, v) in ((uA, vA), (uB, vA), (uB, vB), (uA, vB)):
        p = [0.0, 0.0, 0.0]
        p[axis] = plane
        p[ua] = u
        p[va] = v
        corners.append(((round(p[0], 6), round(p[1], 6), round(p[2], 6)), (round(u / TILE_STUDS, 6), round(v / TILE_STUDS, 6))))
    if _dot(_cross(_sub(corners[1][0], corners[0][0]), _sub(corners[2][0], corners[0][0])), n) < 0:
        corners = [corners[0], corners[3], corners[2], corners[1]]
    base = len(mesh.positions)
    for pos, uv in corners:
        mesh.positions.append(pos)
        mesh.normals.append(n)
        mesh.uvs.append(uv)
    mesh.indices.extend((base, base + 1, base + 2, base, base + 2, base + 3))


def bake(model: VoxelModel) -> dict[str, Mesh]:
    if len(model.palette) > MAX_ROLES:
        raise BudgetError(f"{model.name}: too many roles ({len(model.palette)} > {MAX_ROLES})")
    meshes: dict[str, Mesh] = {}
    for (axis, sign, k, role), grid in sorted(exposed_faces(model.cells).items()):
        mesh = meshes.setdefault(role, Mesh(role))
        for rect in greedy_rects(grid):
            _quad(mesh, axis, sign, k, rect, model.pitch)
    total = 0
    for role, mesh in meshes.items():
        if mesh.triangles > MAX_TRIS_ROLE:
            raise BudgetError(f"{model.name}: role {role!r} has {mesh.triangles} triangles > {MAX_TRIS_ROLE}")
        total += mesh.triangles
    if total > MAX_TRIS_MODEL:
        raise BudgetError(f"{model.name}: {total} triangles > {MAX_TRIS_MODEL}")
    return dict(sorted(meshes.items()))


def triangle_report(meshes: dict[str, Mesh]) -> dict[str, int]:
    return {role: m.triangles for role, m in meshes.items()}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd tools && python -m pytest brainrot_forge/tests/test_bake.py -q`
Expected: `10 passed`.

- [ ] **Step 5: Commit**

```bash
git add tools/brainrot_forge/bake.py tools/brainrot_forge/tests/test_bake.py
git commit -m "feat(forge): bake voxels into flat-shaded per-role meshes with greedy rectangles and a triangle gate

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

### Task 3: glTF binary writer, reader and the batch manifest

**Files:**
- Create: `tools/brainrot_forge/export_glb.py`, `tools/brainrot_forge/tests/test_export_glb.py`

**Interfaces:**
- Consumes: `VoxelModel` (Task 1), `Mesh`, `triangle_report` (Task 2).
- Produces: `Batch = list[tuple[VoxelModel, dict[str, Mesh]]]`; `part_name(model_name, role) -> str` (`"<Model Name>__<role>"`); `write_glb(path, batch, flip_z=False) -> None`; `read_glb(path) -> dict[node_name, {"positions", "normals", "uvs", "indices", "color"}]`; `build_manifest(batch) -> dict`; `srgb_to_linear(hex) -> (r, g, b)`.

- [ ] **Step 1: Write the failing tests** — `tools/brainrot_forge/tests/test_export_glb.py`

```python
import json
import os
import struct

from brainrot_forge.voxel import VoxelModel
from brainrot_forge.bake import bake
from brainrot_forge import export_glb as G


def cube(name="T", role="body", color="#FF0000"):
    m = VoxelModel(name, "Epic").role(role, color)
    m.set(0, 0, 0, role)
    return m


def batch_of(*models):
    return [(m, bake(m)) for m in models]


def test_part_name_convention():
    assert G.part_name("Nonno Ghiacciaio", "beard") == "Nonno Ghiacciaio__beard"


def test_srgb_to_linear():
    assert G.srgb_to_linear("#FFFFFF") == (1.0, 1.0, 1.0)
    assert G.srgb_to_linear("#000000") == (0.0, 0.0, 0.0)
    r, g, b = G.srgb_to_linear("#808080")
    assert abs(r - 0.2158605) < 1e-5 and r == g == b


def test_glb_container_is_well_formed(tmp_path):
    path = tmp_path / "one.glb"
    G.write_glb(path, batch_of(cube()))
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67 and version == 2 and length == len(data)
    json_len, json_type = struct.unpack_from("<II", data, 12)
    assert json_type == 0x4E4F534A and json_len % 4 == 0
    doc = json.loads(data[20:20 + json_len])
    assert doc["asset"]["version"] == "2.0"
    bin_len, bin_type = struct.unpack_from("<II", data, 20 + json_len)
    assert bin_type == 0x004E4942 and bin_len % 4 == 0
    assert doc["nodes"][0]["name"] == "T__body" and doc["meshes"][0]["name"] == "T__body"
    assert doc["materials"][0]["name"] == "T__body"


def test_round_trip_geometry_and_colour(tmp_path):
    path = tmp_path / "one.glb"
    b = batch_of(cube())
    G.write_glb(path, b)
    back = G.read_glb(path)
    node = back["T__body"]
    src = b[0][1]["body"]
    assert node["positions"] == [tuple(round(c, 6) for c in p) for p in src.positions]
    assert node["normals"] == src.normals
    assert node["uvs"] == src.uvs
    assert node["indices"] == src.indices
    assert node["color"] == (1.0, 0.0, 0.0)


def test_batch_has_one_node_per_role_in_order(tmp_path):
    a = cube("Alpha")
    b = VoxelModel("Beta", "Secret").role("body", "#0000FF").role("eye", "#FFFFFF")
    b.set(0, 0, 0, "body"); b.set(1, 0, 0, "eye")
    path = tmp_path / "two.glb"
    G.write_glb(path, batch_of(a, b))
    assert list(G.read_glb(path)) == ["Alpha__body", "Beta__body", "Beta__eye"]


def test_flip_z_mirrors_and_keeps_ccw(tmp_path):
    path = tmp_path / "flip.glb"
    G.write_glb(path, batch_of(cube()), flip_z=True)
    node = G.read_glb(path)["T__body"]
    assert min(p[2] for p in node["positions"]) == -0.2 and max(p[2] for p in node["positions"]) == 0.0
    for i in range(0, len(node["indices"]), 3):
        a, b, c = (node["positions"][node["indices"][i + k]] for k in range(3))
        n = node["normals"][node["indices"][i]]
        ab = (b[0] - a[0], b[1] - a[1], b[2] - a[2]); ac = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        cr = (ab[1] * ac[2] - ab[2] * ac[1], ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0])
        assert cr[0] * n[0] + cr[1] * n[1] + cr[2] * n[2] > 0


def test_manifest_shape():
    m = VoxelModel("Beta", "Secret").role("body", "#0000FF").role("eye", "#FFFFFF")
    m.box(-2, 2, 0, 29, -2, 2, "body"); m.eyes([(0, 20)], z=-2, size=3, pupil=1)
    m.height_scale = 1.46; m.motion = "shiver"; m.fx = [{"kit": "aura1", "color": [200, 232, 245], "rate": 8}]
    man = G.build_manifest(batch_of(m))
    entry = man["models"]["Beta"]
    assert man["version"] == 1 and man["pitch"] == 0.2
    assert entry["rarity"] == "Secret" and entry["world"] == "Tundra"
    assert entry["roles"] == {"body": "#0000FF", "eye": "#FFFFFF", "pupil": "#141218"}
    assert entry["parts"] == ["Beta__body", "Beta__eye", "Beta__pupil"]
    assert entry["heightScale"] == 1.46 and entry["widthScale"] == 1.0 and entry["motion"] == "shiver"
    assert entry["material"] == "Plastic" and entry["fx"][0]["kit"] == "aura1"
    assert entry["bbox"] == [1.0, 6.0, 1.0] and entry["totalTriangles"] == sum(entry["triangles"].values())
    json.dumps(man)  # must be serialisable
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd tools && python -m pytest brainrot_forge/tests/test_export_glb.py -q`
Expected: `ModuleNotFoundError: No module named 'brainrot_forge.export_glb'`.

- [ ] **Step 3: Write `tools/brainrot_forge/export_glb.py`**

```python
"""export_glb.py — a batch of baked models -> ONE glTF 2.0 binary for File > Import 3D,
plus the manifest the Studio assembler reads.

Node/mesh/material names are "<Model Name>__<role>"; Roblox's importer names each
MeshPart after its node, which is how BrainrotForge.Assemble finds them. The importer
ignores baseColorFactor when a material has no texture (measured 2026-07-31), so the
manifest carries the palette and Assemble repaints — the colour here is for viewers.
Stdlib only.
"""
from __future__ import annotations

import json
import struct
from pathlib import Path

from . import __version__
from .bake import Mesh, triangle_report
from .voxel import VoxelModel

Batch = list[tuple[VoxelModel, dict[str, Mesh]]]

_MAGIC = 0x46546C67
_JSON = 0x4E4F534A
_BIN = 0x004E4942
_FLOAT, _UINT = 5126, 5125
_ARRAY_BUFFER, _ELEMENT_ARRAY_BUFFER = 34962, 34963


def part_name(model_name: str, role: str) -> str:
    return f"{model_name}__{role}"


def srgb_to_linear(hex_color: str) -> tuple[float, float, float]:
    def ch(v: int) -> float:
        c = v / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    h = hex_color.lstrip("#")
    return tuple(round(ch(int(h[i:i + 2], 16)), 7) for i in (0, 2, 4))  # type: ignore[return-value]


def _pad(b: bytes, fill: bytes) -> bytes:
    return b + fill * (-len(b) % 4)


def write_glb(path: str | Path, batch: Batch, flip_z: bool = False) -> None:
    buffer = bytearray()
    views, accessors, materials, meshes, nodes = [], [], [], [], []

    def view(blob: bytes, target: int) -> int:
        while len(buffer) % 4:
            buffer.append(0)
        views.append({"buffer": 0, "byteOffset": len(buffer), "byteLength": len(blob), "target": target})
        buffer.extend(blob)
        return len(views) - 1

    def accessor(v: int, ctype: int, count: int, atype: str, lo=None, hi=None) -> int:
        a = {"bufferView": v, "componentType": ctype, "count": count, "type": atype}
        if lo is not None:
            a["min"], a["max"] = lo, hi
        accessors.append(a)
        return len(accessors) - 1

    for model, role_meshes in batch:
        for role, mesh in role_meshes.items():
            name = part_name(model.name, role)
            pos = [(p[0], p[1], -p[2] if flip_z else p[2]) for p in mesh.positions]
            nrm = [(n[0], n[1], -n[2] if flip_z else n[2]) for n in mesh.normals]
            idx = list(mesh.indices)
            if flip_z:  # mirroring flips handedness; reverse each triangle to stay CCW
                idx = [i for t in range(0, len(idx), 3) for i in (idx[t], idx[t + 2], idx[t + 1])]
            p_blob = b"".join(struct.pack("<3f", *p) for p in pos)
            n_blob = b"".join(struct.pack("<3f", *n) for n in nrm)
            t_blob = b"".join(struct.pack("<2f", *uv) for uv in mesh.uvs)
            i_blob = struct.pack(f"<{len(idx)}I", *idx)
            lo = [min(p[k] for p in pos) for k in range(3)]
            hi = [max(p[k] for p in pos) for k in range(3)]
            a_pos = accessor(view(p_blob, _ARRAY_BUFFER), _FLOAT, len(pos), "VEC3", lo, hi)
            a_nrm = accessor(view(n_blob, _ARRAY_BUFFER), _FLOAT, len(nrm), "VEC3")
            a_uv = accessor(view(t_blob, _ARRAY_BUFFER), _FLOAT, len(mesh.uvs), "VEC2")
            a_idx = accessor(view(i_blob, _ELEMENT_ARRAY_BUFFER), _UINT, len(idx), "SCALAR")
            r, g, b = srgb_to_linear(model.palette[role])
            materials.append({"name": name, "pbrMetallicRoughness": {"baseColorFactor": [r, g, b, 1.0], "metallicFactor": 0.0, "roughnessFactor": 1.0}})
            meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv}, "indices": a_idx, "material": len(materials) - 1, "mode": 4}]})
            nodes.append({"name": name, "mesh": len(meshes) - 1})

    doc = {
        "asset": {"version": "2.0", "generator": f"brainrot_forge {__version__}"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes, "meshes": meshes, "materials": materials,
        "accessors": accessors, "bufferViews": views,
        "buffers": [{"byteLength": len(buffer)}],
    }
    json_chunk = _pad(json.dumps(doc, separators=(",", ":")).encode("utf-8"), b" ")
    bin_chunk = _pad(bytes(buffer), b"\x00")
    total = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", _MAGIC, 2, total))
        f.write(struct.pack("<II", len(json_chunk), _JSON)); f.write(json_chunk)
        f.write(struct.pack("<II", len(bin_chunk), _BIN)); f.write(bin_chunk)


def read_glb(path: str | Path) -> dict[str, dict]:
    data = Path(path).read_bytes()
    json_len = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + json_len])
    bin_off = 20 + json_len + 8
    blob = data[bin_off:bin_off + struct.unpack_from("<I", data, 20 + json_len)[0]]

    def read(acc_index: int):
        acc = doc["accessors"][acc_index]
        bv = doc["bufferViews"][acc["bufferView"]]
        start = bv["byteOffset"]
        n = acc["count"]
        if acc["componentType"] == _UINT:
            return list(struct.unpack_from(f"<{n}I", blob, start))
        width = {"VEC3": 3, "VEC2": 2}[acc["type"]]
        flat = struct.unpack_from(f"<{n * width}f", blob, start)
        return [tuple(round(v, 6) for v in flat[i:i + width]) for i in range(0, len(flat), width)]

    out: dict[str, dict] = {}
    for node in doc["nodes"]:
        prim = doc["meshes"][node["mesh"]]["primitives"][0]
        color = doc["materials"][prim["material"]]["pbrMetallicRoughness"]["baseColorFactor"][:3]
        out[node["name"]] = {
            "positions": read(prim["attributes"]["POSITION"]),
            "normals": read(prim["attributes"]["NORMAL"]),
            "uvs": read(prim["attributes"]["TEXCOORD_0"]),
            "indices": read(prim["indices"]),
            "color": tuple(color),
        }
    return out


def build_manifest(batch: Batch) -> dict:
    models: dict[str, dict] = {}
    pitch = batch[0][0].pitch if batch else 0.2
    for model, role_meshes in batch:
        tris = triangle_report(role_meshes)
        w, h, d = model.size_studs()
        models[model.name] = {
            "rarity": model.rarity, "world": model.world,
            "roles": {role: model.palette[role] for role in role_meshes},
            "parts": [part_name(model.name, role) for role in role_meshes],
            "heightScale": model.height_scale, "widthScale": model.width_scale,
            "motion": model.motion, "material": model.material, "fx": model.fx,
            "bbox": [w, h, d], "triangles": tris, "totalTriangles": sum(tris.values()),
        }
    return {"version": 1, "generator": f"brainrot_forge {__version__}", "pitch": pitch, "models": models}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd tools && python -m pytest brainrot_forge/tests/test_export_glb.py -q`
Expected: `7 passed`.

- [ ] **Step 5: Commit**

```bash
git add tools/brainrot_forge/export_glb.py tools/brainrot_forge/tests/test_export_glb.py
git commit -m "feat(forge): glTF binary writer/reader and batch manifest

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

### Task 4: Preview renderer (approve looks before importing anything)

**Files:**
- Create: `tools/brainrot_forge/render.py`, `tools/brainrot_forge/tests/test_render.py`

**Interfaces:**
- Consumes: `Batch`, `Mesh`, palettes.
- Produces: `render_model(model, meshes, size=512, dir=DEFAULT_DIR) -> PIL.Image.Image`; `render_plot_tile(model, meshes, tile=(200, 200)) -> Image`; `contact_sheet(batch, out_dir) -> list[Path]`; constants `DEFAULT_DIR = (0.9, 0.45, -1.0)` (the game's thumbnail direction), `PX_PER_STUD_AT_PLOT = 19.3` (6 studs → 116 px: a 1080p viewer 40 studs from a pad at a 70° FOV), `SKY = (196, 224, 240)`.

- [ ] **Step 1: Write the failing tests** — `tools/brainrot_forge/tests/test_render.py`

```python
from brainrot_forge.voxel import VoxelModel
from brainrot_forge.bake import bake
from brainrot_forge import render as R


def sample(height_scale=1.0):
    m = VoxelModel("Sample", "Epic").role("body", "#C0392B")
    m.box(-4, 4, 0, 29, -3, 3, "body"); m.eyes([(-2, 22), (2, 22)], z=-3, size=3, pupil=1)
    m.height_scale = height_scale
    return m, bake(m)


def test_render_model_size_and_content():
    m, meshes = sample()
    img = R.render_model(m, meshes, size=256)
    assert img.size == (256, 256) and img.mode == "RGB"
    pixels = list(img.getdata())
    assert pixels.count(R.SKY) < len(pixels) * 0.9          # something was drawn
    assert any(abs(p[0] - p[1]) > 60 for p in pixels)        # the red body is visible


def test_front_quarter_shows_the_eyes():
    m, meshes = sample()
    img = R.render_model(m, meshes, size=256)
    # shaded white reads as a bright NEUTRAL grey (~170-185); the sky is tinted blue, the body red
    assert any(min(p) > 140 and max(p) - min(p) < 12 for p in img.getdata())


def test_plot_tile_height_follows_height_scale():
    m1, k1 = sample(1.0)
    m2, k2 = sample(1.5)
    t1, t2 = R.render_plot_tile(m1, k1), R.render_plot_tile(m2, k2)
    assert t1.size == (200, 200) == t2.size
    h1 = R._drawn_height(t1); h2 = R._drawn_height(t2)
    assert abs(h1 - 116) <= 3 and abs(h2 - 174) <= 4


def test_contact_sheet_writes_files(tmp_path):
    m, meshes = sample()
    paths = R.contact_sheet([(m, meshes)], tmp_path)
    names = sorted(p.name for p in paths)
    assert names == ["contact_sheet.png", "sample.png"]
    assert all(p.stat().st_size > 0 for p in paths)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd tools && python -m pytest brainrot_forge/tests/test_render.py -q`
Expected: `ModuleNotFoundError: No module named 'brainrot_forge.render'`.

- [ ] **Step 3: Write `tools/brainrot_forge/render.py`**

```python
"""render.py — software previews of the BAKED faces (exactly what Roblox will draw).

Orthographic front-quarter view along the game's own thumbnail direction
(BrainrotThumb.DEFAULT_DIR), painter's algorithm, one flat shade per face normal.
Two views per model: a close-up and a "plot tile" where the body is drawn at the
pixel height it has on screen at gameplay distance, so silhouettes are judged where
they are actually seen. Verifying offline, before any import, is a project rule.
"""
from __future__ import annotations

import math
import re
from pathlib import Path

from PIL import Image, ImageDraw

from .bake import Mesh
from .voxel import VoxelModel

DEFAULT_DIR = (0.9, 0.45, -1.0)
PX_PER_STUD_AT_PLOT = 19.3     # 1080 px / (2 * 40 studs * tan(35 deg))
PLOT_FIT_STUDS = 6.0           # BrainrotSpawner.MODEL_HEIGHT
SKY = (196, 224, 240)
GROUND = (168, 190, 178)


def _norm(v):
    l = math.sqrt(sum(c * c for c in v)) or 1.0
    return tuple(c / l for c in v)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def _hex_rgb(h: str):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _triangles(model: VoxelModel, meshes: dict[str, Mesh]):
    for role, mesh in meshes.items():
        rgb = _hex_rgb(model.palette[role])
        for i in range(0, len(mesh.indices), 3):
            ids = mesh.indices[i:i + 3]
            yield [mesh.positions[j] for j in ids], mesh.normals[ids[0]], rgb


def _project(model, meshes, size_px, height_px=None, dir=DEFAULT_DIR):
    """Returns (draw list sorted far->near, image size). height_px pins the projected
    model height; otherwise the model is fit into size_px with a margin."""
    d = _norm(dir)                      # centre -> camera
    f = tuple(-c for c in d)            # camera forward
    r = _norm(_cross(f, (0.0, 1.0, 0.0)))
    u = _cross(r, f)
    light = _norm((d[0] + 0.3, d[1] + 0.8, d[2]))
    tris = list(_triangles(model, meshes))
    pts = [p for t, _, _ in tris for p in t]
    cx = (min(p[0] for p in pts) + max(p[0] for p in pts)) / 2
    cy = (min(p[1] for p in pts) + max(p[1] for p in pts)) / 2
    cz = (min(p[2] for p in pts) + max(p[2] for p in pts)) / 2
    proj = []
    for t, n, rgb in tris:
        sp = [(_dot((p[0] - cx, p[1] - cy, p[2] - cz), r), _dot((p[0] - cx, p[1] - cy, p[2] - cz), u), _dot((p[0] - cx, p[1] - cy, p[2] - cz), f)) for p in t]
        shade = 0.45 + 0.55 * max(0.0, _dot(n, light))
        proj.append((sum(p[2] for p in sp) / 3, sp, tuple(int(c * shade) for c in rgb)))
    proj.sort(key=lambda e: -e[0])
    ys = [p[1] for _, sp, _ in proj for p in sp]
    if height_px is None:
        ext = max(max(abs(p[0]) for _, sp, _ in proj for p in sp), max(abs(y) for y in ys))
        scale = (size_px * 0.42) / ext
    else:
        # pin the PROJECTED extent (the camera has pitch, so this is a little more
        # than the stud height) to height_px: what is drawn is exactly that tall
        scale = height_px / (max(ys) - min(ys))
    return proj, scale


def _paint(proj, scale, size_px):
    img = Image.new("RGB", (size_px, size_px), SKY)
    draw = ImageDraw.Draw(img)
    ox, oy = size_px / 2, size_px / 2
    for _, sp, colour in proj:
        draw.polygon([(ox + x * scale, oy - y * scale) for x, y, _ in sp], fill=colour)
    return img


def render_model(model: VoxelModel, meshes: dict[str, Mesh], size: int = 512, dir=DEFAULT_DIR) -> Image.Image:
    proj, scale = _project(model, meshes, size, dir=dir)
    return _paint(proj, scale, size)


def render_plot_tile(model: VoxelModel, meshes: dict[str, Mesh], tile=(200, 200)) -> Image.Image:
    """The body at its on-screen height from a pad: the spawner fits it to
    PLOT_FIT_STUDS * HeightScale studs; at 40 studs that is PX_PER_STUD_AT_PLOT px per stud."""
    height_px = PLOT_FIT_STUDS * model.height_scale * PX_PER_STUD_AT_PLOT
    proj, scale = _project(model, meshes, tile[0], height_px=height_px)
    img = _paint(proj, scale, tile[0])
    return img.crop((0, 0, tile[0], tile[1]))


def _drawn_height(img: Image.Image) -> int:
    rows = [y for y in range(img.height) if any(img.getpixel((x, y)) != SKY for x in range(img.width))]
    return (max(rows) - min(rows) + 1) if rows else 0


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def contact_sheet(batch, out_dir) -> list[Path]:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    paths: list[Path] = []
    rows = []
    for model, meshes in batch:
        close = render_model(model, meshes, 512)
        tile = render_plot_tile(model, meshes)
        row = Image.new("RGB", (512 + 220, 512), SKY)
        row.paste(close, (0, 0)); row.paste(tile, (522, 156))
        ImageDraw.Draw(row).text((526, 120), f"{model.name} ({model.rarity}) at pad distance", fill=(20, 20, 30))
        p = out_dir / f"{slug(model.name)}.png"
        row.save(p); paths.append(p); rows.append(row)
    sheet = Image.new("RGB", (732, 512 * len(rows)), SKY)
    for i, row in enumerate(rows):
        sheet.paste(row, (0, 512 * i))
    p = out_dir / "contact_sheet.png"
    sheet.save(p); paths.append(p)
    return paths
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd tools && python -m pytest brainrot_forge/tests/test_render.py -q`
Expected: `4 passed`. If `test_plot_tile_height_follows_height_scale` is off by more than the tolerance, the fix is in `_project`'s `height_px` branch (it must scale by the model's projected height along `u`, which for a front-quarter view is the true height because `u` has no roll) — not in the test.

- [ ] **Step 5: Commit**

```bash
git add tools/brainrot_forge/render.py tools/brainrot_forge/tests/test_render.py
git commit -m "feat(forge): offline preview renderer with plot-distance tiles and contact sheet

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

### Task 5: The three pilot designs (+ `paint()` helper)

**Files:**
- Modify: `tools/brainrot_forge/voxel.py` (add `paint()` after `carve()`), `tools/brainrot_forge/tests/test_voxel.py` (one test)
- Create: `tools/brainrot_forge/designs/__init__.py`, `tools/brainrot_forge/designs/guantone_brontolone.py`, `tools/brainrot_forge/designs/alce_lampadario.py`, `tools/brainrot_forge/designs/nonno_ghiacciaio.py`, `tools/brainrot_forge/tests/test_designs.py`

**Interfaces:**
- Consumes: `VoxelModel` helpers (Task 1), `bake` + `BudgetError` (Task 2).
- Produces: `VoxelModel.paint(x0, x1, y0, y1, z0, z1, role)` (recolours EXISTING cells only, never adds); `designs.DESIGNS: dict[str, Callable[[], VoxelModel]]` keyed by the exact roster names; `designs.PILOT = ["Guantone Brontolone", "Alce Lampadario", "Nonno Ghiacciaio"]`.

- [ ] **Step 1: Add the failing `paint` test to `tests/test_voxel.py`**

```python
def test_paint_recolours_only_existing_cells():
    m = make()
    m.box(0, 2, 0, 2, 0, 0, "body")
    m.paint(1, 1, -5, 5, -5, 5, "eye")
    assert m.count_by_role() == {"body": 6, "eye": 3} and len(m.cells) == 9
```

Run: `cd tools && python -m pytest brainrot_forge/tests/test_voxel.py -q` → Expected: `1 failed, 11 passed` (`AttributeError: 'VoxelModel' object has no attribute 'paint'`).

- [ ] **Step 2: Add `paint()` to `voxel.py` directly after `carve()`**

```python
    def paint(self, x0, x1, y0, y1, z0, z1, role: str) -> "VoxelModel":
        """Recolour existing cells only — crevasses, stripes, markings. Never adds a cell."""
        if role not in self.palette:
            raise KeyError(f"role {role!r} is not in the palette; call .role() first")
        for x in _rng(x0, x1):
            for y in _rng(y0, y1):
                for z in _rng(z0, z1):
                    if (x, y, z) in self.cells:
                        self.cells[(x, y, z)] = role
        return self
```

Run the voxel tests again → Expected: `12 passed`.

- [ ] **Step 3: Write the failing design tests** — `tools/brainrot_forge/tests/test_designs.py`

```python
import pytest
from brainrot_forge.bake import bake, triangle_report
from brainrot_forge.voxel import MAX_ROLES
from brainrot_forge.designs import DESIGNS, PILOT

LADDER = {"Epic": 1.30, "Legendary": 1.36, "Secret": 1.46}   # Tundra HeightScale per rarity


@pytest.mark.parametrize("name", PILOT)
def test_registry_and_gate(name):
    model = DESIGNS[name]()
    assert model.name == name and model.world == "Tundra"
    assert model.validate() == []
    assert len(model.palette) <= MAX_ROLES
    assert model.height_scale == LADDER[model.rarity]


@pytest.mark.parametrize("name", PILOT)
def test_deterministic(name):
    a, b = DESIGNS[name](), DESIGNS[name]()
    assert a.cells == b.cells and a.palette == b.palette


@pytest.mark.parametrize("name", PILOT)
def test_bakes_under_budget(name):
    meshes = bake(DESIGNS[name]())
    report = triangle_report(meshes)
    assert 200 <= sum(report.values()) <= 8000
    assert len(meshes) <= 10


@pytest.mark.parametrize("name", PILOT)
def test_eyes_face_minus_z(name):
    m = DESIGNS[name]()
    eye_z = {z for (x, y, z), r in m.cells.items() if r == "pupil"}
    assert len(eye_z) == 1, "both pupils sit on one front layer"
    z = eye_z.pop()
    assert all((x, y, z - 1) not in m.cells for (x, y, zz), r in m.cells.items() if r == "pupil" and zz == z), "pupils are exposed toward -Z"


def test_bands_and_effects():
    epic, leg, sec = (DESIGNS[n]() for n in PILOT)
    assert (epic.rarity, leg.rarity, sec.rarity) == ("Epic", "Legendary", "Secret")
    assert epic.fx is None and len(leg.fx) <= 6 and len(sec.fx) <= 6
    assert sec.motion == "shiver" and epic.motion == "hover" and leg.motion == "hover"
    assert all(e["kit"] in {"glow", "flare", "aura1", "aura2", "aura3", "snow", "glare", "specs", "cubes", "stars"} for e in leg.fx + sec.fx)
```

Run: `cd tools && python -m pytest brainrot_forge/tests/test_designs.py -q` → Expected: `ModuleNotFoundError: No module named 'brainrot_forge.designs'`.

- [ ] **Step 4: Write `designs/__init__.py`**

```python
"""Registry of forge designs. Keys are the EXACT roster names (Model.Name == config Name)."""
from . import alce_lampadario, guantone_brontolone, nonno_ghiacciaio

DESIGNS = {
    "Guantone Brontolone": guantone_brontolone.build,
    "Alce Lampadario": alce_lampadario.build,
    "Nonno Ghiacciaio": nonno_ghiacciaio.build,
}
PILOT = ["Guantone Brontolone", "Alce Lampadario", "Nonno Ghiacciaio"]
```

- [ ] **Step 5: Write `designs/guantone_brontolone.py`** (Epic — the grumbling mitten; exaggerated feature: the thumb)

```python
"""Guantone Brontolone (Epic): a chunky knitted mitten on two stubby boots, face on
the palm under a heavy unibrow, one giant thumb waved like an arm. Front = -Z."""
from ..voxel import VoxelModel


def build() -> VoxelModel:
    m = VoxelModel("Guantone Brontolone", "Epic")
    m.role("wool", "#C0392B").role("wool_dark", "#96271F").role("cuff", "#F1E4C8").role("ink", "#2F2A33")
    m.height_scale = 1.30
    # palm: 19 wide x 17 tall x 9 deep slab with a domed top (reaches y = 30)
    m.box(-9, 9, 8, 24, -4, 4, "wool")
    m.stepped_ellipsoid(0, 24, 0, 9, 6, 4, "wool")
    # knit stripes: flush recolour, zero geometry cost
    for y in (11, 16, 21):
        m.paint(-9, 9, y, y, -4, 4, "wool_dark")
    # THE THUMB: out to the right and up, rounded tip
    m.box(9, 14, 17, 23, -3, 3, "wool")
    m.box(13, 18, 20, 27, -3, 3, "wool")
    m.stepped_ellipsoid(18, 26, 0, 4, 4, 3, "wool")
    # cuff: a wider band with ribs on the front
    m.box(-11, 11, 3, 8, -6, 6, "cuff")
    for x in range(-11, 12, 2):
        m.box(x, x, 3, 8, -7, -7, "cuff")
    # boots
    m.box(-8, -2, 0, 2, -5, 3, "ink")
    m.box(2, 8, 0, 2, -5, 3, "ink")
    # face on the palm (front layer z = -4): eyes looking down, unibrow one voxel proud, flat mouth
    m.eyes([(-3, 19), (3, 19)], z=-4, size=4, pupil=2, gaze=(0, -1))
    m.box(-6, 6, 22, 23, -5, -5, "ink")
    m.paint(-3, 3, 14, 14, -4, -4, "ink")
    return m
```

- [ ] **Step 6: Write `designs/alce_lampadario.py`** (Legendary — chandelier moose; exaggerated feature: the antlers)

```python
"""Alce Lampadario (Legendary): a squat moose whose antlers are an icicle chandelier
twice its body width, candles burning on the crossbar. Front = -Z (muzzle forward)."""
from ..voxel import VoxelModel


def build() -> VoxelModel:
    m = VoxelModel("Alce Lampadario", "Legendary")
    m.role("fur", "#6B4A2B").role("muzzle", "#D9C4A5").role("ice", "#BFE6FF").role("candle", "#FFF1C9").role("flame", "#FFC24D").role("ink", "#141218")
    m.height_scale = 1.36
    m.fx = [
        {"kit": "glow", "color": [255, 210, 120]},
        {"kit": "flare", "color": [255, 210, 120]},
        {"kit": "aura2", "color": [191, 230, 255], "rate": 6},
    ]
    # barrel body + solid core
    m.stepped_ellipsoid(0, 14, 1, 7, 6, 10, "fur")
    m.box(-6, 6, 9, 18, -8, 10, "fur")
    # four stubby legs with hooves
    for x0, x1 in ((-6, -3), (3, 6)):
        for z0, z1 in ((-7, -4), (5, 8)):
            m.box(x0, x1, 0, 9, z0, z1, "fur")
            m.paint(x0, x1, 0, 1, z0, z1, "ink")
    # head block, long pale muzzle forward, nostrils, ears
    m.box(-5, 5, 15, 25, -14, -8, "fur")
    m.box(-4, 4, 13, 20, -19, -14, "muzzle")
    m.paint(-3, -2, 17, 18, -19, -19, "ink")
    m.paint(2, 3, 17, 18, -19, -19, "ink")
    m.box(-8, -6, 23, 26, -13, -11, "fur")
    m.box(6, 8, 23, 26, -13, -11, "fur")
    # eyes on the head front, above the muzzle
    m.eyes([(-3, 22), (3, 22)], z=-14, size=3, pupil=1)
    # THE CHANDELIER: post, 43-wide crossbar, six hanging icicles (behind the ears), five candles
    m.box(-2, 2, 26, 29, -11, -9, "ice")
    m.box(-21, 21, 29, 30, -11, -9, "ice")
    for x in (-19, -13, -7, 7, 13, 19):
        m.box(x - 1, x + 1, 22, 28, -10, -8, "ice")
        m.box(x, x, 19, 21, -9, -9, "ice")
    for x in (-16, -10, 10, 16):
        m.box(x, x, 31, 34, -10, -10, "candle")
        m.box(x, x, 35, 35, -10, -10, "flame")
    m.box(0, 0, 31, 33, -10, -10, "candle")
    m.box(0, 0, 34, 34, -10, -10, "flame")
    return m
```

- [ ] **Step 7: Write `designs/nonno_ghiacciaio.py`** (Secret — grandpa glacier; exaggerated feature: the beard)

```python
"""Nonno Ghiacciaio (Secret): a mountain-shaped grandfather whose snow beard is the whole
lower body, tiny boots below, a wool cap with one gold medal on top. Slow shiver. Front = -Z."""
from ..voxel import VoxelModel


def build() -> VoxelModel:
    m = VoxelModel("Nonno Ghiacciaio", "Secret")
    m.role("ice", "#8FB8D6").role("ice_dark", "#5E86A8").role("snow", "#F4F8FB").role("wool", "#B23A3A").role("gold", "#D4AF37").role("ink", "#2A2530")
    m.height_scale = 1.46
    m.motion = "shiver"
    m.fx = [
        {"kit": "aura1", "color": [200, 232, 245], "rate": 8},
        {"kit": "snow", "color": [255, 255, 255], "rate": 6},
        {"kit": "glare", "color": [200, 232, 245], "size": 0.5},
    ]
    # mountain base: terraces y 12..18, half-width 14 -> 11
    for i, y in enumerate(range(12, 19)):
        w = 14 - i // 2
        m.box(-w, w, y, y, -(w - 3), w - 3, "ice")
    # head: a flat-fronted block so the face sits on one layer (z = -8)
    m.box(-10, 10, 19, 30, -8, 8, "ice")
    # peak: terraces y 31..37, half-width 8 -> 2
    for i, y in enumerate(range(31, 38)):
        w = 8 - i
        m.box(-w, w, y, y, -max(2, w - 2), max(2, w - 2), "ice")
    # crevasses: recolour only (peak front/back, head sides)
    for x in (-3, 2):
        m.paint(x, x, 31, 36, -20, 20, "ice_dark")
    m.paint(-10, -10, 20, 28, -2, 0, "ice_dark")
    m.paint(10, 10, 20, 28, -2, 0, "ice_dark")
    # THE BEARD: the whole lower body, in front of and around the base
    m.stepped_ellipsoid(0, 10, -3, 15, 8, 11, "snow")
    m.keep_above(3)
    # boots poking out under the beard
    m.box(-5, -2, 0, 2, -5, -1, "ink")
    m.box(2, 5, 0, 2, -5, -1, "ink")
    # face: eyes, bushy proud eyebrows, proud nose, moustache over the beard line
    m.eyes([(-4, 25), (4, 25)], z=-8, size=3, pupil=1)
    m.box(-7, -2, 27, 28, -9, -9, "snow")
    m.box(2, 7, 27, 28, -9, -9, "snow")
    m.box(-1, 1, 22, 23, -9, -9, "ice_dark")
    m.box(-5, 5, 19, 20, -9, -9, "snow")
    # wool cap on the peak, pompom, one gold medal
    m.box(-4, 4, 36, 40, -3, 3, "wool")
    m.box(0, 0, 41, 42, 0, 0, "snow")
    m.box(-1, 1, 38, 39, -4, -4, "gold")
    return m
```

- [ ] **Step 8: Run the design tests**

Run: `cd tools && python -m pytest brainrot_forge/tests/test_designs.py -q`
Expected: `13 passed` (4 parametrized tests x 3 designs + 1). If `test_eyes_face_minus_z` fails for a design, the eye layer `z` passed to `.eyes()` is not that head's front layer — fix the design's `z`, never the test. If `validate()` reports a height outside 25–45, adjust the y ranges, not the gate.

- [ ] **Step 9: Commit**

```bash
git add tools/brainrot_forge/voxel.py tools/brainrot_forge/tests/test_voxel.py tools/brainrot_forge/designs tools/brainrot_forge/tests/test_designs.py
git commit -m "feat(forge): three Frozen Tundra pilot designs (Epic/Legendary/Secret) + paint helper

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

### Task 6: CLI build + preview approval gate

**Files:**
- Create: `tools/brainrot_forge/__main__.py`, `tools/brainrot_forge/tests/test_cli.py`
- Create at runtime (git-ignored): `tools/out/pilot/pilot_batch.glb`, `manifest.json`, `previews/*.png`; add `tools/.gitignore` containing `out/`.

**Interfaces:**
- Consumes: `DESIGNS`, `PILOT`, `bake`, `write_glb`, `build_manifest`, `contact_sheet`.
- Produces: `main(argv) -> int`; `python -m brainrot_forge build pilot [--out DIR] [--flip-z]` and `python -m brainrot_forge list`.

- [ ] **Step 1: Write the failing test** — `tools/brainrot_forge/tests/test_cli.py`

```python
import json
from brainrot_forge.__main__ import main


def test_build_pilot_writes_batch(tmp_path, capsys):
    assert main(["build", "pilot", "--out", str(tmp_path)]) == 0
    assert (tmp_path / "pilot_batch.glb").stat().st_size > 1000
    man = json.loads((tmp_path / "manifest.json").read_text())
    assert set(man["models"]) == {"Guantone Brontolone", "Alce Lampadario", "Nonno Ghiacciaio"}
    assert (tmp_path / "previews" / "contact_sheet.png").exists()
    out = capsys.readouterr().out
    assert "Nonno Ghiacciaio" in out and "triangles" in out


def test_list(capsys):
    assert main(["list"]) == 0
    assert "Alce Lampadario" in capsys.readouterr().out
```

Run: `cd tools && python -m pytest brainrot_forge/tests/test_cli.py -q` → Expected: `ModuleNotFoundError: No module named 'brainrot_forge.__main__'`.

- [ ] **Step 2: Write `tools/brainrot_forge/__main__.py`**

```python
"""CLI: python -m brainrot_forge build pilot [--out out/pilot] [--flip-z] | list"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .bake import BudgetError, bake, triangle_report
from .designs import DESIGNS, PILOT
from .export_glb import build_manifest, write_glb
from .render import contact_sheet

BATCHES = {"pilot": PILOT}


def build(batch_name: str, out: Path, flip_z: bool) -> int:
    names = BATCHES[batch_name]
    batch = []
    for name in names:
        model = DESIGNS[name]()
        problems = model.validate()
        if problems:
            print(f"REFUSED {name}: " + "; ".join(problems))
            return 1
        try:
            meshes = bake(model)
        except BudgetError as e:
            print(f"REFUSED {e}")
            return 1
        batch.append((model, meshes))
    out.mkdir(parents=True, exist_ok=True)
    write_glb(out / f"{batch_name}_batch.glb", batch, flip_z=flip_z)
    manifest = build_manifest(batch)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2))
    contact_sheet(batch, out / "previews")
    print(f"{'name':<22} {'rarity':<10} {'roles':>5} {'triangles':>9} {'bbox studs (w,h,d)':>22}")
    for model, meshes in batch:
        e = manifest["models"][model.name]
        print(f"{model.name:<22} {model.rarity:<10} {len(meshes):>5} {e['totalTriangles']:>9} {str(tuple(e['bbox'])):>22}")
        for role, tris in triangle_report(meshes).items():
            print(f"    {role:<18} {tris:>6} triangles  {model.palette[role]}")
    print(f"wrote {out / (batch_name + '_batch.glb')}, manifest.json, previews/contact_sheet.png")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="brainrot_forge")
    sub = p.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build"); b.add_argument("batch", choices=sorted(BATCHES)); b.add_argument("--out"); b.add_argument("--flip-z", action="store_true")
    sub.add_parser("list")
    a = p.parse_args(argv)
    if a.cmd == "list":
        for name, fn in DESIGNS.items():
            m = fn()
            print(f"{name:<22} {m.rarity:<10} {m.world}")
        return 0
    return build(a.batch, Path(a.out or f"out/{a.batch}"), a.flip_z)


if __name__ == "__main__":
    sys.exit(main())
```

Also: `printf 'out/\n' > tools/.gitignore`.

- [ ] **Step 3: Run all tests**

Run: `cd tools && python -m pytest brainrot_forge/tests -q`
Expected: all green (`12 + 10 + 7 + 4 + 13 + 2 = 48 passed`).

- [ ] **Step 4: Build the pilot batch and LOOK at it**

Run: `cd tools && python -m brainrot_forge build pilot`
Expected: the table prints three rows with triangles between 200 and 8000 each; `out/pilot/previews/contact_sheet.png` exists. Open it (`start out\pilot\previews\contact_sheet.png` from PowerShell, or `SendUserFile`) and check every design against the standard's design language: one exaggerated feature reads at the pad-distance tile, eyes visible from the front-quarter, 2–3 main colours, nothing floating. Iterate the design scripts until they read well — re-running the build takes seconds and touches nothing in Studio.

- [ ] **Step 5: USER GATE — send `contact_sheet.png` to the user and wait for approval**

Send the contact sheet (`SendUserFile`, display `render`) with one line per model naming the exaggerated feature. Do not proceed to Task 7 until the user approves the three looks (swaps are done by editing the design script and re-running Step 4).

- [ ] **Step 6: Commit**

```bash
git add tools/.gitignore tools/brainrot_forge/__main__.py tools/brainrot_forge/tests/test_cli.py
git commit -m "feat(forge): build CLI producing the batch glb, manifest and preview contact sheet

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

### Task 7: `BrainrotBudget` — the build-time gate (mirror + Studio install + live checks)

**Files:**
- Create: `game-src/BrainrotBudget.lua` (mirror), then `game.ServerStorage.BrainrotBudget` (ModuleScript) with identical source.

**Interfaces:**
- Produces (Luau): `M.report(model) -> table` (every counter in the standard §3), `M.compare(model) -> { rows = {...}, verdict = "PASS"|"WARN"|"FAIL" }`, `M.review(model) -> string`, `M.compareMany(models) -> string`, `M.baseline(folder, predicate?) -> table`, `M.triangles(model) -> number?, string?`; constants `M.BASELINE`, `M.RANGES`, `M.FORBIDDEN`.
- Usage from the command bar / MCP in Edit mode: `local B = require(game.ServerStorage.BrainrotBudget:Clone())` — always require a **clone** (an Edit session caches `require` per instance, so a re-edited module would otherwise run stale code).

- [ ] **Step 1: Write `game-src/BrainrotBudget.lua`**

```lua
--[[ ServerStorage.BrainrotBudget -- BUILD-TIME performance/build gate for brainrot templates.

Standard: docs/brainrot-build-standard.md (section 2.1 caps, section 3 report). The baseline is
the 148 imported .glb pack models, measured 2026-09-17 (p50 / p90). Never required by game code;
run from the command bar / MCP in Edit mode:

    local B = require(game.ServerStorage.BrainrotBudget:Clone())
    print(B.review(game.ReplicatedStorage.BrainrotModels["Nonno Ghiacciaio"]))
    print(B.compareMany({ modelA, modelB, ... }))       -- side-by-side columns
    print(game:GetService("HttpService"):JSONEncode(B.baseline(folder, predicate)))

Verdicts: PASS <= typical, WARN <= max, FAIL above max or any forbidden object present.
]]
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local M = {}

-- pack p50 / p90, 148 rigged-mesh models, 2026-09-17 (standard section 1.2)
M.BASELINE = {
	baseParts = { p50 = 11, p90 = 19 }, visibleParts = { p50 = 8, p90 = 14 }, invisibleParts = { p50 = 3, p90 = 6 },
	meshParts = { p50 = 8, p90 = 14 }, descendants = { p50 = 57, p90 = 111 },
	particleEmitters = { p50 = 4, p90 = 16 }, particlesAlive = { p50 = 43, p90 = 152 },
	surfaceAppearances = { p50 = 1, p90 = 1 }, neonParts = { p50 = 0, p90 = 0 },
	attachments = { p50 = 29, p90 = 52 }, beams = { p50 = 0, p90 = 0 }, transparentParts = { p50 = 0, p90 = 0 },
}
-- standard section 2.1: typical (PASS) and max (WARN up to, FAIL above)
M.RANGES = {
	{ key = "baseParts", typical = 15, max = 20 }, { key = "visibleParts", typical = 11, max = 14 },
	{ key = "invisibleParts", typical = 3, max = 3 }, { key = "meshParts", typical = 11, max = 14 },
	{ key = "descendants", typical = 60, max = 80 }, { key = "particleEmitters", typical = 6, max = 8 },
	{ key = "particlesAlive", typical = 80, max = 100 }, { key = "attachments", typical = 6, max = 8 },
	{ key = "surfaceAppearances", typical = 1, max = 1 }, { key = "beams", typical = 0, max = 2 },
	{ key = "neonParts", typical = 0, max = 3 }, { key = "transparentParts", typical = 0, max = 1 },
}
M.FORBIDDEN = { "unions", "trails", "lights", "highlights", "scripts", "localScripts", "moduleScripts", "motor6d",
	"bones", "welds", "constraints", "humanoids", "animationControllers", "sounds", "billboardGuis", "surfaceGuis",
	"decals", "textures", "textureIds", "canCollideParts", "surfaceAppearanceMaps" }
M.ALLOWED_MATERIALS = { Plastic = true, SmoothPlastic = true, Neon = true }

local COUNTERS = { "descendants", "baseParts", "visibleParts", "invisibleParts", "meshParts", "parts", "unions", "wedges",
	"attachments", "bones", "motor6d", "welds", "weldConstraints", "constraints", "particleEmitters", "particlesAlive",
	"trails", "beams", "lights", "highlights", "scripts", "localScripts", "moduleScripts", "decals", "textures",
	"textureIds", "surfaceAppearances", "surfaceAppearanceMaps", "materialVariants", "neonParts", "transparentParts",
	"canCollideParts", "unanchoredParts", "castShadowParts", "sounds", "billboardGuis", "surfaceGuis", "humanoids",
	"animationControllers", "uniqueMeshIds", "other" }

function M.report(model)
	local r = { name = model.Name, className = model.ClassName, materials = {},
		hasPrimaryPart = model:IsA("Model") and model.PrimaryPart ~= nil, attributes = model:GetAttributes() }
	for _, k in ipairs(COUNTERS) do r[k] = 0 end
	local meshIds = {}
	for _, d in ipairs(model:GetDescendants()) do
		r.descendants += 1
		if d:IsA("BasePart") then
			r.baseParts += 1
			if d.Transparency >= 1 then r.invisibleParts += 1 else
				r.visibleParts += 1
				if d.Transparency > 0 then r.transparentParts += 1 end
			end
			if d.Material == Enum.Material.Neon then r.neonParts += 1 end
			if d.MaterialVariant ~= "" then r.materialVariants += 1 end
			if d.CanCollide then r.canCollideParts += 1 end
			if not d.Anchored then r.unanchoredParts += 1 end
			if d.CastShadow then r.castShadowParts += 1 end
			r.materials[d.Material.Name] = (r.materials[d.Material.Name] or 0) + 1
			if d:IsA("MeshPart") then
				r.meshParts += 1
				meshIds[d.MeshId] = true
				if d.TextureID ~= "" then r.textureIds += 1 end
			elseif d:IsA("UnionOperation") then r.unions += 1
			elseif d:IsA("WedgePart") or d:IsA("CornerWedgePart") then r.wedges += 1
			elseif d:IsA("Part") then r.parts += 1 end
		elseif d:IsA("Bone") then r.bones += 1              -- Bone IsA Attachment: test first
		elseif d:IsA("Attachment") then r.attachments += 1
		elseif d:IsA("ParticleEmitter") then
			r.particleEmitters += 1
			r.particlesAlive += d.Rate * (d.Lifetime.Min + d.Lifetime.Max) * 0.5
		elseif d:IsA("Trail") then r.trails += 1
		elseif d:IsA("Beam") then r.beams += 1
		elseif d:IsA("Light") then r.lights += 1
		elseif d:IsA("Highlight") then r.highlights += 1
		elseif d:IsA("LocalScript") then r.localScripts += 1
		elseif d:IsA("ModuleScript") then r.moduleScripts += 1
		elseif d:IsA("Script") then r.scripts += 1
		elseif d:IsA("Texture") then r.textures += 1           -- Texture IsA Decal: test first
		elseif d:IsA("Decal") then r.decals += 1
		elseif d:IsA("SurfaceAppearance") then
			r.surfaceAppearances += 1
			for _, map in ipairs({ d.NormalMap, d.MetalnessMap, d.RoughnessMap }) do
				if map ~= "" then r.surfaceAppearanceMaps += 1 end
			end
		elseif d:IsA("Motor6D") then r.motor6d += 1
		elseif d:IsA("WeldConstraint") then r.weldConstraints += 1
		elseif d:IsA("JointInstance") then r.welds += 1
		elseif d:IsA("Constraint") then r.constraints += 1
		elseif d:IsA("Sound") then r.sounds += 1
		elseif d:IsA("BillboardGui") then r.billboardGuis += 1
		elseif d:IsA("SurfaceGui") then r.surfaceGuis += 1
		elseif d:IsA("Humanoid") then r.humanoids += 1
		elseif d:IsA("AnimationController") then r.animationControllers += 1
		else r.other += 1 end
	end
	for _ in pairs(meshIds) do r.uniqueMeshIds += 1 end
	r.particlesAlive = math.floor(r.particlesAlive + 0.5)
	return r
end

local function worst(a, b)
	local rank = { PASS = 1, WARN = 2, FAIL = 3 }
	return rank[b] > rank[a] and b or a
end

function M.compare(model)
	local r = M.report(model)
	local rows, verdict = {}, "PASS"
	for _, range in ipairs(M.RANGES) do
		local v = r[range.key]
		local b = M.BASELINE[range.key] or {}
		local vd = (v <= range.typical) and "PASS" or (v <= range.max and "WARN" or "FAIL")
		verdict = worst(verdict, vd)
		rows[#rows + 1] = { key = range.key, value = v, p50 = b.p50, p90 = b.p90, typical = range.typical, max = range.max, verdict = vd }
	end
	for _, key in ipairs(M.FORBIDDEN) do
		local v = r[key]
		local vd = v > 0 and "FAIL" or "PASS"
		verdict = worst(verdict, vd)
		rows[#rows + 1] = { key = key, value = v, p50 = 0, p90 = 0, typical = 0, max = 0, verdict = vd }
	end
	for mat, n in pairs(r.materials) do
		if not M.ALLOWED_MATERIALS[mat] then
			verdict = "FAIL"
			rows[#rows + 1] = { key = "material:" .. mat, value = n, p50 = 0, p90 = 0, typical = 0, max = 0, verdict = "FAIL" }
		end
	end
	if not r.hasPrimaryPart then
		verdict = "FAIL"
		rows[#rows + 1] = { key = "PrimaryPart", value = 0, p50 = 1, p90 = 1, typical = 1, max = 1, verdict = "FAIL" }
	end
	return { report = r, rows = rows, verdict = verdict }
end

local function pad(s, n) s = tostring(s) return s .. string.rep(" ", math.max(0, n - #s)) end

function M.review(model)
	local c = M.compare(model)
	local r = c.report
	local out = { ("BrainrotBudget review: %s  [%s]"):format(model.Name, c.verdict),
		pad("metric", 24) .. pad("value", 8) .. pad("pack p50", 10) .. pad("pack p90", 10) .. pad("typical", 9) .. pad("max", 6) .. "verdict" }
	for _, row in ipairs(c.rows) do
		out[#out + 1] = pad(row.key, 24) .. pad(row.value, 8) .. pad(row.p50 or "-", 10) .. pad(row.p90 or "-", 10) .. pad(row.typical, 9) .. pad(row.max, 6) .. row.verdict
	end
	local within = true
	for _, row in ipairs(c.rows) do if row.p90 and row.value > row.p90 then within = false end end
	local function yn(b) return b and "yes" or "NO" end
	out[#out + 1] = ""
	out[#out + 1] = "1. Object count reasonable?        " .. yn(r.baseParts <= 20 and r.descendants <= 80)
	out[#out + 1] = "2. Geometry complexity reasonable? " .. yn(r.meshParts <= 14) .. " (triangles: run BrainrotBudget.triangles with Studio focused)"
	out[#out + 1] = "3. Texture/material use reasonable?" .. yn(r.textureIds == 0 and r.surfaceAppearances <= 1 and r.surfaceAppearanceMaps == 0 and r.neonParts <= 3)
	out[#out + 1] = "4. No unnecessary runtime effects? " .. yn(r.particleEmitters <= 8 and r.particlesAlive <= 100 and r.trails == 0 and r.lights == 0 and r.beams <= 2)
	out[#out + 1] = "5. No scripts?                     " .. yn(r.scripts + r.localScripts + r.moduleScripts == 0)
	out[#out + 1] = "6. No physics?                     " .. yn(r.constraints + r.motor6d + r.welds + r.humanoids + r.canCollideParts == 0)
	out[#out + 1] = "7. Profile within pack p90?        " .. yn(within)
	out[#out + 1] = "8. Visually belongs?               HUMAN CHECK (Play mode, 20-60 studs from a pad)"
	out[#out + 1] = "9. Completely original?            HUMAN CHECK (name/concept vs both rosters + lexicon)"
	return table.concat(out, "\n")
end

function M.compareMany(models)
	local keys = { "baseParts", "visibleParts", "meshParts", "descendants", "particleEmitters", "particlesAlive",
		"attachments", "bones", "motor6d", "surfaceAppearances", "neonParts", "beams", "trails", "lights", "scripts" }
	local reports = {}
	for i, m in ipairs(models) do reports[i] = M.report(m) end
	local lines = { pad("metric", 20) }
	for _, r in ipairs(reports) do lines[1] = lines[1] .. pad(r.name:sub(1, 16), 18) end
	for _, k in ipairs(keys) do
		local line = pad(k, 20)
		for _, r in ipairs(reports) do line = line .. pad(r[k], 18) end
		lines[#lines + 1] = line
	end
	return table.concat(lines, "\n")
end

-- Percentiles over a folder so BASELINE can be refreshed. predicate(model) -> bool selects the population
-- (pack = has a MeshPart AND a Motor6D; voxel = no MeshPart).
function M.baseline(folder, predicate)
	local reports = {}
	for _, m in ipairs(folder:GetChildren()) do
		if not predicate or predicate(m) then reports[#reports + 1] = M.report(m) end
	end
	local out = { n = #reports }
	for _, k in ipairs(COUNTERS) do
		local v = {}
		for i, r in ipairs(reports) do v[i] = r[k] end
		table.sort(v)
		local n = #v
		local function q(x) return n > 0 and v[math.max(1, math.min(n, math.ceil(x * n)))] or 0 end
		out[k] = { min = v[1] or 0, p50 = q(0.5), p75 = q(0.75), p90 = q(0.9), max = v[n] or 0 }
	end
	return out
end

-- Opaque triangles of this model alone, fitted to 6 studs, minus an empty-sky baseline. Needs Studio
-- to be RENDERING (window focused/visible); returns nil + reason when the counter is frozen.
function M.triangles(model)
	local SceneAnalysisService = game:GetService("SceneAnalysisService")
	local cam = workspace.CurrentCamera
	local savedCF, savedType = cam.CFrame, cam.CameraType
	local function opaque()
		local res = SceneAnalysisService:GetTriangleCompositionAsync()
		for _, c in ipairs(res.Children) do if c.Name == "Opaque" then return c.Sizes.Triangles, c.Sizes.Drawcalls end end
		return 0, 0
	end
	local site = Vector3.new(0, 4000, 0)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(site + Vector3.new(0, 3, 20), site)
	for _ = 1, 10 do RunService.RenderStepped:Wait() end
	local base = opaque()
	local clone = model:Clone()
	for _, d in ipairs(clone:GetDescendants()) do if d:IsA("BasePart") then d.Anchored = true end end
	clone.Parent = workspace
	local _, ext = clone:GetBoundingBox()
	if ext.Y > 0 then clone:ScaleTo(clone:GetScale() * (6 / ext.Y)) end
	local bcf = clone:GetBoundingBox()
	clone:PivotTo(clone:GetPivot() + (site - bcf.Position))
	for _ = 1, 15 do RunService.RenderStepped:Wait() end
	local withModel, drawcalls = opaque()
	clone:Destroy()
	cam.CameraType = savedType
	cam.CFrame = savedCF
	if withModel == base then
		return nil, "render counters did not change: Studio is not rendering (focus the 3D viewport) or the model drew nothing"
	end
	return withModel - base, ("drawcalls=%d"):format(drawcalls)
end

return M
```

- [ ] **Step 2: Install it in Studio as `game.ServerStorage.BrainrotBudget`**

Use `multi_edit` with `file_path = "game.ServerStorage.BrainrotBudget"`, `className = "ModuleScript"`, `datamodel_type = "Edit"`, and one edit `{ old_string = "", new_string = <the exact contents of game-src/BrainrotBudget.lua> }`. Then verify the byte count matches the mirror: `script_read` the module and compare `#Source` (from `execute_luau`: `return #game.ServerStorage.BrainrotBudget.Source`) against `wc -c game-src/BrainrotBudget.lua` (allow a difference only for CRLF vs LF).

- [ ] **Step 3: Live checks (`execute_luau`, Edit mode)**

```lua
local B = require(game.ServerStorage.BrainrotBudget:Clone())
local RS = game:GetService("ReplicatedStorage")
local ok, err = loadstring(game.ServerStorage.BrainrotBudget.Source)
assert(ok, "compile: " .. tostring(err))
local t = B.report(RS.BrainrotModels["Tralalero Tralala"])
assert(t.baseParts == 8 and t.meshParts == 5 and t.invisibleParts == 3 and t.particleEmitters == 6, "pack census mismatch: " .. game:GetService("HttpService"):JSONEncode(t))
assert(t.bones > 0 and t.motor6d == 5, "rig counters: bones=" .. t.bones .. " motor6d=" .. t.motor6d)
local v = B.compare(RS.BrainrotModels["Valanga Ruggente"])
assert(v.verdict == "FAIL", "Valanga should FAIL on baseParts")
assert(B.compare(RS.BrainrotModels["Tralalero Tralala"]).report.scripts == 0)
print(B.review(RS.BrainrotModels["Tralalero Tralala"]))
print(B.compareMany({ RS.BrainrotModels["Tralalero Tralala"], RS.BrainrotModels["Chimpanzini Bananini"], RS.BrainrotModels["Zero Assoluto"], RS.BrainrotModels["Valanga Ruggente"] }))
return "OK"
```

Expected: returns `"OK"`; the review for Tralalero shows `[FAIL]` (its rig residue — bones/motor6d — is forbidden for NEW models; that is the intended reading: the pack's *rendering* profile is the baseline, its import cruft is not), Valanga FAILs on `baseParts 1106`.

- [ ] **Step 4: Commit the mirror**

```bash
git add game-src/BrainrotBudget.lua
git commit -m "feat(studio): BrainrotBudget build-time gate (mirror of ServerStorage.BrainrotBudget)

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

### Task 8: `BrainrotForge` — the assembler (mirror + Studio install + synthetic test)

**Files:**
- Create: `game-src/BrainrotForge.lua` (mirror), then `game.ServerStorage.BrainrotForge` (ModuleScript) with identical source.

**Interfaces:**
- Consumes: `manifest.json` (Task 3 shape), `BrainrotBudget` (Task 7), `BrainrotFX.apply(model, rarity)` (existing, recipes added in Task 9).
- Produces (Luau): `M.Assemble(importedRoot: Instance, manifestJson: string, opts?: { tile: boolean?, replace: boolean?, fx: boolean? }) -> { [name] = Model }, { [name] = errorString }`; `M.AssembleOne(importedRoot, name, entry, opts) -> Model` (throws); constants `M.TARGET_FOLDER = "BrainrotModels"`, `M.TILE_VARIANT = "BrainrotTile"`, `M.BACKUP_FOLDER = "AuditBackups"`.

- [ ] **Step 1: Write `game-src/BrainrotForge.lua`**

```lua
--[[ ServerStorage.BrainrotForge -- BUILD-TIME assembler: File > Import 3D output + manifest.json
-> brainrot templates that satisfy the content-drop contract (docs/brainrot-build-standard.md, 2.7).

Never required by game code. From the command bar / MCP in Edit mode, after the user has imported
tools/out/<batch>/<batch>_batch.glb (the importer parks it under workspace.AuxScene):

    local F = require(game.ServerStorage.BrainrotForge:Clone())
    local models, errors = F.Assemble(workspace.AuxScene, MANIFEST_JSON, { tile = true })

Per model, all-or-nothing: on any error the imported parts are put back under the import root with
their original names and nothing is parented into BrainrotModels. Existing templates are never
overwritten unless opts.replace, and then the old one is moved to ServerStorage.AuditBackups first.
]]
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local M = {}
M.TARGET_FOLDER = "BrainrotModels"
M.TILE_VARIANT = "BrainrotTile"
M.BACKUP_FOLDER = "AuditBackups"

local function hexToColor3(hex)
	local h = hex:gsub("#", "")
	return Color3.fromRGB(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16))
end

local function findParts(root, names)
	local wanted, found, missing = {}, {}, {}
	for _, n in ipairs(names) do wanted[n] = true end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and wanted[d.Name] then
			if found[d.Name] then error(("duplicate imported part %q under %s"):format(d.Name, root:GetFullName())) end
			found[d.Name] = d
		end
	end
	for _, n in ipairs(names) do if not found[n] then missing[#missing + 1] = n end end
	if #missing > 0 then error("missing imported parts: " .. table.concat(missing, ", ")) end
	return found
end

local function flags(p)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

-- Builds one template. Throws on any problem; the caller restores the imported parts.
function M.AssembleOne(root, name, entry, opts)
	opts = opts or {}
	local tile = opts.tile ~= false
	local parts = findParts(root, entry.parts)
	local model = Instance.new("Model")
	model.Name = name
	for _, partName in ipairs(entry.parts) do
		local role = partName:sub(#name + 3) -- strip "<name>__"
		local p = parts[partName]
		assert(entry.roles[role], ("manifest has no colour for role %q"):format(role))
		p.Name = role
		p.Color = hexToColor3(entry.roles[role])
		if p:IsA("MeshPart") then
			-- PluginSecurity write: fine from the command bar / MCP; never touch RenderFidelity here
			local okCF = pcall(function() p.CollisionFidelity = Enum.CollisionFidelity.Box end)
			if not okCF then warn("BrainrotForge: could not set CollisionFidelity on " .. partName .. " (set it by hand in Properties)") end
		end
		if tile then
			p.Material = Enum.Material.Plastic       -- BrainrotTile.BaseMaterial; a variant is ignored on any other Material
			p.MaterialVariant = M.TILE_VARIANT
		else
			p.Material = Enum.Material.SmoothPlastic
			p.MaterialVariant = ""
		end
		flags(p)
		for _, child in ipairs(p:GetChildren()) do child:Destroy() end -- the importer adds nothing we want
		p.Parent = model
	end
	local cf, size = model:GetBoundingBox()
	local rootPart = Instance.new("Part")
	rootPart.Name = "RootPart"
	rootPart.Size = size
	rootPart.CFrame = cf
	rootPart.Transparency = 1
	flags(rootPart)
	rootPart.Parent = model
	model.PrimaryPart = rootPart
	model:SetAttribute("HeightScale", entry.heightScale or 1)
	model:SetAttribute("WidthScale", entry.widthScale or 1)
	if entry.fx and opts.fx ~= false then
		local FX = require(ReplicatedStorage.Modules.BrainrotFX:Clone())
		local n = FX.apply(model, entry.rarity)
		if n == 0 then warn(("BrainrotForge: %s has fx in its manifest but BrainrotFX.RECIPES has no row for it (add the recipe, then FX.apply again)"):format(name)) end
	end
	return model
end

function M.Assemble(root, manifestJson, opts)
	opts = opts or {}
	local manifest = HttpService:JSONDecode(manifestJson)
	local folder = ReplicatedStorage:FindFirstChild(M.TARGET_FOLDER) or error("ReplicatedStorage." .. M.TARGET_FOLDER .. " missing")
	local models, errors = {}, {}
	local names = {}
	for name in pairs(manifest.models) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		local entry = manifest.models[name]
		local existing = folder:FindFirstChild(name)
		if existing and not opts.replace then
			errors[name] = "a template named " .. name .. " already exists; pass { replace = true } to back it up and replace"
		else
			-- remember the imported parts so a failure can put them back exactly as they were
			local originals = {}
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("BasePart") then originals[#originals + 1] = { part = d, name = d.Name, parent = d.Parent } end
			end
			local ok, result = pcall(M.AssembleOne, root, name, entry, opts)
			if ok then
				if existing then
					local backups = ServerStorage:FindFirstChild(M.BACKUP_FOLDER) or Instance.new("Folder")
					backups.Name = M.BACKUP_FOLDER
					backups.Parent = ServerStorage
					existing.Name = ("BrainrotForge_%s_%s"):format(name, os.date("%Y-%m-%d"))
					existing.Parent = backups
				end
				result.Parent = folder
				models[name] = result
				print(("BrainrotForge: assembled %s (%d parts)"):format(name, #entry.parts + 1))
			else
				for _, o in ipairs(originals) do
					if o.part.Parent ~= o.parent then o.part.Name = o.name; o.part.Parent = o.parent end
				end
				errors[name] = tostring(result)
				warn("BrainrotForge: " .. name .. " FAILED: " .. tostring(result))
			end
		end
	end
	local budget = ServerStorage:FindFirstChild("BrainrotBudget")
	if budget then
		local B = require(budget:Clone())
		for _, name in ipairs(names) do if models[name] then print(B.review(models[name])) end end
	end
	return models, errors
end

return M
```

- [ ] **Step 2: Install it as `game.ServerStorage.BrainrotForge`** (same `multi_edit` create pattern as Task 7 Step 2; verify the byte count against the mirror).

- [ ] **Step 3: Synthetic test in Studio (`execute_luau`, Edit mode) — plain Parts stand in for imported MeshParts**

```lua
local RS, SS = game:GetService("ReplicatedStorage"), game:GetService("ServerStorage")
assert(loadstring(SS.BrainrotForge.Source), "compile")
local F = require(SS.BrainrotForge:Clone())
-- fake import root
local root = Instance.new("Model"); root.Name = "__ForgeTest_AuxScene"; root.Parent = workspace
local function fake(name, size, pos)
	local p = Instance.new("Part"); p.Name = name; p.Size = size; p.Position = pos; p.Anchored = false; p.Parent = root; return p
end
fake("Forge Test__body", Vector3.new(4, 6, 2), Vector3.new(0, 3, 0))
fake("Forge Test__eye", Vector3.new(1, 1, 0.2), Vector3.new(1, 5, -1.1))
local manifest = [[{"version":1,"pitch":0.2,"models":{"Forge Test":{"rarity":"Epic","world":"Tundra","roles":{"body":"#C0392B","eye":"#F5F5F5"},"parts":["Forge Test__body","Forge Test__eye"],"heightScale":1.3,"widthScale":1,"motion":"hover","material":"Plastic","fx":null,"bbox":[4,6,2.1],"triangles":{"body":12,"eye":12},"totalTriangles":24}}}]]
local models, errors = F.Assemble(root, manifest, { tile = false })
local m = models["Forge Test"]
assert(m and m.Parent == RS.BrainrotModels, "not assembled: " .. game:GetService("HttpService"):JSONEncode(errors))
assert(m.PrimaryPart and m.PrimaryPart.Name == "RootPart" and m.PrimaryPart.Transparency == 1)
assert(m:GetAttribute("HeightScale") == 1.3 and m:GetAttribute("WidthScale") == 1)
local body = m:FindFirstChild("body"); local eye = m:FindFirstChild("eye")
assert(body and eye and body.Color == Color3.fromRGB(192, 57, 43) and eye.Color == Color3.fromRGB(245, 245, 245))
for _, p in ipairs(m:GetChildren()) do
	assert(p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch and not p.CastShadow, p.Name .. " flags")
	assert(p.Material == Enum.Material.SmoothPlastic and p.MaterialVariant == "", p.Name .. " material")
end
-- second run must refuse, third run with replace must back up
fake("Forge Test__body", Vector3.new(4, 6, 2), Vector3.new(0, 3, 0)); fake("Forge Test__eye", Vector3.new(1, 1, 0.2), Vector3.new(1, 5, -1.1))
local _, e2 = F.Assemble(root, manifest, { tile = false })
assert(e2["Forge Test"] and e2["Forge Test"]:find("already exists"), "should refuse overwrite")
assert(#root:GetChildren() == 2, "refused run must leave the imported parts in place")
local m3 = F.Assemble(root, manifest, { tile = false, replace = true })["Forge Test"]
assert(m3 and m3 ~= m and SS.AuditBackups:FindFirstChild("BrainrotForge_Forge Test_" .. os.date("%Y-%m-%d")), "replace should back up")
-- failure path: a manifest naming a part that is not there restores nothing and parents nothing
local bad = manifest:gsub("Forge Test__eye", "Forge Test__nose")
local _, e4 = F.Assemble(root, bad, { tile = false, replace = true })
assert(e4["Forge Test"] and e4["Forge Test"]:find("missing imported parts"), tostring(e4["Forge Test"]))
-- cleanup: nothing of this test may remain
m3:Destroy(); root:Destroy()
SS.AuditBackups["BrainrotForge_Forge Test_" .. os.date("%Y-%m-%d")]:Destroy()
assert(not RS.BrainrotModels:FindFirstChild("Forge Test"))
return "OK"
```

Expected: `"OK"` and no `Forge Test` model left anywhere (`search_game_tree` keywords `Forge Test` returns nothing).

- [ ] **Step 4: Commit the mirror**

```bash
git add game-src/BrainrotForge.lua
git commit -m "feat(studio): BrainrotForge assembler (mirror of ServerStorage.BrainrotForge)

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

### Task 9: `BrainrotFX` recipe rows for the two Legendary+ pilots (live + mirror)

**Files:**
- Modify: `ReplicatedStorage.Modules.BrainrotFX` (live, at the `local RECIPES = {` anchor, line ~111), `game-src/BrainrotFX.lua` (mirror).

**Interfaces:**
- Consumes: `E(kit, color, extra)` and the colour constants already defined in `BrainrotFX` (`WHITE`, `C(r,g,b)`), kits `glow`, `flare`, `aura1`, `aura2`, `snow`, `glare`.
- Produces: `BrainrotFX.RECIPES["Alce Lampadario"]`, `BrainrotFX.RECIPES["Nonno Ghiacciaio"]` — exactly the `fx` rows in `manifest.json`.

- [ ] **Step 1: Confirm the anchor is unique and read it live**

`script_grep` for `local RECIPES = {` → expect exactly one hit in `ReplicatedStorage.Modules.BrainrotFX` (backups under `ServerStorage.AuditBackups` may also match — ignore them). Then `script_read` that script, lines 100–115, and confirm the line reads exactly `local RECIPES = {`.

- [ ] **Step 2: Insert the two rows (live) with `multi_edit`** — `file_path = "game.ReplicatedStorage.Modules.BrainrotFX"`, `datamodel_type = "Edit"`:

```
old_string:
local RECIPES = {

new_string:
local RECIPES = {
	["Alce Lampadario"] = { -- chandelier moose (Legendary, Forge pilot): candle glow at the crown, icy aura
		E("glow", C(255, 210, 120)), E("flare", C(255, 210, 120)), E("aura2", C(191, 230, 255), { rate = 6 }),
	},
	["Nonno Ghiacciaio"] = { -- grandpa glacier (Secret, Forge pilot): frost aura, falling snow, a cold glare
		E("aura1", C(200, 232, 245), { rate = 8 }), E("snow", WHITE, { rate = 6 }), E("glare", C(200, 232, 245), { size = 0.5 }),
	},
```

Both rows must match the `fx` arrays in `tools/out/pilot/manifest.json` kit-for-kit and value-for-value (the manifest is the source; this is its Luau transcription).

- [ ] **Step 3: Compile-gate and check the rows exist (`execute_luau`)**

```lua
local src = game.ReplicatedStorage.Modules.BrainrotFX.Source
assert(loadstring(src), "BrainrotFX no longer compiles")
local FX = require(game.ReplicatedStorage.Modules.BrainrotFX:Clone())
assert(#FX.RECIPES["Alce Lampadario"] == 3 and #FX.RECIPES["Nonno Ghiacciaio"] == 3)
assert(FX.RECIPES["Nonno Ghiacciaio"][2].kit == "snow" and FX.KITS.snow and FX.KITS.glare and FX.KITS.glow)
return "OK"
```

- [ ] **Step 4: Mirror**

Compare sizes first: `execute_luau` → `return #game.ReplicatedStorage.Modules.BrainrotFX.Source` vs `wc -c game-src/BrainrotFX.lua`. If they differ by more than the inserted text (the mirror is stale), overwrite the mirror with the full live source (`script_read` entire file → write `game-src/BrainrotFX.lua`); otherwise apply the same insertion with `Edit` at the same anchor. Then:

```bash
git add game-src/BrainrotFX.lua
git commit -m "feat(fx): BrainrotFX recipes for the two Legendary+ Forge pilots (pack-kit clones)

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

### Task 10: Import the batch (user) and assemble the templates

**Files:**
- Input: `tools/out/pilot/pilot_batch.glb`, `tools/out/pilot/manifest.json` (Task 6 output, user-approved).
- Studio: `workspace.AuxScene` (importer output) → `ReplicatedStorage.BrainrotModels.{Guantone Brontolone, Alce Lampadario, Nonno Ghiacciaio}`.

- [ ] **Step 1: USER STEP — File > Import 3D**

Ask the user to: Studio → **File > Import 3D** → pick `C:\Users\m\Coding\skip-a-brainrot\tools\out\pilot\pilot_batch.glb` → in the preview dialog keep the defaults (no rig, no anchoring changes) and click **Import**. Tell them the result lands under `Workspace.AuxScene` (or a model named `pilot_batch`) and that nothing else changes until the assembler runs. Wait for them to confirm.

- [ ] **Step 2: Locate and sanity-check the import (`execute_luau`)**

```lua
local HS = game:GetService("HttpService")
local root = workspace:FindFirstChild("AuxScene") or workspace:FindFirstChild("pilot_batch") or error("no import root found; ask the user where Import 3D parked it")
local byName = {}
for _, d in ipairs(root:GetDescendants()) do if d:IsA("MeshPart") then byName[d.Name] = d end end
local wool, pupil = byName["Guantone Brontolone__wool"], byName["Guantone Brontolone__pupil"]
assert(wool and pupil, "expected parts not found: " .. HS:JSONEncode((function() local t = {} for n in pairs(byName) do t[#t + 1] = n end return t end)()))
local report = {
	partCount = (function() local n = 0 for _ in pairs(byName) do n += 1 end return n end)(),
	woolSize = tostring(wool.Size), meshIdSet = wool.MeshId ~= "",
	pupilIsInFront = pupil.Position.Z < wool.Position.Z,     -- front = -Z: the pupils must have the SMALLER Z
	scaleLooksRight = math.abs(wool.Size.Y - 4.6) < 0.3,        -- wool spans y 8..30 => 23 voxels * 0.2 = 4.6 studs
}
return HS:JSONEncode(report)
```

Expected: `partCount = 22` (6 + 8 + 8 roles), `meshIdSet = true`, `pupilIsInFront = true`, `scaleLooksRight = true`.
- If `pupilIsInFront` is false the importer mirrored Z: delete the import, rebuild with `python -m brainrot_forge build pilot --flip-z`, ask the user to import again, re-check.
- If `scaleLooksRight` is false by a factor of ~100 or ~0.01, the importer's unit setting was not studs: delete the import and ask the user to re-import with **Unit = studs** (Import 3D dialog → File General → Unit).
- If `meshIdSet` is false the import did not upload (EditableMesh trap): stop, the geometry will never replicate; re-import through the dialog.

- [ ] **Step 3: Assemble (`execute_luau`)** — paste the manifest inside a Luau long string:

```lua
local MANIFEST = [==[
<contents of tools/out/pilot/manifest.json, verbatim>
]==]
local F = require(game.ServerStorage.BrainrotForge:Clone())
local root = workspace:FindFirstChild("AuxScene") or workspace:FindFirstChild("pilot_batch")
local models, errors = F.Assemble(root, MANIFEST, { tile = true })
local HS = game:GetService("HttpService")
local names = {}
for n in pairs(models) do names[#names + 1] = n end
return HS:JSONEncode({ assembled = names, errors = errors })
```

Expected: `assembled` lists all three, `errors = {}`, and three `BrainrotBudget review` printouts in the output; each review must end `[PASS]` — if any row is WARN or FAIL, fix the design (not the gate) and rebuild.

- [ ] **Step 4: Verify the templates against the contract (`execute_luau`)**

```lua
local RS = game:GetService("ReplicatedStorage")
local HS = game:GetService("HttpService")
local out = {}
for _, name in ipairs({ "Guantone Brontolone", "Alce Lampadario", "Nonno Ghiacciaio" }) do
	local m = RS.BrainrotModels:FindFirstChild(name)
	assert(m, name .. " missing")
	assert(m.PrimaryPart and m.PrimaryPart.Name == "RootPart", name .. " PrimaryPart")
	local bp, mesh, fx = 0, 0, 0
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			bp += 1
			assert(d.Anchored and not d.CanCollide and not d.CanQuery and not d.CanTouch and not d.CastShadow, name .. "/" .. d.Name .. " flags")
			if d:IsA("MeshPart") then mesh += 1; assert(d.MeshId ~= "", d.Name .. " has no MeshId"); assert(d.Material == Enum.Material.Plastic and d.MaterialVariant == "BrainrotTile", d.Name .. " tile") end
		elseif d:IsA("ParticleEmitter") then fx += 1 end
	end
	local _, size = m:GetBoundingBox()
	out[name] = { baseParts = bp, meshParts = mesh, emitters = fx, height = size.Y, heightScale = m:GetAttribute("HeightScale") }
end
return HS:JSONEncode(out)
```

Expected: Guantone 7 BaseParts / 6 MeshParts / 0 emitters / height ≈ 6.2 / 1.3; Alce 9 / 8 / 3 / ≈ 7.2 / 1.36; Nonno 9 / 8 / 3 / ≈ 8.6 / 1.46. (Emitter counts = the recipe rows; hosts add invisible Parts, so BaseParts may read +1..+2 for the two with effects — still ≤ 20.)

- [ ] **Step 5: Leave `workspace.AuxScene` in place until the user has looked at the assembled models** (Task 12 shows them in Play); it is deleted in Task 13.

### Task 11: Roster rows in `BrainrotConfigTundra` (live + mirror)

**Files:**
- Modify: `ReplicatedStorage.Modules.BrainrotConfigTundra` (live), `game-src/place-full/ReplicatedStorage/Modules/BrainrotConfigTundra.lua` (re-mirrored from live).

- [ ] **Step 1: Read the anchors live**

`script_grep` each of `Name = "Pinguinotto Frappuccino"` (last Epic row), `Name = "Narvalino Trapanino"` (last Legendary row), `Name = "Balenone Iceberghino Trombonone"` (last Secret row) in `ReplicatedStorage.Modules.BrainrotConfigTundra`, then `script_read` ±3 lines around each hit and copy the **exact** full line text (tabs included) for the anchors below.

- [ ] **Step 2: Append one row after each tier's last row (`multi_edit`, three edits, each `old_string` = the exact live line, `new_string` = that line + the new row)**

```
after the Pinguinotto Frappuccino line:
	{ Name = "Guantone Brontolone", Rarity = "Epic", CashPerSecond = 108000, Weight = 0, Origin = "Forge" },

after the Narvalino Trapanino line:
	{ Name = "Alce Lampadario", Rarity = "Legendary", CashPerSecond = 230000, Weight = 0, Origin = "Forge" },

after the Balenone Iceberghino Trombonone line:
	{ Name = "Nonno Ghiacciaio", Rarity = "Secret", CashPerSecond = 900000, Weight = 0, Origin = "Forge", Motion = "shiver" },
```

If any live line does not match verbatim (collaborators edit this module), stop and re-read — never guess the anchor.

- [ ] **Step 3: Compile-gate and verify (`execute_luau`)**

```lua
local src = game.ReplicatedStorage.Modules.BrainrotConfigTundra.Source
assert(loadstring(src), "BrainrotConfigTundra no longer compiles")
local n, forge = 0, {}
for name, rarity, rest in src:gmatch('{%s*Name%s*=%s*"([^"]+)"%s*,%s*Rarity%s*=%s*"([^"]+)"([^}]*)}') do
	n += 1
	if rest:find('Origin%s*=%s*"Forge"') then forge[#forge + 1] = name .. "/" .. rarity .. (rest:find("Weight%s*=%s*0[^%d]") and " w0" or " W?") end
end
return ("%d entries; forge rows: %s"):format(n, table.concat(forge, ", "))
```

Expected: `113 entries; forge rows: Guantone Brontolone/Epic w0, Alce Lampadario/Legendary w0, Nonno Ghiacciaio/Secret w0`. Weight 0 means the throw pool is unchanged (the fish use the same idiom); the owner sets real weights when the pilot is approved.

- [ ] **Step 4: Re-mirror the whole module from live and commit**

`script_read` the entire live `BrainrotConfigTundra` → overwrite `game-src/place-full/ReplicatedStorage/Modules/BrainrotConfigTundra.lua` (the mirror was already stale). Then:

```bash
git add game-src/place-full/ReplicatedStorage/Modules/BrainrotConfigTundra.lua
git commit -m "feat(roster): three Forge pilot brainrots in BrainrotConfigTundra at Weight 0 (mirror resync)

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

### Task 12: In-game verification (the user's steps 8–12)

**Files:** none created; results are recorded in Task 13. All Studio work here is Play mode via `start_stop_play`, then the Client/Server DataModels with `execute_luau`.

- [ ] **Step 1: Budget comparison table (Edit mode, `execute_luau`)** — the pilots beside four pack and three voxel models:

```lua
local RS = game:GetService("ReplicatedStorage")
local B = require(game.ServerStorage.BrainrotBudget:Clone())
local names = { "Guantone Brontolone", "Alce Lampadario", "Nonno Ghiacciaio", "Tralalero Tralala", "Chimpanzini Bananini", "Las Capuchinas", "Los Crocodillitos", "Zero Assoluto", "Yeti Cappuccino", "Valanga Ruggente" }
local models = {}
for i, n in ipairs(names) do models[i] = RS.BrainrotModels[n] end
return B.compareMany(models)
```

Expected: the three pilots sit at or below the pack columns on every row and are 0 on bones/motor6d/scripts; the voxel columns show the 170–1,106 baseParts. Paste this table into the execution log (Task 13).

- [ ] **Step 2: Enter Play mode** — ensure ≥ 90 s since the last playtest (SessionLock), then `start_stop_play` with `is_start = true`; `get_studio_state` must list `Client` and `Server`. Never call `PDM.Load`.

- [ ] **Step 3: Spawn the pilots on a test plot (Server DM)**

```lua
local Spawner = require(game.ServerScriptService.Modules.BrainrotSpawner)
local bases = workspace.PlayerBases:GetChildren()
table.sort(bases, function(a, b) return a.Name < b.Name end)
-- pick the LAST plot (farthest from the spawn area); Spawn has no ownership check (documented test trick)
local plot = bases[#bases]
local placed = {}
for i, spec in ipairs({ { "Guantone Brontolone" }, { "Alce Lampadario" }, { "Nonno Ghiacciaio" }, { "Guantone Brontolone", "Golden" }, { "Nonno Ghiacciaio", nil, "Massive" }, { "Alce Lampadario", "Diamond" } }) do
	local m = Spawner.Spawn(plot, spec[1], i, spec[2], nil, spec[3])
	placed[#placed + 1] = m and (m:GetFullName() .. " mut=" .. tostring(spec[2]) .. " size=" .. tostring(spec[3])) or ("FAILED pad " .. i)
end
return plot.Name .. "\n" .. table.concat(placed, "\n")
```

Expected: six full names under `Workspace.PlayerBases.<Plot>.Pads`, none `FAILED`. Note the plot name for the next steps.

- [ ] **Step 4: Client-side checks (Client DM)** — replace `<Plot>` with the name from Step 3:

```lua
local HS = game:GetService("HttpService")
local CS = game:GetService("CollectionService")
local pads = workspace.PlayerBases["<Plot>"].Pads
local out = {}
for _, m in ipairs(pads:GetChildren()) do
	if m:IsA("Model") then
		local meshes, blank, emitters, unanchored, welds = 0, 0, 0, 0, 0
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("MeshPart") then meshes += 1; if d.MeshId == "" then blank += 1 end end
			if d:IsA("BasePart") and not d.Anchored then unanchored += 1 end
			if d:IsA("WeldConstraint") then welds += 1 end
			if d:IsA("ParticleEmitter") then emitters += 1 end
		end
		out[#out + 1] = { name = m.Name, meshes = meshes, blankMeshIds = blank, emitters = emitters, unanchored = unanchored, welds = welds,
			rootAnchored = m.PrimaryPart and m.PrimaryPart.Anchored, tagged = CS:HasTag(m, "BrainrotBody"),
			motion = m:GetAttribute("Motion"), mutation = m:GetAttribute("Mutation"), size = m:GetAttribute("Size") or m:GetAttribute("SizeVariant") }
	end
end
return HS:JSONEncode(out)
```

Expected per body: `blankMeshIds = 0` (the geometry replicated — the whole point), `rootAnchored = true`, `unanchored = meshes (+ hosts)`, `welds = unanchored`, `tagged = true`, `motion = "hover"` (Nonno: `"shiver"`), mutations/sizes set on the three variants. `emitters > 0` on Alce and Nonno.

- [ ] **Step 5: LOD and FX gate (Client DM)**

```lua
local RunService = game:GetService("RunService")
local pads = workspace.PlayerBases["<Plot>"].Pads
local target = pads:FindFirstChild("Nonno Ghiacciaio")
local cam = workspace.CurrentCamera
local function probe()
	local blanked, enabled, total = 0, 0, 0
	for _, d in ipairs(target:GetDescendants()) do
		if d:IsA("BasePart") then total += 1; if d.LocalTransparencyModifier >= 1 then blanked += 1 end end
		if d:IsA("ParticleEmitter") and d.Enabled then enabled += 1 end
	end
	return ("blanked %d/%d parts, emitters on %d"):format(blanked, total, enabled)
end
local centre = target:GetPivot().Position
cam.CameraType = Enum.CameraType.Scriptable
cam.CFrame = CFrame.lookAt(centre + Vector3.new(0, 20, 110), centre)   -- 110 studs: past LOD_FAR (70)
for _ = 1, 90 do RunService.Heartbeat:Wait() end
local far = probe()
cam.CFrame = CFrame.lookAt(centre + Vector3.new(0, 4, 25), centre)      -- 25 studs: inside LOD_NEAR (60)
for _ = 1, 90 do RunService.Heartbeat:Wait() end
local near = probe()
cam.CameraType = Enum.CameraType.Custom
return "FAR: " .. far .. "\nNEAR: " .. near
```

Expected: FAR blanks all but ~3 parts and turns every emitter off; NEAR restores everything. (CameraWatchdog may reclaim the camera after ~6 s in Play — if the probe reads identical values, re-run with `cam.CFrame` re-asserted every Heartbeat inside the wait loops.)

- [ ] **Step 6: Thumbnails and reveal (Client DM)**

`BrainrotThumb` and `CatchReveal` may carry script capabilities that block `require` from the sandbox; try it, and fall back to the human check.

```lua
local RS = game:GetService("ReplicatedStorage")
local ok, Thumb = pcall(require, RS.Modules.BrainrotThumb)
if not ok then return "BrainrotThumb not requirable from the sandbox (" .. tostring(Thumb) .. ") -> verify the Bag/Index tiles by eye" end
local out = {}
for _, n in ipairs({ "Guantone Brontolone", "Alce Lampadario", "Nonno Ghiacciaio" }) do
	local m = Thumb.master(n)
	out[#out + 1] = n .. ": master=" .. tostring(m ~= nil)
end
return table.concat(out, "\n")
```

Expected: `master=true` for all three. For the reveal: `script_read` `StarterPlayer.StarterPlayerScripts.CatchRevealClient` lines 1–80 to see the exact fields it forwards from `remotes.ThrowResult` to `CatchReveal.play`, then call `CatchReveal.play` once per pilot with a table carrying those fields (`Name`, the tier string, `Mutation = nil`, `Size = nil`, plus whatever else that file reads) inside `pcall`, and report the outcome. If `require` is blocked the same way, the user triggers a real throw later — record it as a human check.

- [ ] **Step 7: The user looks** — with the six bodies standing on the plot, ask the user to look at them in the Play viewport from a normal player position (or, with their OK, `screen_capture` after they bring Studio to the front — captures time out while Studio is minimised). Two questions for them: does each read as its concept at pad distance, and does `BrainrotTile` look right on the meshes (if not, re-run `Assemble` with `{ tile = false, replace = true }`).

- [ ] **Step 8: Stop Play** — `start_stop_play` with `is_start = false`. Spawned test bodies do not persist (nothing was written through the inventory). Wait ≥ 90 s before any further playtest.

- [ ] **Step 9: Triangle measurement (Edit mode, Studio in the FOREGROUND)** — ask the user to bring Studio to the front (or get their OK to foreground it), then:

```lua
local RS = game:GetService("ReplicatedStorage")
local B = require(game.ServerStorage.BrainrotBudget:Clone())
local out = {}
for _, n in ipairs({ "Tralalero Tralala", "Chimpanzini Bananini", "Las Capuchinas", "Los Crocodillitos", "Guantone Brontolone", "Alce Lampadario", "Nonno Ghiacciaio", "Zero Assoluto", "Valanga Ruggente" }) do
	local tris, note = B.triangles(RS.BrainrotModels[n])
	out[#out + 1] = n .. ": " .. tostring(tris) .. " (" .. tostring(note) .. ")"
end
return table.concat(out, "\n")
```

Expected: numbers, not `nil`. If every line says the counters did not change, Studio is still not rendering — do not record anything; retry when it is focused. Record the numbers in Task 13.

### Task 13: Closeout — cleanup, docs, execution log, report

**Files:**
- Modify: `docs/brainrot-build-standard.md` (§2.2 caps, §4 numbers), `game-src/README.md` (Forge section + dead-code note), this plan (execution log at the bottom).
- Studio: delete `workspace.AuxScene` (or `pilot_batch`) after the user has seen the assembled models.

- [ ] **Step 1: Studio cleanup (`execute_luau`)**

```lua
local gone = {}
for _, n in ipairs({ "AuxScene", "pilot_batch", "__ForgeTest_AuxScene" }) do
	local x = workspace:FindFirstChild(n)
	if x then x:Destroy(); gone[#gone + 1] = n end
end
return "removed: " .. table.concat(gone, ", ")
```

Then confirm with `search_game_tree` (`keywords: "Forge Test, AuxScene, pilot_batch"`) that nothing remains.

- [ ] **Step 2: Fill in the standard**

In `docs/brainrot-build-standard.md` §4, replace the "not yet measured" paragraph with the Task 12 Step 9 table (pack samples + pilots + two voxel models), and in §2.2 replace the provisional "≤ 2,000 per MeshPart / ≤ 8,000 per model" with caps derived from the pack numbers (typical = pack p50 rounded up to the nearest 500, max = pack maximum measured). If Step 9 could not run, leave §4 as is and say so in the report.

- [ ] **Step 3: `game-src/README.md`** — add at the top:

```markdown
## Brainrot Forge (2026-09-17) — how NEW brainrots are made now
- Standard: `docs/brainrot-build-standard.md`. Pipeline spec + plan: `docs/superpowers/{specs,plans}/2026-09-17-brainrot-forge-pilot*.md`.
- `tools/brainrot_forge/` (Python): design scripts -> per-colour baked meshes -> `out/<batch>/<batch>_batch.glb` + `manifest.json` + previews. The user imports the glb via File > Import 3D.
- `BrainrotForge.lua` -> `ServerStorage.BrainrotForge` (build-time assembler), `BrainrotBudget.lua` -> `ServerStorage.BrainrotBudget` (build-time gate). Neither is required by game code.
- ⚠️ `BrainrotLooks.lua` / `BrainrotBodyBuilder.lua` / `BrainrotModelFactory.lua` below are DEAD CODE since 2026-07-25 (roster replaced the same day; verified 2026-08-28) — kept as history only.
```

- [ ] **Step 4: Execution log** — append to the bottom of this plan a `## Execution log` with: the budget table from Task 12 Step 1, the client-check JSON from Step 4, the LOD probe lines, the triangle table (or "not measured: Studio unfocused"), the user's visual verdict and any design swaps, and the exact list of Studio objects touched (3 templates, 2 modules created, `BrainrotFX` + `BrainrotConfigTundra` edited). State plainly that **all Studio changes are UNSAVED until the owner saves the place**.

- [ ] **Step 5: Commit docs**

```bash
git add docs/brainrot-build-standard.md game-src/README.md docs/superpowers/plans/2026-09-17-brainrot-forge-pilot.md docs/superpowers/specs/2026-09-17-brainrot-forge-pilot-design.md
git commit -m "docs(forge): pilot execution log, measured triangle caps, README pointer to the Forge

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Report to the user** — in their preferred round-report shape: what shipped (3 templates, 2 modules, 2 recipe rows, 3 roster rows at Weight 0), the budget table, what was verified live and what was a human check, the two owner calls left open (set the weights; keep or drop the tile on meshes), the save reminder, and the follow-ups from the spec's out-of-scope list (convert the 66 originals; World 3 roster; effects at Common–Epic).

---

## Self-review (done while writing)

- **Spec coverage:** components 1–8 → Tasks 1–5 (Python), 7–8 (Luau), 9 (FX rows), 11 (roster); data flow → Tasks 6 and 10; verification plan → Task 12; error handling → bake `BudgetError` (Task 2), assembler restore/backup (Task 8 + synthetic test), anchored roster edit + compile gates (Tasks 9, 11); testing section → every Python task is TDD, Luau modules have live checks. Out-of-scope items are only referenced in the closeout report.
- **Placeholders:** the only "read live first" steps (Tasks 9 Step 1, 11 Step 1, 12 Step 6 reveal fields) name the exact script and lines to read and fully specify the text to insert; they are anchor lookups, not TBDs.
- **Type consistency:** `part_name` / `parts` naming (`"<Name>__<role>"`) is identical in `export_glb.py`, the manifest, the Studio sanity check and `BrainrotForge.AssembleOne`; `bake()` returns roles sorted, and the manifest/glTF/assembler all iterate that order; `BrainrotBudget.review` is what `BrainrotForge.Assemble` prints; HeightScale values (1.30 / 1.36 / 1.46) match in the designs, the design tests and the Task 10 expectations.

---

## Execution log (2026-09-17, inline execution)

### Deviations from the plan as written (all resolved)
- **`require` is impossible from the MCP exec sandbox in this place** (every ModuleScript carries default script Capabilities the sandbox lacks; even freshly created ones). Build-time modules are loaded with `loadstring(module.Source)()` in Edit mode; `BrainrotForge.loadModule` tries `require` first and falls back. In **Play** mode the sandbox also has no `loadstring`, so the spawner round trip runs from a temporary Script (`ServerScriptService.__ForgeSpawnTest_DELETE_ME`, created in Edit mode, self-destroying, deleted in closeout).
- **The exec sandbox has no `Network` capability** (cannot even read `HttpService.HttpEnabled`); the re-mirror of `BrainrotConfigTundra` was written from the fetched source and proven byte-exact by checksum (16,010 bytes, weighted 71246225, xor 99).
- **Roblox's Import 3D turns a glTF 180° about Y** (glTF +Z-forward → Roblox −Z-forward): measured on the first import (thumb X and pupil Z both negated, rotations identity). Fixed twice over: `BrainrotForge.Assemble` takes `turn180` (inferred from the manifest's `robloxForward` flag), and `export_glb.write_glb(roblox_forward=True)` now pre-turns every future batch so it lands facing −Z with no correction. The pilot batch was assembled with `turn180 = true`.
- `multi_edit` with an empty `old_string` on an EXISTING script PREPENDS; the temporary harness was trimmed with a direct `Source` write.
- Test counts: design suite is 13 (not 17); the full suite is **50 passed** after the `robloxForward` tests were added.

### Task 6 — previews
Contact sheet approved by the user as proposed (Guantone Brontolone / Alce Lampadario / Nonno Ghiacciaio). Bake: 676 / 708 / 1,696 triangles; 6 / 8 / 8 roles.

### Task 10 — import + assembly
Import landed as `Workspace.pilot_batch` (22 MeshParts, each in a `<name>_Node` model), all with real `MeshId`s (e.g. `rbxassetid://125920668998987`), scale correct (wool 6.4 × 4.4 × 1.8 studs). Assembled with `{ tile = true, turn180 = true }`: 3 templates in `ReplicatedStorage.BrainrotModels`, **BrainrotBudget verdict PASS for all three**, pupils at −Z, heights 6.2 / 7.3 / 8.6 studs, HeightScale 1.30 / 1.36 / 1.46, BaseParts 7 / 11 / 10 (incl. invisible RootPart + FX hosts), MeshParts 6 / 8 / 8, emitters 0 / 3 / 3, Material Plastic + BrainrotTile on every MeshPart, CollisionFidelity Box.

### Task 12 Step 1 — budget table (Edit mode)
```
metric              Guantone Brontol  Alce Lampadario   Nonno Ghiacciaio  Tralalero Tralal  Chimpanzini Bana  Las Capuchinas    Los Crocodillito  Zero Assoluto     Yeti Cappuccino   Valanga Ruggente
baseParts           7                 11                10                8                 7                 15                39                172               463               1106
visibleParts        6                 8                 8                 5                 4                 9                 36                170               461               1104
meshParts           6                 8                 8                 5                 4                 9                 36                0                 0                 0
descendants         7                 14                13                49                57                197               121               179               469               1111
particleEmitters    0                 3                 3                 6                 1                 9                 10                7                 6                 5
particlesAlive      0                 7                 20                64                8                 102               65                64                29                56
attachments         0                 0                 0                 9                 8                 17                25                0                 0                 0
bones               0                 0                 0                 18                34                141               9                 0                 0                 0
motor6d             0                 0                 0                 5                 4                 9                 36                0                 0                 0
surfaceAppearances  0                 0                 0                 1                 1                 1                 0                 0                 0                 0
neonParts           0                 0                 0                 0                 0                 0                 0                 0                 21                12
beams/trails/lights/scripts: 0 everywhere
```

### Task 12 Steps 2–3 — first Play round
The harness spawned all six (plain ×3, Golden Guantone, Massive Nonno, Diamond Alce) on Plot9 through the real `BrainrotSpawner.Spawn` — then the test account's profile claimed **Plot9** (its saved camp) and restored its 16 saved bodies over the pads. Harness re-armed to wait for the claim and use an unclaimed Tundra plot; second round below.

### Task 12 Steps 3–5 — Play round trip (third session, Plot7)
Harness (request-driven) spawned all six on **Plot7** (unclaimed Tundra plot, character parked 55 studs outside the camp — standing inside a camp claims it and restores the account's saved 16 bodies over the pads; that wiped rounds one and two on Plot9/Plot10). Streaming follows the CHARACTER, not the camera: with the camera alone at 22 studs the bodies had 0 parts; at 55 studs from the character everything streamed.

Client DataModel, all six bodies: `blankMeshIds = 0` (geometry replicated), root anchored + every other part unanchored and welded (welds == unanchored), `BrainrotBody` tag, `Motion` = hover / shiver, every MeshPart carrying `BrainrotTile`; sizes at the spawner's fit: Guantone 7.8, Alce 8.1 (width-capped 9.5), Nonno 8.8 studs; **Massive Nonno 43.4 studs**; `MutationBody` tag on the Golden Guantone (+1 emitter) and Diamond Alce (+1 emitter). LOD probe on Nonno: **FAR (110 studs) blanked 7/10 parts, emitters 0 on; NEAR (25 studs) blanked 0/10, emitters 3 on.** Console: no errors from any body (only the harness's own `_G` probe and CameraWatchdog rescues from the camera holds).

### Task 12 Step 6 — thumbnails / reveal
`BrainrotThumb.master(name)` = `BrainrotModels:FindFirstChild(name)` → stripped clone; all three resolve and their MeshIds are real, so viewport tiles render. `require` is impossible from the Play sandbox, so the catch reveal was NOT driven programmatically — it is a human check when the owner sets weights and a real throw lands one.

### Task 12 Step 7 — the user looked
`screen_capture` returns a black world layer unless Studio is the visible window (UI layer only), so the look was checked by the user in an **Edit-mode showcase** (the three templates cloned to a row north of SpawnLocation at their plot fit). Verdict: **"Look good, keep the tile."**

### Task 12 Step 9 — triangles
See the standard §4 (10 pack samples 790–16,064; pilots 660 / 744 / 1,720; voxel 2,040 / 4,116 / 8,196). First-pass readings under-count until the meshes have downloaded once; measure twice.

### Studio objects touched (ALL UNSAVED until the owner saves the place)
- Created: `ReplicatedStorage.BrainrotModels.{Guantone Brontolone, Alce Lampadario, Nonno Ghiacciaio}` (22 uploaded MeshAssets on the user's account), `ServerStorage.BrainrotForge`, `ServerStorage.BrainrotBudget`.
- Edited: `ReplicatedStorage.Modules.BrainrotFX` (+2 recipe rows), `ReplicatedStorage.Modules.BrainrotConfigTundra` (+3 rows at Weight 0, Origin "Forge").
- Removed after use: `Workspace.pilot_batch` (import group), `Workspace.__ForgeShowcase_DELETE_ME`, `ServerScriptService.__ForgeSpawnTest_DELETE_ME`. `BrainrotModels` count 215 → 218; nothing else in the place was changed.

### Open owner calls
1. Set real `Weight`s for the three rows (they never roll from a throw until then).
2. Whether Common–Epic originals should get effects (pack has them at every tier; forge Epic ships without).
