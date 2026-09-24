"""pets.py — the Forge's PET MODE: fine voxel pets and eggs, shaded per voxel, baked to ONE MESH PER
ANATOMY GROUP.

Why a mode of its own. The brainrot bake (bake.py) turns every colour role into one MeshPart, which suits
a body that only ever moves as a whole. A pet walks: PetVisualsClient builds its joints from the Model
names under `anatomy` (legs, arms, ears, tail, neck, and the head with everything that rides it), so a pet
bakes one mesh per anatomy group instead, and every voxel's own shade rides in COLOR_0 as a ratio over the
group's MeshPart colour (the same scheme bake_boxes uses; the importer keeps vertex colours, measured with
BrainrotForge's probe on 2026-09-17).

Two rules follow from the joints:
- A face between two voxels of the SAME group is hidden and dropped. A face where two groups meet is KEPT
  on both sides, because that seam moves: a leg's top shows when it swings, and so does the body above it.
- Left and right follow the rig, not anatomy. PetVisualsClient flaps an ear or wing about Z by +angle when
  its name ends in "l" (ear.side / wing.side), so for a pair to flap together the `_l` side is +X. Design
  the +X half with `_l` groups and let mirror_x() write the `_r` half.

Shading (Item 6, Steal An Egg reference): every colour role gets a handful of tones. A voxel's tone comes
from a top-lit gradient over its own group plus a deterministic +-6 % brightness jitter, snapped to the
nearest tone, and the row of a limb that touches its parent group is pushed to the darkest tone, the
outline that separates the parts. Roles in `flat` (eye ink, glint) are never shaded.
"""
from __future__ import annotations

import json
import math
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path

from .bake import BudgetError, Mesh, _quad, greedy_rects
from .voxel import Cell, VoxelModel

PET_PITCH = 0.08            # studs per voxel at pet scale (Item 6)
PET_SIZE = 3.2              # PetConfig.PET_SIZE: the follow rig scales a pet's longest side to this
PET_LONGEST = 40            # voxels on the longest side, so the rig shows the pet 1:1 (40 * 0.08 = 3.2)
EYES = "eyes"               # the eye group: its MeshPart name keeps "eye" for EggHatch.RewardRig.facingOf
EGG_BODY = "shell_body"     # EggStallIdle's bobbing family, so a baked egg drops onto the shelf by name
TONES = (0.72, 0.86, 0.96, 1.06, 1.16)   # [0] = outline; the rest are the lit range (3 to 5 tones per colour)
SPREAD = 0.26               # top-lit gradient: 0.87 at the bottom of a group, 1.13 at its top
JITTER = 0.06               # per-voxel brightness jitter, +-6 %
MAX_TRIS_PET = 16000        # standard §2.2 max per body; a sanity gate, not a budget (nothing is trimmed)
MAX_TRIS_GROUP = 8000

_OTHER = {0: (1, 2), 1: (2, 0), 2: (0, 1)}
_DIRS = ((0, 1), (0, -1), (1, 1), (1, -1), (2, 1), (2, -1))

# Group names PetVisualsClient.groupKeyOf gives a joint; the head family rides the head. Anything else
# (a shell, spots) rides the body rigidly, which is fine but has to be meant, so designs are checked
# against this list.
_HEAD_FAMILY = ("head", "snout", "nose", "eyes", "cap", "antler_l", "antler_r", "antenna_l", "antenna_r")
_BODY_FAMILY = ("body", "shell")


def leaf(path: str) -> str:
    return path.rsplit("/", 1)[-1]


def swap_side(path: str) -> str:
    """leg_1l <-> leg_1r, ears/ear_l <-> ears/ear_r; groups without a side are unchanged."""
    name = leaf(path)
    if name.endswith("_l") or (name.startswith("leg_") and name.endswith("l")):
        other = name[:-1] + "r"
    elif name.endswith("_r") or (name.startswith("leg_") and name.endswith("r")):
        other = name[:-1] + "l"
    else:
        return path
    return path[: len(path) - len(name)] + other


