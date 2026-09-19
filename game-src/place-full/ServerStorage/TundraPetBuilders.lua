-- Straight transliterations of the handoff's pets.js builder functions. Every number is
-- the JS number; units stay in the handoff's metres and TundraPetKit applies the stud
-- conversion once, at realise() time. Keep these line-comparable with the source.
local B = {}

function B.penguin(K)
	local g = K.group("penguin")
	K.at(g, K.sph(0.42, K.M.ink, "body", {1, 1.24, 0.92}), 0, 0.54)
	K.at(g, K.sph(0.36, K.M.snow, "belly", {0.88, 1.1, 0.72}), 0, 0.52, 0.15)
	K.at(g, K.sph(0.36, K.M.ink, "head", {1, 0.96, 0.96}), 0, 1.14)
	K.at(g, K.sph(0.3, K.M.snow, "face", {0.86, 0.86, 0.6}), 0, 1.09, 0.13)
	K.at(g, K.cone(0.1, 0.22, K.M.amber, "beak"), 0, 1.06, 0.36, math.pi/2)
	K.eyes(g, 1.22, 0.29, 0.13)
	K.pair(g, function() return K.sph(0.23, K.M.ink, "flipper", {0.28, 1, 0.55}) end, 0.41, 0.54, 0, 0, 0, 0.3)
	K.pair(g, function() return K.box(0.2, 0.1, 0.3, K.M.amber, "foot") end, 0.17, 0.05, 0.16)
	for _, s in ipairs({-1, 1}) do
		K.studs(g, K.M.amber, { x = s*0.17, z = 0.16, y = 0.1, d = 0.16, nx = 1, nz = 2, r = 0.055 })
	end
	return g
end

function B.fox(K)
	local g = K.group("fox")
	K.at(g, K.sph(0.34, K.M.snow, "body", {1.05, 0.95, 1.25}), 0, 0.52)
	K.at(g, K.sph(0.33, K.M.snow, "head", {1.02, 0.96, 0.96}), 0, 1.02, 0.08)
	K.at(g, K.sph(0.16, K.M.frost, "snout", {0.72, 0.6, 1.1}), 0, 0.94, 0.34)
	K.at(g, K.sph(0.068, K.M.ink, "nose", {1.2, 0.9, 1}), 0, 0.96, 0.5)
	K.smile(g, 0.86, 0.46, 0.055)
	K.pair(g, function() return K.cone(0.13, 0.32, K.M.snow, "ear") end, 0.19, 1.3, 0.03, 0, 0, 0.22)
	K.pair(g, function() return K.cone(0.075, 0.2, K.M.blush, "earInner") end, 0.185, 1.29, 0.09, 0, 0, 0.22)
	K.eyes(g, 1.07, 0.32, 0.135)
	K.at(g, K.sph(0.21, K.M.snow, "tail", {0.8, 0.8, 1.5}), 0, 0.58, -0.44, -0.25)
	K.at(g, K.sph(0.15, K.M.frost, "tailTip"), 0, 0.7, -0.72)
	K.pair(g, function() return K.cyl(0.075, 0.08, 0.32, K.M.snow, "legFront") end, 0.17, 0.16, 0.22)
	K.pair(g, function() return K.cyl(0.075, 0.08, 0.32, K.M.snow, "legBack") end, 0.19, 0.16, -0.2)
	K.pair(g, function() return K.box(0.16, 0.09, 0.23, K.M.frost, "paw") end, 0.17, 0.045, 0.24)
	K.pair(g, function() return K.box(0.16, 0.09, 0.23, K.M.frost, "paw") end, 0.19, 0.045, -0.18)
	for _, s in ipairs({-1, 1}) do
		K.studs(g, K.M.frost, { x = s*0.17, z = 0.29, y = 0.09, nx = 1, nz = 1, r = 0.055 })
		K.studs(g, K.M.frost, { x = s*0.19, z = -0.13, y = 0.09, nx = 1, nz = 1, r = 0.055 })
	end
	return g
end

