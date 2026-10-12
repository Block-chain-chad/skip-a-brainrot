# ShopPanel remotes + wiring — companion to `GameHUDPanels/ShopPanel.lua`

**Status: ShopPanel.lua is the ONLY game file created. Nothing else was edited.** Every
edit below is PROPOSED, written against the live mirror under `game-src\place-full\` as of
2026-08-04. Per the standing handoff caveat, byte-count-verify any file against live Studio
before landing anything (the mirror has gone unsaved-stale before).

The panel is fully functional **today with zero server changes**: every GamepassId and pack
ProductId is `0`, so every card renders COMING SOON on a dead (never-connected,
`Active=false`) button. The moment real ids land in `GamepassConfig.lua` /
`ProductRegistry.lua` (+ the ShopState patch below), the same cards go live with no client
edit.

---

## 1. Remotes the panel consumes

### Required today: NONE

The panel ships against existing shared data only:

- **Pass catalog** — `ReplicatedStorage.Modules.GamepassConfig` (shared by design; its
  header says a shop UI should read names/icons/prices straight from it).
- **Purchases** — client-side `MarketplaceService:PromptGamePassPurchase(player, id)` and
  `MarketplaceService:PromptProductPurchase(player, id)`. No purchase remote is needed:
  pass grants land via `GamepassService.Init`'s `PromptGamePassPurchaseFinished` cache
  listener, product grants via `ProductRegistry.ProcessReceipt` (the game's single
  `ProcessReceipt` assignment — see that file's header; do NOT add another).

### Optional, recommended once ids exist: `ShopState`

| | |
|---|---|
| Instance | `ReplicatedStorage.Remotes.ShopState` |
| Class | **RemoteFunction** |
| Client → server | `ShopState:InvokeServer()` — **no arguments** |
| Returns | `{ Owned = { [PassKey: string]: true }, Packs = { { Amount: number, ProductId: number }, ... } }` |
| Call sites | once when the remote resolves after Build, then once per panel open (`Visible` flip), single-flighted |

`Owned` keys are `GamepassConfig` `Key` strings (`"Cash2x"`, `"VIP"`, ...). `Packs` is in
display order and should mirror `ProductRegistry.Init`'s `PACK_AMOUNTS` / `PACK_IDS`
pairing.

**Why it's wanted:**

1. **Pack product ids are invisible to the client.** `PACK_IDS` / `PACK_AMOUNTS` are locals
   inside `ProductRegistry.Init` (ServerScriptService — not requirable from the client).
   Until ShopState exists the panel carries a hand-kept mirror
   (`PACK_FALLBACK = {80, 180, 400, 1000}`, all id 0) that **must be kept in sync
   manually** — flagged in both file headers.
2. **Server-truth ownership beats the client API.** `GamepassService`'s cache is the same
   source the gameplay effects will use; client-side `UserOwnsGamePassAsync` results are
   session-cached by Roblox and can go stale around purchases.

**Resolution contract in the panel:** bounded `ctx.remotes:WaitForChild("ShopState", 5)`
inside a spawned thread (SettingsPanel/ToastClient convention — never an unbounded wait,
never stalling the lazy Build). Absent after 5s → permanent client-only fallback:

- ownership: pcall'd `MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)` per pass
  with a **real** id only (zero calls in today's all-zero build), plus the
  `PromptGamePassPurchaseFinished` overlay below;
- packs: the `PACK_FALLBACK` mirror (all COMING SOON).

### Existing remotes considered and deliberately NOT used

- `remotes.DarrelState` (RemoteFunction, DarrelService) — returns
  `{ Darrels, Daily }`: the player's **balance**, not the purchasable packs. The gem pill
  already renders balance; the shop doesn't need it.
- No other remote in the game carries gamepass/product data (grep: `GamepassService` is
  referenced only by `Main.server.lua`).

### Client-side signal used (not a remote)

`MarketplaceService.PromptGamePassPurchaseFinished` — on `wasPurchased == true` for the
local player, the panel flips `owned[Key]` locally and re-renders. This is the one
non-server write, and it mirrors `GamepassService.Init`'s own cache update on the identical
server-side signal, so client UI and server effects can't disagree about a mid-session buy.

---

## 2. Proposed server patch — create `ShopState` (NOT applied)

Three small edits, matching existing conventions (self-heal remote creation copied from
`DarrelService.Init`'s `DarrelState`).

### Edit 2.1 — `ProductRegistry.lua`: hoist the pack tables + expose `M.Packs()`

Before (inside `M.Init`, `:67-72`):
```lua
	-- Darrel packs (user creates dev products on roblox.com, then replaces these zeros):
	local PACK_IDS = { 0, 0, 0, 0 }           -- <- fill with real dev product ids
	local PACK_AMOUNTS = { 80, 180, 400, 1000 }
	for i, id in ipairs(PACK_IDS) do
		M.Register(id, { Type = "Darrels", Amount = PACK_AMOUNTS[i] })
	end
```

After (tables hoisted to module scope above `M.Init`, plus an accessor):
```lua
-- Darrel packs (user creates dev products on roblox.com, then replaces these zeros).
-- Module-scope so ShopState (Main.server.lua) can serve them to the shop panel.
local PACK_IDS = { 0, 0, 0, 0 }           -- <- fill with real dev product ids
local PACK_AMOUNTS = { 80, 180, 400, 1000 }

-- Display-order pack list for the client shop panel (ids stay 0 until created).
function M.Packs()
	local out = {}
	for i, amount in ipairs(PACK_AMOUNTS) do
		out[i] = { Amount = amount, ProductId = PACK_IDS[i] }
	end
	return out
