-- NumberFormat: the ONE abbreviator for player-facing cash.
--
-- Replaces nine near-identical local copies (formatShort x4, formatNumber x4,
-- shorten x1) that had already drifted apart -- %.1fB vs %.2fB, %.0fK vs %.1fK --
-- and all capped at B. A single Secret earning 9.99B/s reaches a trillion in 100
-- seconds, so the missing tiers were about to render live balances as "86400.0B".
--
-- Two deliberate choices:
--  * TRUNCATES, never rounds. Currency must not read higher than it is, and
--    9,999,999,999 has to show as "9.99B" rather than rounding up to "10.00B".
--  * nil/NaN/negative safe. Callers read straight off replicated attributes that
--    can be nil for a frame (see PlotSignClient), and a formatter is the wrong
--    place to throw.

local NumberFormat = {}

-- descending: first threshold that fits wins.
--
-- Sx/Sp were added 2026-08-15 with World 2's 21-rock ladder: its top rock is 29e21,
-- which without a sextillion unit renders as "29000.00Qi". Standard short-scale
-- abbreviations, so the sequence stays guessable past the point players stop
-- recognising the words.
local UNITS = {
	{ 1e24, "Sp" },
	{ 1e21, "Sx" },
	{ 1e18, "Qi" },
	{ 1e15, "Qa" },
	{ 1e12, "T"  },
	{ 1e9,  "B"  },
	{ 1e6,  "M"  },
	{ 1e3,  "K"  },
}

-- Truncate to 2 decimals. Done on the DIVIDED value (e.g. 9.999999999) where the
-- magnitude is small, so the multiply cannot lose precision the way it would on
-- the raw 1e10+ input.
local function trunc2(x)
	return math.floor(x * 100) / 100
end

-- 1234 -> "1.23K"   9999999999 -> "9.99B"   8.64e13 -> "86.40T"
function NumberFormat.Short(n)
	if type(n) ~= "number" or n ~= n then return "0" end   -- nil, non-number, NaN
	if n == math.huge then return "\u{221E}" end
	if n == -math.huge then return "-\u{221E}" end

	local sign = n < 0 and "-" or ""
	n = math.abs(n)

	for _, unit in ipairs(UNITS) do
		local threshold, suffix = unit[1], unit[2]
		if n >= threshold then
			return sign .. string.format("%.2f%s", trunc2(n / threshold), suffix)
		end
	end
	return sign .. tostring(math.floor(n))
end

-- "$9.99B" -- the prefix every call site was gluing on by hand
function NumberFormat.Cash(n)
	return "$" .. NumberFormat.Short(n)
end

-- "+9.99B/s" for rate lines. Sub-1000 rates keep a decimal, because most of the
-- roster sits between 1 and 1000 and "+1/s" vs "+1.03/s" is a real difference there.
function NumberFormat.Rate(cps)
	if type(cps) ~= "number" or cps ~= cps then return "+0/s" end
	if cps >= 1000 then return "+" .. NumberFormat.Short(cps) .. "/s" end
	if cps == math.floor(cps) then return "+" .. tostring(math.floor(cps)) .. "/s" end
	return string.format("+%.1f/s", cps)
end

return NumberFormat
