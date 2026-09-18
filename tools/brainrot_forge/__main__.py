"""CLI: python -m brainrot_forge build pilot [--out out/pilot] [--flip-z] | list
     | convert [--dump out/convert/dump] [--out out/convert] [--batches 4] [--max-tris 12000] [--max-tris-role 4000]"""
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
    write_glb(out / f"{batch_name}_batch.glb", batch, flip_z=flip_z, roblox_forward=True)
    manifest = build_manifest(batch, roblox_forward=True)
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
    b = sub.add_parser("build")
    b.add_argument("batch", choices=sorted(BATCHES))
    b.add_argument("--out")
    b.add_argument("--flip-z", action="store_true")
    sub.add_parser("list")
    c = sub.add_parser("convert")
    c.add_argument("--dump", default="out/convert/dump")
    c.add_argument("--out", default="out/convert")
    c.add_argument("--batches", type=int, default=4)
    c.add_argument("--max-tris", type=int, default=12000, help="triangle gate per body (sanity, not a budget — geometry is never dropped)")
    c.add_argument("--max-tris-role", type=int, default=4000, help="triangle gate per role mesh")
    a = p.parse_args(argv)
    if a.cmd == "convert":
        from .convert import convert_all
        try:
            rows = convert_all(a.dump, a.out, a.batches, max_tris_model=a.max_tris, max_tris_role=a.max_tris_role)
        except BudgetError as e:
            print(f"REFUSED {e}")
            return 1
        print(f"{'name':<34} {'batch':>5} {'boxes':>6} {'roles':>5} {'triangles':>9} {'vcol':>5} {'posed':>5} {'fx':>3}")
        for r in rows:
            print(f"{r['name']:<34} {r['batch']:>5} {r['boxes']:>6} {r['roles']:>5} {r['triangles']:>9} {str(r['vertexColors']):>5} {str(r['posed']):>5} {str(r['fx']):>3}")
        print(f"{len(rows)} bodies in {a.batches} batches -> {a.out}/convert_batch<i>.glb, manifest_batch<i>.json, previews/batch<i>_sheet<k>.png")
        return 0
    if a.cmd == "list":
        for name, fn in DESIGNS.items():
            m = fn()
            print(f"{name:<22} {m.rarity:<10} {m.world}")
        return 0
    return build(a.batch, Path(a.out or f"out/{a.batch}"), a.flip_z)


if __name__ == "__main__":
    sys.exit(main())
