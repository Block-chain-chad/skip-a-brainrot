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

Batch = list[tuple[VoxelModel, dict[str, Mesh]]]   # or ConvertedModel: same duck-typed fields plus the manifest extras

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
    r, g, b = (round(ch(int(h[i:i + 2], 16)), 7) for i in (0, 2, 4))
    return (r, g, b)


def _pad(b: bytes, fill: bytes) -> bytes:
    return b + fill * (-len(b) % 4)


def write_glb(path: str | Path, batch: Batch, flip_z: bool = False, roblox_forward: bool = True) -> None:
    """roblox_forward: Roblox's Import 3D turns a glTF 180 degrees about Y (glTF is +Z-forward,
    Roblox is -Z-forward; measured 2026-09-17). Pre-turning here (negate x and z — a rotation, so
    winding is untouched) makes the imported model face -Z with no assembler correction.
    flip_z is a true mirror (kept for an importer that mirrors instead of turning)."""
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
            sx = -1.0 if roblox_forward else 1.0
            sz = sx * (-1.0 if flip_z else 1.0)
            pos = [(p[0] * sx, p[1], p[2] * sz) for p in mesh.positions]
            nrm = [(n[0] * sx, n[1], n[2] * sz) for n in mesh.normals]
            idx = list(mesh.indices)
            if flip_z:  # mirroring flips handedness; reverse each triangle to stay CCW
                idx = [i for t in range(0, len(idx), 3) for i in (idx[t], idx[t + 2], idx[t + 1])]
            p_blob = b"".join(struct.pack("<3f", *p) for p in pos)
            n_blob = b"".join(struct.pack("<3f", *n) for n in nrm)
            t_blob = b"".join(struct.pack("<2f", *uv) for uv in mesh.uvs)
            c_blob = b"".join(struct.pack("<3f", *c) for c in mesh.colors) if mesh.colors is not None else None
            i_blob = struct.pack(f"<{len(idx)}I", *idx)
            lo = [min(p[k] for p in pos) for k in range(3)]
            hi = [max(p[k] for p in pos) for k in range(3)]
            a_pos = accessor(view(p_blob, _ARRAY_BUFFER), _FLOAT, len(pos), "VEC3", lo, hi)
            a_nrm = accessor(view(n_blob, _ARRAY_BUFFER), _FLOAT, len(nrm), "VEC3")
            a_uv = accessor(view(t_blob, _ARRAY_BUFFER), _FLOAT, len(mesh.uvs), "VEC2")
            attributes = {"POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv}
            if c_blob is not None:
                attributes["COLOR_0"] = accessor(view(c_blob, _ARRAY_BUFFER), _FLOAT, len(mesh.colors), "VEC3")
            a_idx = accessor(view(i_blob, _ELEMENT_ARRAY_BUFFER), _UINT, len(idx), "SCALAR")
            r, g, b = srgb_to_linear(model.palette[role])
            materials.append({"name": name, "pbrMetallicRoughness": {
                "baseColorFactor": [r, g, b, 1.0], "metallicFactor": 0.0, "roughnessFactor": 1.0}})
            meshes.append({"name": name, "primitives": [{
                "attributes": attributes,
                "indices": a_idx, "material": len(materials) - 1, "mode": 4}]})
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
        f.write(struct.pack("<II", len(json_chunk), _JSON))
        f.write(json_chunk)
        f.write(struct.pack("<II", len(bin_chunk), _BIN))
        f.write(bin_chunk)


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
            "colors": read(prim["attributes"]["COLOR_0"]) if "COLOR_0" in prim["attributes"] else None,
        }
    return out


def build_manifest(batch: Batch, roblox_forward: bool = True) -> dict:
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
            "attributes": dict(getattr(model, "attributes", {}) or {}),
            "materials": dict(getattr(model, "materials", None) or {role: model.material for role in role_meshes}),
            "poseRotation": list(model.pose_rotation) if getattr(model, "pose_rotation", None) else None,
            "poseCentre": list(model.pose_centre) if getattr(model, "pose_centre", None) else None,
            "vertexColors": bool(getattr(model, "vertex_colors", False)),
        }
    return {"version": 1, "generator": f"brainrot_forge {__version__}", "pitch": pitch,
            "robloxForward": roblox_forward, "models": models}