def rig_known(path: str) -> bool:
    name = leaf(path)
    if name in _HEAD_FAMILY or name in _BODY_FAMILY or name in ("neck", "tail", EGG_BODY):
        return True
    if path.startswith("ears/") or path.startswith("wings/"):
        return name[-1] in "lr"
    if name.startswith("leg_") and len(name) == 6 and name[4].isdigit() and name[5] in "lr":
        return True
    return name in ("arm_l", "arm_r")


def parent_of(path: str, has_neck: bool) -> str | None:
    """The group a limb hangs from: the side of a seam that stays lit (the child's row is the outline)."""
    name = leaf(path)
    if name in _BODY_FAMILY or name == EGG_BODY:
        return None
    if name == "neck":
        return "body"
    if name == "head":
        return "neck" if has_neck else "body"
    if name in _HEAD_FAMILY or path.startswith("ears/"):
        return "head"
    return "body"


# ------------------------------------------------------------------------------------------ the model
@dataclass
class PetModel(VoxelModel):
    """A VoxelModel whose every cell also knows its anatomy group. Paint inside `with m.group(path):`."""
    kind: str = "pet"                                        # "pet" or "egg"
    art_key: str = ""                                        # PetConfig model key, e.g. pet_14_elder_stag
    groups: dict[Cell, str] = field(default_factory=dict)    # cell -> anatomy path ("head", "ears/ear_l")
    flat: set[str] = field(default_factory=set)              # roles drawn without shading
    seed: int = 0
    current: str = "body"

    @contextmanager
    def group(self, path: str):
        prev, self.current = self.current, path
        try:
            yield self
        finally:
            self.current = prev

    def set(self, x: int, y: int, z: int, role: str) -> None:
        super().set(x, y, z, role)
        self.groups[(int(x), int(y), int(z))] = self.current

    def carve(self, x0, x1, y0, y1, z0, z1) -> "PetModel":
        super().carve(x0, x1, y0, y1, z0, z1)
        self.groups = {c: g for c, g in self.groups.items() if c in self.cells}
        return self

    def keep_above(self, y_min: int) -> "PetModel":
        super().keep_above(y_min)
        self.groups = {c: g for c, g in self.groups.items() if c in self.cells}
        return self

    def remove(self, cells) -> "PetModel":
        for c in list(cells):
            self.cells.pop(c, None)
            self.groups.pop(c, None)
        return self

    def mirror_x(self) -> "PetModel":
        """Copy every cell with x > 0 onto -x, swapping _l/_r in its group (x = 0 stays)."""
        for (x, y, z), r in list(self.cells.items()):
            if x > 0:
                self.cells[(-x, y, z)] = r
                self.groups[(-x, y, z)] = swap_side(self.groups[(x, y, z)])
        return self

    # ------------------------------------------------------------------ float shapes (cell-index space)
    def _put(self, x, y, z, role, only_empty):
        if only_empty and (x, y, z) in self.cells:
            return
        self.set(x, y, z, role)

    def blob(self, cx, cy, cz, rx, ry, rz, role, only_empty=False) -> "PetModel":
        """Every cell whose index lies inside the ellipsoid (float centre and radii)."""
        for x in range(math.floor(cx - rx), math.ceil(cx + rx) + 1):
            for y in range(math.floor(cy - ry), math.ceil(cy + ry) + 1):
                for z in range(math.floor(cz - rz), math.ceil(cz + rz) + 1):
                    if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 + ((z - cz) / rz) ** 2 <= 1.0:
                        self._put(x, y, z, role, only_empty)
        return self

    def capsule(self, a, b, ra, rb, role, only_empty=False) -> "PetModel":
        """A tapered capsule from point a (radius ra) to point b (radius rb)."""
        ax, ay, az = a
        bx, by, bz = b
        dx, dy, dz = bx - ax, by - ay, bz - az
        ll = dx * dx + dy * dy + dz * dz or 1e-9
        rmax = max(ra, rb)
        for x in range(math.floor(min(ax, bx) - rmax), math.ceil(max(ax, bx) + rmax) + 1):
            for y in range(math.floor(min(ay, by) - rmax), math.ceil(max(ay, by) + rmax) + 1):
                for z in range(math.floor(min(az, bz) - rmax), math.ceil(max(az, bz) + rmax) + 1):
                    t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy + (z - az) * dz) / ll))
                    px, py, pz = ax + dx * t, ay + dy * t, az + dz * t
                    r = ra + (rb - ra) * t
                    if (x - px) ** 2 + (y - py) ** 2 + (z - pz) ** 2 <= r * r:
                        self._put(x, y, z, role, only_empty)
        return self

    def egg(self, height: int, radius: float, role, widest: float = 0.42) -> "PetModel":
        """A stepped egg standing on y = 0, centred on x = z = 0: two half-ellipses meeting at `widest`
        of the height, so the top half is the longer, pointier one."""
        r_cells = math.ceil(radius)
        for y in range(height):
            h = (y + 0.5) / height
            k = (widest - h) / widest if h < widest else (h - widest) / (1.0 - widest)
            r = radius * math.sqrt(max(0.0, 1.0 - k * k))
            for x in range(-r_cells, r_cells + 1):
                for z in range(-r_cells, r_cells + 1):
                    if x * x + z * z <= r * r:
                        self.set(x, y, z, role)
        return self

    def surface(self) -> set[Cell]:
        """Cells with at least one face open to the air."""
        out = set()
        for c in self.cells:
            for axis, sign in _DIRS:
                n = list(c)
                n[axis] += sign
                if tuple(n) not in self.cells:
                    out.add(c)
                    break
        return out

    def recolour(self, role, where, group: str | None = None) -> "PetModel":
        """Recolour existing cells (optionally of one group) for which where(x, y, z) is true."""
        if role not in self.palette:
            raise KeyError(f"role {role!r} is not in the palette; call .role() first")
        for c in list(self.cells):
            if (group is None or self.groups.get(c) == group) and where(*c):
                self.cells[c] = role
        return self

    def outermost(self, axis: int, sign: int, u: int, v: int, group: str | None = None):
        """The last cell along +/-axis at (u, v) on the other two axes, or None."""
        best = None
        for c in self.cells:
            ua, va = _OTHER[axis]
            if c[ua] == u and c[va] == v and (group is None or self.groups.get(c) == group):
                if best is None or c[axis] * sign > best[axis] * sign:
                    best = c
        return best

    # ------------------------------------------------------------------ measuring and the gate
    def group_paths(self) -> dict[str, str]:
        return {leaf(g): g for g in sorted(set(self.groups.values()))}

    def validate(self) -> list[str]:
        # The brainrot gate's "one role covers 40 %" rule counts hidden interior voxels and exists to stop
        # confetti bodies; a pet is judged by its groups instead (below). Eggs have no eyes.
        problems = [p for p in super().validate()
                    if not p.startswith("no body") and not (self.kind == "egg" and p.startswith("no eyes"))]
        if set(self.groups) != set(self.cells):
            problems.append("every cell needs a group")
        paths = sorted(set(self.groups.values()))
        leaves = [leaf(p) for p in paths]
        if len(leaves) != len(set(leaves)):
            problems.append(f"group names must be unique by their last part: {paths}")
        for p in paths:
            if not rig_known(p):
                problems.append(f"group {p!r} is not one the follow rig knows")
        if self.kind == "pet":
            if "body" not in leaves or "head" not in leaves:
                problems.append("a pet needs body and head groups")
            if EYES not in leaves:
                problems.append("a pet needs an eyes group (the hatch finds the face by it)")
            if max(self.size_voxels()) != PET_LONGEST:
                problems.append(f"longest side {max(self.size_voxels())} voxels, want {PET_LONGEST} (1:1 at PET_SIZE)")
            eye_z = [c[2] for c, g in self.groups.items() if g == EYES]
            lo, hi = self.bounds()
            if eye_z and sum(eye_z) / len(eye_z) > (lo[2] + hi[2]) / 2:
                problems.append("the eyes sit behind the middle; the face must point -Z")
            for c, g in self.groups.items():
                name = leaf(g)
                if name.endswith("_l") and name.startswith(("ear", "wing")) and c[0] < 0:
                    problems.append(f"{g} has a cell at x < 0; the rig's l side is +X")
                    break
        else:
            if leaves != [EGG_BODY]:
                problems.append(f"an egg is one {EGG_BODY!r} group, got {leaves}")
        return problems


