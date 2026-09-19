-- BrainrotFX: bespoke particle packages for OUR top brainrots (Legendary+ voxel models).
--
-- WHY THIS SHAPE (2026-09-03): the first effects pass (2026-08-28) was hand-authored
-- and the owner reported it made the game "super laggy", so it was removed. The 149
-- imported pack models carry 890 emitters between them and the owner says those are
-- fine. So this pass copies the PACK's emitters instead of inventing new ones: every
-- kit below is a Clone() of a real pack emitter (texture, flipbook, brightness,
-- orientation, curves all inherited) with only colour / rate / size retuned. Budget
-- per model is held to the pack's own median: 4-7 emitters on one invisible host,
-- ~40-80 particles alive, auras LockedToPart at Speed 0.
--
-- Effects are BAKED as instances into the templates (both BrainrotModels and
-- BrainrotModelsPlot, because BrainrotSpawner prefers the Plot folder for the 43
-- heavy models) exactly like the pack. Hosts are named so a revert is one line:
--   BrainrotFX.stripAll()
-- The idle client (BrainrotIdleClient) switches emitters OFF on far bodies, so a
-- full camp of these never runs more than the near plots' worth.
--
-- Rarity intensity multiplies Rate only: Legendary .85, Mythic 1, Secret 1.15, God 1.3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotFX = {}

BrainrotFX.HOST  = "BrainrotFxHost"    -- body-sized invisible part, auras live here
BrainrotFX.CROWN = "BrainrotFxCrown"   -- small part just above the head: glow/flare/steam
BrainrotFX.BASE  = "BrainrotFxBase"    -- flat part at the feet: rings, dust, splashes
BrainrotFX.VERSION = 1

local INTENSITY = { Legendary = 0.85, Mythic = 1.0, Secret = 1.15, God = 1.3 }

-- ===== colours ===============================================================
local function C(r, g, b) return Color3.fromRGB(r, g, b) end
local WHITE   = C(255, 255, 255)
local ICE     = C(200, 232, 245)
local FROST   = C(127, 216, 255)
local SKY     = C(120, 190, 240)
local DEEP    = C(80, 120, 230)
local GOLD    = C(255, 200, 70)
local AMBER   = C(240, 150, 50)
local ORANGE  = C(255, 120, 20)
local RED     = C(230, 50, 40)
local PURPLE  = C(150, 80, 255)
local LILAC   = C(190, 140, 255)
local NEON_G  = C(110, 240, 170)
local LIME    = C(215, 240, 110)
local MOSS    = C(140, 200, 90)
local SAND    = C(230, 215, 180)
local CREAM   = C(245, 238, 222)
local COFFEE  = C(140, 95, 60)
local BROWN   = C(190, 120, 60)
local GREY    = C(170, 170, 180)
local SMOKE   = C(110, 115, 125)
local DARK    = C(70, 72, 82)
local TEAL    = C(70, 180, 190)
local PINK    = C(255, 160, 175)

