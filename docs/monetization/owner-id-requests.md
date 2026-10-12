# Message for BigFrogTerryBruh — everything we need created on Roblox

One round-trip instead of six. Everything below is created on the Roblox website
(Creator Dashboard → the game → Monetization), then just send back the numeric IDs.

---

## Copy-paste message

Hey! The monetization code is all built and safe — it just needs the actual passes
and products created on Roblox, which only you can do as the owner. Could you create
these and send me back the ID numbers? Everything ships disabled until we paste the
IDs in, so nothing goes live by accident.

**Game Passes** (Creator Dashboard → Skip a Brainrot → Monetization → Passes), with
these exact prices:

| # | Name | Price (R$) | Description to paste |
|---|------|-----------|----------------------|
| 1 | 2x Cash | 199 | Double all brainrot income |
| 2 | 2x Luck | 249 | Double your rarity luck on throws |
| 3 | Super Arm | 149 | Skip rocks much farther |
| 4 | Fast Charge | 99 | Charge your throw meter faster |
| 5 | Auto Collect | 299 | Automatically collect brainrot cash |
| 6 | VIP | 499 | 1.5x cash & luck, plus a VIP tag |
| 7 | Season Pass Premium | (your call — suggest 399) | Unlock the premium reward track for every season |

**Developer Products** (same page → Developer Products):

| # | Name | Grants | Price (R$) |
|---|------|--------|-----------|
| 1 | Darrel Pouch | 80 Darrels | (suggest 99) |
| 2 | Darrel Bag | 180 Darrels | (suggest 199) |
| 3 | Darrel Crate | 400 Darrels | (suggest 399) |
| 4 | Darrel Vault | 1000 Darrels | (suggest 799) |
| 5 | Wheel Spin | 1 prize-wheel spin | ~29 |

(Pack prices past the first six are suggestions — set whatever you think is fair,
just tell me the final numbers so the shop UI shows them right.)

**Two non-ID things:**

1. **Roblox group** — the Group Rewards chest in-game needs the game owned by (or
   linked to) a group so it can check membership. If you make a group, send the
   group ID too.
2. That's it — the VIP chest and season premium track unlock automatically once
   passes #6 and #7 exist.

Send back: 7 gamepass IDs + 5 dev product IDs (+ group ID if you make one). I'll
wire them in and we can playtest the shop same day.

---

## Where each ID gets pasted (for us, later)

| ID | File | Spot |
|----|------|------|
| Gamepass IDs 1–6 | `ReplicatedStorage/Modules/GamepassConfig.lua` | `GamepassId = 0` per pass, lines ~29–34 |
| Season premium pass | per season-premium-track.md design (new key in GamepassConfig) | — |
| Darrel pack products | `ServerScriptService/Modules/ProductRegistry.lua:68` | `PACK_IDS = { 0, 0, 0, 0 }` |
| Wheel spin product | per the buy-spins design (wheel plan) | — |
| Group ID | Group Rewards chest config | — |

Everything treats `0` as "not created yet" and stays inert, so IDs can be pasted
one at a time as they arrive.
