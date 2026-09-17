"""Nonno Ghiacciaio (Secret): a mountain-shaped grandfather whose snow beard is the whole
lower body, tiny boots below, a wool cap with one gold medal on top. Slow shiver. Front = -Z."""
from ..voxel import VoxelModel


def build() -> VoxelModel:
    m = VoxelModel("Nonno Ghiacciaio", "Secret")
    m.role("ice", "#8FB8D6").role("ice_dark", "#5E86A8").role("snow", "#F4F8FB")
    m.role("wool", "#B23A3A").role("gold", "#D4AF37").role("ink", "#2A2530")
    m.height_scale = 1.46
    m.motion = "shiver"
    m.fx = [
        {"kit": "aura1", "color": [200, 232, 245], "rate": 8},
        {"kit": "snow", "color": [255, 255, 255], "rate": 6},
        {"kit": "glare", "color": [200, 232, 245], "size": 0.5},
    ]
    # mountain base: terraces y 12..18, half-width 14 -> 11
    for i, y in enumerate(range(12, 19)):
        w = 14 - i // 2
        m.box(-w, w, y, y, -(w - 3), w - 3, "ice")
    # head: a flat-fronted block so the face sits on one layer (z = -8)
    m.box(-10, 10, 19, 30, -8, 8, "ice")
    # peak: terraces y 31..37, half-width 8 -> 2
    for i, y in enumerate(range(31, 38)):
        w = 8 - i
        m.box(-w, w, y, y, -max(2, w - 2), max(2, w - 2), "ice")
    # crevasses: recolour only (peak front/back, head sides)
    for x in (-3, 2):
        m.paint(x, x, 31, 36, -20, 20, "ice_dark")
    m.paint(-10, -10, 20, 28, -2, 0, "ice_dark")
    m.paint(10, 10, 20, 28, -2, 0, "ice_dark")
    # THE BEARD: the whole lower body, in front of and around the base
    m.stepped_ellipsoid(0, 10, -3, 15, 8, 11, "snow")
    m.keep_above(3)
    # boots poking out under the beard
    m.box(-5, -2, 0, 2, -5, -1, "ink")
    m.box(2, 5, 0, 2, -5, -1, "ink")
    # face: eyes, bushy proud eyebrows, proud nose, moustache over the beard line
    m.eyes([(-4, 25), (4, 25)], z=-8, size=3, pupil=1)
    m.box(-7, -2, 27, 28, -9, -9, "snow")
    m.box(2, 7, 27, 28, -9, -9, "snow")
    m.box(-1, 1, 22, 23, -9, -9, "ice_dark")
    m.box(-5, 5, 19, 20, -9, -9, "snow")
    # wool cap on the peak, pompom, one gold medal
    m.box(-4, 4, 36, 40, -3, 3, "wool")
    m.box(0, 0, 41, 42, 0, 0, "snow")
    m.box(-1, 1, 38, 39, -4, -4, "gold")
    return m