-- ===== kits ==================================================================
-- Each kit clones a named emitter off a pack model, then applies its overrides.
-- Fields recognised on a kit or a recipe entry: color, rate, size, host, le, speed,
-- accel, drag, life, spread, locked, bright, name.
local KITS = {
	aura1    = { src = { "Carrotini Brainini", "aura1" } },
	aura2    = { src = { "Carrotini Brainini", "aura2" } },
	aura3    = { src = { "Carrotini Brainini", "aura3" } },
	glow     = { src = { "Carrotini Brainini", "glow" },  host = "crown", size = 0.7 },                 -- toned down 2026-09-03 (owner: "crown glows a bit much")
	flare    = { src = { "Carrotini Brainini", "flare" }, host = "crown", size = 0.7, bright = 0.6 },
	specs    = { src = { "La Vacca Saturno Saturnita", "specs1" }, rate = 18 },
	cubes    = { src = { "Tralalero Tralala", "specs1" }, rate = 14, speed = NumberRange.new(4, 9), locked = true, spread = Vector2.new(360, 360) },
	stars    = { src = { "Los Tungtungtungcitos", "stars" } },
	lightning= { src = { "Los Tungtungtungcitos", "lightning1" } },
	fire     = { src = { "Bulbito Bandito Traktorito", "fire" } },
	smoke    = { src = { "Trenostruzzo Turbo 3000", "smoke1" }, host = "crown" },
	snow     = { src = { "Spioniro Golubiro", "feather1" }, rate = 16, speed = NumberRange.new(1, 3), accel = Vector3.new(0, -5, 0), drag = 2, spread = Vector2.new(360, 360), life = NumberRange.new(1.0, 1.8) },
	feather  = { src = { "Spioniro Golubiro", "feather1" }, rate = 10 },
	droplets = { src = { "Fragola La La La", "droplets1" }, rate = 20 },
	spout    = { src = { "Fragola La La La", "droplets1" }, rate = 22, host = "crown", speed = NumberRange.new(6, 10), spread = Vector2.new(25, 25), accel = Vector3.new(0, -12, 0), life = NumberRange.new(0.8, 1.2) },
	leaves   = { src = { "Ketupat Kepat", "leaves1" } },
	rays     = { src = { "Las Vaquitas Saturnitas", "rays1" } },
	ripple   = { src = { "Los Orcalitos", "ripple1" }, host = "base", rate = 4 },
	notes    = { src = { "Cavallo Virtuoso", "notes1" }, host = "crown", rate = 5 },
	bones    = { src = { "Extinct Ballerina", "bones" } },
	glitch   = { src = { "Los Hotspotsitos", "glitch1" } },
	dust     = { src = { "Dug dug dug", "dust1" }, host = "base" },
	rock     = { src = { "Agarrini la Palini", "rock1" }, rate = 4 },
	darkaura = { src = { "Gorillo Watermelondrillo", "darkaura1" } },
	hearts   = { src = { "Espresso Signora", "hearts" } },
	bubbles  = { src = { "Blueberrinni Octopusini", "bubbles" } },
	swirls   = { src = { "Los Chicleteiras", "swirls" } },
	mucus    = { src = { "La Karkerkar Combinasion", "mucus" } },
	splash   = { src = { "Tralalero Tralala", "water1" }, host = "base", rate = 6 },
	wave     = { src = { "Tralalero Tralala", "wave1" }, host = "base", rate = 1.5, size = 0.5 },
	glare    = { src = { "La Vacca Saturno Saturnita", "glare1" }, size = 0.5 },
	ring     = { src = { "La Vacca Saturno Saturnita", "aura1" }, rate = 1.5, size = 0.6 },
	swarm    = { src = { "La Vacca Saturno Saturnita", "specs1" }, rate = 16, speed = NumberRange.new(0.5, 2), drag = 2, accel = Vector3.new(0, 0, 0), life = NumberRange.new(1.2, 2.2), le = 1 },
	sparks   = { src = { "La Vacca Saturno Saturnita", "specs1" }, rate = 22, speed = NumberRange.new(7, 12), drag = 8, le = 1, life = NumberRange.new(0.3, 0.7) },
	steam    = { src = { "Trenostruzzo Turbo 3000", "smoke1" }, host = "crown", rate = 8, speed = NumberRange.new(1.5, 3), accel = Vector3.new(0, 1.5, 0) },
}
BrainrotFX.KITS = KITS

-- ===== recipes ===============================================================
-- One per Legendary+ voxel brainrot, read off what the Italian name says the
-- creature IS. Colours come from the model's own palette (measured 2026-09-03).
local function E(kit, color, extra)
	local e = extra or {}
	e.kit = kit
	e.color = color
	return e
end