# ------------------------------------------------------------------------------------------ shading
def _hash01(x: int, y: int, z: int, seed: int) -> float:
    h = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (seed * 2654435761)
    h &= 0xFFFFFFFF
    h ^= h >> 13
    h = (h * 0x5BD1E995) & 0xFFFFFFFF
    h ^= h >> 15
    return h / 0xFFFFFFFF


def _rgb(h: str) -> tuple[int, int, int]:
    return (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16))


def _hex(rgb) -> str:
    return "#%02X%02X%02X" % tuple(max(0, min(255, int(round(c)))) for c in rgb)


def tone_of(base_hex: str, factor: float) -> str:
    r, g, b = _rgb(base_hex)
    return _hex((r * factor, g * factor, b * factor))


def seam_cells(model: PetModel) -> set[Cell]:
    """Cells of a child group that touch their parent group: the outline row."""
    has_neck = any(leaf(g) == "neck" for g in model.groups.values())
    out: set[Cell] = set()
    for c, g in model.groups.items():
        parent = parent_of(g, has_neck)
        if parent is None or leaf(g) == EYES or model.cells[c] in model.flat:
            continue
        for axis, sign in _DIRS:
            n = list(c)
            n[axis] += sign
            ng = model.groups.get(tuple(n))
            if ng is not None and leaf(ng) == parent:
                out.add(c)
                break
    return out


