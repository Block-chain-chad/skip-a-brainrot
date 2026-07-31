local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local BrainrotSpawner = require(script.Parent.BrainrotSpawner)

local dataStore = DataStoreService:GetDataStore("BrainrotSkip_PlayerData_v1")

local BASE_SPOTS = 12
local MAX_SPOTS = 16
local SPOT_PRICES = { [13] = 10000, [14] = 50000, [15] = 250000, [16] = 1000000 }

-- Saves outlive renames: BrainrotConfig entries must never be DELETED, but they
-- can be RENAMED, and every save written before a rename still holds the old
-- string. Those records resolve to nil in every entryByName lookup -- the item
-- can't be placed, sold, or traded -- so they are walked forward once per load.
local RENAMES = {
	-- ROSTER REBUILD 2026-07-25: the 213-name Italian roster was replaced by the
	-- 148-model pack. Every retired name maps to a LIVE name of the SAME TIER, at
	-- the same relative position on that tier's power ladder, so a player's
	-- Legendary stays a comparable Legendary instead of silently becoming a
	-- Common. Without this every pre-rebuild item would resolve to nil in
	-- entryByName and be unplaceable, unsellable and untradeable.
	-- Secret Pete is absent on purpose: he survived the rebuild under his own name.
	["Acquedotto Sterminato"] = "Los Tungtungtungcitos",
	["Affogato Ragno"] = "Tipi Topi Taco",
	["Amaca Trottante"] = "Dragon Cannelloni",
	["Amaretto Ghiro"] = "Gattatino Nyanino",
	["Ammazzacaffe Nerissimo"] = "Carloo",
	["Anfiteatro Sgabello"] = "Los Tipi Tacos",
	["Arancino Sgabello"] = "Pipi Corni",
	["Arconte Ricotta"] = "Agarrini la Palini",
	["Astrolabio Abbagliante"] = "Cavallo Virtuoso",
	["Bagnasciuga Illimitato"] = "Nuclearo Dinossauro",
	["Bancarella Tasso"] = "Pandaccini Bananini",
	["Barchetta Orca"] = "Bisonte Giuppitere",
	["Baritono Bruschetta"] = "Los Crocodillitos",
	["Basilico Bombarda"] = "Bandito Axolito",
	["Bastione Struffolo"] = "Los Tacoritas",
	["Batacchio Tuono"] = "Piccione Macchina",
	["Battello Cernia"] = "Espresso Signora",
	["Battistero Cotognata"] = "La Extinct Grande",
	["Bicicletta Piovra"] = "Piccione Macchina",
	["Biscotto Pantofola"] = "Alessio",
	["Boccione Turbine"] = "Cacasito Satalito",
	["Bottega Immortale"] = "Brri Brri Bicus Dicus Bombicus",
	["Bricco Grandine"] = "Brr es Teh Patipum",
	["Broccolo Torpedo"] = "Antonio",
	["Bruschetta Tamburello"] = "Tim Cheese",
	["Bucatino Elettrodotto"] = "Brri Brri Bicus Dicus Bombicus",
	["Bullone Supersonico"] = "Zibra Zubra Zibralini",
	["Burrata Scorpione"] = "Carrotini Brainini",
	["Caffettiera Furiosa"] = "Penguino Cocosino",
	["Calamaro Vulcano"] = "Bombombini Gusini",
	["Calzone Pipistrello"] = "Crabbo Limonetta",
	["Campanaccio Tonante"] = "Tigrilini Watermelini",
	["Campanello Falco"] = "Rhino Toasterino",
	["Campanile Crocchetta"] = "Las Capuchinas",
	["Cannolo Sveglia"] = "Gattito Tacoto",
	["Cantina Grillotalpa"] = "Lionel Cactuseli",
	["Cantuccio Secchio"] = "Avocadini Guffo",
	["Capitano Pentolaccia"] = "Tralalita Tralala",
	["Cappelletto Istrice"] = "Gattatino Nyanino",
	["Caraffa Rovente"] = "Tigroligre Frutonni",
	["Carciofo Cravatta"] = "Dul Dul Dul",
	["Cardinale Pizzocchero"] = "Tracoducotulu Delapeladustuz",
	["Carretto Ululante"] = "Spaghetti Tualetti",
	["Carriola Diluvio"] = "Esok Sekolah",
	["Casciotta Astrale"] = "Blackhole Goat",
	["Castello Magnetico"] = "Chicleteira Bicicleteira",
	["Centurione Polpetta"] = "Los Nooo My Hotspotsitos",
	["Chiacchiera Nevischio"] = "Esok Sekolah",
	["Chiatta Smisurata"] = "Lirilì Larilà",
	["Chinotto Piazzetta"] = "Te Te Te Sahur",
	["Ciabatta Clandestina"] = "Ti Ti Ti Sahur",
	["Cittadella Fiammante"] = "Los Matteos",
	["Colonnato Fotonico"] = "Chef Crabracadabra",
	["Colosseo Cyborgo"] = "Ballerina Cappuccina",
	["Conclave Sanguinaccio"] = "Mythic Lucky Block",
	["Condottiero Piadina"] = "Los Bros",
	["Console Grattugia"] = "Los Chicleteiras",
	["Coppetta Cicala"] = "Spaghetti Tualetti",
	["Corsaro Ombrello"] = "Los Noobinis",
	["Cotoletta Reattore"] = "Bulbito Bandito Traktorito",
	["Crocchetta Mandolino"] = "Svinina Bombardino",
	["Crostino Padella"] = "Avocadorilla",
	["Custode Caffettiera"] = "Las Sis",
	["Despota Grattachecca"] = "Extinct Tralalero",
	["Dirigibile Anguilla"] = "Strawberrelli Flamingelli",
	["Duca Mortadella"] = "Tralalita Tralala",
	["Duomo Zucchina"] = "La Karkerkar Combinasion",
	["Espresso Errante"] = "Te Te Te Sahur",
	["Farfalla Scarabeo"] = "Penguino Cocosino",
	["Ferragosto Nucleare"] = "Tralaledon",
	["Fiasco Tramezzino"] = "Cacto Hipopotamo",
	["Finocchio Bicicletta"] = "Trippi Troppi",
	["Formaggio Missile"] = "Bambini Crostini",
	["Fornello Salamandra"] = "Celularcini Viciosini",
	["Fortezza Siderale"] = "Chef Crabracadabra",
	["Frittata Meccanica"] = "Fluriflura",
	["Frittella Astronave"] = "Orcalero Orcala",
	["Frullatore Cavalletta"] = "Urubini Flamenguini",
	["Funivia Libellula"] = "Unclito Samito",
	["Fusillo Corvo"] = "Fragola La La La",
	["Giardiniera Bussola"] = "Talpa Di Fero",
	["Giudizio Panzerotto"] = "La Sahur Combinasion",
	["Gladiatore Cucchiaio"] = "Los Noobinis",
	["Gondola Turbo"] = "Bambini Crostini",
	["Grammofono Lamentoso"] = "Torrtuginni Dragonfrutini",
	["Grattugia Feroce"] = "Sammyni Spyderini",
	["Grissino Rimbalzante"] = "Gattito Tacoto",
	["Grotta Navicella"] = "Spioniro Golubiro",
	["Idolo Cappelletto"] = "La Sahur Combinasion",
	["Idrante Ionizzato"] = "Tralaledon",
	["Idrovolante Svasso"] = "Trulimero Trulicina",
	["Il Colosso Equinozio"] = "Matteo",
	["Il Firmamento Ribollente"] = "Odin Din Din Dun",
	["Il Papa Meteorite"] = "Tralalero Tralala",
	["Il Tiranno Eclissi"] = "Los Tralaleritos",
	["Il Verdetto Supernova"] = "La Grande Combinasion",
	["Imperatore Focaccia"] = "Chimpanzini Bananini",
	["Ingranaggio Gufo"] = "Sammyni Spyderini",
	["L'Ammiraglio Nebulosa"] = "Secret Lucky Block",
	["La Cattedrale Cometa"] = "Los Combinasionas",
	["La Genesi Corazzata"] = "Brainrot God Lucky Block",
	["La Sentinella Vuoto"] = "La Vacca Saturno Saturnita",
	["Lampione Sonnambulo"] = "Trenostruzzo Turbo 3000",
	["Lardello Ipersonico"] = "Strawberry Elephant",
	["Lasagna Gabbiano"] = "Frigo Camelo",
	["Limoncello Geco"] = "Tukanno Bananno",
	["Loggiato Penombra"] = "Spioniro Golubiro",
	["Maccherone Blindato"] = "Tigroligre Frutonni",
	["Maritozzo Ruggente"] = "Strawberrelli Flamingelli",
	["Martello Idraulico"] = "Gorillo Watermelondrillo",
	["Materasso Slavina"] = "La Cucaracha",
	["Mausoleo Panettone"] = "Girafa Celestre",
	["Megafono Taccola"] = "Unclito Samito",
	["Melanzana Cucchiaio"] = "Sigma Boy",
	["Melodramma Ossobuco"] = "Extinct Ballerina",
	["Michetta Tifone"] = "Bandito Bobritto",
	["Mietitrebbia Solare"] = "Ketchuru and Musturu",
	["Minestrone Carriola"] = "Talpa Di Fero",
	["Monarca Zeppola"] = "Los Bombinitos",
	["Monolito Semifreddo"] = "Extinct Matteo",
	["Mortadella Danzante"] = "Salamino Penguino",
	["Mostacciolo Fantasma"] = "Boneca Ambalabu",
	["Motorino Squalo"] = "Bandito Axolito",
	["Nocciola Specchio"] = "Pipi Potato",
	["Obelisco Tagliatella"] = "Los Spyderinis",
	["Oliva Forchetta"] = "Dug dug dug",
	["Oracolo Cassata"] = "Cocofanto Elefanto",
	["Orecchietta Furgone"] = "To to to Sahur",
	["Orologio Lucciola"] = "Lionel Cactuseli",
	["Ossario Panforte"] = "Taco Lucky Block",
	["Padella Stambecco"] = "Job Job Job Sahur",
	["Pancetta Riccio"] = "Caramello Filtrello",
	["Panchetto Tornado"] = "Burbaloni Loliloli",
	["Pandoro Tazzina"] = "Chihuanini Taconini",
	["Panino Kraken"] = "Bombombini Gusini",
	["Panzanella Ocarina"] = "Tim Cheese",
	["Panzerotto Cuscino"] = "Alessio",
	["Parapioggia Uragano"] = "La Cucaracha",
	["Parmigiano Ramarro"] = "Carrotini Brainini",
	["Pecorino Trattore"] = "Sigma Boy",
	["Pentola Fiammante"] = "Perochello Lemonchello",
	["Peperone Rastrello"] = "Lerulerulerule",
	["Periscopio Procella"] = "Espresso Signora",
	["Peschereccio Vongola"] = "Rhino Toasterino",
	["Pesto Falconetto"] = "Ketupat Kepat",
	["Piadina Bullone"] = "Avocadorilla",
	["Pizzarino Volante"] = "67",
	["Polenta Fischietto"] = "Chachechi",
	["Polpetta Baldanzosa"] = "Fluriflura",
	["Pomodoro Slitta"] = "Dul Dul Dul",
	["Pontefice Stracciatella"] = "Cocofanto Elefanto",
	["Porchetta Murena"] = "Perochello Lemonchello",
	["Progenitore Zuppa"] = "Tung Tung Tung Sahur",
	["Prosciutto Calabrone"] = "Bananita Dolphinita",
	["Provolone Bottiglia"] = "Sigma Girl",
	["Radicchio Galoppante"] = "Tric Trac Baraboom",
	["Reliquiario Zuccotto"] = "La Extinct Grande",
	["Ricotta Ombrello"] = "Salamino Penguino",
	["Risotto Granchio"] = "Bananita Dolphinita",
	["Rucola Cappello"] = "Trippi Troppi",
	["Salame Donnola"] = "Frigo Camelo",
	["Salsiccia Spietata"] = "Celularcini Viciosini",
	["Santuario Sfogliatella"] = "Graipuss Medussi",
	["Sbattitore Torpedine"] = "Ganganzelli Trulala",
	["Scaldabagno Stellare"] = "Garama and Madundung",
	["Scamorza Barchetta"] = "Noobini Pizzanini",
	["Scarpa Volante"] = "Carloo",
	["Scodella Temibile"] = "Orangutini Ananassini",
	["Scopa Civetta"] = "Orangutini Ananassini",
	["Secchio Aragosta"] = "Karkerkar Kurkur",
	["Seggiovia Gambero"] = "Pot Hotspot",
	["Semifreddo Zattera"] = "Pipi Corni",
	["Senatore Bottiglia"] = "Los Hotspotsitos",
	["Setaccio Tarantola"] = "Pakrahmatmamat",
	["Sfogliatella Vaporosa"] = "Cacto Hipopotamo",
	["Sgroppino Sovversivo"] = "Chicleteira Bicicleteira",
	["Simulacro Ciabatta"] = "Las Tralaleritas",
	["Slitta Terremoto"] = "Quivioli Ameleonni",
	["Soppressata Valanga"] = "Bandito Bobritto",
	["Sottomarino Tarabuso"] = "Trulimero Trulicina",
	["Sovrano Pancetta"] = "Los Bombinitos",
	["Specchio Costellazione"] = "Glorbo Fruttodrillo",
	["Stracciatella Dado"] = "Pipi Avocado",
	["Struffolo Candela"] = "Pipi Potato",
	["Sua Altezza Galassia"] = "Las Vaquitas Saturnitas",
	["Sua Grazia Abisso"] = "Admin Lucky Block",
	["Tabaccheria Quantistica"] = "Nuclearo Dinossauro",
	["Tagliatella Storione"] = "Gangster Footera",
	["Taleggio Automatico"] = "Pipi Avocado",
	["Tamburello Balistico"] = "Zibra Zubra Zibralini",
	["Teiera Pettirosso"] = "Tukanno Bananno",
	["Tempesta Cannolo"] = "Los Crocodillitos",
	["Titano Mozzarella"] = "Bombardiro Crocodilo",
	["Torcetto Cinghiale"] = "Gangster Footera",
	["Torrone Zoccolo"] = "Ta Ta Ta Ta Sahur",
	["Tortellino Coperta"] = "Ti Ti Ti Sahur",
	["Tovaglia Serpeggiante"] = "Tigrilini Watermelini",
	["Traghetto Balena"] = "Karkerkar Kurkur",
	["Trattore Maremoto"] = "Burbaloni Loliloli",
	["Trattoria Perpetua"] = "Trippi Troppi Troppa Trippa",
	["Trombino Spaghetto"] = "Avocadini Antilopini",
	["Vaporetto Antimateria"] = "Garama and Madundung",
	["Verricello Sbraitante"] = "Dragon Cannelloni",
	["Vespa Dragonessa"] = "Ballerino Lololo",
	["Vesuvio Tortellino"] = "Los Orcalitos",
	["Vulcano Spaghettoni"] = "Cappuccino Assassino",
	["Zabaione Ellittico"] = "Lirilì Larilà",
	["Zampogna Tellurica"] = "Guerriro Digitale",
	["Zappetta Mantide"] = "Crabbo Limonetta",
	["Zeppola Cannocchiale"] = "Pipi Kiwi",
	["Zolletta Lucertola"] = "Blueberrinni Octopusini",
	["Zuccherino Cosmico"] = "Brr Brr Patapim",
	["Zucchina Pomposa"] = "Lerulerulerule",
}

