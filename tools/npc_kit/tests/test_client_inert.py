"""NpcLifeClient (the LocalScript) is inert in a place with no NPC-01 bodies:
it registers nothing, writes nothing, and leaves a legacy Humanoid rig alone."""


def test_client_runs_inert_and_ignores_legacy_rigs(H):
    I = H.stub.Instance
    # a legacy shopkeeper-like rig: Humanoid + HRP, no tag
    legacy = I.new("Model"); legacy.Name = "NPC"
    hrp = I.new("Part"); hrp.Name = "HumanoidRootPart"; hrp.CFrame = H.stub.CFrame.new(3, 3, 3); hrp.Parent = legacy
    head = I.new("Part"); head.Name = "Head"; head.CFrame = H.stub.CFrame.new(3, 4.5, 3); head.Parent = legacy
    I.new("Humanoid").Parent = legacy
    legacy.Parent = H.stub.services.Workspace
    before = (H.v3t(hrp.CFrame.Position), H.v3t(head.CFrame.Position))

    H.run_local_script("StarterPlayer/StarterPlayerScripts/NpcLifeClient")
    log = H.log()
    assert any("online (0 NPC-01 bodies)" in line for line in log), log
    for _ in range(300):
        H.tick()
    assert H.v3t(hrp.CFrame.Position) == before[0] and H.v3t(head.CFrame.Position) == before[1]
    assert not any("WARN" in line for line in H.log()), H.log()


def test_client_picks_up_a_tagged_body_later(H):
    H.run_local_script("StarterPlayer/StarterPlayerScripts/NpcLifeClient")
    forge = H.forge()
    model, _ = forge.Build("Villager_Valley_01", H.table(blockout=True))
    model.Parent = H.stub.services.Workspace
    model.PivotTo(model, H.stub.CFrame.new(0, 3, 0))
    H.stub.services.Workspace.CurrentCamera.CFrame = H.stub.CFrame.lookAt(H.stub.Vector3.new(0, 5, 15), H.stub.Vector3.new(0, 3, 0))
    waist = H.find(model, "UpperTorso", False).FindFirstChild(H.find(model, "UpperTorso", False), "Waist")
    rest = waist.C0
    for _ in range(40):
        H.tick()
    assert waist.C0.LookVector.Y != rest.LookVector.Y, "a tagged body entering Workspace should start breathing"


def test_client_hooks_dialogue_ui_created_later(H):
    """MerchantDialog creates its ScreenGui on the first conversation; the client must
    hook it whenever it appears and use it to start/stop the talking state."""
    H.run_local_script("StarterPlayer/StarterPlayerScripts/NpcLifeClient")
    forge = H.forge()
    model, _ = forge.Build("Villager_Valley_01", H.table(blockout=True))
    model.Parent = H.stub.services.Workspace
    model.PivotTo(model, H.stub.CFrame.new(0, 3, 0))
    H.stub.services.Workspace.CurrentCamera.CFrame = H.stub.CFrame.lookAt(H.stub.Vector3.new(0, 5, 15), H.stub.Vector3.new(0, 3, 0))
    prompt = H.stub.Instance.new("ProximityPrompt")
    prompt.Parent = H.find(model, "HumanoidRootPart", False)
    for _ in range(5):
        H.tick()
    # the dialogue UI appears now (first conversation of the session)
    I = H.stub.Instance
    gui = I.new("ScreenGui"); gui.Name = "MerchantDialogUI"
    root = I.new("Frame"); root.Name = "DialogRoot"; root.Parent = gui
    gui.Parent = H.stub.services.Players.LocalPlayer.PlayerGui
    PPS = H.stub.ProximityPromptService
    PPS.PromptShown.Fire(PPS.PromptShown, prompt)
    PPS.PromptTriggered.Fire(PPS.PromptTriggered, prompt)
    root.Visible = True
    H.tick()
    mouth = H.find(H.find(model, "Face", False), "Mouth", False)
    sizes = set()
    for _ in range(120):
        H.tick()
        sizes.add(round(mouth.Size.Y, 3))
    assert len(sizes) > 2, "talking should have started from the dialogue Visible signal"
    root.Visible = False
    H.tick()
    H.tick()
    assert round(mouth.Size.Y, 3) == round(H.require("ReplicatedStorage/Modules/NpcKit/NpcFaceConfig").Resolve("friendly").Mouth.size.Y, 3)
