"""NpcForge builds Gianluca (blockout) and the Veteran (on a clone) from data;
the results satisfy the manifests, the budget gate and the never-touch-the-source rule."""
import pytest

from npc_kit.tests.conftest import build_gianluca, rows


def classes(H, model):
    out = {}
    for d in H.descendants(model):
        out[d.ClassName] = out.get(d.ClassName, 0) + 1
    return out


def test_gianluca_blockout_matches_manifest(H):
    model, report = build_gianluca(H)
    assert model.Name == "StupidGianluca"
    c = classes(H, model)
    base_parts = c.get("Part", 0) + c.get("MeshPart", 0)
    # blockout pieces are 2-3 primitives where the mesh build has one; the mesh build must hit <= 38
    assert 33 <= base_parts <= 49, base_parts
    assert model.GetAttribute(model, "NpcBlockout") is True
    assert c.get("Motor6D") == 22, c
    assert c.get("Humanoid", 0) == 0 and c.get("AnimationController") == 1
    assert c.get("ProximityPrompt", 0) == 0, "the live TalkPrompt must never be recreated by the forge"
    face = H.find(model, "Face", False)
    assert face is not None and len(H.children_names(face)) == 7
    hrp = H.find(model, "HumanoidRootPart", False)
    assert hrp.Anchored is True and hrp.Transparency == 1 and H.same(model.PrimaryPart, hrp)
    head = H.find(model, "Head", False)
    assert head.Position.Y - hrp.Position.Y == pytest.approx(1.45, abs=0.01)  # +4 deg rest lean moves it ~3 mm
    collider = H.find(model, "Collider", False)
    assert collider is not None and collider.CanCollide is True and collider.CollisionGroup == "NpcBody"
    assert collider.Size.X <= 2.2 and collider.Size.Y <= 5.0, "collider must stay tight to the body (D-1)"
    anchored = [d.Name for d in H.descendants(model) if d.IsA(d, "BasePart") and d.Anchored]
    assert sorted(anchored) == ["Collider", "HumanoidRootPart"]
    for d in H.descendants(model):
        if d.IsA(d, "BasePart"):
            assert d.CanQuery is False and d.CanTouch is False
            if d.Name != "Collider":
                assert d.CanCollide is False
    assert H.stub.CollectionService.HasTag(H.stub.CollectionService, model, "NpcBody")
    assert model.GetAttribute(model, "NpcPack") == "Villager"
    assert "greet=ringBell" in model.GetAttribute(model, "NpcPackOverrides")
    assert model.Parent.Name == "Valley" and model.Parent.Parent.Name == "NpcStaging"
    assert report.budget["pass"] is True, rows(report)
    assert "register:NpcBody" in H.lua_list(H.stub.PhysicsService.calls)


def test_gianluca_pieces_are_welded_and_rest_pose_is_baked(H):
    model, _ = build_gianluca(H)
    cane = H.find(model, "Cane", True)
    bell = H.find(model, "Bell", True)
    assert cane is not None and bell is not None
    assert cane.GetAttribute(cane, "Planted") is True and cane.GetAttribute(cane, "Grip") == "RightHand"
    weld = cane.FindFirstChildWhichIsA(cane, "WeldConstraint")
    assert weld is not None and weld.Part0.Name == "RightHand"
    bell_weld = bell.FindFirstChildWhichIsA(bell, "WeldConstraint")
    assert bell_weld.Part0.Name.startswith("Cane")
    Rig = H.require("ReplicatedStorage/Modules/NpcKit/NpcRigSpec")
    c0_raw, _, _ = Rig.JointFrames("standard", "Waist")
    waist = H.find(model, "UpperTorso", False).FindFirstChild(H.find(model, "UpperTorso", False), "Waist")
    assert waist is not None
    assert abs(waist.C0.LookVector.Y - c0_raw.LookVector.Y) > 0.01, "rest pose (Waist bend +4) should be baked into C0"
    names = H.children_names(H.find(model, "Outfit", False))
    assert "BracerR" in names and "BracerL" in names and any(n.startswith("ToolBeltCollar") for n in names)
    hair = H.children_names(H.find(model, "Hair", False))
    assert any(n.startswith("HairTousled") for n in hair) and any(n.startswith("HatFloppyPinned") for n in hair)