local PlayerDataManager = {}
PlayerDataManager.cache = {} -- [userId] = data table

-- canonical abbreviator, K through Qi -- see Modules.NumberFormat
local formatShort = require(ReplicatedStorage.Modules.NumberFormat).Short

local function defaultData()
	return {
		Cash = 0,
		OwnedRocks = { Pebble = true },
		EquippedRock = "Pebble",
		Brainrots = {}, -- array of { Name = string, PadIndex = number?, Mutation = string? }
		UnlockedSpots = BASE_SPOTS,
		-- daily login rewards
		DailyStreak = 0,
		LastClaimDay = 0,
		LastFreezeDay = 0, -- last day the streak-freeze grace was used
		RedeemedCodes = {}, -- [CODE] = true
		-- daily quests
		Quests = {}, -- [questId] = { claimed = bool }
		QuestDay = 0,
		-- Gianluca's Secret Chim questline:
		--   0 = not started  1 = active (searching)  2 = holding the Chim
		--   3 = handed the Chim back to Gianluca and took the Key
		ChimQuest = 0,
		-- Gianluca's Keys. Awarded for handing the Chim back. Counted rather than a
		-- Backpack Tool because Tools in this game are brainrots and only brainrots --
		-- InventoryHandler.SyncBackpack rebuilds that list from data.Brainrots and would
		-- destroy any non-brainrot Tool on the next sync.
		Keys = 0,
		-- prestige
		Rebirths = 0,
		-- Maxwell the cat's secret questline (see MaxwellQuest):
		--   0 = locked/greeting  1 = collecting 5 Secret catches  2 = reach Rebirth 15
		--   3 = reward ready to claim  4 = done, God Maxwell awarded
		MaxwellQuest = 0,
		MaxwellSecrets = 0,   -- Secret-rarity catches counted while MaxwellQuest == 1
		-- rarity pity: [tierName] = throws-since-last-catch of that tier (see PityConfig)
		Pity = {},
		-- brainrot index: [name] = true once caught
		Discovered = {},
		-- purchased upgrade levels: [id] = level
		Upgrades = {},
		-- first-time onboarding shown?
		TutorialDone = false,
		-- rolling id so each brainrot can own a Backpack tool
		NextUid = 1,
		-- unix time of last save, for offline earnings
		LastSeen = 0,
		-- brainrots burned into the campfire as Offerings (permanent luck, diminishing)
		Offerings = 0,
		-- season pass
		SeasonXP = 0,
		SeasonClaimed = {}, -- [tostring(tier)] = true
		SeasonQuests = {}, -- [questId] = { P = n, D = bool }, resets daily
		SeasonQuestDay = 0,
		-- === camp board (2026-07-24) ===
		TotalEarned = 0,      -- lifetime cash PRODUCED by this player's brainrots; survives rebirth
		PlotLikes = 0,        -- lifetime likes received on this player's camp
		LikedPlayers = {},    -- [tostring(otherUserId)] = true : camps I have already liked
		-- === global leaderboards (2026-07-25) ===
		LifetimeEarned = 0,   -- ALL money ever received, from every source. This is what the
		                      -- leaderboard means by "earned"; TotalEarned above is narrower
		                      -- (production only) and must stay that way, because the camp
		                      -- board and offline earnings are built on it.
		TimePlayed = 0,       -- lifetime seconds in game. Accumulated on a timer rather than
		                      -- measured on leave: Main's PlayerRemoving saves before any
		                      -- later-Init'd handler could flush a session length.
		BrainrotsCaught = 0,  -- lifetime CATCHES. Trades, booth buys and offerings deliberately
		                      -- do not count -- this is meant to measure throwing, not acquiring.
		-- === daily wheel (2026-07-25) ===
		LastSpinAt = 0,       -- os.time() of the last free spin; 0 means never spun
		Boosts = {},          -- ["Luck"|"Power"] = os.time() the boost expires. Real-time, so a
		                      -- 10 minute boost does not pause when the player logs off.
	}
