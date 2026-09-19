"""NpcLife: inert with nothing tagged; animates a built Gianluca from the
captured rest without drift; greets on prompt; talks on dialogue; respects the
LOD bands and the animated cap; the NpcFace attribute is the public face API."""
import pytest

from npc_kit.tests.conftest import build_gianluca


def make_life(H):
    NpcLife = H.require("ReplicatedStorage/Modules/NpcKit/NpcLife")
    mods = H.kit_modules()
    deps = H.table(
        CollectionService=H.stub.CollectionService,
        Workspace=H.stub.services.Workspace,
        Players=H.stub.services.Players,
        camera=H.lua.eval("function() return workspace.CurrentCamera end"),
        playerHead=H.lua.eval("function() local c = game:GetService('Players').LocalPlayer.Character; local h = c and c:FindFirstChild('Head'); return h and h.Position end"),
        now=H.lua.eval("function() return workspace:GetServerTimeNow() end"),
        modules=mods,
    )
    life = NpcLife.new(deps)
    return life


def place_in_workspace(H, model, x=0, z=0):
    model.Parent = H.stub.services.Workspace
    model.PivotTo(model, H.stub.CFrame.new(x, 3, z))
    return model


def step(H, life, frames=1, dt=1 / 60):
    for _ in range(frames):
        H.stub["clock"] = H.stub.clock + dt
        life.step(life, dt, H.stub.clock)


def joint(H, model, part, name):
    p = H.find(model, part, False)
    return p.FindFirstChild(p, name)


def test_inert_with_no_tagged_bodies(H):
    life = make_life(H)
    life.start(life)
    assert life.count == 0
    step(H, life, 120)
    assert life.stats.ranks == 0 and life.stats.writes == 0


def test_adopts_built_gianluca_and_animates_from_rest(H):
    life = make_life(H)
    life.start(life)
    model, _ = build_gianluca(H)
    place_in_workspace(H, model, 0, 0)
    H.stub.services.Workspace.CurrentCamera.CFrame = H.stub.CFrame.lookAt(H.stub.Vector3.new(0, 5, 20), H.stub.Vector3.new(0, 3, 0))
    assert life.count == 1  # the tag signal adopted it when it entered Workspace
    waist = joint(H, model, "UpperTorso", "Waist")
    rest = waist.C0
    step(H, life, 30)
    assert life.stats.ranks >= 1 and life.stats.writes > 0
    # drift check: run for "60 seconds" and the root joint stays within the layer amplitude
    root = joint(H, model, "LowerTorso", "Root")
    root_rest = root.C0
    step(H, life, 60 * 60)
    assert H.dist(root.C0.Position, root_rest.Position) < 0.2
    up = root.C0.UpVector
    assert abs(up.X) < 0.12, "root tilt must stay within +-4 deg (weight shift) and never accumulate"


def test_prompt_shown_triggers_greet_then_dialogue_talking(H):
    life = make_life(H)
    life.start(life)
    model, _ = build_gianluca(H)
    place_in_workspace(H, model, 0, 0)
    H.stub.services.Workspace.CurrentCamera.CFrame = H.stub.CFrame.lookAt(H.stub.Vector3.new(0, 5, 20), H.stub.Vector3.new(0, 3, 0))
    # a prompt inside his HRP, as GianlucaClient expects
    prompt = H.stub.Instance.new("ProximityPrompt")
    prompt.Name = "TalkPrompt"
    prompt.Parent = H.find(model, "HumanoidRootPart", False)
    step(H, life, 2)
    life.onPromptShown(life, prompt)
    step(H, life, 20)
    entry = life.entries[model]
    assert entry.gesture is not None and entry.gesture.name == "ringBell"
    shoulder = joint(H, model, "RightUpperArm", "RightShoulder")
    Rig = H.require("ReplicatedStorage/Modules/NpcKit/NpcRigSpec")
    c0_raw, _, _ = Rig.JointFrames("standard", "RightShoulder")
    assert abs(shoulder.C0.LookVector.Y - c0_raw.LookVector.Y) > 0.05, "the arm should be lifting the cane"
    # conversation: trigger + dialogue frame becomes visible within 1.5 s
    life.onPromptTriggered(life, prompt, H.stub.clock)
    life.onDialogVisible(life, True, H.stub.clock)
    assert entry.talking is True and H.same(life.talkingEntry, entry)
    mouth = H.find(H.find(model, "Face", False), "Mouth", False)
    sizes = set()
    for _ in range(90):
        step(H, life, 1)
        sizes.add(round(mouth.Size.Y, 3))
    assert len(sizes) > 2, "mouth should oscillate while talking"
    life.onDialogVisible(life, False, H.stub.clock)
    assert entry.talking is False
    step(H, life, 1)
    assert round(mouth.Size.Y, 3) == round(entry.face.rest.Mouth.size.Y, 3)


def test_face_attribute_is_the_public_interface(H):
    life = make_life(H)
    life.start(life)
    model, _ = build_gianluca(H)
    place_in_workspace(H, model)
    face = H.find(model, "Face", False)
    browR = H.find(face, "BrowR", False)
    before = browR.FindFirstChild(browR, "FaceJoint").C0.RightVector.Y
    model.SetAttribute(model, "NpcFace", "stern")
    after = browR.FindFirstChild(browR, "FaceJoint").C0.RightVector.Y
    assert before != after and life.entries[model].face.expr == "stern"


def test_far_bodies_hold_and_cap_is_twelve(H):
    life = make_life(H)
    life.start(life)
    H.stub.services.Workspace.CurrentCamera.CFrame = H.stub.CFrame.lookAt(H.stub.Vector3.new(0, 5, 30), H.stub.Vector3.new(0, 3, 0))
    forge = H.forge()
    models = []
    for i in range(16):
        m, _ = forge.Build("Villager_Valley_01", H.table(blockout=True))
        m.Name = f"NPC{i}"
        place_in_workspace(H, m, (i % 4) * 4 - 6, -(i // 4) * 6)
        models.append(m)
    far, _ = forge.Build("Villager_Valley_01", H.table(blockout=True))
    far.Name = "Far"
    place_in_workspace(H, far, 500, 500)
    assert life.count == 17
    step(H, life, 12)
    animated = [e for e in H.lua_list(life.animated)]
    assert 1 <= len(animated) <= 12
    assert life.entries[far].animatedFlag is False and life.entries[far].band is None


def test_drop_when_removed_from_workspace(H):
    life = make_life(H)
    life.start(life)
    model, _ = build_gianluca(H)
    place_in_workspace(H, model)
    assert life.count == 1
    model.Parent = None
    assert life.count == 0