function B.hare(K)
	local g = K.group("hare")
	K.at(g, K.sph(0.33, K.M.snow, "body", {1, 1.12, 1}), 0, 0.46)
	K.at(g, K.sph(0.28, K.M.snow, "head", {1.05, 0.98, 0.98}), 0, 0.96)
	K.pair(g, function() return K.sph(0.13, K.M.snow, "cheek") end, 0.15, 0.91, 0.14)
	K.at(g, K.sph(0.05, K.M.blush, "nose"), 0, 0.95, 0.28)
	K.eyes(g, 1.02, 0.23, 0.12, 0.07)
	K.pair(g, function() return K.sph(0.1, K.M.snow, "ear", {0.55, 2.7, 0.34}) end, 0.12, 1.36, -0.02, 0, 0, 0.11)
	K.pair(g, function() return K.sph(0.09, K.M.blush, "earInner", {0.4, 2.4, 0.2}) end, 0.115, 1.36, 0.03, 0, 0, 0.11)
	K.pair(g, function() return K.box(0.17, 0.11, 0.34, K.M.snow, "foot") end, 0.15, 0.055, 0.15)
	for _, s in ipairs({-1, 1}) do
		K.studs(g, K.M.snow, { x = s*0.15, z = 0.17, y = 0.11, d = 0.16, nx = 1, nz = 2, r = 0.055 })
	end
	K.pair(g, function() return K.sph(0.1, K.M.snow, "arm", {0.7, 1.2, 0.7}) end, 0.28, 0.5, 0.05)
	K.at(g, K.sph(0.13, K.M.white, "tail"), 0, 0.52, -0.32)
	return g
end

function B.seal(K)
	local g = K.group("seal")
	K.at(g, K.sph(0.42, K.M.slate, "body", {0.95, 0.86, 1.45}), 0, 0.42)
	K.at(g, K.sph(0.3, K.M.snow, "belly", {0.92, 0.5, 1.2}), 0, 0.22, 0.04)
	K.at(g, K.sph(0.3, K.M.slate, "head", {1.04, 1, 1}), 0, 0.84, 0.32)
	K.at(g, K.sph(0.17, K.M.snow, "muzzle", {1.1, 0.8, 0.9}), 0, 0.76, 0.55)
	K.at(g, K.sph(0.05, K.M.ink, "nose", {1.2, 0.9, 1}), 0, 0.81, 0.66)
	K.eyes(g, 0.93, 0.52, 0.13, 0.075)
	K.smile(g, 0.68, 0.6, 0.06)
	for _, s in ipairs({-1, 1}) do
		for i = 0, 2 do
			K.at(g, K.cyl(0.006, 0.006, 0.2, K.M.ink, "whisker", 10), s*0.09, 0.76 + i*0.03, 0.63, 0, 0, s*(1.3 - i*0.15))
		end
	end
	K.pair(g, function() return K.sph(0.16, K.M.slate, "flipper", {0.34, 0.66, 1}) end, 0.35, 0.26, 0.2, 0, 0.4, 0)
	K.pair(g, function() return K.sph(0.17, K.M.slate, "fluke", {1.15, 0.26, 0.6}) end, 0.12, 0.3, -0.6, 0, 0, 0.3)
	return g
end

function B.snowman(K)
	local g = K.group("snowman")
	K.at(g, K.sph(0.4, K.M.snow, "base"), 0, 0.4)
	K.at(g, K.sph(0.3, K.M.snow, "torso"), 0, 0.93)
	K.at(g, K.sph(0.24, K.M.snow, "head"), 0, 1.37)
	for i = 0, 2 do
		K.at(g, K.sph(0.042, K.M.ink, "coalButton"), 0, 1.02 - i*0.14, 0.27 + i*0.02)
	end
	K.at(g, K.cone(0.07, 0.28, K.M.amber, "carrotNose"), 0, 1.36, 0.32, math.pi/2)
	K.eyes(g, 1.44, 0.2, 0.1, 0.055)
	K.pair(g, function() return K.cyl(0.022, 0.026, 0.52, K.M.furDark, "twigArm") end, 0.42, 1.05, 0, 0, 0, 1.0)
	K.pair(g, function() return K.cyl(0.016, 0.016, 0.18, K.M.furDark, "twigBranch") end, 0.62, 1.2, 0, 0, 0, 0.4)
	K.at(g, K.tor(0.21, 0.055, K.M.berry, "scarf"), 0, 1.16, 0, math.pi/2)
	K.at(g, K.box(0.12, 0.3, 0.07, K.M.berry, "scarfTail"), 0.16, 1.02, 0.14, 0, 0, 0.2)
	K.at(g, K.cyl(0.23, 0.24, 0.05, K.M.ink, "hatBrim"), 0, 1.58)
	K.at(g, K.cyl(0.155, 0.16, 0.28, K.M.ink, "hatCrown"), 0, 1.74)
	K.at(g, K.cyl(0.162, 0.165, 0.06, K.M.ice, "hatBand"), 0, 1.63)
	for i = 0, 5 do
		local a = i * math.pi / 3
		K.at(g, K.cyl(0.045, 0.045, 0.038, K.M.ink, "stud", 28), math.cos(a)*0.19, 1.612, math.sin(a)*0.19)
	end
	K.at(g, K.cyl(0.068, 0.068, 0.04, K.M.ink, "stud", 28), 0, 1.898)
	return g