end

function PlayerDataManager.Get(player)
	return PlayerDataManager.cache[player.UserId]
end

function PlayerDataManager.GetPlot(player)
	local plotsFolder = Workspace:FindFirstChild("PlayerBases")
	if not plotsFolder then return nil end
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot
		end
	end
	return nil
end

function PlayerDataManager.TakeUid(data)
	data.NextUid = data.NextUid or 1
	local id = data.NextUid
	data.NextUid = id + 1
	return id
end

function PlayerDataManager.FindFreePad(data)
	local used = {}
	for _, entry in ipairs(data.Brainrots) do
		if entry.PadIndex then
			used[entry.PadIndex] = true
		end
	end
	local limit = math.min(data.UnlockedSpots or BASE_SPOTS, MAX_SPOTS)
	for i = 1, limit do
		if not used[i] then
			return i
		end
	end
	return nil
end

-- Show/refresh which plot spots are open vs locked (with buy prompts) for the owner
function PlayerDataManager.RefreshPlotSpots(player)
	local data = PlayerDataManager.cache[player.UserId]
	local plot = PlayerDataManager.GetPlot(player)
	if not data or not plot then return end
	local pads = plot:FindFirstChild("Pads")
	if not pads then return end
	local unlocked = data.UnlockedSpots or BASE_SPOTS

	for i = 1, MAX_SPOTS do
		local pad = pads:FindFirstChild("Pad" .. i)
		if pad then
			local oldGui = pad:FindFirstChild("LockGui")
			if oldGui then oldGui:Destroy() end
			local oldPrompt = pad:FindFirstChildOfClass("ProximityPrompt")
			if oldPrompt then oldPrompt:Destroy() end

			-- SmoothPlastic, not Metal/Slate: this runs on every refresh and would
			-- otherwise repaint the pads back over the flat-cartoon art pass.
			if i <= unlocked then
				pad.Color = Color3.fromRGB(150, 154, 166)
				pad.Material = Enum.Material.SmoothPlastic
				pad.Transparency = 0
			else
				pad.Color = ((i == unlocked + 1) and Color3.fromRGB(214, 164, 78) or Color3.fromRGB(122, 112, 122))
				pad.Material = Enum.Material.SmoothPlastic
				pad.Transparency = ((i == unlocked + 1) and 0 or 0.45)
				local price = SPOT_PRICES[i] or 0
				local isNext = (i == unlocked + 1)

				local gui = Instance.new("BillboardGui")
				gui.Name = "LockGui"
				gui.Size = UDim2.new(0, 130, 0, 46)
				gui.StudsOffset = Vector3.new(0, 3, 0)
				gui.AlwaysOnTop = true
				-- Must be set here: RefreshPlotSpots destroys and rebuilds these on every spot
				-- purchase and on load, so a value authored in Studio would not survive.
				-- 150 to match the campfire BankGui and the pad name tags on the same plot.
				gui.MaxDistance = 150
				gui.Parent = pad
				local label = Instance.new("TextLabel")
				label.Size = UDim2.new(1, 0, 1, 0)
				label.BackgroundTransparency = 1
				label.TextColor3 = isNext and Color3.fromRGB(255, 220, 90) or Color3.fromRGB(132, 132, 148)
				label.TextStrokeTransparency = 0
				label.Font = Enum.Font.GothamBold
				label.TextScaled = true
				label.Text = isNext and ("\u{1F512} Buy Spot\n$" .. formatShort(price)) or ("\u{1F512} $" .. formatShort(price) .. "\nUnlock #" .. (unlocked + 1) .. " first")
				label.Parent = gui

				if isNext then
					local prompt = Instance.new("ProximityPrompt")
					prompt.Name = "BuySpotPrompt"
					prompt.ActionText = "Buy ($" .. formatShort(price) .. ")"
					prompt.ObjectText = "Plot Spot " .. i
					prompt.HoldDuration = 0.3
					prompt.MaxActivationDistance = 14
					prompt.RequiresLineOfSight = false
					prompt.Parent = pad
					prompt.Triggered:Connect(function(triggerPlayer)
						if triggerPlayer == player then
							PlayerDataManager.TryBuySpot(player)
						end
					end)
				end
			end
		end
	end
