"""Sap Snail (Legendary, pet_07_sapsnail, gait "glide"): a garden snail carrying a shell full of sap.

A long lime foot that tapers to a pointed tail, a raised head with two eye stalks, and a big round orange
shell with a bold dark spiral on both faces and honey dripping down its sides. The shell rides the body
(the rig has no joint for it). Face = -Z; the stalks are built on +X as antenna_l and mirrored.
"""
import math

from ...pets import PET_PITCH, PetModel


def build() -> PetModel:
    m = PetModel("Sap Snail", "Legendary", world="Forest", pitch=PET_PITCH, kind="pet",
                 art_key="pet_07_sapsnail", seed=7)
    m.role("body", "#A8D84E").role("shell", "#F08A24").role("spiral", "#6B3310").role("sap", "#FFC43D")
    m.role("pupil", "#1E1F2A").role("eye", "#F4F6F8")
    m.flat = {"pupil", "eye"}

    with m.group("body"):
        m.blob(0, 2.2, -2.0, 4.6, 2.7, 13.0, "body")                      # the foot
        m.capsule((0, 2.8, -11.0), (0, 3.0, -15.0), 3.4, 3.0, "body")
    with m.group("tail"):
        m.capsule((0, 2.0, 9.0), (0, 1.0, 19.0), 2.9, 0.9, "body", only_empty=True)
    with m.group("head"):
        m.capsule((0, 3.6, -13.0), (0, 9.6, -16.4), 3.1, 2.8, "body")
        m.blob(0, 10.6, -16.8, 2.9, 2.6, 2.8, "body")
        m.capsule((1.2, 8.6, -18.8), (1.9, 7.8, -19.9), 0.6, 0.55, "body")   # short feelers
    with m.group("antenna_l"):
        m.capsule((1.2, 12.0, -16.6), (2.8, 17.6, -18.2), 0.85, 0.7, "body")
    with m.group("eyes"):
        m.blob(3.0, 18.4, -18.5, 1.15, 1.15, 1.15, "pupil")
    bulb = [c for c, g in m.groups.items() if g == "eyes"]
    top = max(c[1] for c in bulb)
    m.cells[min((c for c in bulb if c[1] == top), key=lambda c: c[2])] = "eye"   # glint, top-front
    m.mirror_x()
    m.keep_above(0)

    with m.group("shell"):
        m.blob(0, 14.2, 3.4, 6.2, 10.6, 10.8, "shell")

    def on_spiral(x, y, z):
        dz, dy = z - 3.4, y - 14.2
        r = math.hypot(dz, dy)
        if r < 1.6:
            return True
        t = (math.atan2(dy, dz) + math.pi) / (2 * math.pi)
        return ((r / 3.6 - t) % 1.0) < 1.25 / 3.6
    m.recolour("spiral", on_spiral, group="shell")
    m.recolour("sap", lambda x, y, z: y >= 23 and abs(z - 3.4) <= 3.2, group="shell")
    for sign in (1, -1):
        for z0, y_top, length in ((0, 22, 4), (5, 23, 6), (9, 21, 3)):
            for y in range(y_top - length, y_top + 1):
                c = m.outermost(0, sign, y, z0, group="shell")
                if c:
                    m.cells[c] = "sap"
    return m
