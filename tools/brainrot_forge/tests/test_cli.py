import json
from brainrot_forge.__main__ import main


def test_build_pilot_writes_batch(tmp_path, capsys):
    assert main(["build", "pilot", "--out", str(tmp_path)]) == 0
    assert (tmp_path / "pilot_batch.glb").stat().st_size > 1000
    man = json.loads((tmp_path / "manifest.json").read_text())
    assert set(man["models"]) == {"Guantone Brontolone", "Alce Lampadario", "Nonno Ghiacciaio"}
    assert (tmp_path / "previews" / "contact_sheet.png").exists()
    out = capsys.readouterr().out
    assert "Nonno Ghiacciaio" in out and "triangles" in out


def test_list(capsys):
    assert main(["list"]) == 0
    assert "Alce Lampadario" in capsys.readouterr().out
