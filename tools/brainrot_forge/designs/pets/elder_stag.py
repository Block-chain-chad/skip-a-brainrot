"""Elder Stag (Mythic, pet_14_elder_stag, gait "stomp"): a red deer in its prime that wears the forest.

Real proportions: long legs that are thick at the top and slender below, a deep chest, a thick neck into
a narrower head, a pale throat, belly and rump, and a big branching rack with moss hanging off it (the
"elder" read at Bag size). Face = -Z. The rig's l side is +X, so the +X half is built with _l groups and
mirrored.
"""
from ...pets import PET_PITCH, PetModel


def build() -> PetModel:
    m = PetModel("Elder Stag", "Mythic", world="Forest", pitch=PET_PITCH, kind="pet",
                 art_key="pet_14_elder_stag", seed=14)
    m.role("fur", "#D0772F").role("fur_dark", "#8F4A1C").role("cream", "#F6E4B8").role("hoof", "#3A2618")
    m.role("antler", "#EFDDAE").role("moss", "#64C83C").role("pupil", "#1E1F2A").role("eye", "#F4F6F8")
    m.flat = {"pupil", "eye"}

    with m.group("body"):
        m.blob(0, 15.5, 0.5, 4.4, 4.3, 10.8, "fur")        # barrel
        m.blob(0, 15.3, -6.5, 4.6, 4.9, 5.0, "fur")        # deep chest
        m.blob(0, 16.2, 7.5, 4.7, 4.5, 5.2, "fur")         # rump
        m.blob(0, 19.3, -5.5, 3.3, 1.7, 4.0, "fur")        # withers

    with m.group("neck"):
        m.capsule((0, 18.5, -9.0), (0, 24.6, -13.2), 3.6, 2.6, "fur", only_empty=True)

    with m.group("head"):
        m.blob(0, 26.4, -15.4, 2.7, 2.6, 3.4, "fur")       # skull
        m.capsule((0, 25.6, -17.8), (0, 25.2, -21.6), 2.1, 1.5, "fur")   # muzzle tapering to the nose
        m.blob(0, 28.2, -14.6, 2.2, 1.3, 2.3, "fur")       # crown between the antler bases

    with m.group("antler_l"):
        m.blob(1.8, 29.5, -14.2, 1.3, 1.1, 1.3, "antler")  # burr
        beam = [((1.8, 29.5, -14.2), 1.15), ((3.6, 32.8, -13.2), 1.05), ((5.8, 35.6, -12.0), 0.95),
                ((6.8, 38.6, -11.0), 0.85)]
        for (a, ra), (b, rb) in zip(beam, beam[1:]):
            m.capsule(a, b, ra, rb, "antler")
        for a, b, ra, rb in (((2.6, 30.8, -14.0), (3.0, 31.6, -17.8), 0.85, 0.7),    # brow tine
                             ((4.6, 34.2, -12.6), (5.0, 36.8, -15.8), 0.8, 0.7),     # bez tine
                             ((5.8, 35.6, -12.0), (8.6, 36.8, -11.4), 0.8, 0.7),     # outer tine
                             ((6.6, 37.6, -11.3), (5.6, 39.2, -12.8), 0.75, 0.65),   # crown fork
                             ((6.8, 38.4, -11.0), (8.8, 39.2, -9.6), 0.75, 0.65)):
            m.capsule(a, b, ra, rb, "antler")
        for c in ((4.5, 33.4, -12.9), (7.2, 36.4, -11.5)):                         # moss on the rack
            m.blob(*c, 1.2, 1.0, 1.2, "moss")
        m.capsule((4.5, 32.6, -12.9), (4.5, 31.2, -12.9), 0.6, 0.5, "moss")         # a hanging strand
        m.capsule((7.4, 35.6, -11.4), (7.6, 34.4, -11.4), 0.55, 0.5, "moss")

    with m.group("ears/ear_l"):
        m.capsule((2.5, 27.6, -13.0), (7.2, 29.4, -12.2), 1.35, 0.95, "fur", only_empty=True)

    with m.group("leg_1l"):                                # front leg
        m.capsule((2.6, 13.0, -7.6), (2.6, 7.4, -7.8), 1.7, 1.25, "fur", only_empty=True)
        m.blob(2.6, 7.0, -7.8, 1.35, 1.1, 1.35, "fur", only_empty=True)            # knee
        m.capsule((2.6, 6.8, -7.8), (2.6, 2.4, -7.7), 1.05, 0.9, "fur", only_empty=True)
        m.box(2, 3, 0, 1, -9, -7, "hoof")

    with m.group("leg_2l"):                                # hind leg: thigh, hock angled back, cannon
        m.blob(2.9, 12.4, 7.0, 1.9, 2.8, 2.6, "fur", only_empty=True)
        m.capsule((2.8, 10.5, 7.8), (2.8, 6.4, 9.4), 1.5, 1.1, "fur", only_empty=True)
        m.blob(2.8, 6.2, 9.5, 1.1, 1.1, 1.1, "fur", only_empty=True)               # hock
        m.capsule((2.8, 6.0, 9.4), (2.8, 2.4, 8.8), 1.0, 0.9, "fur", only_empty=True)
        m.box(2, 3, 0, 1, 7, 9, "hoof")

    with m.group("tail"):
        m.blob(0, 18.0, 12.9, 1.3, 1.3, 1.6, "fur", only_empty=True)
        m.capsule((0, 18.4, 13.0), (0, 19.8, 14.8), 1.2, 0.8, "fur", only_empty=True)

    m.mirror_x()
    m.keep_above(0)

    # markings: pale belly, rump, throat and chin; a darker back, mane and socks
    m.recolour("cream", lambda x, y, z: y <= 12, group="body")
    m.recolour("cream", lambda x, y, z: z >= 11 and y >= 13, group="body")
    m.recolour("fur_dark", lambda x, y, z: y >= 19 and abs(x) <= 1, group="body")
    axis = lambda y: -9.0 - (y - 18.5) * (4.2 / 6.1)      # the neck's centre line, z at height y
    m.recolour("cream", lambda x, y, z: z < axis(y) - 2.2 and y <= 22, group="neck")
    m.recolour("fur_dark", lambda x, y, z: z > axis(y) + 1.8, group="neck")
    m.recolour("hoof", lambda x, y, z: z <= -21, group="head")
    m.recolour("cream", lambda x, y, z: -20.5 <= z <= -19 and y <= 25, group="head")
    for leg in ("leg_1l", "leg_1r", "leg_2l", "leg_2r"):
        m.recolour("fur_dark", lambda x, y, z: 2 <= y <= 3, group=leg)
    m.recolour("cream", lambda x, y, z: y <= 18, group="tail")
    for side in ("ears/ear_l", "ears/ear_r"):
        m.recolour("cream", lambda x, y, z: z <= -14, group=side)

    # eyes: 2 x 2 ink on each side of the skull, glint on the top-front voxel
    with m.group("eyes"):
        for sign in (1, -1):
            for y in (26, 27):
                for z in (-17, -16):
                    c = m.outermost(0, sign, y, z, group="head")
                    m.set(c[0], y, z, "eye" if (y, z) == (27, -17) else "pupil")
    return m