end

function B.bear(K)
	local g = K.group("bear")
	K.at(g, K.sph(0.43, K.M.snow, "body", {1.05, 1, 1.08}), 0, 0.52)
	K.at(g, K.sph(0.38, K.M.snow, "head", {1.1, 1, 1}), 0, 1.16)
	K.at(g, K.sph(0.17, K.M.snow, "muzzle", {1.1, 0.85, 1}), 0, 1.07, 0.32)
	K.at(g, K.sph(0.07, K.M.ink, "nose", {1.3, 0.9, 1}), 0, 1.12, 0.44)
	K.smile(g, 1.02, 0.42, 0.06)
	K.pair(g, function() return K.sph(0.1, K.M.snow, "ear") end, 0.28, 1.43, -0.02)
	K.pair(g, function() return K.sph(0.055, K.M.blush, "earInner") end, 0.28, 1.44, 0.06)
	K.eyes(g, 1.22, 0.3, 0.13, 0.07)
	K.pair(g, function() return K.sph(0.16, K.M.snow, "arm", {0.82, 1.1, 0.9}) end, 0.42, 0.52, 0.04, 0, 0, 0.12)
	K.pair(g, function() return K.sph(0.09, K.M.ink, "pawPad", {1, 0.4, 1}) end, 0.42, 0.24, 0.1)
	K.pair(g, function() return K.sph(0.17, K.M.snow, "leg", {0.9, 0.8, 1.1}) end, 0.2, 0.15, 0.08)
	K.pair(g, function() return K.box(0.19, 0.1, 0.28, K.M.ink, "footPad") end, 0.2, 0.05, 0.14)
	for _, s in ipairs({-1, 1}) do
		K.studs(g, K.M.ink, { x = s*0.2, z = 0.16, y = 0.1, d = 0.13, nx = 1, nz = 2, r = 0.055 })
	end
	return g
end

function B.owl(K)
	local g = K.group("owl")
	K.at(g, K.sph(0.36, K.M.snow, "body", {1, 1.3, 0.95}), 0, 0.62)
	for i = 0, 6 do
		local a = i * 1.9
		K.at(g, K.sph(0.045, K.M.frost, "speckle", {1, 0.6, 0.4}),
			math.sin(a)*0.26, 0.5 + (i % 4)*0.16, -0.24 - math.cos(a)*0.08)
	end
	K.at(g, K.sph(0.36, K.M.snow, "head", {1.12, 0.95, 1}), 0, 1.22)
	K.pair(g, function() return K.cyl(0.125, 0.125, 0.03, K.M.white, "faceDisc") end, 0.155, 1.22, 0.3, math.pi/2)
	K.pair(g, function() return K.tor(0.118, 0.026, K.M.gold, "eyeRing") end, 0.155, 1.22, 0.31)
	K.pair(g, function() return K.sph(0.062, K.M.ink, "pupil", {1, 1, 0.6}) end, 0.155, 1.22, 0.33)
	K.at(g, K.cone(0.075, 0.17, K.M.amber, "beak"), 0, 1.09, 0.33, math.pi/2)
	K.pair(g, function() return K.cone(0.062, 0.16, K.M.snow, "earTuft") end, 0.2, 1.52, -0.02, 0, 0, 0.2)
	K.pair(g, function() return K.sph(0.25, K.M.snow, "wing", {0.26, 1.05, 0.8}) end, 0.35, 0.64, 0, 0, 0, 0.06)
	K.pair(g, function() return K.cyl(0.05, 0.055, 0.16, K.M.amber, "leg", 28) end, 0.15, 0.15, 0.04)
	K.pair(g, function() return K.box(0.19, 0.1, 0.28, K.M.amber, "talon") end, 0.15, 0.05, 0.1)
	for _, s in ipairs({-1, 1}) do
		K.studs(g, K.M.amber, { x = s*0.15, z = 0.13, y = 0.1, d = 0.14, nx = 1, nz = 2, r = 0.055 })
	end
	return g