def shade(model: PetModel, tones=TONES, spread=SPREAD, jitter=JITTER, outline=True) -> dict[Cell, str]:
    """-> {cell: '#RRGGBB'}: every voxel's own colour (see the module docstring)."""
    lit = tones[1:]
    ys: dict[str, list[int]] = {}
    for (x, y, z), g in model.groups.items():
        ys.setdefault(g, []).append(y)
    span = {g: (min(v), max(v)) for g, v in ys.items()}
    seams = seam_cells(model) if outline else set()
    out: dict[Cell, str] = {}
    for c, role in model.cells.items():
        base = model.palette[role]
        if role in model.flat:
            out[c] = base
            continue
        if c in seams:
            out[c] = tone_of(base, tones[0])
            continue
        lo, hi = span[model.groups[c]]
        t = (c[1] - lo) / (hi - lo) if hi > lo else 0.5
        f = (1.0 + spread * (t - 0.5)) * (1.0 + jitter * (2.0 * _hash01(*c, model.seed) - 1.0))
        out[c] = tone_of(base, min(lit, key=lambda k: abs(k - f)))
    return out


# ------------------------------------------------------------------------------------------ the bake
@dataclass
class BakedPet:
    """What export_glb.write_glb / build_manifest read (the duck type of VoxelModel/ConvertedModel)."""
    name: str
    rarity: str
    world: str
    kind: str
    art_key: str
    pitch: float
    palette: dict[str, str]          # group -> MeshPart colour (per-channel max of the group's shades)
    meshes: dict[str, Mesh]
    group_paths: dict[str, str]
    voxels: int
    colours: int
    tones: dict[str, int]            # role -> shades it ended up with
    bounds: tuple[tuple[float, float, float], tuple[float, float, float]]
    height_scale: float = 1.0
    width_scale: float = 1.0
    motion: str = "pet"
    material: str = "SmoothPlastic"
    fx: list | None = None
    attributes: dict = field(default_factory=dict)
    materials: dict = field(default_factory=dict)
    pose_rotation: tuple | None = None
    pose_centre: tuple | None = None
    vertex_colors: bool = True

    def size_studs(self) -> tuple[float, float, float]:
        lo, hi = self.bounds
        return tuple(round(hi[i] - lo[i], 6) for i in range(3))  # type: ignore[return-value]


