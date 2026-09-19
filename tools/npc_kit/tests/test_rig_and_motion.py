"""SR-Rig arithmetic and the semantic-axis -> CFrame mapping, checked with real
rotation math in the stub (doc C1 sign conventions)."""
import math

import pytest


def approx(a, b, tol=1e-6):
    return abs(a - b) <= tol


def test_joint_frames_match_the_manifest(H):
    Rig = H.require("ReplicatedStorage/Modules/NpcKit/NpcRigSpec")
    c0, c1, j = Rig.JointFrames("standard", "Neck")
    assert approx(c0.Position.Y, 0.60) and approx(c1.Position.Y, -0.45)
    c0, c1, j = Rig.JointFrames("standard", "RightShoulder")
    assert approx(c0.Position.X, 1.45) and approx(c0.Position.Y, 0.55) and approx(c1.Position.Y, 0.40)
    c0, c1, j = Rig.JointFrames("standard", "LeftShoulder")
    assert approx(c0.Position.X, -1.45)
    c0, c1, j = Rig.JointFrames("standard", "RightAnkle")
    assert approx(c1.Position.Z, 0.15) and approx(c1.Position.Y, 0.30)
    assert approx(Rig.Height("standard"), 5.225)
    assert approx(Rig.Root.HeadOffset, 1.45)


def test_body_types_have_full_skeleton(H):
    Rig = H.require("ReplicatedStorage/Modules/NpcKit/NpcRigSpec")
    for bt in ("standard", "stout", "slight"):
        b = Rig.BodyTypes[bt]
        parts = H.lua_list(b.parts)
        joints = H.lua_list(b.joints)
        assert len(parts) == 15 and len(joints) == 15, bt
        names = {p.name for p in parts}
        assert {"Head", "UpperTorso", "LowerTorso", "LeftHand", "RightFoot"} <= names
        left = [p for p in parts if p.name.startswith("Left")]
        assert all(p.offset.X < 0 for p in left)
    stout = Rig.PartByName("stout", "UpperTorso")
    assert stout.size.X > Rig.PartByName("standard", "UpperTorso").size.X


def test_limb_swing_moves_hand_forward(H):
    Motion = H.require("ReplicatedStorage/Modules/NpcKit/NpcMotion")
    down = H.stub.Vector3.new(0, -1, 0)
    off = Motion.offsetFor("limb", 1, H.table(swing=90))
    v = off.VectorToWorldSpace(off, down)
    assert v.Z < -0.99, f"swing +90 should point the limb forward (-Z), got {v}"


def test_spread_is_outward_on_both_sides(H):
    Motion = H.require("ReplicatedStorage/Modules/NpcKit/NpcMotion")
    down = H.stub.Vector3.new(0, -1, 0)
    right = Motion.offsetFor("limb", 1, H.table(spread=30)).VectorToWorldSpace(Motion.offsetFor("limb", 1, H.table(spread=30)), down)
    left = Motion.offsetFor("limb", -1, H.table(spread=30)).VectorToWorldSpace(Motion.offsetFor("limb", -1, H.table(spread=30)), down)
    assert right.X > 0.4 and left.X < -0.4


def test_spine_turn_right_and_bend_forward(H):
    Motion = H.require("ReplicatedStorage/Modules/NpcKit/NpcMotion")
    turn = Motion.offsetFor("spine", 1, H.table(turn=45))
    assert turn.LookVector.X > 0.5, "turn + should face the character's right (+X)"
    bend = Motion.offsetFor("spine", 1, H.table(bend=30))
    assert bend.LookVector.Y < -0.4, "bend + should nod the face down"
    tilt = Motion.offsetFor("spine", 1, H.table(tilt=30))
    assert tilt.UpVector.X > 0.4, "tilt + should lean the top toward the right shoulder"


def test_brow_outer_up_mirrors_per_side(H):
    Motion = H.require("ReplicatedStorage/Modules/NpcKit/NpcMotion")
    r = Motion.offsetFor("face", 1, H.table(browOuterUp=20))
    l = Motion.offsetFor("face", -1, H.table(browOuterUp=20))
    outer_r = r.VectorToWorldSpace(r, H.stub.Vector3.new(1, 0, 0))    # right brow's outer end is +X
    outer_l = l.VectorToWorldSpace(l, H.stub.Vector3.new(-1, 0, 0))   # left brow's outer end is -X
    assert outer_r.Y > 0.3 and outer_l.Y > 0.3


def test_ring_bell_gesture_keys(H):
    MC = H.require("ReplicatedStorage/Modules/NpcKit/NpcMotionConfig")
    Motion = H.require("ReplicatedStorage/Modules/NpcKit/NpcMotion")
    g = MC.Gestures.ringBell
    vals, done = Motion.evalGesture(g, 0.45)
    assert approx(vals.RightShoulder.swing, 75) and approx(vals.RightShoulder.spread, 8)
    vals, done = Motion.evalGesture(g, 1.45)
    assert approx(vals.Neck.turn, -38, 1e-6) and not done
    vals, done = Motion.evalGesture(g, 2.4)
    assert done and (vals.RightShoulder is None or approx(vals.RightShoulder.swing or 0, 0))
    vals, _ = Motion.evalGesture(g, 0.225)   # halfway through the lift, smoothstep gives exactly half
    assert approx(vals.RightShoulder.swing, 37.5, 1e-6)


def test_snap_and_hash_are_bounded_and_deterministic(H):
    Motion = H.require("ReplicatedStorage/Modules/NpcKit/NpcMotion")
    vals = [Motion.snapValue(t / 10.0, 6.5, 0.18, 22, 0.3) for t in range(0, 400)]
    assert max(abs(v) for v in vals) <= 22 + 1e-9
    p1 = Motion.phaseFor("StupidGianluca", H.stub.Vector3.new(12.3, 6, -40.2))
    p2 = Motion.phaseFor("StupidGianluca", H.stub.Vector3.new(12.3, 6, -40.2))
    p3 = Motion.phaseFor("StupidGianluca", H.stub.Vector3.new(80.0, 6, -40.2))
    assert p1 == p2 and p1 != p3 and 0 <= p1 <= 6.29
    d1 = Motion.draw(1234, 3, 14, 26)
    assert 14 <= d1 <= 26 and d1 == Motion.draw(1234, 3, 14, 26)


def test_aim_angles(H):
    Motion = H.require("ReplicatedStorage/Modules/NpcKit/NpcMotion")
    root = H.stub.CFrame.new(0, 3, 0)                      # facing -Z
    turn, bend = Motion.aimAngles(root, H.stub.Vector3.new(0, 4.5, 0), H.stub.Vector3.new(5, 4.5, -5))
    assert approx(turn, 45, 1e-6) and approx(bend, 0, 1e-6)
    turn, bend = Motion.aimAngles(root, H.stub.Vector3.new(0, 4.5, 0), H.stub.Vector3.new(0, 1.5, -3))
    assert turn == 0 and bend == pytest.approx(45, abs=1e-6)
