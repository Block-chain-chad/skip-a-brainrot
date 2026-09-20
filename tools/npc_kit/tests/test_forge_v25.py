"""NpcForge assembles the APPROVED Gianluca V2.5 from the generated shell manifest: every
bone is the manifest's slot MeshPart, the face is a mesh face driven through the same
seven parts, the spear is planted in his hand, the body sits on the p2 profile with
D-22 overrides, the Veteran pack and the warMemory reaction run in NpcLife, and the
checked-in manifest still matches the study kit it was generated from."""
import numpy as np
import pytest

from npc_kit.v2 import characters25 as C25
from npc_kit.v2 import export_kit as X
from npc_kit.tests.test_life import make_life, place_in_workspace, step

BONES = ["Head", "UpperTorso", "LowerTorso", "RightUpperArm", "LeftUpperArm", "RightLowerArm", "LeftLowerArm", "RightHand", "LeftHand",
         "RightUpperLeg", "LeftUpperLeg", "RightLowerLeg", "LeftLowerLeg", "RightFoot", "LeftFoot"]


def rows(report):
    b = report.budget
    return {r.name: (r.value, r.limit, r.status) for r in [b.rows[i] for i in range(1, len(b.rows) + 1)]}


def build(H, **opts):
    forge = H.forge()
    root = H.import_root_for_shells("Gianluca_V25")
    model, report = forge.Build("Gianluca", H.table(importRoot=root, **opts))
    assert model is not None, rows(report)
    return model, report


def aabb_y(H, part):
    lo, hi = H.world_aabb(part)
    return lo[1], hi[1]


# ----- assembly ---------------------------------------------------------------------
def test_v25_builds_every_bone_from_the_shell_manifest(H):
    model, report = build(H)
    assert model.Name == "StupidGianluca", "the live root name contract"
    assert dict(report.sources.items()) == {"forge": 41}
    r = rows(report)
    assert report.budget["pass"] is True, r
    assert r["baseParts"][0] == 43 and r["welds"][0] == 19 and r["motor6d"][0] == 22 and r["bespokeMeshes"][0] == 7
    assert r["trianglesEstimated"][0] == 4188 and r["trianglesEstimated"][1] == 16000, "Tier 3 caps"
    for bone in BONES:
        p = H.find(model, bone, False)
        assert p is not None and p.ClassName == "MeshPart" and p.Parent.Name == model.Name, f"{bone} must be the slot MeshPart, a direct child"
        assert p.GetAttribute(p, "Tris") > 0
    assert model.GetAttribute(model, "NpcShells") == "Gianluca_V25"
    assert model.GetAttribute(model, "NpcTier") == 3 and model.GetAttribute(model, "NpcPack") == "Veteran"
    assert model.GetAttribute(model, "NpcBodyType") == "p2"
    assert model.GetAttribute(model, "NpcHeadOffset") == pytest.approx(1.575, abs=1e-6)
    assert model.GetAttribute(model, "NpcBlockout") is None
    assert H.find(model, "Collider", False) is not None
    assert not [d for d in H.descendants(model) if d.ClassName == "ProximityPrompt"], "never recreates the TalkPrompt"


def test_v25_slot_meshes_sit_on_the_bone_origin_and_joints_stay_on_the_pivots(H):
    # an unposed build: part centre = HRP + bone offset + the mesh's bbox centre
    forge = H.forge()
    root = H.import_root_for_shells("Gianluca_V25")
    rec = H.require("ReplicatedStorage/Modules/NpcKit/NpcCharacters/Gianluca")
    g = H.lua.eval("function(r) local t = {} for k, v in pairs(r) do t[k] = v end return t end")(rec)
    g["restPose"] = H.lua.table(); g["id"] = "Gianluca_unposed"; g["rootName"] = "Gianluca_unposed"
    model, report = forge.Build(g, H.table(importRoot=root))
    assert model is not None
    Rig = H.require("ReplicatedStorage/Modules/NpcKit/NpcRigSpec")
    man = H.require("ReplicatedStorage/Modules/NpcKit/NpcShells/Gianluca_V25")
    centres = {man.pieces[i].name: man.pieces[i].offset for i in range(1, len(man.pieces) + 1) if man.pieces[i].slot}
    hrp = H.find(model, "HumanoidRootPart", False)
    for bone in BONES:
        spec = Rig.PartByName("p2", bone)
        p = H.find(model, bone, False)
        want = (hrp.Position.X + spec.offset.X + centres[bone].X, hrp.Position.Y + spec.offset.Y + centres[bone].Y, hrp.Position.Z + spec.offset.Z + centres[bone].Z)
        assert H.dist(p.Position, H.stub.Vector3.new(*want)) < 1e-5, bone
    # every Motor6D's pivot (Part0 * C0) equals the rig pivot in world
    for d in H.descendants(model):
        if d.ClassName == "Motor6D" and d.Name != "FaceJoint":
            c0, c1, j = Rig.JointFrames("p2", d.Name)
            piv = H.mul(d.Part0.CFrame, d.C0).Position
            want = H.stub.Vector3.new(hrp.Position.X + j.pivot.X, hrp.Position.Y + j.pivot.Y, hrp.Position.Z + j.pivot.Z)
            assert H.dist(piv, want) < 1e-5, d.Name
            piv1 = H.mul(d.Part1.CFrame, d.C1).Position
            assert H.dist(piv, piv1) < 1e-5, d.Name


