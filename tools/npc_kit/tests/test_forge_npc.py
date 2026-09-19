"""The forge NPC profile: the standard SR-Rig body bakes to exact sizes within
budget, exports a valid Import 3D batch, and everything that hangs off the body
(attachments, face, hair/hat, clothing, props, joints) lands where the spec says."""
import json

import pytest

from brainrot_forge.export_glb import read_glb

from npc_kit import forge_npc as F
from npc_kit.build import base_body_recipe, import_root


@pytest.fixture
def body(H):
    res = F.build_segments(H)
    assert F.validate_segments(res) == []
    return res


def bbox(H, part):
    return H.world_aabb(part)


def inside(pt, box, pad=0.0):
    lo, hi = box
    return all(lo[i] - pad <= pt[i] <= hi[i] + pad for i in range(3))


def overlap(a, b, pad=0.0):
    return all(a[0][i] - pad <= b[1][i] and b[0][i] - pad <= a[1][i] for i in range(3))


# ----- 1. segments, proportions, budgets ---------------------------------------
def test_segments_generate_at_exact_spec_sizes(body):
    assert [r.name for r in body] == F.SEGMENTS
    for r in body:
        for want, got in zip(r.size, r.bbox_size):
            assert abs(want - got) <= F.SIZE_TOL, r.name
        assert r.cells > 0 and r.triangles > 0


def test_proportions_match_the_approved_standard(H, body):
    Rig = H.require("ReplicatedStorage/Modules/NpcKit/NpcRigSpec")
    height = Rig.Height("standard")
    head = next(r for r in body if r.name == "Head")
    assert height == pytest.approx(5.225, abs=1e-6)
    assert 3.2 <= height / head.size[1] <= 3.6, "3.4 heads tall (chunky, not chibi)"
    assert Rig.Root.HeadOffset == pytest.approx(1.45)
    ua = Rig.PartByName("standard", "RightUpperArm")
    shoulders = 2 * (ua.offset.X + ua.size.X / 2)
    assert 3.4 <= shoulders <= 4.3, f"shoulder span {shoulders}"


def test_mesh_budgets(body):
    for r in body:
        assert r.triangles <= 2000, r.name
    total = F.body_triangles(body)
    assert total <= F.TARGET_TRIS_BODY, f"body {total} triangles exceeds the Tier 2 target"


def test_glb_export_round_trips(H, body, tmp_path):
    npc = F.export(H, body, tmp_path)
    nodes = read_glb(tmp_path / "npc_body_standard_batch.glb")
    assert set(nodes) == {F.part_name(s, F.ROLE) for s in F.SEGMENTS}
    for r in body:
        n = nodes[F.part_name(r.name, F.ROLE)]
        xs = [p[0] for p in n["positions"]]; ys = [p[1] for p in n["positions"]]; zs = [p[2] for p in n["positions"]]
        got = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
        for want, g in zip(r.size, got):
            assert abs(want - g) <= F.SIZE_TOL
        assert len(n["indices"]) // 3 == r.triangles
    manifest = json.loads((tmp_path / "npc_manifest.json").read_text())
    assert manifest["profile"] == "npc" and len(manifest["joints"]) == 15 and len(manifest["parts"]) == 15
    assert manifest["bodyTriangles"] == F.body_triangles(body)
    assert "manifest.json" in {p.name for p in tmp_path.iterdir()}


# ----- 2. what the forge builds on top of the meshes -------------------------------
@pytest.fixture
def built(H, body):
    root = import_root(H, body)
    forge = H.forge()
    base, rep = forge.Build(base_body_recipe(H), H.table(importRoot=root))
    gia, grep = forge.Build("Gianluca", H.table(importRoot=root))
    assert base is not None and gia is not None
    return base, gia, rep, grep


def test_base_body_in_mesh_mode_passes_the_strict_budget(H, built):
    base, gia, rep, grep = built
    assert dict(rep.sources.items()) == {"forge": 15}, "no blockout piece on the base body"
    assert base.GetAttribute(base, "NpcBlockout") is None
    Budget = H.require("ServerStorage/NpcBudget")
    review = Budget.review(base, 1, "human")
    assert review["pass"] is True, [(r.name, r.value, r.limit, r.status) for r in H.lua_list(review.rows) if r.status != "PASS"]
    assert review.report.trianglesEstimated == F.body_triangles(F.build_segments(H))
    assert dict(grep.sources.items())["forge"] == 15, "Gianluca's body must come from the baked meshes"


def test_attachment_locations_sit_on_their_parts(H, built):
    base = built[0]
    for d in H.descendants(base):
        if d.ClassName == "Attachment":
            part = d.Parent
            assert part.IsA(part, "BasePart"), d.Name
            assert inside((d.WorldPosition.X, d.WorldPosition.Y, d.WorldPosition.Z), bbox(H, part), pad=0.05), f"{d.Name} floats off {part.Name}"
    head = H.find(base, "Head", False)
    hat = H.find(head, "HatAttachment", False)
    assert hat.WorldPosition.Y == pytest.approx(head.Position.Y + head.Size.Y / 2, abs=1e-6), "hat anchor on the crown"
    hand = H.find(base, "RightHand", False)
    grip = H.find(hand, "RightGripAttachment", False)
    assert inside((grip.WorldPosition.X, grip.WorldPosition.Y, grip.WorldPosition.Z), bbox(H, hand)), "grip inside the fist"


