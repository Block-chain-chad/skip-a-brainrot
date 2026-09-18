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


def test_load_dump_padded_result(tmp_path):
    # execute_luau results are padded with trailing spaces to force persistence
    models = [{"name": "A", "rarity": "Epic", "world": "Tundra", "attrs": {}, "fx": False, "parts": [[0, 1, 0, 2, 2, 2, "ff0000", "P"]]}]
    p = tmp_path / "padded.json"; p.write_text(dump_json(models) + " " * 500)
    assert [m.name for m in I.load_dump(p)] == ["A"]


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
    # the second box sits +2 along world x; in the shared local frame R^T * (2,0,0) = (0,0,+2)
    p0, p1 = u.boxes[0].pos, u.boxes[1].pos
    assert math.isclose(p1[2] - p0[2], 2, abs_tol=1e-6) and math.isclose(p1[0] - p0[0], 0, abs_tol=1e-6)
    # round trip: world = R * (local - c) + c
    c = u.pose_centre
    for b, w in zip(u.boxes, boxes):
        d = (b.pos[0] - c[0], b.pos[1] - c[1], b.pos[2] - c[2])
        back = (R[0] * d[0] + R[1] * d[1] + R[2] * d[2] + c[0],
                R[3] * d[0] + R[4] * d[1] + R[5] * d[2] + c[1],
                R[6] * d[0] + R[7] * d[1] + R[8] * d[2] + c[2])
        assert all(math.isclose(a, e, abs_tol=1e-6) for a, e in zip(back, w.pos))


def test_unpose_mixed_rotations_refused():
    R = (0, 0, 1, 0, 1, 0, -1, 0, 0)
    boxes = [I.Box((0, 0, 0), (1, 1, 1), "#FFFFFF", "Plastic", R), I.Box((2, 0, 0), (1, 1, 1), "#FFFFFF", "Plastic", None)]
    with pytest.raises(ValueError, match="mixed"):
        I.unpose(I.PartModel("T", "Epic", "Tundra", {}, False, boxes))