end

function PlayerDataManager.TryBuySpot(player)
	local data = PlayerDataManager.cache[player.UserId]
	if not data then return end
	local unlocked = data.UnlockedSpots or BASE_SPOTS
	local nextSpot = unlocked + 1
	if nextSpot > MAX_SPOTS then return end
	local price = SPOT_PRICES[nextSpot]
	if not price then return end

	local result = ReplicatedStorage.Remotes:FindFirstChild("PurchaseResult")
	if data.Cash < price then
		if result then
			result:FireClient(player, { Success = false, Message = "Need $" .. formatShort(price) .. " to unlock spot " .. nextSpot })
		end
		return
	end

	data.Cash -= price
	data.UnlockedSpots = nextSpot
	PlayerDataManager.RefreshPlotSpots(player)
	if result then
		result:FireClient(player, { Success = true, Message = "Unlocked plot spot " .. nextSpot .. "!" })
	end
	PlayerDataManager.PushUpdate(player)
end

-- Camp board state lives as attributes on the plot Model; the client renders it.
local function refreshPlotBoard(plot, player)
	if not plot then return end
	if not player then
		plot:SetAttribute("OwnerName", "")
		plot:SetAttribute("TotalEarned", 0)
		plot:SetAttribute("PlotLikes", 0)
		return
	end
	local d = PlayerDataManager.cache[player.UserId]
	plot:SetAttribute("OwnerName", string.sub(player.DisplayName or player.Name, 1, 18))
	plot:SetAttribute("TotalEarned", math.floor((d and d.TotalEarned) or 0))
	plot:SetAttribute("PlotLikes", math.floor((d and d.PlotLikes) or 0))