local RECIPES = {
	["Alce Lampadario"] = { -- chandelier moose (Legendary, Forge pilot): candle glow at the crown, icy aura
		E("glow", C(255, 210, 120)), E("flare", C(255, 210, 120)), E("aura2", C(191, 230, 255), { rate = 6 }),
	},
	["Nonno Ghiacciaio"] = { -- grandpa glacier (Secret, Forge pilot): frost aura, falling snow, a cold glare
		E("aura1", C(200, 232, 245), { rate = 8 }), E("snow", WHITE, { rate = 6 }), E("glare", C(200, 232, 245), { size = 0.5 }),
	},
	["Alcione Trombettone"] = { -- kingfisher trumpet: song + feathers + amber crown
		E("notes", AMBER), E("feather", SKY), E("glow", AMBER), E("flare", AMBER), E("aura1", C(255, 200, 120), { rate = 8 }),
	},
	["Aurora Serpentina"] = { -- the northern lights as a snake
		E("aura1", NEON_G, { size = 1.1 }), E("aura2", LILAC), E("rays", LILAC), E("stars", C(200, 255, 230)), E("specs", LILAC),
	},
	["Balena Polare"] = { -- polar whale: blowhole spout, ripples at the feet
		E("spout", ICE), E("ripple", WHITE), E("aura2", C(200, 225, 240), { rate = 8 }), E("specs", ICE, { rate = 10 }),
	},
	["Balenone Iceberghino Trombonone"] = { -- iceberg whale on trombone (Secret)
		E("notes", C(90, 170, 230)), E("splash", C(90, 170, 230)), E("cubes", ICE), E("aura3", C(210, 235, 255)), E("glow", AMBER), E("flare", AMBER),
	},
	["Ceppone Zampalunga"] = { -- long-legged log: falling leaves, dust at the feet
		E("leaves", MOSS), E("dust", SAND), E("specs", C(200, 110, 100), { rate = 8 }), E("aura1", C(120, 90, 60), { rate = 6 }),
	},
	["Chim"] = { -- chimney: smoke and soot
		E("smoke", GREY, { rate = 10 }), E("darkaura", C(90, 90, 100)), E("specs", C(190, 190, 195), { rate = 10 }),
	},
	["Colosso Glaciale"] = { -- glacial colossus: imposing stillness, frost falling off it
		E("dust", ICE), E("ripple", ICE), E("aura1", ICE, { rate = 8, size = 1.2 }), E("specs", WHITE, { rate = 8 }), E("rays", FROST, { rate = 1 }),
	},
	["Corvacchio Beccarino"] = { -- big-beaked crow: dark feathers, amber eyes
		E("feather", C(70, 70, 75)), E("darkaura", DARK), E("glow", AMBER), E("flare", AMBER), E("specs", AMBER, { rate = 8 }),
	},
	["Cristallo Vivente"] = { -- living crystal: refracting shards, glints
		E("cubes", NEON_G, { rate = 8 }), E("cubes", C(240, 100, 220), { rate = 8, name = "cubes2" }), E("stars", WHITE), E("flare", WHITE), E("glare", WHITE), E("aura3", C(223, 240, 248)),
	},
	["Cuore della Tundra"] = { -- heart of the tundra (Secret): gold pulse in the ice
		E("hearts", GOLD), E("glow", GOLD), E("flare", GOLD), E("aura2", ICE), E("stars", GOLD, { rate = 6 }),
	},
	["Focarella Ballonzolo"] = { -- little bouncing bonfire
		E("fire", C(255, 115, 80)), E("sparks", ORANGE), E("smoke", C(100, 100, 110), { rate = 6 }), E("glow", ORANGE), E("flare", ORANGE),
	},
	["Gufocervo Stiltini"] = { -- owl-deer on stilts: forest floor + moon glow
		E("leaves", MOSS), E("feather", SAND), E("glow", C(255, 240, 200)), E("specs", C(185, 160, 117), { rate = 8 }),
	},
	["Inverno Eterno"] = { -- eternal winter (God): the blizzard itself
		E("snow", WHITE, { rate = 20 }), E("aura1", C(232, 238, 244), { rate = 12, size = 1.2 }), E("rays", C(200, 230, 255)), E("stars", WHITE), E("glare", C(200, 230, 255), { size = 0.6 }), E("flare", WHITE),
	},
	["Kraken Congelato"] = { -- frozen kraken (Secret): rising bubbles, deep-sea aura
		E("bubbles", C(140, 220, 230)), E("splash", TEAL), E("darkaura", C(31, 96, 104)), E("droplets", C(207, 230, 238)), E("ripple", ICE),
	},
	["Lucciolone Pantanini"] = { -- swamp firefly: a slow swarm of lights
		E("swarm", LIME, { rate = 20 }), E("glow", LIME), E("darkaura", C(60, 80, 50)), E("stars", LIME, { rate = 4 }),
	},
	["Lupo Tempesta"] = { -- storm wolf: lightning in a dark cloud
		E("lightning", FROST, { rate = 5 }), E("smoke", SMOKE, { rate = 6 }), E("darkaura", C(58, 63, 69)), E("specs", FROST), E("glare", FROST, { size = 0.4 }),
	},
	["Mammuto Lanoso"] = { -- woolly mammoth: dust from the footfalls, snow in the wool
		E("dust", C(200, 180, 150), { rate = 10 }), E("snow", WHITE, { rate = 8 }), E("aura1", BROWN, { rate = 6 }), E("specs", SAND, { rate = 8 }),
	},
	["Martellone Squaletto Bum Bum"] = { -- hammerhead drum: rings pulse like a beat
		E("splash", C(80, 150, 200)), E("ripple", WHITE, { rate = 6 }), E("droplets", C(188, 198, 194)), E("glow", AMBER), E("flare", AMBER), E("aura2", C(80, 130, 170)),
	},
	["Muschione Cornaluna"] = { -- moss-horned moon (Secret)
		E("leaves", MOSS), E("glow", C(255, 245, 210)), E("stars", C(255, 245, 210)), E("aura1", C(140, 190, 100)), E("specs", SAND, { rate = 8 }),
	},
	["Narvalino Trapanino"] = { -- narwhal drill: sparks and shavings
		E("sparks", ORANGE), E("cubes", GREY, { rate = 8 }), E("droplets", C(200, 225, 240)), E("glow", ORANGE), E("flare", ORANGE), E("aura3", C(120, 150, 175), { rate = 6 }),
	},
	["Nave Rompighiaccio"] = { -- icebreaker ship: funnel smoke, bow wave, cracked ice
		E("smoke", C(90, 90, 100), { rate = 10 }), E("splash", C(200, 230, 255)), E("cubes", ICE, { host = "base", rate = 8 }), E("aura1", RED, { rate = 8 }), E("specs", WHITE, { rate = 6 }),
	},
	["Ombra Bianca"] = { -- white shadow (Secret): a veil that flickers
		E("aura1", WHITE, { rate = 14, size = 1.3 }), E("glitch", WHITE), E("specs", WHITE, { rate = 8 }), E("glare", WHITE, { size = 0.5 }),
	},
	["Orcarella Bibitona"] = { -- orca soda: fizz
		E("bubbles", C(200, 230, 255), { rate = 10 }), E("splash", C(110, 170, 230)), E("droplets", C(180, 220, 255)), E("glow", RED), E("flare", RED), E("aura2", C(70, 90, 120)),
	},
	["Orso Frigorifero"] = { -- fridge bear: cold mist rolling out
		E("steam", C(220, 240, 255)), E("cubes", ICE, { rate = 6 }), E("specs", WHITE, { rate = 8 }), E("aura3", C(200, 225, 240)), E("glow", FROST), E("flare", FROST),
	},
	["Pattinatore Fantasma"] = { -- ghost skater: skate arcs, fading trail
		E("glitch", C(188, 216, 232)), E("aura1", C(220, 235, 245), { size = 1.2 }), E("specs", WHITE, { rate = 10 }), E("swirls", C(200, 225, 245)), E("glare", C(200, 225, 245), { size = 0.4 }),
	},
	["Regina Brinata"] = { -- frost queen: snow, a crown of light
		E("snow", WHITE, { rate = 12 }), E("stars", WHITE), E("rays", FROST), E("aura2", DEEP), E("flare", WHITE), E("glare", C(200, 220, 255), { size = 0.5 }),
	},
	["Rospino Bavaglio"] = { -- drooling toad
		E("mucus", C(150, 220, 110)), E("bubbles", C(200, 240, 180)), E("specs", MOSS, { rate = 8 }), E("aura1", C(90, 150, 100), { rate = 8 }), E("droplets", C(150, 220, 110), { rate = 10 }),
	},
	["Rospoluna Lanternina"] = { -- moon-toad lantern (Secret): orange lantern in purple night
		E("glow", ORANGE, { rate = 4 }), E("flare", ORANGE), E("swarm", C(255, 200, 80), { rate = 12 }), E("aura1", PURPLE, { rate = 10 }), E("stars", ORANGE, { rate = 5 }),
	},
	["Secret Pete"] = { -- (God) the big one: gold rays
		E("rays", GOLD, { rate = 1.5 }), E("flare", GOLD), E("stars", GOLD), E("aura1", PINK, { rate = 12, size = 1.3 }), E("glare", GOLD, { size = 0.6 }), E("hearts", C(255, 150, 160), { rate = 4 }),
	},
	["Squalone Frigidone Bianchissimo"] = { -- big frigid white shark (Secret): frost breath
		E("steam", C(220, 240, 255), { rate = 10 }), E("cubes", ICE, { rate = 8 }), E("ripple", ICE), E("aura2", C(133, 196, 233)), E("specs", C(60, 130, 240), { rate = 8 }), E("droplets", C(188, 198, 194), { rate = 10 }),
	},
	["Titano Sepolto"] = { -- buried titan (Secret): dust and falling stone, stillness
		E("dust", GREY, { rate = 10 }), E("rock", C(127, 114, 104)), E("ripple", GREY), E("aura1", C(160, 160, 165), { rate = 8 }), E("specs", MOSS, { rate = 6 }),
	},
	["Tricheco Sommozzatore"] = { -- diver walrus: bubbles and a brass helmet glow
		E("bubbles", C(200, 230, 255), { rate = 12 }), E("droplets", C(220, 235, 245)), E("glow", C(230, 190, 60)), E("flare", C(230, 190, 60)), E("aura2", C(130, 160, 180)), E("specs", C(230, 190, 60), { rate = 6 }),
	},
	["Trono Ghiacciato"] = { -- frozen throne: royal gold on ice
		E("rays", GOLD), E("cubes", ICE, { rate = 8 }), E("glare", GOLD, { size = 0.5 }), E("aura3", C(120, 190, 230)), E("stars", WHITE), E("flare", GOLD),
	},
	["Valanga Ruggente"] = { -- roaring avalanche: snow, dust, rocks, a shockwave
		E("snow", WHITE, { rate = 24, speed = NumberRange.new(3, 6) }), E("dust", WHITE, { rate = 14 }), E("rock", C(154, 166, 174)), E("wave", WHITE), E("aura2", C(240, 246, 248), { rate = 8 }),
	},
	["Yeti Cappuccino"] = { -- yeti made of cappuccino: steam and coffee flecks
		E("steam", CREAM), E("specs", COFFEE, { rate = 10 }), E("hearts", CREAM, { rate = 3 }), E("aura1", CREAM, { rate = 8 }), E("glow", C(255, 240, 200)), E("flare", C(255, 240, 200)),
	},
	["Zero Assoluto"] = { -- absolute zero (God): white shards off a black body
		E("cubes", WHITE, { rate = 16, le = 1 }), E("aura1", WHITE, { rate = 12, size = 1.2, le = 1, bright = 3 }), E("rays", C(200, 240, 255)), E("glare", C(200, 240, 255), { size = 0.6 }), E("stars", WHITE), E("flare", WHITE), E("snow", C(200, 240, 255), { rate = 8 }),
	},
}
BrainrotFX.RECIPES = RECIPES

