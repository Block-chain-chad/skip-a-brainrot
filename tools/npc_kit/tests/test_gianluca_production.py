"""Gianluca production pass: the dialogue data reads as an old veteran (short, calm, no
shouting), NpcTalk walks a whole relationship deterministically (first meeting with the
existing Chim offer, searching, handover, thanks, then rotating lore with guidance every
third visit) and tells the body driver when a war memory is spoken, the driver acknowledges
an approaching player before the prompt without snapping, the prompt greet is a nod, and
adopting / dropping the body never leaks a connection."""
import re

import pytest

from npc_kit.tests.test_forge_v25 import build
from npc_kit.tests.test_life import make_life, place_in_workspace, step

SHOUT = re.compile(r"!!|\b[A-Z]{5,}\b")          # no "!!", no shouted words (labels are checked separately)
BANNED = ("bambino", "grazie", "stupid", "lol", "bro", "epic", "awesome sauce", "xd")


def dialogue(H):
    return H.require("ReplicatedStorage/Modules/NpcKit/NpcDialogue/Gianluca")


def talk(H):
    return H.require("ReplicatedStorage/Modules/NpcKit/NpcTalk")


def lines_of(H, result):
    return H.lua_list(result.lines)


# ----- the voice --------------------------------------------------------------------------
def test_dialogue_set_has_the_requested_shape_and_voice(H):
    D = dialogue(H)
    T = talk(H)
    assert len(D.greetings) == 3 and len(D.returning) == 3 and len(D.lore) == 4 and len(D.guidance) == 2
    assert D.name == "Gianluca", "the box shows his real name, not the joke name"
    for text in H.lua_list(T.AllLines(D)):
        assert len(text) <= 120, f"too long for one breath: {text!r}"
        assert not SHOUT.search(text), f"shouting: {text!r}"
        assert not any(re.search(r"\b" + re.escape(b) + r"\b", text.lower()) for b in BANNED), f"wrong voice: {text!r}"
        assert "moon" not in text.lower(), "no moon imagery (D-18)"
    tags = {H.lua_list(D.lore)[i].tag for i in range(4)}
    assert tags == {"war", "clasp"} and D.reactions.war == "warMemory"
    assert "Tung" in H.lua_list(D.lore)[0][1] and "clasp" in H.lua_list(D.lore)[2][1].lower(), "Elder Tung and the clue are referenced naturally"
    assert D.prompt.maxActivationDistance == 10 and D.prompt.holdDuration == pytest.approx(0.3)
    for k in ("offer", "searching", "holding", "done"):
        assert D.quest[k] is not None and D.quest[k].label.endswith("▶"), k
    assert D.quest.offer.action == "start" and D.quest.holding.action == "handover"
    assert D.hooks.persistMet == "GianlucaMet" and D.hooks.veteranChallenge is False


def test_first_meeting_is_a_greeting_plus_the_existing_chim_offer(H):
    D, T = dialogue(H), talk(H)
    mem = T.NewMemory()
    r = T.Next(D, mem, H.table(questState=0, hasChim=False, userId=1234))
    ls = lines_of(H, r)
    assert r.kind == "first" and len(ls) == 3
    assert ls[0] in H.lua_list(D.greetings)
    assert ls[1:] == H.lua_list(D.quest.offer.lines)
    assert r.action == "start" and r.label == D.quest.offer.label and r.reaction is None
    # the same player always gets the same opener; another player may get a different one
    r2 = T.Next(D, T.NewMemory(), H.table(questState=0, hasChim=False, userId=1234))
    assert lines_of(H, r2)[0] == ls[0]
    openers = {lines_of(H, T.Next(D, T.NewMemory(), H.table(questState=0, hasChim=False, userId=u)))[0] for u in range(1, 7)}
    assert len(openers) == 3


