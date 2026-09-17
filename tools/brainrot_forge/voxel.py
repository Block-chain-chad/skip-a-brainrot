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
        xs = [c[0] for c in self.cells]
        ys = [c[1] for c in self.cells]
        zs = [c[2] for c in self.cells]
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
        share = max(used.values()) / len(self.cells)
        if share < MIN_BODY_SHARE:
            problems.append(f"no body: largest role covers {share:.0%} < {MIN_BODY_SHARE:.0%}")
        if used.get("eye", 0) == 0 or used.get("pupil", 0) == 0:
            problems.append("no eyes: paint some with .eyes()")
        if self.bounds()[0][1] != 0:
            problems.append(f"feet must sit at y = 0 (lowest cell is y = {self.bounds()[0][1]})")
        return problems
