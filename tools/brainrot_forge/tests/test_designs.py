import pytest
from brainrot_forge.bake import bake, triangle_report
from brainrot_forge.voxel import MAX_ROLES
from brainrot_forge.designs import DESIGNS, PILOT

LADDER = {"Epic": 1.30, "Legendary": 1.36, "Secret": 1.46}   # Tundra HeightScale per rarity


@pytest.mark.parametrize("name", PILOT)
def test_registry_and_gate(name):
    model = DESIGNS[name]()
    assert model.name == name and model.world == "Tundra"
    assert model.validate() == []
    assert len(model.palette) <= MAX_ROLES
    assert model.height_scale == LADDER[model.rarity]


@pytest.mark.parametrize("name", PILOT)
def test_deterministic(name):
    a, b = DESIGNS[name](), DESIGNS[name]()
    assert a.cells == b.cells and a.palette == b.palette


@pytest.mark.parametrize("name", PILOT)
def test_bakes_under_budget(name):
    meshes = bake(DESIGNS[name]())
    report = triangle_report(meshes)
    assert 200 <= sum(report.values()) <= 8000
    assert len(meshes) <= 10


@pytest.mark.parametrize("name", PILOT)
def test_eyes_face_minus_z(name):
    m = DESIGNS[name]()
    eye_z = {z for (x, y, z), r in m.cells.items() if r == "pupil"}
    assert len(eye_z) == 1, "both pupils sit on one front layer"
    z = eye_z.pop()
    pupils = [(x, y) for (x, y, zz), r in m.cells.items() if r == "pupil" and zz == z]
    assert all((x, y, z - 1) not in m.cells for (x, y) in pupils), "pupils are exposed toward -Z"


def test_bands_and_effects():
    epic, leg, sec = (DESIGNS[n]() for n in PILOT)
    assert (epic.rarity, leg.rarity, sec.rarity) == ("Epic", "Legendary", "Secret")
    assert epic.fx is None and len(leg.fx) <= 6 and len(sec.fx) <= 6
    assert sec.motion == "shiver" and epic.motion == "hover" and leg.motion == "hover"
    kits = {"glow", "flare", "aura1", "aura2", "aura3", "snow", "glare", "specs", "cubes", "stars"}
    assert all(e["kit"] in kits for e in leg.fx + sec.fx)
