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
    python -m npc_kit.build        # forge NPC profile: bakes the SR-Rig body to out/npc_body_standard (Import 3D batch) and renders ../docs/npc/previews
    python -m npc_kit.v2.study     # V2 character art study: low-poly shells on the SR-Rig skeleton -> ../docs/npc/previews/v2 (+ out/npc_v2_study/*.glb)
    python -m npc_kit.v2.study25   # V2.5 study: tiers + old-veteran Gianluca -> ../docs/npc/previews/v25 (+ out/npc_v25_study/*.glb)
    python -m npc_kit.v2.export_kit   # regenerate NpcShells/Gianluca_V25.lua + the Import 3D batch out/npc_v25_kit/Gianluca_V25.glb (41 nodes)
    python -m npc_kit.v2.forge_check  # port fidelity: NpcForge build vs the study render -> ../docs/npc/previews/v25/v25-K-forge-vs-study.png

`npc_kit/forge_npc.py` is the forge's NPC profile (pitch 0.05, sizes read from NpcRigSpec.lua, forge bake()/write_glb unchanged); `npc_kit/preview.py` is the harness-side renderer.

Kit sources and install order: ../game-src/npc-kit/README.md. Specs: ../docs/npc/PHASE2.5-IMPLEMENTATION-PREP.md. Visual prototype: ../docs/npc/STEP0-VISUAL-PROTOTYPE.md. Production pass (dialogue, approach, drop-in client): ../docs/npc/GIANLUCA-PRODUCTION-PASS.md. Art studies: ../docs/npc/V25-CHARACTER-ART-STUDY.md (APPROVED; decisions in ../docs/npc/V25-APPROVAL-RECORD.md), ../docs/npc/V2-CHARACTER-ART-STUDY.md (superseded Gianluca).
