-- WheelConfig: the free daily spin.
--
-- Shared deliberately. The client draws the wheel from this exact table and the server
-- rolls from it, so a segment can never show one prize and pay another. The client is
-- told WHICH slot won and animates to it; it never decides the outcome.
--
-- Weights are whole percents and must total 100 -- see the assertion at the bottom.
-- To retune, change the numbers and keep the sum at 100; nothing else needs touching.

local WheelConfig = {}

WheelConfig.COOLDOWN   = 24 * 60 * 60   -- rolling 24h from the last spin, not calendar midnight
WheelConfig.BOOST_TIME = 10 * 60        -- seconds a boost lasts
WheelConfig.BOOST_MULT = 1.30           -- +30%

-- Order here is the order around the wheel, clockwise from the top. The two boosts sit
-- opposite each other and the 1% jackpot sits between two commons, so the pointer is
-- never parked next to two big prizes at once.
-- Each slot carries three separate display strings because the wedge shows all three at
-- different radii, the way a real prize wheel does:
--   Name   big, curved along the outer arc
--   Value  what you actually get, under the icon
--   Short  the compact form, used where space is tight (the world wheel)
-- Colours are deliberately saturated and high-contrast against white outlined text;
-- muted tones read as grey mush at wheel scale.
WheelConfig.SLOTS = {
	{ Id = "Cash1k",    Kind = "Cash",  Amount = 1000,    Weight = 35,
	  Name = "SMALL CASH",  Value = "+$1,000",     Label = "$1,000",     Short = "$1K",
	  Colour = Color3.fromRGB(214, 219, 226), Text = Color3.fromRGB(52, 58, 68), Icon = "\u{1F4B5}" },

	{ Id = "LuckBoost", Kind = "Boost", Stat = "Luck",    Weight = 15,
	  Name = "LUCK BOOST",  Value = "+30%  10 MIN", Label = "30% LUCK",   Short = "LUCK",
	  Colour = Color3.fromRGB(64, 206, 227), Text = Color3.fromRGB(255, 255, 255), Icon = "\u{1F340}" },

	{ Id = "Cash10k",   Kind = "Cash",  Amount = 10000,   Weight = 25,
	  Name = "BIG CASH",    Value = "+$10,000",    Label = "$10,000",    Short = "$10K",
	  Colour = Color3.fromRGB(88, 214, 62),  Text = Color3.fromRGB(255, 255, 255), Icon = "\u{1F4B0}" },

	{ Id = "Cash2500k", Kind = "Cash",  Amount = 2500000, Weight = 1,
	  Name = "JACKPOT",     Value = "+$2,500,000", Label = "$2,500,000", Short = "$2.5M",
	  Colour = Color3.fromRGB(255, 199, 26), Text = Color3.fromRGB(255, 255, 255), Icon = "\u{1F3C6}" },

	{ Id = "PowerBoost",Kind = "Boost", Stat = "Power",   Weight = 15,
	  Name = "POWER BOOST", Value = "+30%  10 MIN", Label = "30% POWER",  Short = "POWER",
	  Colour = Color3.fromRGB(240, 74, 74),  Text = Color3.fromRGB(255, 255, 255), Icon = "\u{1F4AA}" },

	{ Id = "Cash100k",  Kind = "Cash",  Amount = 100000,  Weight = 9,
	  Name = "HUGE CASH",   Value = "+$100,000",   Label = "$100,000",   Short = "$100K",
	  Colour = Color3.fromRGB(178, 96, 232), Text = Color3.fromRGB(255, 255, 255), Icon = "\u{1F48E}" },
}

WheelConfig.TOTAL_WEIGHT = 0
for _, s in ipairs(WheelConfig.SLOTS) do
	WheelConfig.TOTAL_WEIGHT += s.Weight
end

-- Loud on purpose: a wheel whose odds silently stop summing to 100 is the kind of bug
-- nobody notices until players do the maths for you.
assert(WheelConfig.TOTAL_WEIGHT == 100,
	("WheelConfig weights must total 100, got %d"):format(WheelConfig.TOTAL_WEIGHT))

function WheelConfig.SlotById(id)
	for i, s in ipairs(WheelConfig.SLOTS) do
		if s.Id == id then return s, i end
	end
	return nil
end

-- Weighted pick. Server-only in practice, but it lives here so the odds and the labels
-- can never drift apart.
function WheelConfig.Roll(rng)
	local r = (rng and rng:NextNumber() or math.random()) * WheelConfig.TOTAL_WEIGHT
	local cum = 0
	for i, s in ipairs(WheelConfig.SLOTS) do
		cum += s.Weight
		if r <= cum then return i, s end
	end
	return #WheelConfig.SLOTS, WheelConfig.SLOTS[#WheelConfig.SLOTS]
end

-- "1 in 100" reads better than "1%" for the jackpot; used on the prize list.
function WheelConfig.OddsText(slot)
	if slot.Weight >= 10 then return slot.Weight .. "%" end
	return ("%g%%  (1 in %d)"):format(slot.Weight, math.floor(100 / slot.Weight + 0.5))
end

return WheelConfig