def pet_faces(model: PetModel, colours: dict[Cell, str]):
    """(group, axis, sign, slice, colour) -> {(u, v)}: faces open to the air or to another group."""
    faces: dict[tuple[str, int, int, int, str], set[tuple[int, int]]] = {}
    for c, g in model.groups.items():
        for axis, sign in _DIRS:
            n = list(c)
            n[axis] += sign
            if model.groups.get(tuple(n)) == g:
                continue
            ua, va = _OTHER[axis]
            faces.setdefault((g, axis, sign, c[axis], colours[c]), set()).add((c[ua], c[va]))
    return faces


def bake_pet(model: PetModel, colours: dict[Cell, str] | None = None,
             max_tris_group: int = MAX_TRIS_GROUP, max_tris: int = MAX_TRIS_PET) -> BakedPet:
    colours = colours if colours is not None else shade(model)
    faces = pet_faces(model, colours)
    reps: dict[str, list[int]] = {}
    for (g, _, _, _, col) in faces:
        rgb = _rgb(col)
        rep = reps.setdefault(leaf(g), [0, 0, 0])
        for i in range(3):
            rep[i] = max(rep[i], rgb[i])
    meshes: dict[str, Mesh] = {}
    for (g, axis, sign, k, col), grid in sorted(faces.items()):
        name = leaf(g)
        mesh = meshes.setdefault(name, Mesh(name, colors=[]))
        rgb, rep = _rgb(col), reps[name]
        ratio = tuple(rgb[i] / rep[i] if rep[i] else 1.0 for i in range(3))
        for rect in greedy_rects(grid):
            _quad(mesh, axis, sign, k, rect, model.pitch)
            mesh.colors.extend([ratio] * 4)
    total = 0
    for name, mesh in meshes.items():
        if mesh.triangles > max_tris_group:
            raise BudgetError(f"{model.name}: group {name} has {mesh.triangles} triangles > {max_tris_group}")
        total += mesh.triangles
    if total > max_tris:
        raise BudgetError(f"{model.name}: {total} triangles > {max_tris}")
    lo, hi = model.bounds()
    p = model.pitch
    shades_by_role: dict[str, set[str]] = {}
    for c, role in model.cells.items():
        shades_by_role.setdefault(role, set()).add(colours[c])
    return BakedPet(
        name=model.name, rarity=model.rarity, world=model.world, kind=model.kind, art_key=model.art_key,
        pitch=p, palette={n: _hex(reps[n]) for n in meshes}, meshes=dict(sorted(meshes.items())),
        group_paths=model.group_paths(), voxels=len(model.cells), colours=len(set(colours.values())),
        tones={r: len(s) for r, s in sorted(shades_by_role.items())},
        bounds=((lo[0] * p, lo[1] * p, lo[2] * p), ((hi[0] + 1) * p, (hi[1] + 1) * p, (hi[2] + 1) * p)),
        materials={n: "SmoothPlastic" for n in meshes},
    )


def pet_manifest(batch: list[BakedPet]) -> dict:
    from .export_glb import build_manifest
    manifest = build_manifest([(bp, bp.meshes) for bp in batch])
    manifest["mode"] = "pet"
    for bp in batch:
        e = manifest["models"][bp.name]
        e["kind"] = bp.kind
        e["artKey"] = bp.art_key
        e["groupPaths"] = bp.group_paths
        e["meshes"] = len(bp.meshes)
        e["voxels"] = bp.voxels
        e["colours"] = bp.colours
        e["tonesPerRole"] = bp.tones
    return manifest


