from brainrot_forge.voxel import VoxelModel
from brainrot_forge.bake import bake
from brainrot_forge import render as R


def sample(height_scale=1.0):
    m = VoxelModel("Sample", "Epic").role("body", "#C0392B")
    m.box(-4, 4, 0, 29, -3, 3, "body")
    m.eyes([(-2, 22), (2, 22)], z=-3, size=3, pupil=1)
    m.height_scale = height_scale
    return m, bake(m)


def test_render_model_size_and_content():
    m, meshes = sample()
    img = R.render_model(m, meshes, size=256)
    assert img.size == (256, 256) and img.mode == "RGB"
    pixels = list(img.get_flattened_data())
    assert pixels.count(R.SKY) < len(pixels) * 0.9          # something was drawn
    assert any(abs(p[0] - p[1]) > 60 for p in pixels)        # the red body is visible


def test_front_quarter_shows_the_eyes():
    m, meshes = sample()
    img = R.render_model(m, meshes, size=256)
    # shaded white reads as a bright NEUTRAL grey (~170-185); the sky is tinted blue, the body red
    assert any(min(p) > 140 and max(p) - min(p) < 12 for p in img.get_flattened_data())


def test_plot_tile_height_follows_height_scale():
    m1, k1 = sample(1.0)
    m2, k2 = sample(1.5)
    t1, t2 = R.render_plot_tile(m1, k1), R.render_plot_tile(m2, k2)
    assert t1.size == (200, 200) == t2.size
    h1 = R._drawn_height(t1)
    h2 = R._drawn_height(t2)
    assert abs(h1 - 116) <= 3 and abs(h2 - 174) <= 4


def test_contact_sheet_writes_files(tmp_path):
    m, meshes = sample()
    paths = R.contact_sheet([(m, meshes)], tmp_path)
    names = sorted(p.name for p in paths)
    assert names == ["contact_sheet.png", "sample.png"]
    assert all(p.stat().st_size > 0 for p in paths)