end

local function releasePlot(player)
	local plot = PlayerDataManager.GetPlot(player)
	if not plot then return end
	local pads = plot:FindFirstChild("Pads")
	if pads then
		for _, child in ipairs(pads:GetChildren()) do
			if not child.Name:match("^Pad%d+$") then
				child:Destroy() -- brainrot models
			else
				local lock = child:FindFirstChild("LockGui")
				if lock then lock:Destroy() end
				local prompt = child:FindFirstChildOfClass("ProximityPrompt")
				if prompt then prompt:Destroy() end
			end
		end
	end
	plot:SetAttribute("Claimed", false)
	plot:SetAttribute("OwnerUserId", 0)
	refreshPlotBoard(plot, nil)
	local campfire = plot:FindFirstChild("Campfire")
	if campfire then
		campfire:SetAttribute("Banked", 0)
	end
end

function PlayerDataManager.Snapshot(player)
	local data = PlayerDataManager.cache[player.UserId]
	if not data then return nil end
	return {
		Cash = data.Cash,
		OwnedRocks = data.OwnedRocks,
		EquippedRock = data.EquippedRock,
		Brainrots = data.Brainrots,
		UnlockedSpots = data.UnlockedSpots,
		Discovered = data.Discovered,
		Upgrades = data.Upgrades,
		TutorialDone = data.TutorialDone,
		Rebirths = data.Rebirths,
		TotalEarned = data.TotalEarned,
		Offerings = data.Offerings,
		PlotLikes = data.PlotLikes,
		LikedPlayers = data.LikedPlayers,
		Keys = data.Keys,
	}
