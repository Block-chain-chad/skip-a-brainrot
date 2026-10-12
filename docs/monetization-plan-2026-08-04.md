# Skip a Brainrot — monetization plan (revised after reading the repo)

Replaces the generic plan I sent earlier. Most of what I proposed you build **already
exists** — the gaps are somewhere else entirely.

Read from `C:\Users\m\Coding\skip-a-brainrot`, mirror `game-src/place-full/`.
Caveat: per your handoff, the mirror was resynced byte-exact at `4800cfb` but the place
went **unsaved again** afterwards, so verify anything below against live Studio with the
byte-count trick before editing.

---

## What the game is

Skip rocks across a lake to catch brainrots → place them on a plot for passive income →
sell, trade, or fuse them → rebirth and climb the index. Two currencies: **Cash** (soft,
from placed brainrots) and **Darrels** (premium, from daily quests and spent on eggs).

Already built and running: eggs + pets (shipped disabled behind `PetConfig.ENABLED`),
prize wheel, trading + booths, campfire fusion, offerings, three NPC quest lines
(Gianluca / Maxwell / Tung), a 25-tier season pass, daily rewards, offline earnings,
leaderboards, mutations, a rarity + pity system, weather, a price index, and a
universe-wide hard mint cap on Secrets (`LimitedStock`, 500 down to 5 for Secret Pete).

That's a real game, not a prototype. Which changes the advice.

---

## What's already built for monetization

| Piece | File | State |
|---|---|---|
| Receipt handling | `ServerScriptService/Modules/ProductRegistry.lua` | **Built.** Single `ProcessReceipt` assignment at `:65`, `ReceiptLog` dedupe on `PurchaseId`, save-before-grant ordering with a documented rationale. |
| Gamepass ownership | `ServerScriptService/Modules/GamepassService.lua` | **Built.** pcall'd `UserOwnsGamePassAsync`, per-session cache, `PromptGamePassPurchaseFinished` listener, full accessor API. Headless by design. |
| Pass catalog | `ReplicatedStorage/Modules/GamepassConfig.lua` | **Built.** Six passes with prices: 2x Cash 199, 2x Luck 249, Super Arm 149, Fast Charge 99, Auto Collect 299, VIP 499. |
| Init wiring | `ServerScriptService/Main.server.lua:131,146` | **Built.** Both services init in the right order. |

So the warning I gave you last message — *"check you don't have two `ProcessReceipt`
assignments"* — you'd already solved, with a comment at `ProductRegistry.lua:63` saying
exactly that. Ignore that part of the old plan.

---

## The three actual gaps

### 1. Every ID is `0`

`GamepassConfig.lua` — all six passes have `GamepassId = 0`.
`ProductRegistry.lua:68` — `PACK_IDS = { 0, 0, 0, 0 }` against Darrel amounts
`{80, 180, 400, 1000}`.

Both files treat `0` as "not created yet" and skip cleanly, so nothing is broken —
nothing is *buyable*. **This is blocked on BigFrogTerryBruh**, not on code. Per your
standing rule, no ID gets invented.

### 2. The gamepass effects are never consumed

`GamepassService` exposes `CashMult` / `LuckMult` / `PowerMult` / `ChargeMult` /
`HasFlag`. Grep says **nothing calls any of them** — the only references anywhere are
the `require` and `Init()` in `Main.server.lua`.

So even with real IDs pasted in, buying 2x Cash today would do nothing at all.

The seam is one line. `IncomeLoop.lua:119`:

```lua
e.Pending = (e.Pending or 0) + (cashPerSecondByName[e.Name] or 0)
    * Mutations.Mult(e.Mutation) * rebirthMult * upMult * PetHandler.IncomeMult(player) * dt
```

`GamepassService.CashMult(player)` drops straight into that chain, same shape as
`PetHandler.IncomeMult`.

> **Catch worth knowing before you touch it:** the *displayed* rate at `IncomeLoop.lua:139`
> multiplies `Mutations.Mult * rebirthMult * upMult` but **omits** `PetHandler.IncomeMult`
> that the actual accrual at `:119` applies. Harmless today because pets are off — but it
> means the display path and the accrual path have already drifted once. Add the gamepass
> multiplier to **both** lines or the HUD will under-report what players are earning, which
> is the worst possible bug to have on a paid multiplier.

### 3. No Robux shop exists

`GamepassConfig`'s own header: *"NOTHING here is surfaced in-game yet: no shop UI, and no
purchase prompt fires on its own."* `ShopHandler.lua` is only the soft-currency rock
ladder. There is no way for a player to see or buy a pass.

