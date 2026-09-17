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


def test_paint_recolours_only_existing_cells():
    m = make()
    m.box(0, 2, 0, 2, 0, 0, "body")
    m.paint(1, 1, -5, 5, -5, 5, "eye")
    assert m.count_by_role() == {"body": 6, "eye": 3} and len(m.cells) == 9


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