end

function B.walrus(K)
	local g = K.group("walrus")
	K.at(g, K.sph(0.46, K.M.slate, "body", {1, 0.92, 1.3}), 0, 0.5)
	K.at(g, K.sph(0.34, K.M.slate, "head", {1.02, 1, 1}), 0, 0.92, 0.38)
	K.at(g, K.sph(0.26, K.M.slate, "muzzle", {1.12, 0.82, 0.9}), 0, 0.78, 0.6)
	K.at(g, K.sph(0.062, K.M.ink, "nose", {1.4, 0.9, 1}), 0, 0.82, 0.83)
	K.pair(g, function() return K.cyl(0.028, 0.058, 0.42, K.M.bone, "tusk") end, 0.1, 0.5, 0.68, 0.16)
	K.eyes(g, 1.04, 0.67, 0.15, 0.062)
	for _, s in ipairs({-1, 1}) do
		for i = 0, 2 do
			K.at(g, K.sph(0.019, K.M.ink, "whiskerDot"), s*(0.09 + (i % 2)*0.06), 0.72 - i*0.05, 0.79)
		end
	end
	K.pair(g, function() return K.sph(0.21, K.M.slate, "flipper", {0.38, 0.55, 1}) end, 0.4, 0.2, 0.26, 0, 0.35, 0)
	K.at(g, K.sph(0.22, K.M.slate, "rearFluke", {1.2, 0.3, 0.55}), 0, 0.22, -0.62)
	return g
end

function B.reindeer(K)
	local g = K.group("reindeer")
	K.at(g, K.sph(0.34, K.M.fur, "body", {1, 0.95, 1.35}), 0, 0.8)
	K.at(g, K.sph(0.24, K.M.snow, "chest", {0.9, 0.7, 0.8}), 0, 0.68, 0.3)
	K.at(g, K.cyl(0.14, 0.17, 0.36, K.M.fur, "neck"), 0, 1.06, 0.26, -0.4)
	K.at(g, K.sph(0.22, K.M.fur, "head", {1, 0.92, 1.2}), 0, 1.3, 0.38)
	K.at(g, K.sph(0.13, K.M.furDark, "muzzle", {0.92, 0.8, 0.9}), 0, 1.24, 0.57)
	K.at(g, K.sph(0.07, K.M.berry, "nose"), 0, 1.26, 0.66)
	K.eyes(g, 1.36, 0.52, 0.15, 0.055)
	K.pair(g, function() return K.sph(0.09, K.M.fur, "ear", {0.5, 1.2, 0.3}) end, 0.2, 1.45, 0.3, 0, 0, 0.4)
	for _, s in ipairs({-1, 1}) do
		local x, y = s*0.1, 1.42
		local tilt = {0.28, 0.55, 0.85}
		local len = {0.3, 0.25, 0.2}
		for i = 0, 2 do
			local dx = math.sin(tilt[i+1]) * s
			local dy = math.cos(tilt[i+1])
			local L = len[i+1]
			K.at(g, K.cyl(0.03 - i*0.006, 0.036 - i*0.006, L + 0.04, K.M.bone, "antler", 24),
				x + dx*L/2, y + dy*L/2, 0.32, 0, 0, -s*tilt[i+1])
			x = x + dx*L
			y = y + dy*L
		end
		K.at(g, K.cyl(0.018, 0.024, 0.24, K.M.bone, "antlerTine", 22), s*0.17, 1.62, 0.44, 0.95, 0, -s*0.25)
	end
	for _, s in ipairs({-1, 1}) do
		for _, z in ipairs({0.28, -0.26}) do
			K.at(g, K.cyl(0.058, 0.07, 0.52, K.M.fur, "leg"), s*0.18, 0.28, z)
			K.at(g, K.cyl(0.076, 0.076, 0.1, K.M.ink, "hoof"), s*0.18, 0.05, z)
		end
	end
	K.at(g, K.sph(0.1, K.M.fur, "tail"), 0, 0.9, -0.46)
	return g
end

