"""Heartwood Guardian (Secret, gait "stomp"): a small forest guardian, a walking tree.

Stubby root legs, a barrel trunk with wavy bark grooves, branch arms that end in twig fingers and a leaf
tuft, a carved face under a big leafy canopy (the tree silhouette has to carry at Bag size), and the
heart it is named for set into its chest as a raised pink gem. Face = -Z; the +X half is built with _l
groups and mirrored, then the canopy is added after the mirror so it stays lopsided like a real crown.
"""
import math

from ...pets import PET_PITCH, PetModel, _hash01


def build() -> PetModel:
    m = PetModel("Heartwood Guardian", "Secret", world="Forest", pitch=PET_PITCH, kind="pet",
                 art_key="pet_15_heartwood_guardian", seed=15)
    m.role("bark", "#A8662F").role("bark_dark", "#5E3516").role("leaf", "#5CC83A").role("leaf_dark", "#2E9A34")
    m.role("blossom", "#FF7FA8").role("heart", "#FF4F6E").role("pupil", "#1E1F2A").role("eye", "#F4F6F8")
    m.flat = {"pupil", "eye"}

    with m.group("body"):
        m.capsule((0, 8.0, 0), (0, 20.5, 0), 4.9, 4.3, "bark")          # trunk
        m.blob(0, 8.8, 0, 5.6, 2.4, 5.2, "bark")                          # root flare
        m.blob(0, 15.0, -1.0, 4.4, 5.4, 4.3, "bark")                      # chest

    with m.group("head"):
        m.blob(0, 27.0, -0.2, 4.4, 4.3, 4.2, "bark")                      # upper trunk with the face

    with m.group("leg_1l"):
        m.capsule((2.4, 8.5, 0.2), (2.7, 2.2, -0.2), 2.0, 1.7, "bark", only_empty=True)
        m.blob(2.8, 1.0, -0.6, 2.2, 1.2, 2.5, "bark", only_empty=True)   # foot
        m.capsule((2.8, 0.7, -2.0), (3.8, 0.6, -4.0), 0.75, 0.6, "bark", only_empty=True)   # root toes
        m.capsule((3.4, 0.7, 0.8), (5.2, 0.6, 1.8), 0.75, 0.6, "bark", only_empty=True)

    with m.group("arm_l"):
        m.capsule((3.8, 19.5, 0), (7.4, 16.4, -0.8), 1.7, 1.25, "bark", only_empty=True)
        m.capsule((7.4, 16.4, -0.8), (9.6, 19.4, -1.8), 1.25, 0.95, "bark")
        for tip in ((10.4, 21.8, -2.4), (11.8, 19.8, -1.2), (10.2, 20.8, -3.8)):  # twig fingers
            m.capsule((9.6, 19.4, -1.8), tip, 0.65, 0.5, "bark")
        m.blob(10.6, 22.6, -2.4, 2.1, 1.7, 2.1, "leaf")                   # leaf tuft in the hand
        m.blob(11.4, 23.6, -1.6, 1.3, 1.1, 1.3, "leaf_dark")

    # the carved face: brow, eye sockets, a knot of a nose, a small smile
    front = lambda x, y: m.outermost(2, -1, x, y, group="head")
    with m.group("head"):
        for x in range(1, 5):
            for y in range(26, 31):
                c = front(x, y)
                if c:
                    m.cells[c] = "bark_dark"                              # socket
        for x in range(0, 4):
            c = front(x, 30)
            m.set(c[0], 30, c[2] - 1, "bark_dark")                        # brow ridge, proud of the face
        c = front(0, 26)
        m.set(0, 26, c[2] - 1, "bark")                                    # nose knot
        m.set(0, 27, c[2] - 1, "bark")
        for x, y in ((2, 25), (1, 24), (0, 24)):
            m.cells[front(x, y)] = "bark_dark"                            # smile
    with m.group("eyes"):
        for x in (2, 3):
            for y in (27, 28, 29):
                c = front(x, y)
                m.set(c[0], c[1], c[2], "eye" if (x, y) == (2, 29) else "pupil")

    m.mirror_x()
    m.keep_above(0)

    # bark grooves: seven bold vertical lines round the trunk with a slow wave in them
    def groove(x, y, z):
        if x * x + z * z < 9:
            return False
        a = (math.atan2(z, x) + math.pi) / (2 * math.pi) * 7 + 0.07 * math.sin(y * 0.5)
        return (a % 1.0) < 0.3
    m.recolour("bark_dark", groove, group="body")
    m.recolour("bark_dark", lambda x, y, z: y <= 1, group="leg_1l")
    m.recolour("bark_dark", lambda x, y, z: y <= 1, group="leg_1r")

    # the heart: a raised pink gem on the chest, ringed in dark bark
    heart = {2: (-2, -1, 1, 2), 1: range(-3, 4), 0: range(-3, 4), -1: range(-2, 3), -2: range(-1, 2), -3: (0,)}
    pixels = {(x, 16 + dy) for dy, xs in heart.items() for x in xs}
    rim = {(x + i, y + j) for (x, y) in pixels for i in (-1, 0, 1) for j in (-1, 0, 1)} - pixels
    for (x, y) in rim:
        c = m.outermost(2, -1, x, y, group="body")
        if c:
            m.cells[c] = "bark_dark"
    with m.group("body"):
        for (x, y) in pixels:
            c = m.outermost(2, -1, x, y, group="body")
            m.cells[c] = "heart"
            m.set(x, y, c[2] - 1, "heart")

    # the canopy, added after the mirror so it stays lopsided; it never eats the face
    with m.group("cap"):
        for c, r in (((0, 34.0, 0.5), (10.5, 5.6, 9.0)), ((5.5, 35.8, -2.5), (4.8, 3.8, 4.8)),
                     ((-5.5, 35.4, 1.5), (4.8, 3.8, 4.8)), ((0, 37.0, -2.5), (5.2, 2.6, 4.6)),
                     ((1.5, 36.5, 5.0), (5.5, 3.0, 4.2)), ((8.8, 30.8, 0.5), (2.6, 2.6, 3.2)),
                     ((-8.6, 31.2, -1.0), (2.6, 2.6, 3.2)), ((3.5, 30.5, 7.5), (3.0, 2.2, 2.4))):
            m.blob(*c, *r, "leaf", only_empty=True)
    m.remove([c for c, g in m.groups.items() if g == "cap" and c[1] <= 31 and abs(c[0]) <= 4 and c[2] <= -1])
    m.recolour("leaf_dark", lambda x, y, z: _hash01(x // 3, y // 3, z // 3, 7) > 0.62, group="cap")
    skin = m.surface()
    m.recolour("blossom", lambda x, y, z: (x, y, z) in skin and y >= 32 and _hash01(x, y, z, 99) < 0.035,
               group="cap")
    return m
