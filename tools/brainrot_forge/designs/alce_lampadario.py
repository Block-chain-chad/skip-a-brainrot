"""Alce Lampadario (Legendary): a squat moose whose antlers are an icicle chandelier
twice its body width, candles burning on the crossbar. Front = -Z (muzzle forward)."""
from ..voxel import VoxelModel


def build() -> VoxelModel:
    m = VoxelModel("Alce Lampadario", "Legendary")
    m.role("fur", "#6B4A2B").role("muzzle", "#D9C4A5").role("ice", "#BFE6FF")
    m.role("candle", "#FFF1C9").role("flame", "#FFC24D").role("ink", "#141218")
    m.height_scale = 1.36
    m.fx = [
        {"kit": "glow", "color": [255, 210, 120]},
        {"kit": "flare", "color": [255, 210, 120]},
        {"kit": "aura2", "color": [191, 230, 255], "rate": 6},
    ]
    # barrel body + solid core
    m.stepped_ellipsoid(0, 14, 1, 7, 6, 10, "fur")
    m.box(-6, 6, 9, 18, -8, 10, "fur")
    # four stubby legs with hooves
    for x0, x1 in ((-6, -3), (3, 6)):
        for z0, z1 in ((-7, -4), (5, 8)):
            m.box(x0, x1, 0, 9, z0, z1, "fur")
            m.paint(x0, x1, 0, 1, z0, z1, "ink")
    # head block, long pale muzzle forward, nostrils, ears
    m.box(-5, 5, 15, 25, -14, -8, "fur")
    m.box(-4, 4, 13, 20, -19, -14, "muzzle")
    m.paint(-3, -2, 17, 18, -19, -19, "ink")
    m.paint(2, 3, 17, 18, -19, -19, "ink")
    m.box(-8, -6, 23, 26, -13, -11, "fur")
    m.box(6, 8, 23, 26, -13, -11, "fur")
    # eyes on the head front, above the muzzle
    m.eyes([(-3, 22), (3, 22)], z=-14, size=3, pupil=1)
    # THE CHANDELIER: post, 43-wide crossbar, six hanging icicles (behind the ears), five candles
    m.box(-2, 2, 26, 29, -11, -9, "ice")
    m.box(-21, 21, 29, 30, -11, -9, "ice")
    for x in (-19, -13, -7, 7, 13, 19):
        m.box(x - 1, x + 1, 22, 28, -10, -8, "ice")
        m.box(x, x, 19, 21, -9, -9, "ice")
    for x in (-16, -10, 10, 16):
        m.box(x, x, 31, 34, -10, -10, "candle")
        m.box(x, x, 35, 35, -10, -10, "flame")
    m.box(0, 0, 31, 33, -10, -10, "candle")
    m.box(0, 0, 34, 34, -10, -10, "flame")
    return m
