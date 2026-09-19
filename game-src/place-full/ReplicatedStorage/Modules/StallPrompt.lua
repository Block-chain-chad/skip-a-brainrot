-- StallPrompt -- binds a walk-up ProximityPrompt that may not exist yet, and may
-- be REPLACED later.
--
-- WHY THIS EXISTS. Workspace.StreamingEnabled is on and the two worlds sit 11,000
-- studs apart. A player joining in the valley does not get the Frozen Tundra
-- stalls' parts replicated at all -- only the empty Model shells come down. Every
-- stall binder used to do:
--
--     local part = stall:WaitForChild("PromptPart", 30)   -- times out in the valley
--     if not part then return end                         -- ...and gives up forever
--
-- so the tundra prompts were never connected to anything. Walking to world 2 later
-- showed the prompt (it streams in with the model) and pressing E did nothing --
-- no error, no menu, which is exactly how it was reported.
--
-- A one-time fix-up is not enough either: streaming REPLACES instances, so a part
-- that streams out and back in is a NEW part carrying none of the old connections.
-- Come back to the valley after a trip to the tundra and the valley stall would go
-- dead the same way. This therefore watches for the lifetime of the session and
-- calls `onBound` once per prompt INSTANCE, however many times it comes and goes.
local Workspace = game:GetService("Workspace")

local StallPrompt = {}

-- Bind(stallName, promptName, onBound)
--   onBound(promptPart, prompt) runs for each new prompt instance, exactly once.
--   Callers that keep a list of prompt parts should drop entries whose Parent has
--   gone nil -- that is a part which has streamed out.
function StallPrompt.Bind(stallName, promptName, onBound)
	task.spawn(function()
		local gameWorld = Workspace:WaitForChild("GameWorld")
		-- STRONG keys, cleaned up on Destroying.
		--
		-- These were weak, which is a trap with Instance keys: the Lua wrapper is
		-- collectable even while the instance is alive in the DataModel, so an entry
		-- can disappear at any GC. Here that meant tryBind could bind the SAME prompt
		-- a second time, and a double-connected Triggered fires the handler twice --
		-- open then immediately close, which reads to a player as "pressing E does
		-- nothing". Destroying is the precise moment a streamed-out prompt goes away,
		-- so nothing accumulates.
		local bound = {}

		local function tryBind(stall)
			local part = stall:FindFirstChild("PromptPart")
			local prompt = part and part:FindFirstChild(promptName)
			if not prompt or bound[prompt] then return end
			bound[prompt] = true
			prompt.Destroying:Connect(function() bound[prompt] = nil end)
			onBound(part, prompt)
		end

		local watching = {}
		local function watch(stall)
			if watching[stall] then return end
			watching[stall] = true
			stall.Destroying:Connect(function() watching[stall] = nil end)
			tryBind(stall)
			-- DescendantAdded rather than ChildAdded: PromptPart and the prompt inside
			-- it can arrive in either order as the model streams in.
			stall.DescendantAdded:Connect(function(d)
				if d.Name == promptName or d.Name == "PromptPart" then
					task.defer(tryBind, stall)
				end
			end)
		end

		local existing = gameWorld:FindFirstChild(stallName)
		if existing then watch(existing) end
		-- the Model shell itself can arrive late, or be swapped for a new one
		gameWorld.ChildAdded:Connect(function(child)
			if child.Name == stallName then watch(child) end
		end)
	end)
end

return StallPrompt