def test_face_placement_on_the_head(H, built):
    base = built[0]
    head = H.find(base, "Head", False)
    hb = bbox(H, head)
    front_z = hb[0][2]
    face = H.find(base, "Face", False)
    for name in ("EyeL", "EyeR", "PupilL", "PupilR", "BrowL", "BrowR", "Mouth"):
        p = H.find(face, name, False)
        b = bbox(H, p)
        assert b[0][0] >= hb[0][0] and b[1][0] <= hb[1][0], f"{name} outside the head width"
        assert b[0][1] >= hb[0][1] and b[1][1] <= hb[1][1], f"{name} outside the head height"
        proud = front_z - b[0][2]
        assert -0.02 <= proud <= 0.10, f"{name} is {proud:.3f} proud of the face plane (VoxelFace: recessed, only a sliver proud)"
    eye = bbox(H, H.find(face, "EyeR", False)); pupil = bbox(H, H.find(face, "PupilR", False))
    assert pupil[0][2] < eye[0][2] + 0.03, "pupil sits on the eye front"


def test_hair_and_hat_anchor_on_the_crown(H, built):
    gia = built[1]
    head = H.find(gia, "Head", False)
    hb = bbox(H, head)
    hair = H.find(gia, "Hair", False)
    cap = next(c for c in H.lua_list(hair.GetChildren(hair)) if c.Name.startswith("HairTousled"))
    cb = bbox(H, cap)
    assert overlap(cb, hb), "hair cap must sit on the head"
    assert cb[1][1] >= hb[1][1] - 0.15, "hair cap reaches the crown"
    crown = next(c for c in H.lua_list(hair.GetChildren(hair)) if c.Name == "HatFloppyPinned")   # the piece root = the crown
    kb = bbox(H, crown)
    assert kb[0][1] >= hb[1][1] - 0.35 and kb[0][1] <= hb[1][1] + 0.2, "hat crown rests on top of the head"
    for c in H.lua_list(hair.GetChildren(hair)):
        w = c.FindFirstChildWhichIsA(c, "WeldConstraint")
        assert w is not None and w.Part0.Name == "Head", c.Name
    # nothing in the hair/hat slot may cross the brow line in front of the face (checked in HEAD space,
    # so the character's rest lean does not inflate the bounds)
    face = H.find(gia, "Face", False)
    local_box = H.lua.eval("""function(head, p)
        local s = p.Size / 2
        local lo, hi
        for _, sx in ipairs({-1, 1}) do for _, sy in ipairs({-1, 1}) do for _, sz in ipairs({-1, 1}) do
            local c = head.CFrame:PointToObjectSpace(p.CFrame * Vector3.new(sx * s.X, sy * s.Y, sz * s.Z))
            if not lo then lo, hi = c, c else
                lo = Vector3.new(math.min(lo.X, c.X), math.min(lo.Y, c.Y), math.min(lo.Z, c.Z))
                hi = Vector3.new(math.max(hi.X, c.X), math.max(hi.Y, c.Y), math.max(hi.Z, c.Z)) end
        end end end
        return lo.Y, hi.Y, lo.Z, hi.Z
    end""")
    brow_top = max(local_box(head, H.find(face, n, False))[1] for n in ("BrowL", "BrowR"))
    for c in H.lua_list(hair.GetChildren(hair)):
        y0, y1, z0, z1 = local_box(head, c)
        if z0 < -head.Size.Z / 2 + 0.15:                 # reaches the face plane
            assert y0 >= brow_top - 0.02, f"{c.Name} hangs over the brows ({y0:.3f} < {brow_top:.3f})"


def test_clothing_layers_anchor_on_their_bones(H, built):
    gia = built[1]
    outfit = H.find(gia, "Outfit", False)
    for c in H.lua_list(outfit.GetChildren(outfit)):
        bone_name = c.GetAttribute(c, "Bone")
        bone = H.find(gia, bone_name, False)
        assert bone is not None, c.Name
        w = c.FindFirstChildWhichIsA(c, "WeldConstraint")
        assert w is not None and w.Part0.Name == bone_name, f"{c.Name} welded to {w.Part0.Name if w else None}"
        assert overlap(bbox(H, c), bbox(H, bone), pad=0.65), f"{c.Name} floats off {bone_name}"


def test_prop_grips_cane_planted_bell_on_knob(H, built):
    gia = built[1]
    hand = H.find(gia, "RightHand", False)
    cane = H.find(gia, "Cane", True)
    assert inside((cane.Position.X, cane.Position.Y, cane.Position.Z), bbox(H, hand), pad=0.35), "cane knob in the fist"
    props = H.find(gia, "Props", False)
    lowest = min(bbox(H, c)[0][1] for c in H.lua_list(props.GetChildren(props)) if c.Name.startswith("Cane"))
    ground = H.find(gia, "HumanoidRootPart", False).Position.Y - 3.0
    assert abs(lowest - ground) <= 0.35, f"cane tip {lowest - ground:.2f} from the ground"
    bell = H.find(gia, "Bell", True)
    assert H.dist(bell.Position, cane.Position) <= 0.6, "bell hangs at the knob"
    assert cane.GetAttribute(cane, "Planted") is True


def test_motor6d_pivots_are_compatible_with_the_parts(H, built):
    base = built[0]
    for d in H.descendants(base):
        if d.ClassName == "Motor6D" and d.Name != "FaceJoint":
            pivot = H.mul(d.Part0.CFrame, d.C0)
            pv = (pivot.Position.X, pivot.Position.Y, pivot.Position.Z)
            assert inside(pv, bbox(H, d.Part0), pad=0.16), f"{d.Name} pivot off Part0 {d.Part0.Name}"
            assert inside(pv, bbox(H, d.Part1), pad=0.16), f"{d.Name} pivot off Part1 {d.Part1.Name}"
            pivot1 = H.mul(d.Part1.CFrame, d.C1)
            assert H.dist(pivot.Position, pivot1.Position) < 1e-6, f"{d.Name}: C0 and C1 disagree on the pivot"