function B.muskox(K)
	local g = K.group("muskox")
	K.at(g, K.sph(0.44, K.M.charcoal, "body", {1, 1, 1.2}), 0, 0.78, -0.06)
	K.at(g, K.sph(0.46, K.M.charcoal, "shagSkirt", {1.02, 0.62, 1.16}), 0, 0.6, -0.06)
	K.at(g, K.sph(0.44, K.M.charcoal, "shagMid", {1.04, 0.4, 1.1}), 0, 0.74, -0.06)
	K.at(g, K.sph(0.29, K.M.charcoal, "head", {1.08, 0.96, 1}), 0, 0.92, 0.56)
	K.at(g, K.sph(0.21, K.M.frost, "muzzle", {1, 0.72, 0.85}), 0, 0.8, 0.74)
	K.at(g, K.sph(0.06, K.M.ink, "nose", {1.5, 0.8, 1}), 0, 0.87, 0.88)
	K.at(g, K.sph(0.23, K.M.bone, "hornBoss", {1.15, 0.44, 0.62}), 0, 1.13, 0.52)
	for _, s in ipairs({-1, 1}) do
		K.at(g, K.tor(0.16, 0.055, K.M.bone, "horn", math.pi * 1.15, 32), s*0.3, 1.06, 0.5, math.pi/2, s*0.25, s*1.85)
	end
	K.eyes(g, 1.0, 0.76, 0.18, 0.055)
	for _, s in ipairs({-1, 1}) do
		for _, z in ipairs({0.3, -0.3}) do
			K.at(g, K.cyl(0.085, 0.095, 0.44, K.M.charcoal, "leg"), s*0.24, 0.24, z)
			K.at(g, K.cyl(0.1, 0.1, 0.1, K.M.ink, "hoof"), s*0.24, 0.05, z)
		end
	end
	return g
end

function B.narwhal(K)
	local g = K.group("narwhal")
	K.at(g, K.sph(0.36, K.M.ice, "body", {1, 0.96, 1.7}), 0, 0.6)
	K.at(g, K.sph(0.28, K.M.snow, "belly", {0.95, 0.55, 1.5}), 0, 0.38, 0.02)
	K.at(g, K.sph(0.3, K.M.ice, "head", {1.02, 1, 0.9}), 0, 0.64, 0.48)
	K.at(g, K.cyl(0.026, 0.055, 0.66, K.M.bone, "tusk"), 0, 0.8, 0.95, math.pi/2)
	for i = 0, 10 do
		local a = i * 1.15
		local r = 0.043 - i*0.0018
		K.at(g, K.sph(0.021, K.M.frost, "tuskRidge", nil, 20), math.cos(a)*r, 0.8 + math.sin(a)*r, 0.68 + i*0.052)
	end
	K.eyes(g, 0.72, 0.66, 0.19, 0.055)
	K.smile(g, 0.55, 0.72, 0.07)
	K.pair(g, function() return K.sph(0.16, K.M.ice, "flipper", {0.28, 0.5, 0.9}) end, 0.33, 0.4, 0.18, 0, 0.3, 0.2)
	K.pair(g, function() return K.sph(0.17, K.M.ice, "fluke", {1.15, 0.24, 0.55}) end, 0.15, 0.62, -0.8, 0, 0, 0.35)
	K.at(g, K.sph(0.1, K.M.iceDeep, "dorsalRidge", {0.5, 0.7, 1.6}), 0, 0.92, -0.1)
	return g
end