def test_no_orphan_parts_every_part_reaches_the_root(H):
    model, report = build_gianluca(H)
    Budget = H.require("ServerStorage/NpcBudget")
    r = Budget.report(model)
    assert r.orphans == 0 and r.faceParts == 7 and r.motor6d == 22


def test_villager_tier1_builds_and_passes(H):
    forge = H.forge()
    model, report = forge.Build("Villager_Valley_01", H.table(blockout=True))
    assert model is not None, rows(report)
    assert model.Name == "NPC" and H.find(model, "Collider", False) is None
    c = classes(H, model)
    assert c.get("Part", 0) <= 30


def test_veteran_builds_on_a_clone_and_never_touches_the_source(H):
    src = H.make_species_template()
    before = len(H.descendants(src))
    emitters_before = sum(1 for d in H.descendants(src) if d.ClassName == "ParticleEmitter")
    forge = H.forge()
    model, report = forge.Build("VeteranBombardiro", H.table(speciesSource=src))
    assert model is not None, rows(report)
    assert not H.same(model, src) and src.Parent.Name == "BrainrotModels"
    assert len(H.descendants(src)) == before
    assert sum(1 for d in H.descendants(src) if d.ClassName == "ParticleEmitter") == emitters_before
    c = classes(H, model)
    assert c.get("ParticleEmitter", 0) == 0 and c.get("Sound", 0) == 0
    layer = H.find(model, "StoryLayer", False)
    assert layer is not None and len(H.children_names(layer)) == 8
    root = H.find(model, "RootPart", False)
    assert root.Anchored is True
    assert model.GetAttribute(model, "NpcRig") == "Creature" and model.GetAttribute(model, "NpcProfile") == "Veteran"
    Budget = H.require("ServerStorage/NpcBudget")
    r = Budget.report(model)
    assert r.orphans == 0 and r.storyParts == 8
    assert model.GetScale(model) != 1.0, "plot fit should have scaled the clone"
    assert abs(model.GetPivot(model).UpVector.Y - 1.0) > 1e-4, "stance should tilt the model"
    splint = H.find(layer, "WingSplint", False)
    assert splint.GetAttribute(splint, "Bone") == "WingL"
    medal = H.find(layer, "Medal", False)
    assert medal.GetAttribute(medal, "Bone") == "HarnessPlate"
    assert not H.stub.CollectionService.HasTag(H.stub.CollectionService, model, "BrainrotBody")


def test_budget_fails_on_forbidden_instances(H):
    model, _ = build_gianluca(H)
    Budget = H.require("ServerStorage/NpcBudget")
    assert Budget.review(model, 2, "human")["pass"] is True
    hum = H.stub.Instance.new("Humanoid")
    hum.Parent = model
    assert Budget.review(model, 2, "human")["pass"] is False
    hum.Destroy(hum)
    loose = H.stub.Instance.new("Part")
    loose.Name = "Loose"
    loose.Parent = model
    r = Budget.review(model, 2, "human")
    assert r["pass"] is False and any(H.lua_list(r.rows)[i].name == "orphans" and H.lua_list(r.rows)[i].status == "FAIL" for i in range(len(H.lua_list(r.rows))))


def test_swap_live_is_gated_and_never_called_by_build(H):
    forge = H.forge()
    staged, _ = build_gianluca(H)
    live = H.stub.Instance.new("Model")
    live.Name = "StupidGianluca"
    with pytest.raises(Exception):
        forge.SwapLive(staged, live, H.table())
    # Build must not reach SwapLive: replace it with a tripwire and build again
    tripped = {"n": 0}

    def trip(*a):
        tripped["n"] += 1
        raise RuntimeError("SwapLive called from Build")
    forge.SwapLive = trip
    m2, _ = forge.Build("Villager_Valley_01", H.table(blockout=True))
    assert m2 is not None and tripped["n"] == 0