end
```
…and `M.Init`'s loop becomes just:
```lua
	for i, id in ipairs(PACK_IDS) do
		M.Register(id, { Type = "Darrels", Amount = PACK_AMOUNTS[i] })
	end
```

### Edit 2.2 — `GamepassService.lua`: expose a copy of the owned set

After `GamepassService.Owns` (`:45-48`):
```lua
-- Copy of the session ownership set, for the shop panel via ShopState.
-- A COPY on purpose: the live cache must never leak to remote handlers.
function GamepassService.OwnedSet(player)
	local out = {}
	local set = owned[player]
	if set then
		for k in pairs(set) do out[k] = true end
	end
	return out
end
```

### Edit 2.3 — `Main.server.lua`: create the remote after both Inits (after `:146`)

```lua
-- Shop panel state (see docs/monetization/shop-panel-remotes.md). Self-heal
-- creation, same pattern as DarrelService.Init's DarrelState.
local shopState = remotes:FindFirstChild("ShopState")
if not shopState then
	shopState = Instance.new("RemoteFunction")
	shopState.Name = "ShopState"
	shopState.Parent = remotes
end
shopState.OnServerInvoke = function(plr)
	return { Owned = GamepassService.OwnedSet(plr), Packs = ProductRegistry.Packs() }
end
```

Notes: `GamepassService.OwnedSet` is fail-neutral (empty table before the pcall'd refresh
resolves — the panel just shows nothing as owned until the next open). No new requires
needed in Main; both modules are already required at `:36` / `:41`.

---

## 3. Panel registration + rail wiring (proposed, NOT applied)

**Module registration: no edit needed.** GameHUDClient's startup loop
(`GameHUDClient.client.lua:1415-1423`) requires every ModuleScript in the sibling
`GameHUDPanels` folder and registers anything returning `{ Id, Build }`. Dropping
`ShopPanel.lua` into the folder registers id `"shop"` automatically — `ctx.openPanel("shop")`
works from anywhere at that point.

**The one-line edit that makes it reachable** — a rail button, in `RAIL_ORDER`
(`GameHUDClient.client.lua:795-811`), e.g. after the daily entry:

```lua
	{ id = "shop", label = "Shop" },
```

Grid math check: `RAIL_ROWS = 4`, `RAIL_COLS = ceil(#RAIL_ORDER / 4)` — an 8th item fills
the second column (2×4), so **no third column appears** and the rebirth-entry review note
about a third column overlapping open panels does not trigger.

**Icon quality (optional follow-ups, without them the rail shows the `"?"` glyph
fallback):** the icon chain for a rail id is `STICKER` → `T.icons` → `IconArt.has` →
`glyphFallback`, and none of the four knows `"shop"`. Either:

- add a `STICKER` entry (`GameHUDClient.client.lua:781-788`), e.g.
  `shop = { glyph = "\u{1F6D2}", size = 62, tilt = -4 },` — **but per that table's own
  discipline, prove U+1F6D2 (shopping cart) renders in this build's emoji font on a probe
  board first** (it is Emoji 3.0-era, likely fine, unproven here); or
- add `shop = "\u{1F4B0}"` to the `GLYPH` table (`:283`) — render-proven, but duplicates
  the coin pill's money bag; or
- (best long-term) draw/import real art: `IconArt.SHAPES` already contains a `shops`
  vector (used by this panel's header) — a `shop = ...` alias entry in `IconArt.SHAPES`
  pointing at the same shape list would light up the `IconArt.has(cfg.id)` branch with
  zero new art.

**No other shell edits needed:** the panel hardcodes width 900 behind a
forward-compatible `T.size.panelWidth.shop or 900` read (Tokens untouched), and
`state.screen` falls back to the raw id (`ID_TO_SCREEN[id] or id`), so `"shop"` needs no
`ID_TO_SCREEN` entry.

---

## 4. Sync + safety flags

- **id == 0 never prompts** — double-guarded in the panel: COMING SOON cards use the
  `"disabled"` button variant (`Active = false`, no click sfx) and **never receive a click
  connection**; the live buy handlers additionally re-check `id > 0` (and not-owned, for
  passes) at click time.
- **PACK_FALLBACK sync** — `ShopPanel.lua`'s `{80, 180, 400, 1000}` mirror must track
  `ProductRegistry.Init`'s `PACK_AMOUNTS` by hand until Edit 2.x lands. Both headers flag
  it.
- **Pass prices are display-only** — `GamepassConfig.RobuxPrice` is what the button shows;
  Roblox charges the dashboard price at prompt time. Keep config in sync when the owner
  creates the passes (prices: 199 / 249 / 149 / 99 / 299 / 499 — already in
  `docs/monetization/owner-id-requests.md`).
- **Pack prices** are fetched live via `GetProductInfo(id, Enum.InfoType.Product)` once
  `ProductId > 0` (pcall'd, cached); the button reads "BUY" until the fetch lands.
- **Unproven emoji** — `GamepassConfig` icons `\u{1F9F2}` (magnet, Auto Collect) and
  `\u{1F340}` (clover, 2x Luck) have not been render-proven in this build's font (the
  proven set is in GameHUDClient's `GLYPH` comment). If either shows tofu in Play, swap
  the `Icon` string in `GamepassConfig` — the panel reads it verbatim.
- **Owner blockers unchanged** — nothing here unblocks the six pass ids / four pack ids;
  that list stays with BigFrogTerryBruh per `owner-id-requests.md`.