def test_v25_blockout_builds_the_same_silhouette_as_boxes(H):
    forge = H.forge()
    model, report = forge.Build("Gianluca", H.table(blockout=True))
    assert model is not None and dict(report.sources.items()) == {"blockout": 41}
    assert model.GetAttribute(model, "NpcBlockout") is True and report.budget["pass"] is True
    assert H.find(model, "Head", False).ClassName == "Part"
    assert len(H.children_names(H.find(model, "Face", False))) == 7


def test_v25_no_family_defaults_stack_on_the_shells(H):
    model, _ = build(H)
    outfit = H.children_names(H.find(model, "Outfit", False))
    assert outfit == ["HoodDown", "Scarf", "Clasp", "TunicFront", "CoatSkirts", "Belt", "Buckle", "Pouch", "ChimCollar", "ShoulderPlate", "LeftPatch"]
    assert H.children_names(H.find(model, "Hair", False)) == ["AgeLines", "Beard", "Hair"]
    assert H.children_names(H.find(model, "Props", False)) == ["Bell", "Spear", "SpearGrip", "SpearHead", "SpearCloth"]
    for name in ("Clasp", "ChimCollar", "ShoulderPlate", "Spear", "SpearGrip", "SpearHead", "SpearCloth"):
        assert H.find(model, name, True).GetAttribute(H.find(model, name, True), "NpcBespoke") is True, name
    for d in H.descendants(model):
        if d.IsA(d, "BasePart") and d.Parent.Name in ("Hair", "Outfit", "Props"):
            w = d.FindFirstChildWhichIsA(d, "WeldConstraint")
            assert w is not None and w.Part0.Name == d.GetAttribute(d, "Bone"), d.Name


def test_v25_spear_is_planted_in_the_right_hand(H):
    model, _ = build(H)
    hand = H.find(model, "RightHand", False)
    grip = H.find(model, "SpearGrip", True)
    assert H.dist(grip.Position, hand.Position) < 0.3
    spear = H.find(model, "Spear", True)
    assert spear.GetAttribute(spear, "Planted") is True and spear.GetAttribute(spear, "Grip") == "RightHand"
    lo = min(aabb_y(H, H.find(model, n, True))[0] for n in ("Spear", "SpearGrip", "SpearHead", "SpearCloth"))
    assert lo == pytest.approx(0.0, abs=0.15), f"planted on the ground, got {lo}"
    head = H.find(model, "Head", False)
    assert aabb_y(H, H.find(model, "SpearHead", True))[1] > aabb_y(H, head)[1] + 0.3, "the head rides above his own"
    assert aabb_y(H, H.find(model, "RightFoot", False))[0] > -0.06, "feet on the ground"


# ----- face -----------------------------------------------------------------------------
def test_v25_mesh_face_states_apply_through_the_same_seven_parts(H):
    model, _ = build(H)
    FC = H.require("ReplicatedStorage/Modules/NpcKit/NpcFaceConfig")
    face = H.find(model, "Face", False)
    assert face.GetAttribute(face, "NpcFaceMesh") is True
    for name in ("EyeL", "EyeR", "PupilL", "PupilR", "BrowL", "BrowR", "Mouth"):
        p = H.find(face, name, False)
        assert p.ClassName == "MeshPart" and p.GetAttribute(p, "RestC0") is not None and p.GetAttribute(p, "RestSize") is not None
        assert p.FindFirstChild(p, "FaceJoint").Part0.Name == "Head"
    browR = H.find(face, "BrowR", False)
    mouth = H.find(face, "Mouth", False)
    assert FC.Apply(model, "serious") == 7
    y_serious = browR.FindFirstChild(browR, "FaceJoint").C0.Position.Y
    assert FC.Apply(model, "shocked") == 7
    y_shocked = browR.FindFirstChild(browR, "FaceJoint").C0.Position.Y
    assert y_shocked > y_serious + 0.15, "shocked lifts the brows"
    assert H.find(face, "EyeR", False).Size.Y > H.find(face, "EyeR", False).GetAttribute(H.find(face, "EyeR", False), "RestSize").Y * 1.1
    FC.Apply(model, "worried")
    assert mouth.FindFirstChild(mouth, "FaceJoint").C0.RightVector.X < -0.99, "a frown = the smile mesh turned 180 deg"
    FC.Apply(model, "friendly")     # legacy name on a mesh face -> alias
    assert mouth.FindFirstChild(mouth, "FaceJoint").C0.RightVector.X > 0.99
    assert mouth.Size.X > mouth.GetAttribute(mouth, "RestSize").X * 1.2


