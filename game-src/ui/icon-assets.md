# Icon asset upload — Step 2b pilot result

**Outcome: FAILED (engine-gated, not fixable from script).**

## What was probed

In Studio Edit mode, via `AssetService`:

| Call | Result |
|---|---|
| `AssetService.CreateEditableImage` | exists (`function`) |
| `AssetService:CreateEditableImage({ Size = Vector2.new(512, 512) })` | **works** — returns a valid `EditableImage` object (`typeof() == "Object"`, `ClassName == "EditableImage"`) |
| `EditableImage:WritePixelsBuffer(pos, size, buffer)` | **works** — accepted a zeroed 4x4 RGBA buffer with no error |
| `EditableImage:WritePixels` | does not exist on this build (`WritePixels is not a valid member of EditableImage`) — `WritePixelsBuffer` is the only pixel-write method, confirming the plan's requirement to emit raw RGBA bytes (not PNG) from the Python helper |
| `AssetService.CreateAssetAsync` | exists (`function`) |
| `AssetService:CreateAssetAsync(img, Enum.AssetType.Image)` | **fails**, every variant tried (no options table, with `{ Name = ... }`, etc.) |

Exact error text, verbatim, from every `CreateAssetAsync` call regardless of arguments:

```
CreateAssetAsync and CreateAssetVersionAsync are not available yet
```

This reads as a hard engine-level stub for this Studio build/session — the method exists and is callable, but always short-circuits to this message independent of parameters, target asset type, or EditableImage validity. It is not a permissions or argument-shape problem we can route around from a script; `AssetManagerService` and `StudioAssetService` also exist as service names but return `nil` (not implemented), and no alternate publish path (`InsertService`, `ContentProvider`) exposes an equivalent "publish this EditableImage as a real asset id" call.

## Conclusion

The pixel pipeline (decode PNG → raw RGBA in Python → base64 → Luau decode → `CreateEditableImage` → `WritePixelsBuffer`) is sound and was not needed further once the terminal step (`CreateAssetAsync`) proved unavailable — no point building the base64/decoder plumbing to feed a call that always errors. The pilot stopped at the API-availability probe per the brief's "probe first" instruction.

## Fallback shipped

`ReplicatedStorage.Modules.UIKit.Tokens` (and `game-src/ui/UIKitTokens.lua`) ships `T.icons` with all 8 keys present, each an empty string:

```lua
T.icons = {
	coin = "", gem = "", bag = "", pass = "", daily = "", goals = "", index = "", settings = "",
}
```

`UI.artSlot(parent, size, image)` originally only checked Lua truthiness (`if image then ...`), so an empty string (`""`) — truthy in Lua — was treated as a real image and rendered an invisible `Image` with `BackgroundTransparency = 1` instead of the placeholder. Fixed in the Task 2 fix pass (2026-07-30): `artSlot` now treats `""` the same as `nil` (`local has = image ~= nil and image ~= ""`), so it degrades gracefully on `image == nil`/`""` (renders a plain coloured placeholder slot instead of an `Image`). Every panel that consumes `Tokens.icons[name]` works today and picks up real ids automatically once they're filled in — no call-site changes needed later.

## USER STEP required to unblock

1. Open **Asset Manager** in Studio.
2. **Bulk Import** the 8 PNGs from `docs/design-handoff/ui-kit/captures/icons/*_512.png`:
   `bag_512.png`, `coin_512.png`, `daily_512.png`, `gem_512.png`, `goals_512.png`, `index_512.png`, `pass_512.png`, `settings_512.png`.
3. For each imported image, copy the resulting `rbxassetid://...` id.
4. Paste the 8 ids into `T.icons` in `ReplicatedStorage.Modules.UIKit.Tokens` (and mirror the edit into `game-src/ui/UIKitTokens.lua`), matching key names to source filenames (`bag_512.png` → `bag`, etc.).

No code changes will be required beyond that — panels already read `Tokens.icons[name]`.