end

function PlayerDataManager.Load(player)
	local data
	local ok, result = pcall(function()
		return dataStore:GetAsync("Player_" .. player.UserId)
	end)
	if ok and result then
		data = result
		if not data.OwnedRocks then data.OwnedRocks = { Pebble = true } end
		if not data.EquippedRock then data.EquippedRock = "Pebble" end
		if not data.Brainrots then data.Brainrots = {} end
		if not data.UnlockedSpots then data.UnlockedSpots = BASE_SPOTS end
		if not data.DailyStreak then data.DailyStreak = 0 end
		if not data.LastClaimDay then data.LastClaimDay = 0 end
		if not data.Quests then data.Quests = {} end
		if data.ChimQuest == nil then data.ChimQuest = 0 end
		if type(data.Keys) ~= "number" then data.Keys = 0 end
		if not data.QuestDay then data.QuestDay = 0 end
		if not data.Rebirths then data.Rebirths = 0 end
		if data.MaxwellQuest == nil then data.MaxwellQuest = 0 end
		if type(data.MaxwellSecrets) ~= "number" then data.MaxwellSecrets = 0 end
		if type(data.Pity) ~= "table" then data.Pity = {} end
		if not data.Discovered then data.Discovered = {} end
		if not data.Upgrades then data.Upgrades = {} end
		if data.TutorialDone == nil then data.TutorialDone = false end
		if not data.LastSeen then data.LastSeen = 0 end
		if not data.LastFreezeDay then data.LastFreezeDay = 0 end
		if not data.RedeemedCodes then data.RedeemedCodes = {} end
		if not data.SeasonXP then data.SeasonXP = 0 end
		if not data.SeasonClaimed then data.SeasonClaimed = {} end
		if not data.SeasonQuests then data.SeasonQuests = {} end
		if not data.SeasonQuestDay then data.SeasonQuestDay = 0 end
		if type(data.Offerings) ~= "number" then data.Offerings = 0 end
		if type(data.TotalEarned) ~= "number" then data.TotalEarned = 0 end
		if type(data.PlotLikes) ~= "number" then data.PlotLikes = 0 end
		if type(data.LikedPlayers) ~= "table" then data.LikedPlayers = {} end
		if type(data.LifetimeEarned) ~= "number" then
			-- One-time estimate for saves predating this field. Money already SPENT is not
			-- recoverable from anything stored, so take the best available floor: you have
			-- earned at least what you are holding, and at least what you produced.
			data.LifetimeEarned = math.max(tonumber(data.Cash) or 0, tonumber(data.TotalEarned) or 0)
		end
		if type(data.TimePlayed) ~= "number" then data.TimePlayed = 0 end
		if type(data.BrainrotsCaught) ~= "number" then data.BrainrotsCaught = 0 end
		if type(data.LastSpinAt) ~= "number" then data.LastSpinAt = 0 end
		if type(data.Boosts) ~= "table" then data.Boosts = {} end
		data.NextUid = data.NextUid or 1
		for _, e in ipairs(data.Brainrots) do
			if RENAMES[e.Name] then e.Name = RENAMES[e.Name] end
			if not e.Uid then e.Uid = data.NextUid; data.NextUid += 1 end
			-- Discovery backfill: the Discovered flag was never written before
			-- 2026-07-25, so owning a copy is the only proof the catch happened.
			data.Discovered[e.Name] = true
		end
		-- Renames must walk EVERY place a config name is persisted. Ancient saves
		-- carry Discovered keys written by an early build (the writer was later
		-- lost in a refactor), so old names can lurk here even when no owned
		-- record does.
		for oldName, newName in pairs(RENAMES) do
			if data.Discovered[oldName] then
				data.Discovered[oldName] = nil
				data.Discovered[newName] = true
			end
		end
	elseif ok then
		data = defaultData()                 -- genuinely a new player: empty read, no error
	else
		data = defaultData()
		data.__noSave = true                 -- DataStore READ FAILED: never overwrite the real profile
		warn("[PlayerDataManager] load failed for " .. player.Name .. "; session is read-only")
	end
	PlayerDataManager.cache[player.UserId] = data

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cashStat = Instance.new("NumberValue")
	cashStat.Name = "Cash"
	cashStat.Value = data.Cash
	cashStat.Parent = leaderstats
	leaderstats.Parent = player

	PlayerDataManager.RefreshPlotSpots(player)

	return data