-- ===== build =================================================================
local function packEmitter(modelName, emitterName)
	local folder = ReplicatedStorage:FindFirstChild("BrainrotModels")
	local m = folder and folder:FindFirstChild(modelName)
	if not m then return nil end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("ParticleEmitter") and d.Name == emitterName then return d end
	end
	return nil
end

local function scaleSeq(seq, k)
	local kps = {}
	for i, kp in ipairs(seq.Keypoints) do
		kps[i] = NumberSequenceKeypoint.new(kp.Time, kp.Value * k, kp.Envelope * k)
	end
	return NumberSequence.new(kps)
end

local function makeHost(model, name, cf, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Parent = model
	return p
end

function BrainrotFX.strip(model)
	local n = 0
	for _, name in ipairs({ BrainrotFX.HOST, BrainrotFX.CROWN, BrainrotFX.BASE }) do
		local h = model:FindFirstChild(name)
		while h do
			h:Destroy()
			n += 1
			h = model:FindFirstChild(name)
		end
	end
	model:SetAttribute("FxVersion", nil)
	return n
end

-- rarity: "Legendary" | "Mythic" | "Secret" | "God" (anything else = 1.0)
function BrainrotFX.apply(model, rarity)
	local recipe = RECIPES[model.Name]
	if not recipe then return 0 end
	BrainrotFX.strip(model)
	local boxCF, box = model:GetBoundingBox()
	-- sizes are authored for a 6-stud body (what the plot fit produces); a template
	-- authored taller/shorter scales its emitters when ScaleTo fits it, so pre-divide
	local sizeMul = box.Y / 6
	local intensity = INTENSITY[rarity] or 1

	local hosts = {}
	local function host(kind)
		if hosts[kind] then return hosts[kind] end
		local h
		if kind == "crown" then
			h = makeHost(model, BrainrotFX.CROWN, CFrame.new(boxCF.Position + Vector3.new(0, box.Y * 0.5 - 0.4 * sizeMul, 0)), Vector3.new(1, 1, 1) * sizeMul)
		elseif kind == "base" then
			h = makeHost(model, BrainrotFX.BASE, CFrame.new(boxCF.Position - Vector3.new(0, box.Y * 0.5 - 0.15 * sizeMul, 0)), Vector3.new(box.X * 0.9, 0.2, box.Z * 0.9))
		else
			h = makeHost(model, BrainrotFX.HOST, CFrame.new(boxCF.Position), Vector3.new(box.X * 0.55, box.Y * 0.8, box.Z * 0.55))
		end
		hosts[kind] = h
		return h
	end

	local count = 0
	for _, entry in ipairs(recipe) do
		local kit = KITS[entry.kit]
		local src = kit and packEmitter(kit.src[1], kit.src[2])
		if src then
			local e = src:Clone()
			e.Name = entry.name or entry.kit
			e.Enabled = true
			e.Color = ColorSequence.new(entry.color)
			local rate = entry.rate or kit.rate or src.Rate
			e.Rate = rate * intensity
			local size = (entry.size or kit.size or 1) * sizeMul
			if size ~= 1 then e.Size = scaleSeq(src.Size, size) end
			local le = entry.le or kit.le
			if le then e.LightEmission = le end
			local bright = entry.bright or kit.bright
			if bright then e.Brightness = bright end
			local speed = entry.speed or kit.speed
			if speed then e.Speed = speed end
			local accel = entry.accel or kit.accel
			if accel then e.Acceleration = accel end
			local drag = entry.drag or kit.drag
			if drag then e.Drag = drag end
			local life = entry.life or kit.life
			if life then e.Lifetime = life end
			local spread = entry.spread or kit.spread
			if spread then e.SpreadAngle = spread end
			local locked = entry.locked
			if locked == nil then locked = kit.locked end
			if locked ~= nil then e.LockedToPart = locked end
			e.Parent = host(entry.host or kit.host or "main")
			count += 1
		else
			warn(("BrainrotFX: kit %s source missing for %s"):format(tostring(entry.kit), model.Name))
		end
	end
	model:SetAttribute("FxVersion", BrainrotFX.VERSION)
	return count
end

-- Apply to every recipe'd model in both template folders. rarityOf: name -> rarity.
function BrainrotFX.applyAll(rarityOf)
	local report = {}
	for _, folderName in ipairs({ "BrainrotModels", "BrainrotModelsPlot" }) do
		local folder = ReplicatedStorage:FindFirstChild(folderName)
		if folder then
			for name in pairs(RECIPES) do
				local m = folder:FindFirstChild(name)
				if m then
					local n = BrainrotFX.apply(m, rarityOf and rarityOf[name])
					report[#report + 1] = ("%s/%s: %d"):format(folderName, name, n)
				end
			end
		end
	end
	return report
end

function BrainrotFX.stripAll()
	local total = 0
	for _, folderName in ipairs({ "BrainrotModels", "BrainrotModelsPlot" }) do
		local folder = ReplicatedStorage:FindFirstChild(folderName)
		if folder then
			for _, m in ipairs(folder:GetChildren()) do
				if m:IsA("Model") then total += BrainrotFX.strip(m) end
			end
		end
	end
	return total
end

return BrainrotFX
