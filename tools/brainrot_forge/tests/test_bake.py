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