# ----- D-22 -------------------------------------------------------------------------------
def test_v25_body_overrides_reshape_the_same_rig(H):
    forge = H.forge()
    root = H.import_root_for_shells("Gianluca_V25")
    rec = H.require("ReplicatedStorage/Modules/NpcKit/NpcCharacters/Gianluca")
    copy = H.lua.eval("function(r) local t = {} for k, v in pairs(r) do t[k] = v end return t end")
    base, _ = build(H)
    g = copy(rec); g["id"] = "Gianluca_big"; g["rootName"] = "Gianluca_big"
    g["bodyOverrides"] = H.table(height=1.12, headScale=1.1, shoulderWidth=1.15, torsoMass=1.1, limbThickness=1.2, legLength=0.9,
                                 posture=H.table(Waist=H.table(bend=2)))
    big, report = forge.Build(g, H.table(importRoot=root))
    assert big is not None, rows(report)
    assert big.GetAttribute(big, "NpcBodyOverrides") == "headScale=1.1;height=1.12;legLength=0.9;limbThickness=1.2;shoulderWidth=1.15;torsoMass=1.1"
    assert big.GetAttribute(big, "NpcHeadOffset") > base.GetAttribute(base, "NpcHeadOffset") + 0.3
    hb, hs = H.find(big, "Head", False), H.find(base, "Head", False)
    assert hb.Size.X > hs.Size.X * 1.05 and H.find(big, "UpperTorso", False).Size.X > H.find(base, "UpperTorso", False).Size.X * 1.2
    assert H.find(big, "RightHand", False).Size.X > H.find(base, "RightHand", False).Size.X * 1.15
    assert len([d for d in H.descendants(big) if d.ClassName == "Motor6D"]) == 22
    assert aabb_y(H, H.find(big, "RightFoot", False))[0] > -0.08, "feet stay on the ground"
    waist = H.find(big, "UpperTorso", False).FindFirstChild(H.find(big, "UpperTorso", False), "Waist")
    waist0 = H.find(base, "UpperTorso", False).FindFirstChild(H.find(base, "UpperTorso", False), "Waist")
    assert abs(waist.C0.LookVector.Y) < abs(waist0.C0.LookVector.Y), "posture override straightened the lean"
    # the v1 literal types ignore overrides, loudly
    v = copy(H.require("ReplicatedStorage/Modules/NpcKit/NpcCharacters/Gianluca_v1"))
    v["bodyOverrides"] = H.table(height=1.3); v["id"] = "v1_over"; v["rootName"] = "v1_over"
    m, rep = forge.Build(v, H.table(blockout=True))
    assert m is not None and any("ignored" in w for w in H.lua_list(rep.warnings))


# ----- runtime -------------------------------------------------------------------------------
def test_v25_life_greets_with_a_nod_and_plays_the_war_memory_reaction(H):
    life = make_life(H)
    life.start(life)
    model, _ = build(H)
    place_in_workspace(H, model, 0, 0)
    H.stub.services.Workspace.CurrentCamera.CFrame = H.stub.CFrame.lookAt(H.stub.Vector3.new(0, 5, 20), H.stub.Vector3.new(0, 3, 0))
    assert life.count == 1
    entry = life.entries[model]
    assert entry.pack.id == "Veteran" and entry.face.mesh is True and entry.headOffset == pytest.approx(1.575, abs=1e-6)
    assert entry.planted.RightHand is True
    prompt = H.stub.Instance.new("ProximityPrompt"); prompt.Name = "TalkPrompt"; prompt.Parent = H.find(model, "HumanoidRootPart", False)
    step(H, life, 2)
    life.onPromptShown(life, prompt)
    step(H, life, 10)
    assert entry.gesture is not None and entry.gesture.name == "nodGreet"
    step(H, life, 120)
    # the reaction through the public attribute
    model.SetAttribute(model, "NpcReaction", "warMemory")
    assert model.GetAttribute(model, "NpcReaction") == "", "consumed"
    assert entry.gesture is not None and entry.gesture.name == "warMemory" and entry.gesture.reaction is True
    assert entry.face.expr == "tired" and entry.freezeIdleUntil > H.stub.clock
    neck = H.find(model, "Head", False).FindFirstChild(H.find(model, "Head", False), "Neck")
    rest_look = neck.C0.LookVector
    step(H, life, 60)
    assert abs(neck.C0.LookVector.X - rest_look.X) > 0.2, "he looks away"
    step(H, life, 60 * 5)
    assert entry.face.expr == "serious" and entry.gesture is None or entry.gesture.name != "warMemory"
    assert life.react(life, model, "noSuchReaction") is False