function B.yeti(K)
	local g = K.group("yeti")
	K.at(g, K.sph(0.46, K.M.snow, "torso", {1.14, 1.05, 0.95}), 0, 0.82)
	K.at(g, K.sph(0.44, K.M.snow, "shagSkirt", {1.14, 0.6, 1}), 0, 0.56)
	K.at(g, K.sph(0.37, K.M.snow, "head", {1.06, 0.96, 0.96}), 0, 1.46)
	K.at(g, K.sph(0.27, K.M.frost, "facePatch", {0.95, 0.88, 0.6}), 0, 1.4, 0.2)
	K.at(g, K.sph(0.3, K.M.frost, "chestPatch", {0.92, 0.78, 0.5}), 0, 0.82, 0.36)
	K.at(g, K.sph(0.24, K.M.snow, "brow", {1.06, 0.34, 0.5}), 0, 1.58, 0.18)
	K.eyes(g, 1.44, 0.34, 0.14, 0.072)
	K.at(g, K.sph(0.16, K.M.ink, "mouth", {1.3, 0.82, 0.5}), 0, 1.18, 0.32)
	K.pair(g, function() return K.box(0.06, 0.08, 0.035, K.M.white, "tooth") end, 0.06, 1.22, 0.42)
	K.pair(g, function() return K.cone(0.09, 0.34, K.M.ice, "iceHorn") end, 0.25, 1.76, -0.02, 0, 0, 0.34)
	K.pair(g, function() return K.sph(0.21, K.M.snow, "arm", {0.58, 1.5, 0.62}) end, 0.54, 0.88, 0.02, 0, 0, 0.12)
	K.pair(g, function() return K.sph(0.21, K.M.frost, "hand") end, 0.6, 0.46, 0.06)
	K.pair(g, function() return K.sph(0.2, K.M.snow, "leg", {0.9, 0.6, 1.05}) end, 0.22, 0.14, 0.04)
	K.pair(g, function() return K.box(0.24, 0.12, 0.34, K.M.frost, "foot") end, 0.23, 0.06, 0.14)
	for _, s in ipairs({-1, 1}) do
		K.studs(g, K.M.frost, { x = s*0.23, z = 0.16, y = 0.12, w = 0.11, d = 0.15, r = 0.055 })
	end
	return g
end

function B.golem(K)
	local g = K.group("golem")
	K.at(g, K.box(0.62, 0.68, 0.5, K.M.ice, "torso"), 0, 1.0, 0, 0, 0.12)
	K.at(g, K.box(0.5, 0.16, 0.42, K.M.iceDeep, "waist"), 0, 0.62, 0, 0, 0.12)
	K.pair(g, function() return K.box(0.28, 0.26, 0.32, K.M.ice, "shoulder") end, 0.43, 1.22, 0, 0, 0, 0.18)
	K.at(g, K.sph(0.13, K.M.aurora, "core"), 0, 1.02, 0.25)
	K.at(g, K.tor(0.18, 0.035, K.M.iceDeep, "coreRing"), 0, 1.02, 0.24)
	K.at(g, K.box(0.24, 0.16, 0.24, K.M.iceDeep, "neck"), 0, 1.37, 0, 0, 0.16)
	K.studs(g, K.M.ice, { y = 1.34, w = 0.34, d = 0.26, ry = 0.12, r = 0.055 })
	for _, s in ipairs({-1, 1}) do
		K.studs(g, K.M.ice, { x = s*0.43, y = 1.35, nx = 1, nz = 1, r = 0.055 })
	end
	K.at(g, K.box(0.42, 0.36, 0.38, K.M.frost, "head"), 0, 1.56, 0, 0, 0.2)
	K.pair(g, function() return K.sph(0.055, K.M.aurora, "eyeGlow") end, 0.11, 1.58, 0.19)
	for i = 0, 2 do
		K.at(g, K.cone(0.075, 0.34, K.M.ice, "crownShard"), (i-1)*0.13, 1.82, -0.02, -0.15, 0, (i-1)*0.35)
	end
	for i = 0, 2 do
		K.at(g, K.cone(0.09, 0.4, K.M.ice, "backShard"), (i-1)*0.2, 1.12 + (1 - math.abs(i-1))*0.16, -0.28, -0.6, 0, (i-1)*0.3)
	end
	K.pair(g, function() return K.box(0.34, 0.34, 0.34, K.M.ice, "fist") end, 0.68, 0.74, 0.04, 0, 0.35, 0)
	for _, s in ipairs({-1, 1}) do
		K.studs(g, K.M.ice, { x = s*0.68, z = 0.04, y = 0.91, w = 0.18, d = 0.18, ry = s*0.35, r = 0.055 })
	end
	K.pair(g, function() return K.cone(0.09, 0.26, K.M.ice, "shoulderShard") end, 0.46, 1.44, 0, 0, 0, 0.5)
	K.pair(g, function() return K.box(0.24, 0.52, 0.28, K.M.iceDeep, "leg") end, 0.18, 0.3, 0)
	K.pair(g, function() return K.box(0.28, 0.14, 0.36, K.M.ice, "foot") end, 0.18, 0.07, 0.04)
	return g
end

