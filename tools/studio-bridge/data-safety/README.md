# Data-safety harness (C1 periodic persistence / C2 profile normalisation)

Unit tests for `ServerScriptService.Modules.SessionLock` and `PlayerDataManager`, run inside
Roblox Studio's **Edit-mode** `execute_luau` VM against a **mock DataStoreService**. No test
touches a production key: the module sources are `loadstring`-ed into an environment whose
`game:GetService("DataStoreService")` is an in-memory fake (JSON round trip, injectable
failures and latency, a write log), `Workspace` has no `PlayerBases`, `BindToClose` is
captured, and `os.time` is a driveable clock so lock staleness can be simulated.

## Run

1. Start the bridge from the checkout you want to test (it serves this folder):

       python tools/studio-bridge/bridge.py

2. Stage the sources (`live` = pre-hotfix mirror at the base commit, `new` = working tree):

       python tools/studio-bridge/data-safety/stage.py

3. In Studio (Edit mode), `execute_luau` this, with `VARIANT` = `"new"` or `"live"`:

   ```lua
   local VARIANT = "new"
   local HS = game:GetService("HttpService")
   local was = HS.HttpEnabled; HS.HttpEnabled = true
   local base = "http://127.0.0.1:8731/data-safety/"
   local okFetch, got = pcall(function()
       return {
           harness = HS:GetAsync(base .. "harness.lua"),
           SessionLock = HS:GetAsync(base .. "stage/" .. VARIANT .. "/SessionLock.lua"),
           PlayerDataManager = HS:GetAsync(base .. "stage/" .. VARIANT .. "/PlayerDataManager.lua"),
       }
   end)
   HS.HttpEnabled = was
   if not okFetch then return "FETCH ERROR: " .. tostring(got) end
   local fn, err = loadstring(got.harness, "=harness")
   if not fn then return "COMPILE ERROR: " .. tostring(err) end
   local ok, res = pcall(fn, VARIANT, { SessionLock = got.SessionLock, PlayerDataManager = got.PlayerDataManager })
   return ok and res or ("HARNESS ERROR: " .. tostring(res))
   ```

   `HttpEnabled` is flipped on only for the three GETs and restored before the tests run
   (the place ships with it off).

The `live` run takes ~40 s (T10 waits out one real 30 s heartbeat to show it never persists the
profile); the `new` run takes ~15 s. Expected: every C1/C2 test FAILs or is n/a on `live`, all
PASS on `new`. Results of the runs that shipped with the hotfix are in
`docs/qa/data-safety/REPORT.md`.

## Cases

| # | Brief case | Test |
|---|---|---|
| 1 | brand-new player joins normally | T1 |
| 2 | brand-new player earns Cash | T2 |
| 3 | first server dies before clean release | T3 |
| 4 | rejoin after the abnormal first session | T4a (inside stale window), T4b (after), T4c (legacy `__sessionNew` marker) |
| 5 | old profile missing Cash | T5 |
| 6 | old profile missing another safe default | T6 |
| 7 | normal established profile | T7 |
| 8 | established profile with changed values | T8 |
| 9 | two servers, same profile | T9a (live lock), T9b (stale takeover), T9c (teleport window) |
| 10 | autosave while playing | T10 |
| 11 | player leaves during/near autosave | T11, T16 (rejoin on the same server mid-write) |
| 12 | BindToClose after recent autosave | T12 |
| 13 | DataStore write failure | T13 |
| 14 | retry behaviour | T14 |
| 15 | multi-player staggered autosaves | T15, T17 (budget floor) |
