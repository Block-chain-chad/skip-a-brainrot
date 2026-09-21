# Egg hatch overhaul — review pack (2026-09-21, checkpoint: 1x + 3x refined)

Owner direction mid-round: Pet-Simulator-quality FEEL (fast, physical, squash/stretch,
rhythmic wobble, short anticipation, sharp pop, immediate reward readability, clean
multi-hatch), an original Skip Rocks interpretation, no copied assets, and the egg — not
effects — carrying the anticipation. Work stopped after 1x and 3x, as asked.

## Videos (real time, recorded at 0.25x and re-timed)

| file | what |
|---|---|
| `hatch_review_1x_3x.mp4` | both clips back to back |
| `hatch_1x_epic.mp4` | x1 Bramble Egg → Bramble Bear (Epic): enter 0.00 → pop 1.30 → reward 1.32 → name/rarity 1.62 → auto-exit 2.47 |
| `hatch_3x_legendary.mp4` | x3 Bramble Eggs → Sap Snail (Rare), Bramble Bear (Epic), Mossback (Legendary): eggs enter together, wobble together with 0.04 s offsets, the Legendary pops last (+0.06 s), plates 0.08 s apart |

Recorded with `tools/studio-bridge/burst-capture.ps1` (PrintWindow, ~28 fps) while the run
played at speed 0.25, then `assemble-video.py` re-timed the frames to real time (so
authored motion is captured at ~110 fps effective). The HUD is the live game HUD; the
grade/DoF/character fade and restore are the real ones.

## Beat sheets

`beats-1x-epic.jpg` and `beats-3x-legendary.jpg`: frames nearest each authored beat
(times are ±0.03 s, t = 0 is the grade ramp).

## The x1 timeline (`EggHatch/Config.lua` BEATS)

| t | beat |
|---|---|
| 0.00–0.16 | egg enters the foreground: scale 0.18→1 with overshoot, rising, from a stud further back |
| 0.16–0.34 | settle: squash to 0.80 tall (wider), stretch back 1.07 |
| 0.32–0.92 | leans about the base: −21°, +21°, then faster −19°, +17°, −14°, +12°, upright; each lean stretches the egg ~7 % |
| 0.94–1.07 | squash: compression to 0.74 tall (the wind-up); first crack lines |
| 1.07–1.29 | rapid shake (16 Hz lean, 21 Hz roll, 30 Hz jitter) releasing the compression into a 1.18 stretch; cracks go neon |
| 1.30 | POP: one 45 ms scale punch, shell gone, six small shards for 0.36 s, a small spark puff, `eggSplit` + cartoon bloop |
| 1.32–1.55 | reward emerges: scale 0.10→1 with the tier's overshoot (1.10 Common … 1.36 God), rise, landing squash |
| 1.62 | name pops, rarity chip 0.08 s later (slams on Epic+) |
| +hold | Common–Epic 0.75–0.85 s, Legendary 1.1, Mythic 1.3, Secret 1.6, God 2.0; tap after the plate ends early |
| exit | reward + plates scale away over 0.18 s, grade/DoF/character/HUD back over 0.24 s |

Rarity changes nothing before the pop. Legendary+ enhance the reveal only: bigger overshoot
and a second bounce, a thin tier-coloured ring, a few sparkles orbiting the reward, a small
confetti burst, a stronger sting with a hit layer, a small camera kick/FOV punch, a longer hold.
