"""Pet-mode designs (Item 6): three pets and two eggs at 0.08 studs per voxel. Keys are the PetConfig
display names; BEFORE maps each to its Item 5 Part-built prototype in ServerStorage._PETS_Prototypes."""
from . import elder_stag, forest_egg, heartwood_guardian, sap_snail, tundra_egg

PET_DESIGNS = {
    "Elder Stag": elder_stag.build,
    "Heartwood Guardian": heartwood_guardian.build,
    "Sap Snail": sap_snail.build,
    "Forest Egg": forest_egg.build,
    "Tundra Egg": tundra_egg.build,
}
PETS = list(PET_DESIGNS)
BEFORE = {
    "Elder Stag": "vox_ElderStag",
    "Heartwood Guardian": "vox_Heartwood",
    "Sap Snail": "vox_SapSnail",
    "Forest Egg": "vox_ForestEgg",
    "Tundra Egg": "vox_TundraEgg",
}
