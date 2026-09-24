import json

import pytest
from brainrot_forge import pets as P
from brainrot_forge.designs.pets import BEFORE, PET_DESIGNS, PETS
from brainrot_forge.export_glb import read_glb, write_glb
from brainrot_forge.pets import EGG_BODY, PetModel, bake_pet, shade, swap_side


def pet(*cells):
    """cells: (x, y, z, group, role)"""
    m = PetModel("T", "Epic", pitch=0.1).role("a", "#C08040").role("b", "#4080C0")
    for x, y, z, g, r in cells:
        with m.group(g):
            m.set(x, y, z, r)
    return m


def lum(h):
    return sum(int(h[i:i + 2], 16) for i in (1, 3, 5))


def test_groups_follow_the_painting_context_and_mirror_swaps_sides():
    m = PetModel("T", "Epic").role("a", "#808080")
    with m.group("ears/ear_l"):
        m.set(2, 5, 0, "a")
    with m.group("leg_1l"):
        m.set(1, 0, 0, "a")
    m.set(0, 3, 0, "a")                                   # outside any context: the body
    m.mirror_x()
    assert m.groups[(2, 5, 0)] == "ears/ear_l" and m.groups[(-2, 5, 0)] == "ears/ear_r"
    assert m.groups[(-1, 0, 0)] == "leg_1r" and m.groups[(0, 3, 0)] == "body"
    assert swap_side("tail") == "tail" and swap_side("antler_r") == "antler_l" and swap_side("eyes") == "eyes"


def test_the_rigs_l_side_is_plus_x():
    """PetVisualsClient: an ear's side is +1 when its name ends in l and the flop is Angles(0, 0, flop * side),
    so only an l ear on +X mirrors an r ear on -X."""
    m = PET_DESIGNS["Elder Stag"]()
    assert min(c[0] for c, g in m.groups.items() if g == "ears/ear_l") > 0
    assert max(c[0] for c, g in m.groups.items() if g == "ears/ear_r") < 0


def test_faces_inside_a_group_are_dropped_and_faces_between_groups_kept():
    grey = lambda m: {c: "#808080" for c in m.cells}
    count = lambda m: sum(len(v) for v in P.pet_faces(m, grey(m)).values())
    assert count(pet((0, 0, 0, "body", "a"), (1, 0, 0, "body", "a"))) == 10
    assert count(pet((0, 0, 0, "body", "a"), (1, 0, 0, "leg_1l", "a"))) == 12   # the seam moves: both sides stay


def test_one_mesh_per_group_and_every_voxel_keeps_its_own_colour():
    m = pet((0, 0, 0, "body", "a"), (1, 0, 0, "body", "b"), (0, 1, 0, "head", "a"))
    colours = {(0, 0, 0): "#C08040", (1, 0, 0): "#4080C0", (0, 1, 0): "#102030"}
    bp = bake_pet(m, colours)
    assert set(bp.meshes) == {"body", "head"}
    assert bp.palette["body"] == "#C080C0"                # per-channel max = the MeshPart colour
    rep = P._rgb(bp.palette["body"])
    body = bp.meshes["body"]
    seen = {}
    for i in range(0, len(body.indices), 6):              # one quad = 2 triangles = 6 indices
        v = body.indices[i]
        n, p, k = body.normals[v], body.positions[v], body.colors[v]
        seen[(n, round(p[0], 3))] = P._hex(tuple(rep[j] * k[j] for j in range(3)))
    assert seen[((1.0, 0.0, 0.0), 0.2)] == "#4080C0"        # the outer face of the blue voxel
    assert seen[((-1.0, 0.0, 0.0), 0.0)] == "#C08040"       # the outer face of the brown one


def test_shading_is_deterministic_bounded_and_top_lit():
    m = PetModel("T", "Epic", seed=3).role("a", "#A0A0A0").role("pupil", "#1E1F2A")
    m.flat = {"pupil"}
    m.box(0, 3, 0, 19, 0, 3, "a")
    m.set(0, 20, 0, "pupil")
    s1, s2 = shade(m), shade(m)
    assert s1 == s2
    assert s1[(0, 20, 0)] == "#1E1F2A"                    # flat roles are never shaded
    assert 3 <= len({s1[c] for c, r in m.cells.items() if r == "a"}) <= 5
    low = [lum(s1[c]) for c, r in m.cells.items() if r == "a" and c[1] < 5]
    high = [lum(s1[c]) for c, r in m.cells.items() if r == "a" and c[1] >= 15]
    assert sum(high) / len(high) > sum(low) / len(low)


