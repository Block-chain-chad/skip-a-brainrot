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
from .bake_boxes import ConvertedModel, bake_boxes, repose
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


def convert_all(dump_dir: str | Path, out_dir: str | Path, batches: int = 4,
                max_tris_model: int = 12000, max_tris_role: int = 4000,
                move: dict[str, int] | None = None) -> list[dict]:
    """move: {name: batch} puts a body into another batch than its alphabetical one (a re-do)."""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    models = [unpose(m) for m in load_models(dump_dir)]
    chunks = _chunks(models, batches)
    for name, target in (move or {}).items():
        found = [(chunk, m) for chunk in chunks for m in chunk if m.name == name]
        assert found, f"--move: no body named {name!r}"
        chunk, m = found[0]
        chunk.remove(m)
        chunks[target - 1].append(m)
    rows: list[dict] = []
    for bi, chunk in enumerate(chunks, 1):
        # posed bodies are baked un-tilted (so faces cull) and the tilt is put back into the vertices
        after = [repose(bake_boxes(m, max_tris_model=max_tris_model, max_tris_role=max_tris_role)) for m in chunk]
        before = [repose(bake_boxes(m, exact=True, max_tris_model=max_tris_model, max_tris_role=max_tris_role)) for m in chunk]
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
                         "posed": m.pose is not None, "fx": bool(cm.fx)})
    return rows
