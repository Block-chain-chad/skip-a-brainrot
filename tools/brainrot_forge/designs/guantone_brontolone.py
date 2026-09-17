"""Guantone Brontolone (Epic): a chunky knitted mitten on two stubby boots, face on
the palm under a heavy unibrow, one giant thumb waved like an arm. Front = -Z."""
from ..voxel import VoxelModel


def build() -> VoxelModel:
    m = VoxelModel("Guantone Brontolone", "Epic")
    m.role("wool", "#C0392B").role("wool_dark", "#96271F").role("cuff", "#F1E4C8").role("ink", "#2F2A33")
    m.height_scale = 1.30
    # palm: 19 wide x 17 tall x 9 deep slab with a domed top (reaches y = 30)
    m.box(-9, 9, 8, 24, -4, 4, "wool")
    m.stepped_ellipsoid(0, 24, 0, 9, 6, 4, "wool")
    # knit stripes: flush recolour, zero geometry cost
    for y in (11, 16, 21):
        m.paint(-9, 9, y, y, -4, 4, "wool_dark")
    # THE THUMB: out to the right and up, rounded tip
    m.box(9, 14, 17, 23, -3, 3, "wool")
    m.box(13, 18, 20, 27, -3, 3, "wool")
    m.stepped_ellipsoid(18, 26, 0, 4, 4, 3, "wool")
    # cuff: a wider band with ribs on the front
    m.box(-11, 11, 3, 8, -6, 6, "cuff")
    for x in range(-11, 12, 2):
        m.box(x, x, 3, 8, -7, -7, "cuff")
    # boots
    m.box(-8, -2, 0, 2, -5, 3, "ink")
    m.box(2, 8, 0, 2, -5, 3, "ink")
    # face on the palm (front layer z = -4): eyes looking down, unibrow one voxel proud, flat mouth
    m.eyes([(-3, 19), (3, 19)], z=-4, size=4, pupil=2, gaze=(0, -1))
    m.box(-6, 6, 22, 23, -5, -5, "ink")
    m.paint(-3, 3, 14, 14, -4, -4, "ink")
    return m
