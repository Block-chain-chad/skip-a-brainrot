"""Registry of forge designs. Keys are the EXACT roster names (Model.Name == config Name)."""
from . import alce_lampadario, guantone_brontolone, nonno_ghiacciaio

DESIGNS = {
    "Guantone Brontolone": guantone_brontolone.build,
    "Alce Lampadario": alce_lampadario.build,
    "Nonno Ghiacciaio": nonno_ghiacciaio.build,
}
PILOT = ["Guantone Brontolone", "Alce Lampadario", "Nonno Ghiacciaio"]