end

function PlayerDataManager.SyncLeaderstat(player)
	local data = PlayerDataManager.cache[player.UserId]
	if not data then return end
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local cashStat = leaderstats:FindFirstChild("Cash")
		if cashStat then
			cashStat.Value = data.Cash
		end
	end
end

-- Single funnel for lifetime earnings. Cash grants that are NOT production
-- (trades, booth sales, daily/quest/season/codes, sell) must not call this.
-- Returns the amount actually credited (0 on failure) so callers can verify.
function PlayerDataManager.AddEarnings(player, amount, dataOpt)
	-- `player and` guard: every spec'd caller passes dataOpt so this short-circuits,
	-- but without it a nil player throws instead of returning 0. See DEVIATIONS.
	local data = dataOpt or (player and PlayerDataManager.cache[player.UserId])
	if not data or type(amount) ~= "number" or amount ~= amount or amount <= 0 then return 0 end
	data.Cash += amount
	data.TotalEarned = (data.TotalEarned or 0) + amount
	data.LifetimeEarned = (data.LifetimeEarned or 0) + amount
	return amount
end

-- The funnel for every NON-production cash grant: sells, booth proceeds, daily rewards,
-- codes, quests, season pass. Exists so LifetimeEarned stays honest without widening
-- AddEarnings, whose narrower meaning other systems depend on.
--
-- Spending must NOT go through here -- subtract from data.Cash directly, the way
-- BoothHandler does for the buyer.
-- Multiplier from a timed wheel boost, or 1 when none is running. Reads os.time() every
-- call rather than caching, so an expiring boost stops mattering mid-session with no
-- tick or cleanup task anywhere.
function PlayerDataManager.BoostMult(data, stat)
	if not data or type(data.Boosts) ~= "table" then return 1 end
	local expiry = tonumber(data.Boosts[stat])
	if not expiry or os.time() >= expiry then return 1 end
	local WheelConfig = require(game:GetService("ReplicatedStorage").Modules.WheelConfig)
	return WheelConfig.BOOST_MULT
end

