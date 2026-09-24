"""Forest Egg: a bright moss-green egg with two bold zig-zag bark bands, lime spots between them, a dark
moss cap and a sprout on top. One shell_body group (EggStallIdle's bobbing family)."""
import math

from ...pets import EGG_BODY, PET_PITCH, PetModel


def tri(u: float) -> float:
    """Triangle wave in [-1, 1] for u in [0, 1)."""
    return 1.0 - 4.0 * abs(u - 0.5)


def build() -> PetModel:
    m = PetModel("Forest Egg", "Common", world="Forest", pitch=PET_PITCH, kind="egg", seed=21)
    m.role("moss", "#4FBF3A").role("bark", "#5B3417").role("lime", "#C8F05A").role("cap", "#2E8F2E")
    m.role("sprout", "#7AD94A")
    with m.group(EGG_BODY):
        m.egg(27, 9.2, "moss")
        m.capsule((0, 26.0, 0), (0.2, 28.8, 0.3), 0.7, 0.6, "sprout")
        m.blob(1.9, 29.2, 0.2, 1.9, 0.75, 1.1, "sprout")
        m.blob(-1.7, 28.7, -0.3, 1.7, 0.75, 1.0, "sprout")

    def theta(x, z):
        return (math.atan2(z, x) + math.pi) / (2 * math.pi)

    def band(x, y, z):
        for yb in (7.5, 15.5):
            if abs(y - (yb + 1.6 * tri((theta(x, z) * 8) % 1.0))) <= 1.2:
                return True
        return False

    skin = m.surface()
    m.recolour("cap", lambda x, y, z: y >= 22 and y <= 26, group=EGG_BODY)
    m.recolour("bark", band, group=EGG_BODY)
    spots = [(0.05, 11.6), (0.22, 12.0), (0.38, 11.2), (0.55, 11.9), (0.71, 11.3), (0.88, 12.1),
             (0.12, 19.4), (0.30, 19.0), (0.47, 19.6), (0.64, 19.1), (0.81, 19.5), (0.97, 19.0)]

    def spot(x, y, z):
        if (x, y, z) not in skin:
            return False
        r = math.hypot(x, z)
        for t, ys in spots:
            dt = (theta(x, z) - t + 0.5) % 1.0 - 0.5
            if (dt * 2 * math.pi * r) ** 2 + (y - ys) ** 2 <= 1.7 ** 2:
                return True
        return False
    m.recolour("lime", spot, group=EGG_BODY)
    return m
