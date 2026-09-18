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


def test_face_normals_point_outward():
    m = BB.bake_boxes(pm([Box((0, 0.5, 0), (1, 1, 1), "#FF0000", "Plastic", None)]))
    mesh = m.meshes["c00"]
    for t in range(mesh.triangles):
        i0, i1, i2 = mesh.indices[3 * t: 3 * t + 3]
        a, b, c = mesh.positions[i0], mesh.positions[i1], mesh.positions[i2]
        ab = tuple(b[k] - a[k] for k in range(3)); ac = tuple(c[k] - a[k] for k in range(3))
        cr = (ab[1] * ac[2] - ab[2] * ac[1], ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0])
        n = mesh.normals[i0]
        assert sum(cr[k] * n[k] for k in range(3)) > 0, "winding must agree with the stored normal (CCW = front)"


def test_roles_split_by_material_and_neon_is_neon():
    boxes = [Box((0, 0.5, 0), (1, 1, 1), "#FF0000", "Plastic", None), Box((3, 0.5, 0), (1, 1, 1), "#FF0000", "Neon", None)]
    m = BB.bake_boxes(pm(boxes))
    assert sorted(m.materials.values()) == ["Neon", "Plastic"] and len(m.meshes) == 2


def test_clustering_to_max_roles_with_vertex_ratios():
    boxes = [Box((i * 2, 0.5, 0), (1, 1, 1), f"#{200 - i * 10:02X}0000", "Plastic", None) for i in range(15)]
    m = BB.bake_boxes(pm(boxes), max_roles=4)
    assert len(m.meshes) == 4 and m.vertex_colors is True
    for role, mesh in m.meshes.items():
        assert mesh.colors is not None and all(0 < c[0] <= 1.0001 and c[1] == c[2] == 1.0 for c in mesh.colors)
        # representative is the per-channel max of its members, so no ratio exceeds 1
        assert max(c[0] for c in mesh.colors) <= 1.0001
        assert len(mesh.colors) == len(mesh.positions)


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


def test_repose_rotates_geometry_and_clears_pose():
    import math
    from brainrot_forge.ingest_parts import unpose
    R = (1, 0, 0, 0, 0, -1, 0, 1, 0)   # +90 degrees about X: (x, y, z) -> (x, -z, y)
    boxes = [Box((0, 0, 0), (1, 1, 3), "#FF0000", "Plastic", R), Box((0, 2, 0), (1, 1, 1), "#00FF00", "Plastic", R)]
    cm = BB.bake_boxes(unpose(pm(boxes)))
    assert cm.pose_rotation == R
    rp = BB.repose(cm)
    assert rp.pose_rotation is None and rp.pose_centre is None
    # the reposed AABB is the exact AABB of the two rotated world boxes: box 1 spans world y in [-1.5, 1.5], box 2 sits at world (0, 2, 0)
    lo, hi = rp.bounds
    assert all(math.isclose(a, b, abs_tol=1e-6) for a, b in zip(lo, (-0.5, -1.5, -0.5))) and all(math.isclose(a, b, abs_tol=1e-6) for a, b in zip(hi, (0.5, 2.5, 0.5)))
    for mesh in rp.meshes.values():
        assert all(math.isclose(n[0] ** 2 + n[1] ** 2 + n[2] ** 2, 1, abs_tol=1e-6) for n in mesh.normals)
        assert len(mesh.positions) == len(mesh.normals)
    # the un-rotated body is returned unchanged
    plain = BB.bake_boxes(pm([Box((0, 0.5, 0), (1, 1, 1), "#FF0000", "Plastic", None)]))
    assert BB.repose(plain) is plain
