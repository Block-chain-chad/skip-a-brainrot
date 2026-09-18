import json
import pytest
from brainrot_forge import convert as C
from brainrot_forge.bake import BudgetError


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
    # the tilt is baked into the vertices, so the manifest carries no pose and the bbox is the tilted body's
    assert tilted["poseRotation"] is None and tilted["poseCentre"] is None and tilted["fx"] is True
    assert tilted["bbox"] == [3.0, 2.0, 1.0] and [r for r in rows if r["name"] == "Tilted Ray"][0]["posed"] is True
    assert sorted(tilted["materials"].values()) == ["Neon", "Plastic"]
    assert (out / "convert_batch1.glb").stat().st_size > 0 and (out / "convert_batch2.glb").stat().st_size > 0
    assert (out / "previews" / "batch1_sheet1.png").exists() and (out / "previews" / "batch2_sheet1.png").exists()
    assert {r["batch"] for r in rows} == {1, 2}


def test_probe_cube_has_six_distinct_face_ratios():
    pr = C.probe()
    mesh = pr.meshes["probe"]
    assert pr.name == "__ForgeProbe_VertexColor" and mesh.triangles == 12 and len(mesh.colors) == 24
    assert len({mesh.colors[i] for i in range(0, 24, 4)}) == 6


def test_triangle_gate_flags_reach_the_bake(tmp_path):
    d = write_fake_dump(tmp_path)
    with pytest.raises(BudgetError):
        C.convert_all(d, tmp_path / "out", batches=1, max_tris_role=4)


def test_move_puts_a_body_in_another_batch(tmp_path):
    d = write_fake_dump(tmp_path)
    out = tmp_path / "out"
    rows = C.convert_all(d, out, batches=2, move={"Grad Fish": 2})
    assert {r["name"]: r["batch"] for r in rows} == {"Plain Cube": 1, "Grad Fish": 2, "Tilted Ray": 2}
    m2 = json.loads((out / "manifest_batch2.json").read_text())
    assert "Grad Fish" in m2["models"] and "Grad Fish" not in json.loads((out / "manifest_batch1.json").read_text())["models"]
