# tools/

`brainrot_forge/` — the Brainrot Forge. Run everything from this folder:

    cd tools
    python -m pytest brainrot_forge/tests -q
    python -m brainrot_forge build pilot      # -> out/pilot/{pilot_batch.glb, manifest.json, previews/}

Design rules and budgets: ../docs/brainrot-build-standard.md. Pipeline: ../docs/superpowers/specs/2026-09-17-brainrot-forge-pilot-design.md.

`npc_kit/` — NPC-01 kit lint + harness (runs the real Luau modules from `../game-src/npc-kit` under Lua 5.1 with a Roblox API stub; no Studio):

    cd tools
    python -m pip install lupa pytest
    python -m npc_kit.lint
    python -m pytest npc_kit/tests -q

Kit sources and install order: ../game-src/npc-kit/README.md. Specs: ../docs/npc/PHASE2.5-IMPLEMENTATION-PREP.md.
