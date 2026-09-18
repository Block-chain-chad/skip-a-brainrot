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


def test_vertex_colours_darken_and_compare_sheet(tmp_path):
    m, meshes = sample()
    dark = {k: v for k, v in meshes.items()}
    from brainrot_forge.bake import Mesh
    body = meshes["body"]
    darker = Mesh("body", list(body.positions), list(body.normals), list(body.uvs), list(body.indices), [(0.5, 0.5, 0.5)] * len(body.positions))
    dark["body"] = darker
    bright = list(R.render_model(m, meshes, size=128).get_flattened_data())
    dim = list(R.render_model(m, dark, size=128).get_flattened_data())
    body = [i for i, p in enumerate(bright) if p != R.SKY]          # compare drawn pixels only, not the sky
    assert body and sum(dim[i][0] for i in body) < sum(bright[i][0] for i in body) * 0.7
    paths = R.compare_sheet([(m, meshes, m, dark)], tmp_path, "batch1", per_sheet=6)
    assert [p.name for p in paths] == ["batch1_sheet1.png"] and paths[0].stat().st_size > 0
