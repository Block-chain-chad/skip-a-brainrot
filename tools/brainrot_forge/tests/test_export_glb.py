import json
import struct

from brainrot_forge.voxel import VoxelModel
from brainrot_forge.bake import bake
from brainrot_forge import export_glb as G


def cube(name="T", role="body", color="#FF0000"):
    m = VoxelModel(name, "Epic").role(role, color)
    m.set(0, 0, 0, role)
    return m


def batch_of(*models):
    return [(m, bake(m)) for m in models]


def test_part_name_convention():
    assert G.part_name("Nonno Ghiacciaio", "beard") == "Nonno Ghiacciaio__beard"


def test_srgb_to_linear():
    assert G.srgb_to_linear("#FFFFFF") == (1.0, 1.0, 1.0)
    assert G.srgb_to_linear("#000000") == (0.0, 0.0, 0.0)
    r, g, b = G.srgb_to_linear("#808080")
    assert abs(r - 0.2158605) < 1e-5 and r == g == b


def test_glb_container_is_well_formed(tmp_path):
    path = tmp_path / "one.glb"
    G.write_glb(path, batch_of(cube()))
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67 and version == 2 and length == len(data)
    json_len, json_type = struct.unpack_from("<II", data, 12)
    assert json_type == 0x4E4F534A and json_len % 4 == 0
    doc = json.loads(data[20:20 + json_len])
    assert doc["asset"]["version"] == "2.0"
    bin_len, bin_type = struct.unpack_from("<II", data, 20 + json_len)
    assert bin_type == 0x004E4942 and bin_len % 4 == 0
    assert doc["nodes"][0]["name"] == "T__body" and doc["meshes"][0]["name"] == "T__body"
    assert doc["materials"][0]["name"] == "T__body"


def test_round_trip_geometry_and_colour(tmp_path):
    path = tmp_path / "one.glb"
    b = batch_of(cube())
    G.write_glb(path, b, roblox_forward=False)
    back = G.read_glb(path)
    node = back["T__body"]
    src = b[0][1]["body"]
    assert node["positions"] == [tuple(round(c, 6) for c in p) for p in src.positions]
    assert node["normals"] == src.normals
    assert node["uvs"] == src.uvs
    assert node["indices"] == src.indices
    assert node["color"] == (1.0, 0.0, 0.0)


def test_batch_has_one_node_per_role_in_order(tmp_path):
    a = cube("Alpha")
    b = VoxelModel("Beta", "Secret").role("body", "#0000FF").role("eye", "#FFFFFF")
    b.set(0, 0, 0, "body")
    b.set(1, 0, 0, "eye")
    path = tmp_path / "two.glb"
    G.write_glb(path, batch_of(a, b))
    assert list(G.read_glb(path)) == ["Alpha__body", "Beta__body", "Beta__eye"]


def test_flip_z_mirrors_and_keeps_ccw(tmp_path):
    path = tmp_path / "flip.glb"
    G.write_glb(path, batch_of(cube()), flip_z=True, roblox_forward=False)
    node = G.read_glb(path)["T__body"]
    assert min(p[2] for p in node["positions"]) == -0.2 and max(p[2] for p in node["positions"]) == 0.0
    for i in range(0, len(node["indices"]), 3):
        a, b, c = (node["positions"][node["indices"][i + k]] for k in range(3))
        n = node["normals"][node["indices"][i]]
        ab = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        ac = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        cr = (ab[1] * ac[2] - ab[2] * ac[1], ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0])
        assert cr[0] * n[0] + cr[1] * n[1] + cr[2] * n[2] > 0


def test_manifest_shape():
    m = VoxelModel("Beta", "Secret").role("body", "#0000FF").role("eye", "#FFFFFF")
    m.box(-2, 2, 0, 29, -2, 2, "body")
    m.eyes([(0, 20)], z=-2, size=3, pupil=1)
    m.height_scale = 1.46
    m.motion = "shiver"
    m.fx = [{"kit": "aura1", "color": [200, 232, 245], "rate": 8}]
    man = G.build_manifest(batch_of(m))
    entry = man["models"]["Beta"]
    assert man["version"] == 1 and man["pitch"] == 0.2
    assert entry["rarity"] == "Secret" and entry["world"] == "Tundra"
    assert entry["roles"] == {"body": "#0000FF", "eye": "#FFFFFF", "pupil": "#141218"}
    assert entry["parts"] == ["Beta__body", "Beta__eye", "Beta__pupil"]
    assert entry["heightScale"] == 1.46 and entry["widthScale"] == 1.0 and entry["motion"] == "shiver"
    assert entry["material"] == "Plastic" and entry["fx"][0]["kit"] == "aura1"
    assert entry["bbox"] == [1.0, 6.0, 1.0] and entry["totalTriangles"] == sum(entry["triangles"].values())
    json.dumps(man)  # must be serialisable


def test_roblox_forward_pre_turns_180_about_y_and_keeps_ccw(tmp_path):
    """Default export negates x and z (a rotation) so Roblox's importer turn lands the front at -Z."""
    path = tmp_path / "turned.glb"
    m = VoxelModel("T", "Epic").role("body", "#FF0000")
    m.set(1, 0, 0, "body")          # off-centre so x is observable
    G.write_glb(path, batch_of(m))  # roblox_forward defaults to True
    node = G.read_glb(path)["T__body"]
    xs = [p[0] for p in node["positions"]]
    zs = [p[2] for p in node["positions"]]
    assert min(xs) == -0.4 and max(xs) == -0.2        # x negated
    assert min(zs) == -0.2 and max(zs) == 0.0         # z negated
    assert (0.0, 0.0, 1.0) in node["normals"] and (0.0, 0.0, -1.0) in node["normals"]
    for i in range(0, len(node["indices"]), 3):
        a, b, c = (node["positions"][node["indices"][i + k]] for k in range(3))
        n = node["normals"][node["indices"][i]]
        ab = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        ac = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        cr = (ab[1] * ac[2] - ab[2] * ac[1], ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0])
        assert cr[0] * n[0] + cr[1] * n[1] + cr[2] * n[2] > 0


def test_manifest_records_roblox_forward():
    m = cube()
    assert G.build_manifest(batch_of(m))["robloxForward"] is True
    assert G.build_manifest(batch_of(m), roblox_forward=False)["robloxForward"] is False
