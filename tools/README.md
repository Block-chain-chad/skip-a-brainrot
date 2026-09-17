# tools/

`brainrot_forge/` — the Brainrot Forge. Run everything from this folder:

    cd tools
    python -m pytest brainrot_forge/tests -q
    python -m brainrot_forge build pilot      # -> out/pilot/{pilot_batch.glb, manifest.json, previews/}

Design rules and budgets: ../docs/brainrot-build-standard.md. Pipeline: ../docs/superpowers/specs/2026-09-17-brainrot-forge-pilot-design.md.