# ------------------------------------------------------------------------------------------ previews
VIEWS = (("front", (0.0, 0.2, -1.0)), ("3/4", (0.9, 0.45, -1.0)), ("side", (1.0, 0.2, 0.0)))


def _panels(pairs, views, size):
    """Render every (model, meshes) in pairs at every view with ONE scale per view, so the before and
    after of a row are drawn at the same pixels per stud."""
    from .render import _paint, _project
    out = []
    for _, d in views:
        projs = [_project(m, k, size, dir=d) for m, k in pairs]
        scale = min(s for _, s in projs)
        out.append([_paint(p, scale, size) for p, _ in projs])
    return out   # [view][pair]


def pet_sheet(rows, out_path, size: int = 300, icon: int = 104) -> Path:
    """rows: [(label, before (model, meshes) or None, after (model, meshes))]. Each row: the Item 5
    version at front / 3/4 / side, the new version at the same three views, and the new one at Bag-card
    size (BrainrotThumb's front-quarter view)."""
    from PIL import Image, ImageDraw
    from .render import SKY, render_model
    head = 22
    width = size * 6 + icon + 40
    sheet = Image.new("RGB", (width, head + size * len(rows)), (236, 240, 244))
    d = ImageDraw.Draw(sheet)
    titles = ["ITEM 5 front", "ITEM 5 3/4", "ITEM 5 side", "ITEM 6 front", "ITEM 6 3/4", "ITEM 6 side"]
    for i, t in enumerate(titles):
        d.text((i * size + 6, 5), t, fill=(20, 20, 30))
    d.text((size * 6 + 16, 5), "Bag size", fill=(20, 20, 30))
    for r, (label, before, after) in enumerate(rows):
        y = head + r * size
        pairs = [p for p in (before, after) if p is not None]
        grid = _panels(pairs, VIEWS, size)
        for v in range(3):
            if before is not None:
                sheet.paste(grid[v][0], (v * size, y))
            else:
                sheet.paste(Image.new("RGB", (size, size), SKY), (v * size, y))
            sheet.paste(grid[v][-1], ((3 + v) * size, y))
        small = render_model(after[0], after[1], icon)
        sheet.paste(small, (size * 6 + 16, y + (size - icon) // 2))
        d.text((6, y + 6), label, fill=(20, 20, 30))
        d.line([(3 * size, y), (3 * size, y + size)], fill=(120, 120, 130), width=2)
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path)
    return out_path


def load_before(dump_path) -> dict[str, tuple]:
    """The Item 5 Part-built prototypes (tools/brainrot_forge/studio/dump_pets.lua) as renderable
    (model, meshes), keyed by the prototype name (vox_ElderStag, ...)."""
    from .bake_boxes import bake_boxes
    from .ingest_parts import load_dump
    out = {}
    for pm in load_dump(dump_path):
        cm = bake_boxes(pm, exact=True, max_tris_model=10 ** 6, max_tris_role=10 ** 6)
        out[pm.name] = (cm, cm.meshes)
    return out


# ------------------------------------------------------------------------------------------ the build
def build_pets(out: Path, before: Path | None = None, previews: bool = True) -> list[BakedPet]:
    from .designs.pets import BEFORE, PET_DESIGNS, PETS
    from .export_glb import write_glb
    baked = []
    for name in PETS:
        model = PET_DESIGNS[name]()
        problems = model.validate()
        if problems:
            raise BudgetError(f"REFUSED {name}: " + "; ".join(problems))
        baked.append(bake_pet(model))
    out.mkdir(parents=True, exist_ok=True)
    write_glb(out / "pets_batch.glb", [(bp, bp.meshes) for bp in baked], roblox_forward=True)
    (out / "manifest.json").write_text(json.dumps(pet_manifest(baked), indent=2))
    if previews:
        old = load_before(before) if before and Path(before).exists() else {}
        rows = [(bp.name, old.get(BEFORE.get(bp.name, "")), (bp, bp.meshes)) for bp in baked]
        pet_sheet(rows, out / "previews" / "contact_sheet.png")
    return baked