def test_relationship_walk_through_the_quest_and_into_rotating_lore(H):
    D, T = dialogue(H), talk(H)
    mem = T.NewMemory()
    ctx = lambda st, chim=False: H.table(questState=st, hasChim=chim, userId=42)
    r = T.Next(D, mem, ctx(0)); T.Remember(mem, r)
    assert mem.met is True and mem.talks == 1
    # searching (state 1): a returning line + the reminder, no quest action
    r = T.Next(D, mem, ctx(1)); T.Remember(mem, r)
    assert r.kind == "searching" and lines_of(H, r)[0] in H.lua_list(D.returning) and lines_of(H, r)[-1] == H.lua_list(D.quest.searching.lines)[0]
    assert r.action is None and r.label == D.quest.searching.label
    # holding the Chim beats every stage
    r = T.Next(D, mem, ctx(1, chim=True)); T.Remember(mem, r)
    assert r.kind == "holding" and r.action == "handover" and r.label == D.quest.holding.label
    # done: thanked exactly once, then he is a lorekeeper
    r = T.Next(D, mem, ctx(3)); T.Remember(mem, r)
    assert r.kind == "done" and lines_of(H, r) == H.lua_list(D.quest.done.lines)
    seen, reactions = [], []
    for i in range(6):
        r = T.Next(D, mem, ctx(3)); T.Remember(mem, r)
        assert r.kind == "return" and r.action is None and lines_of(H, r)[0] in H.lua_list(D.returning)
        seen.append(lines_of(H, r)[1]); reactions.append(r.reaction)
    lore = [H.lua_list(D.lore)[i][1] for i in range(4)]
    guidance = [H.lua_list(D.guidance)[i][1] for i in range(2)]
    # talks 5..10: guidance on every third conversation (6 and 9), lore in between with no repeat until all four are heard
    kinds = ["guidance" if s in guidance else "lore" for s in seen]
    assert kinds == ["lore", "guidance", "lore", "lore", "guidance", "lore"], kinds
    lore_seen = [s for s in seen if s in lore]
    assert len(set(lore_seen[:4])) == 4, "every lore line once before any repeats"
    # war-tagged lore lines carry the body reaction; the clasp line and guidance do not
    for s, rx in zip(seen, reactions):
        if s in lore and "clasp" not in s.lower():
            assert rx == "warMemory", s
        else:
            assert rx is None, s
    # a player who talked in an earlier session (quest state > 0, fresh memory) is not greeted as a
    # stranger: he thanks once per session for the Chim, then talks lore (the persistent flag is a hook)
    fresh = T.NewMemory()
    r = T.Next(D, fresh, ctx(3)); T.Remember(fresh, r)
    assert r.kind == "done"
    assert T.Next(D, fresh, ctx(3)).kind == "return"


def test_server_notes_map_to_popups(H):
    D, T = dialogue(H), talk(H)
    key = T.Note(D, "key")
    assert key.name == "Gianluca" and "key" in H.lua_list(key.lines)[0].lower() and key.label == "TAKE THE KEY ▶"
    found = T.Note(D, "found")
    assert found.name.startswith("✨") and "Gianluca" in H.lua_list(found.lines)[0]
    assert T.Note(D, "hint") is not None and T.Note(D, "nonsense") is None


# ----- the body: approach, prompt, talk, hygiene ------------------------------------------------
def _head_at(H, x, z):
    H.stub.services.Workspace.CurrentCamera.CFrame = H.stub.CFrame.lookAt(H.stub.Vector3.new(x, 5, z), H.stub.Vector3.new(0, 3, 0))
    return H.stub.Vector3.new(x, 4.5, z)


def test_he_notices_an_approaching_player_before_the_prompt_without_snapping(H):
    life = make_life(H)
    life.start(life)
    model, _ = build(H)
    place_in_workspace(H, model, 0, 0)
    entry = life.entries[model]
    head = H.find(model, "Head", False)
    neck = head.FindFirstChild(head, "Neck")
    rest = neck.C0
    # far away (40 studs): no tracking at all
    life.deps.playerHead = lambda: _head_at(H, 0, -40)
    step(H, life, 60)
    assert entry.trackWeight == pytest.approx(0.0, abs=1e-3) and entry.approaching is False
    # inside the Tier 3 track range (24) but no prompt: a third of a turn, eased in over frames
    life.deps.playerHead = lambda: _head_at(H, 12, -14)
    step(H, life, 1)
    first = abs(entry.aimTurn * entry.trackWeight)            # the tracking contribution, apart from the idle glances
    step(H, life, 90)
    settled = abs(entry.aimTurn * entry.trackWeight)
    assert entry.approaching is True and entry.trackWeight == pytest.approx(0.35, abs=0.02)
    assert settled > 8 and first < settled * 0.1, f"the head eases toward the player, it never snaps ({first:.2f} vs {settled:.2f} deg)"
    assert abs(neck.C0.LookVector.X - rest.LookVector.X) > 0.05, "and the neck actually turned"
    # never more than the pack's cap (30 deg) even when the player stands at 80 deg
    life.deps.playerHead = lambda: _head_at(H, 18, -3)
    step(H, life, 120)
    assert abs(neck.C0.LookVector.X - rest.LookVector.X) < 0.55, "turn stays within maxTurn"
    # hysteresis: 25 studs (inside range + 2) keeps him noticing; 27 lets go
    life.deps.playerHead = lambda: _head_at(H, 0, -25)
    step(H, life, 30)
    assert entry.approaching is True
    life.deps.playerHead = lambda: _head_at(H, 0, -27)
    step(H, life, 30)
    assert entry.approaching is False
    step(H, life, 120)
    assert entry.trackWeight == pytest.approx(0.0, abs=1e-3)