def test_v25_mesh_face_blink_and_talk_scale_from_the_rest_sizes(H):
    life = make_life(H)
    life.start(life)
    model, _ = build(H)
    place_in_workspace(H, model, 0, 0)
    H.stub.services.Workspace.CurrentCamera.CFrame = H.stub.CFrame.lookAt(H.stub.Vector3.new(0, 5, 20), H.stub.Vector3.new(0, 3, 0))
    entry = life.entries[model]
    face = H.find(model, "Face", False)
    eye = H.find(face, "EyeR", False); mouth = H.find(face, "Mouth", False)
    rest_eye = entry.face.rest.EyeR.size.Y; rest_mouth = entry.face.rest.Mouth.size.Y
    heights = set()
    for _ in range(60 * 8):
        step(H, life, 1)
        heights.add(round(eye.Size.Y / rest_eye, 2))
    assert min(heights) == pytest.approx(0.15, abs=0.01) and max(heights) == pytest.approx(1.0, abs=0.01), "blinks close to 15 % of the rest height"
    prompt = H.stub.Instance.new("ProximityPrompt"); prompt.Name = "TalkPrompt"; prompt.Parent = H.find(model, "HumanoidRootPart", False)
    life.onPromptTriggered(life, prompt, H.stub.clock)
    life.onDialogVisible(life, True, H.stub.clock)
    ratios = set()
    for _ in range(90):
        step(H, life, 1)
        ratios.add(round(mouth.Size.Y / rest_mouth, 1))
    assert len(ratios) > 2 and max(ratios) <= 2.5 and min(ratios) >= 0.9


# ----- generated data stays in sync with the study --------------------------------------------
def test_checked_in_manifest_matches_the_study_kit(H):
    man = X.manifest_for(C25.gianluca_v25())
    lua = H.require("ReplicatedStorage/Modules/NpcKit/NpcShells/Gianluca_V25")
    assert len(lua.pieces) == len(man["pieces"]) and lua.profile == man["profile"] and lua.headOffset == pytest.approx(man["headOffset"], abs=1e-4)
    for i, want in enumerate(man["pieces"], start=1):
        got = lua.pieces[i]
        assert got.name == want["name"] and got.bone == want["bone"] and bool(got.slot) == want["slot"] and got.tris == want["tris"], want["name"]
        assert H.dist(got.offset, H.stub.Vector3.new(*want["offset"])) < 1e-3 and H.dist(got.size, H.stub.Vector3.new(*want["size"])) < 1e-3, want["name"]
        assert bool(got.bespoke) == want["bespoke"]


def test_veteran_pack_and_reaction_obey_the_motion_limits(H):
    MC = H.require("ReplicatedStorage/Modules/NpcKit/NpcMotionConfig")
    Rig = H.require("ReplicatedStorage/Modules/NpcKit/NpcRigSpec")
    pack = MC.Resolve("Veteran")
    lim = MC.Limits
    joints = set(H.lua_list(Rig.JointOrder))

    def check(def_, label):
        for k in H.lua_list(def_["keys"]):      # item syntax: .keys is a lupa method
            for jname, axes in k.items():
                if jname == "t":
                    continue
                assert jname in joints, f"{label}: unknown joint {jname}"
                for axis, v in axes.items():
                    cap = lim.spineGesture if Rig.JointClass[jname] == "spine" else (lim.elbow if "Elbow" in jname else lim.wrist if "Wrist" in jname else lim.leg if ("Hip" in jname or "Knee" in jname or "Ankle" in jname) else lim.shoulder)
                    assert abs(v) <= cap, f"{label}: {jname}.{axis} = {v} > {cap}"

    for name, g in pack.gestures.items():
        check(g, name)
    assert pack.reactions is not None and pack.reactions.warMemory is not None
    check(pack.reactions.warMemory, "warMemory")
    assert pack.greet == "nodGreet" and pack.reactions.warMemory.face == "tired"