`GameHUDPanels/PassPanel.lua` is the template to copy — contract is
`return { Id = "...", Build = function(ctx) -> Frame }`, built once lazily, shell owns
`Visible`.

Also open: `SeasonConfig.lua` says *"Free track only for now — premium track needs a
gamepass id."*

---

## Blocked on the owner (nothing you do unblocks these)

From your own handoff §6, plus what the code confirms:

- All six gamepass IDs
- Four Darrel-pack dev product IDs
- Wheel-spin dev products (~29 R$, design ready, waiting on IDs)
- Roblox group → Group Rewards chest
- VIP chest (needs the VIP pass to exist)
- Season premium track (needs a pass ID)

Worth sending BigFrogTerryBruh one message with the full list, prices included, so it's
one round-trip instead of six.

---

## The parallel plan

Given all of the above, the honest sequencing:

### Not parallel — do first, alone, in Studio

Byte-count check the files you're about to touch against live. Your handoff calls this
the single biggest project risk and it takes minutes.

### Parallel — four `/bg`, none of them need Studio or real IDs

Each writes files only. Add `Do not use the Roblox Studio MCP — write files only.` to
every one.

**1. Wire the gamepass multipliers**
```
/bg In C:\Users\m\Coding\skip-a-brainrot, GamepassService exposes CashMult/LuckMult/
PowerMult/ChargeMult/HasFlag but nothing calls them. Read
ServerScriptService/Modules/GamepassService.lua, IncomeLoop.lua and ThrowHandler.lua
fully, then write a patch file showing exactly where each multiplier folds in, matching
the existing PetHandler.IncomeMult seam style. Critical: IncomeLoop:119 (accrual) and
IncomeLoop:139 (displayed rate) must both get the multiplier — they have already drifted
once, :139 is missing PetHandler.IncomeMult. Also handle the AutoCollect flag. Output a
patch, do not edit the mirror. Do not use the Roblox Studio MCP — write files only.
```

**2. Robux shop panel**
```
/bg In C:\Users\m\Coding\skip-a-brainrot, write a new GameHUDPanels module
(StarterPlayer/StarterPlayerScripts/GameHUDPanels/ShopPanel.lua) for Robux purchases.
Read PassPanel.lua fully first and match its contract exactly — { Id, Build(ctx) -> Frame },
built once lazily, shell owns Visible. Read GamepassConfig.lua for the catalog and
UIKit/Builders + UIKit/Tokens for styling. Tabs: Passes / Darrels. Owned passes render as
owned and unclickable. Passes with GamepassId == 0 must render as "Coming soon" and never
fire a prompt. List every remote you need with exact name and signature.
Do not use the Roblox Studio MCP — write files only.
```

**3. Receipt-safety hardening**
```
/bg In C:\Users\m\Coding\skip-a-brainrot, ServerScriptService/Modules/ProductRegistry.lua
handles Robux receipts. Handoff §5 lists "ProductRegistry receipt safety" as designed but
never shipped. Read the file plus PlayerDataManager.lua fully and write an adversarial
audit: every ordering where a player could be charged and not granted, or granted twice.
Cover the ReceiptLog 50-entry trim, the DarrelService.Award failure path, unknown product
ids returning NotProcessedYet forever, and __noSave profiles. Output findings with
file:line and a proposed patch per finding. Do not use the Roblox Studio MCP — write files only.
```

**4. Season premium track**
```
/bg In C:\Users\m\Coding\skip-a-brainrot, SeasonConfig.lua says "Free track only for now
— premium track needs a gamepass id." Read SeasonConfig.lua, SeasonPassHandler.lua and
GameHUDPanels/PassPanel.lua fully, then design the premium track: a second reward column
gated on a gamepass key, retroactive unlock when bought mid-season, and claim state that
survives the free/premium split in data.SeasonClaimed. Must stay inert while the pass id
is 0. Output a design doc plus the patches. Do not use the Roblox Studio MCP — write files only.
```

### Back in Studio, alone

Apply, playtest — and remember your own `STALE_AFTER = 90` note: wait ~90s between
playtests or you load a read-only profile and prove nothing.

---

## Correction to what I told you earlier

I suggested opening two Studio windows and pinning a session to each with
`set_active_studio`. **Don't** — your handoff §3 says a second concurrent Studio MCP
session gets *zero* roblox-studio tools from a port conflict. You've already hit this.

And the drift table in §0b is what concurrent sessions actually cost you: twelve files
out of sync, `EggShopClient` off by 34 KB. The file-writing split above isn't the
convenient option here, it's the only safe one.