def test_prompt_greet_is_a_nod_and_repeat_prompts_do_not_stack_greets(H):
    life = make_life(H)
    life.start(life)
    model, _ = build(H)
    place_in_workspace(H, model, 0, 0)
    entry = life.entries[model]
    life.deps.playerHead = lambda: _head_at(H, 0, -8)
    prompt = H.stub.Instance.new("ProximityPrompt"); prompt.Name = "TalkPrompt"; prompt.Parent = H.find(model, "HumanoidRootPart", False)
    step(H, life, 2)
    for _ in range(3):                                  # the prompt flickering does not restart the greet
        life.onPromptShown(life, prompt)
        life.onPromptHidden(life, prompt)
        life.onPromptShown(life, prompt)
    step(H, life, 5)
    assert entry.gesture is not None and entry.gesture.name == "nodGreet"
    started = entry.gesture.started
    life.onPromptShown(life, prompt)
    step(H, life, 5)
    assert entry.gesture is not None and entry.gesture.started == started, "one greet per approach (cooldown)"
    step(H, life, 60)
    assert entry.trackWeight == pytest.approx(0.7, abs=0.03), "prompt up: most of the turn"
    # talking: full tracking, mouth moves, then walk-away ends it
    life.onPromptTriggered(life, prompt, H.stub.clock)
    life.onDialogVisible(life, True, H.stub.clock)
    step(H, life, 60)
    assert entry.talking is True and entry.trackWeight == pytest.approx(1.0, abs=0.03)
    life.deps.playerHead = lambda: _head_at(H, 0, -60)
    step(H, life, 5)
    assert entry.talking is False, "walking away ends the conversation on the driver too"


def test_adopt_drop_readopt_never_leaks_connections(H):
    life = make_life(H)
    life.start(life)
    model, _ = build(H)
    place_in_workspace(H, model, 0, 0)
    assert life.count == 1 and len(H.lua_list(life.conns[model])) == 2       # NpcFace + NpcReaction
    model.Parent = None                                                      # streamed out / removed
    step(H, life, 2)
    assert life.count == 0 and life.conns[model] is None and life.entries[model] is None
    model.Parent = H.stub.services.Workspace                                 # comes back (respawn-like)
    step(H, life, 2)
    assert life.count == 1 and len(H.lua_list(life.conns[model])) == 2
    # adopting again is a no-op
    life.adopt(life, model)
    assert life.count == 1 and len(H.lua_list(life.conns[model])) == 2


def test_client_drop_in_keeps_the_live_contracts():
    from npc_kit.harness import KIT
    src = (KIT / "StarterPlayer/StarterPlayerScripts/GianlucaClient.client.lua").read_text(encoding="utf-8")
    for needle in ('WaitForChild("StupidGianluca"', 'WaitForChild("TalkPrompt"', '"GianlucaTalk"', '"GianlucaState"', '"DataUpdated"',
                   'talkRemote:FireServer()', 'talkRemote:FireServer(r.action)', 'MerchantDialog.Show(', 'SetAttribute("NpcReaction"', 'WaitForChild("SecretChim"'):
        assert needle in src, needle
    assert "ProximityPrompt\")" not in src.replace('d:IsA("ProximityPrompt")', ""), "never creates a prompt"
    assert "IM SO STUPID" not in src and "bambino" not in src
    assert src.count("prompt.Triggered:Connect") == 1