-- Seconds left on a boost, or 0. For the HUD.
function PlayerDataManager.BoostRemaining(data, stat)
	if not data or type(data.Boosts) ~= "table" then return 0 end
	local expiry = tonumber(data.Boosts[stat])
	if not expiry then return 0 end
	return math.max(0, expiry - os.time())
end

function PlayerDataManager.GrantCash(data, amount)
	if not data or type(amount) ~= "number" or amount ~= amount or amount <= 0 then return 0 end
	data.Cash += amount
	data.LifetimeEarned = (data.LifetimeEarned or 0) + amount
	return amount
end

-- Drains a brainrot entry's banked Pending into the owner's cash + lifetime
-- earnings. Call this immediately BEFORE removing or unplacing the entry.
function PlayerDataManager.DrainPending(player, entry, dataOpt)
	if not entry then return 0 end
	local pend = math.floor(entry.Pending or 0)
	entry.Pending = 0
	if pend < 1 then return 0 end
	return PlayerDataManager.AddEarnings(player, pend, dataOpt)
end

function PlayerDataManager.PushUpdate(player)
	PlayerDataManager.SyncLeaderstat(player)
	local data = PlayerDataManager.cache[player.UserId]
	if data and data.Discovered then
		-- Discovery is recorded HERE because every acquisition path (catch, trade,
		-- booth, fusion, wheel) already ends in a PushUpdate: one merge point
		-- instead of five handler edits. The set only ever grows, so selling or
		-- trading away your last copy can never un-discover a name.
		for _, e in ipairs(data.Brainrots) do
			data.Discovered[e.Name] = true
		end
	end
	local snapshot = PlayerDataManager.Snapshot(player)
	if snapshot then
		ReplicatedStorage.Remotes.DataUpdated:FireClient(player, snapshot)
	end
end

-- Returns true if the write landed. Callers that move items BETWEEN players
-- (trades, booth sales) must check this: two independent SetAsync calls with no
-- retry meant a failed giver-write plus a successful receiver-write duplicated
-- the item silently, and duped items poison the whole class because nobody can
-- tell an honest copy from a forged one.
function PlayerDataManager.Save(player)
	local data = PlayerDataManager.cache[player.UserId]
	if not data then return false end
	if data.__noSave then return false end  -- load failed; writing would wipe the real profile
	data.LastSeen = os.time()
	local key = "Player_" .. player.UserId
	for attempt = 1, 3 do
		-- UpdateAsync over SetAsync: it is transactional per key and retries on conflict
		local ok, err = pcall(function()
			dataStore:UpdateAsync(key, function()
				return data
			end)
		end)
		if ok then return true end
		if attempt == 3 then
			warn(("[PlayerDataManager] save FAILED for %s after 3 attempts: %s"):format(player.Name, tostring(err)))
		else
			task.wait(0.4 * attempt)
		end
	end
	return false
end

function PlayerDataManager.Remove(player)
	releasePlot(player)                 -- stop accepting likes BEFORE the SetAsync yield
	PlayerDataManager.Save(player)
	PlayerDataManager.cache[player.UserId] = nil
end

-- === Tycoon-style claiming: walk onto a free plot to claim it ===
function PlayerDataManager.ClaimPlotFor(player, plot)
	if not plot or plot:GetAttribute("Claimed") then return false end
	if PlayerDataManager.GetPlot(player) then return false end
	plot:SetAttribute("OwnerUserId", player.UserId)
	refreshPlotBoard(plot, player)
	plot:SetAttribute("Claimed", true)
	PlayerDataManager.RefreshPlotSpots(player)
	local data = PlayerDataManager.cache[player.UserId]
	if data and data.Brainrots then
		BrainrotSpawner.RestoreAll(plot, data.Brainrots)
	end
	if PlayerDataManager.OnPlotClaimed then PlayerDataManager.OnPlotClaimed(player) end
	local result = ReplicatedStorage.Remotes:FindFirstChild("PurchaseResult")
	if result then
		result:FireClient(player, { Success = true, Message = "Base claimed!" })
	end
	return true
end

local claimCooldown = {}
local function tryClaimByTouch(plot, hit)
	local character = hit and hit.Parent
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end
	if plot:GetAttribute("Claimed") then return end
	if PlayerDataManager.GetPlot(player) then return end
	if claimCooldown[player.UserId] then return end
	claimCooldown[player.UserId] = true
	task.delay(1, function() claimCooldown[player.UserId] = nil end)
	PlayerDataManager.ClaimPlotFor(player, plot)
end

do
	local plotsFolder = Workspace:FindFirstChild("PlayerBases")
	if plotsFolder then
		for _, plot in ipairs(plotsFolder:GetChildren()) do
			if plot:IsA("Model") then
				local pad = plot.PrimaryPart or plot:FindFirstChild("Platform")
				if pad then
					pad.Touched:Connect(function(hit) tryClaimByTouch(plot, hit) end)
				end
			end
		end
	end
end

return PlayerDataManager