def test_outline_darkens_the_limb_row_that_meets_its_parent():
    m = PetModel("T", "Epic").role("a", "#A0A0A0")
    m.box(-2, 2, 5, 8, -2, 2, "a")                        # body
    with m.group("leg_1l"):
        m.box(1, 1, 0, 4, 0, 0, "a")
    assert P.seam_cells(m) == {(1, 4, 0)}
    s = shade(m)
    dark = P.tone_of("#A0A0A0", P.TONES[0])
    assert s[(1, 4, 0)] == dark
    assert all(s[c] != dark for c in m.cells if c != (1, 4, 0))


@pytest.mark.parametrize("name", PETS)
def test_designs_pass_the_gate_and_are_deterministic(name):
    a, b = PET_DESIGNS[name](), PET_DESIGNS[name]()
    assert a.validate() == []
    assert a.pitch == P.PET_PITCH
    assert a.cells == b.cells and a.groups == b.groups and shade(a) == shade(b)


@pytest.mark.parametrize("name", PETS)
def test_designs_bake_one_mesh_per_group_under_the_gate(name):
    m = PET_DESIGNS[name]()
    bp = bake_pet(m)
    assert set(bp.meshes) == {P.leaf(g) for g in set(m.groups.values())}
    assert sum(x.triangles for x in bp.meshes.values()) <= P.MAX_TRIS_PET
    assert all(len(x.colors) == len(x.positions) for x in bp.meshes.values())
    if m.kind == "pet":
        assert max(bp.size_studs()) == pytest.approx(P.PET_SIZE)      # the follow rig shows it 1:1
        assert "eyes" in bp.meshes and 3 <= max(bp.tones.values()) <= 5
    else:
        assert list(bp.meshes) == [EGG_BODY]


def test_glb_and_manifest_round_trip(tmp_path):
    bp = bake_pet(PET_DESIGNS["Sap Snail"]())
    write_glb(tmp_path / "p.glb", [(bp, bp.meshes)])
    nodes = read_glb(tmp_path / "p.glb")
    assert set(nodes) == {f"Sap Snail__{g}" for g in bp.meshes}
    assert all(n["colors"] is not None for n in nodes.values())
    man = P.pet_manifest([bp])
    e = man["models"]["Sap Snail"]
    assert man["mode"] == "pet" and man["pitch"] == 0.08 and man["robloxForward"] is True
    assert e["kind"] == "pet" and e["vertexColors"] is True and e["groupPaths"]["antenna_l"] == "antenna_l"
    assert e["triangles"] == {g: x.triangles for g, x in bp.meshes.items()}
    assert (e["voxels"], e["colours"], e["meshes"]) == (bp.voxels, bp.colours, len(bp.meshes))


def test_contact_sheet_draws_a_before_and_after_row(tmp_path):
    m = pet((0, 0, 0, "body", "a"), (0, 1, 0, "head", "b"))
    bp = bake_pet(m)
    path = P.pet_sheet([("T", (bp, bp.meshes), (bp, bp.meshes)), ("T2", None, (bp, bp.meshes))],
                       tmp_path / "s.png", size=64, icon=32)
    from PIL import Image
    img = Image.open(path)
    assert img.size == (64 * 6 + 32 + 40, 22 + 64 * 2)


def test_before_dump_loads_as_renderable_parts(tmp_path):
    dump = [{"name": "vox_T", "rarity": "Item5", "world": "Prototype", "attrs": {}, "fx": False,
             "parts": [[0, 0.1, 0, 0.2, 0.2, 0.2, "c08040", "S"], [0, 0.3, 0, 0.2, 0.2, 0.2, "4080c0", "S"]]}]
    (tmp_path / "d.json").write_text(json.dumps(dump))
    model, meshes = P.load_before(tmp_path / "d.json")["vox_T"]
    assert len(meshes) == 2 and set(BEFORE) == set(PETS)


def test_cli_pets_without_previews(tmp_path):
    from brainrot_forge.__main__ import main
    assert main(["pets", "--out", str(tmp_path), "--no-previews", "--before", str(tmp_path / "none.json")]) == 0
    man = json.loads((tmp_path / "manifest.json").read_text())
    assert (tmp_path / "pets_batch.glb").exists() and set(man["models"]) == set(PETS)
