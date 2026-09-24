"""Tundra Egg: a sky-blue egg under a dripping snow cap, a bold navy zig-zag band of ice round its middle
and white snowflakes. Blue carries it, so it stays blue in warm light instead of washing out to white.
One shell_body group (EggStallIdle's bobbing family)."""
import math

from ...pets import EGG_BODY, PET_PITCH, PetModel, _hash01
from .forest_egg import tri


def build() -> PetModel:
    m = PetModel("Tundra Egg", "Common", world="Tundra", pitch=PET_PITCH, kind="egg", seed=22)
    m.role("ice", "#5EB8EE").role("navy", "#1C4C96").role("snow", "#F2F7FA")
    with m.group(EGG_BODY):
        m.egg(27, 9.2, "ice")

    def theta(x, z):
        return (math.atan2(z, x) + math.pi) / (2 * math.pi)

    def cap(x, y, z):
        drip = 2.6 * _hash01(int(theta(x, z) * 22), 0, 0, 22)
        return y >= 20.5 - drip
    m.recolour("snow", cap, group=EGG_BODY)
    m.recolour("navy", lambda x, y, z: abs(y - (10.0 + 1.8 * tri((theta(x, z) * 7) % 1.0))) <= 1.3,
               group=EGG_BODY)
    skin = m.surface()
    flakes = [(0.07, 4.6), (0.27, 5.2), (0.47, 4.4), (0.67, 5.0), (0.87, 4.8),
              (0.17, 15.2), (0.37, 15.8), (0.57, 15.0), (0.77, 15.6), (0.97, 15.3)]

    def flake(x, y, z):
        if (x, y, z) not in skin:
            return False
        r = math.hypot(x, z)
        for t, ys in flakes:
            du = ((theta(x, z) - t + 0.5) % 1.0 - 0.5) * 2 * math.pi * r
            dv = y - ys
            if (abs(du) <= 0.5 and abs(dv) <= 1.6) or (abs(dv) <= 0.5 and abs(du) <= 1.6):
                return True
        return False
    m.recolour("snow", flake, group=EGG_BODY)
    return m