function B.mammoth(K)
	local g = K.group("mammoth")
	K.at(g, K.sph(0.5, K.M.fur, "body", {1.05, 1, 1.28}), 0, 0.98)
	K.at(g, K.sph(0.52, K.M.fur, "shagSkirt", {1.04, 0.6, 1.22}), 0, 0.76)
	K.at(g, K.sph(0.34, K.M.fur, "head", {1.02, 1.15, 0.95}), 0, 1.34, 0.44)
	K.at(g, K.sph(0.17, K.M.furDark, "topknot"), 0, 1.66, 0.4)
	K.eyes(g, 1.36, 0.73, 0.19, 0.055)
	K.pair(g, function() return K.sph(0.17, K.M.fur, "ear", {0.3, 1, 0.9}) end, 0.36, 1.3, 0.3, 0, 0.3, 0)
	do
		local py, pz = 1.18, 0.6
		for i = 0, 6 do
			local th = 3.0 - i*0.1
			local L = 0.14
			local dy, dz = math.cos(th), math.sin(th)
			K.at(g, K.cyl(0.115 - i*0.008, 0.122 - i*0.008, L + 0.05, K.M.fur, "trunk", 32),
				0, py + dy*L/2, pz + dz*L/2, th)
			py = py + dy*L
			pz = pz + dz*L
		end
		for _, s in ipairs({-1, 1}) do
			local x, y, z = s*0.3, 1.0, 0.52
			for i = 0, 3 do
				local th = 2.72 - i*0.6
				local L = 0.19
				local dy, dz = math.cos(th), math.sin(th)
				K.at(g, K.cyl(0.058 - i*0.01, 0.066 - i*0.01, L + 0.04, K.M.bone, "tusk", 28),
					x, y + dy*L/2, z + dz*L/2, th)
				y = y + dy*L
				z = z + dz*L
			end
		end
	end
	for _, s in ipairs({-1, 1}) do
		for _, z in ipairs({0.34, -0.34}) do
			K.at(g, K.cyl(0.15, 0.17, 0.6, K.M.fur, "leg"), s*0.27, 0.32, z)
			K.at(g, K.cyl(0.185, 0.185, 0.12, K.M.furDark, "foot"), s*0.27, 0.06, z)
		end
	end
	return g
end

function B.wyrm(K)
	local g = K.group("wyrm")
	K.at(g, K.tor(0.42, 0.16, K.M.ice, "coil"), 0, 0.17, -0.04, math.pi/2)
	for _, a in ipairs({math.pi*0.35, math.pi*0.68, math.pi*1.32, math.pi*1.65}) do
		K.at(g, K.cyl(0.085, 0.085, 0.056, K.M.ice, "stud", 28), math.cos(a)*0.42, 0.315, -0.04 + math.sin(a)*0.42)
	end
	for i = 0, 7 do
		local t = i / 7
		K.at(g, K.sph(0.26 - t*0.09, K.M.ice, "bodySegment", {1, 1, 1}, 36),
			0, 0.32 + t*0.94, 0.16 + math.sin(t*2.4)*0.26)
	end
	K.at(g, K.sph(0.28, K.M.ice, "head", {1.05, 0.9, 1.15}), 0, 1.44, 0.32)
	K.at(g, K.sph(0.17, K.M.frost, "snout", {0.85, 0.62, 1.05}), 0, 1.38, 0.58)
	K.at(g, K.sph(0.16, K.M.iceDeep, "jaw", {0.94, 0.42, 0.95}), 0, 1.28, 0.56)
	K.pair(g, function() return K.sph(0.075, K.M.gold, "eye") end, 0.155, 1.52, 0.52)
	K.pair(g, function() return K.sph(0.032, K.M.ink, "pupil") end, 0.165, 1.52, 0.58)
	K.pair(g, function() return K.cone(0.055, 0.28, K.M.aurora, "horn") end, 0.13, 1.62, 0.16, -0.5, 0, 0.2)
	K.pair(g, function() return K.sph(0.22, K.M.aurora, "frill", {0.1, 0.9, 0.5}) end, 0.26, 1.16, 0.06, 0, 0, 0.55)
	for i = 0, 4 do
		local t = i / 4
		K.at(g, K.cone(0.06, 0.2, K.M.aurora, "crestFin"), 0, 0.6 + t*0.72, -0.02 + math.sin(t*2.6)*0.2 - 0.16, -0.9)
	end
	return g
end

return B
