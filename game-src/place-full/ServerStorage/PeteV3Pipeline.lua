-- Secret Pete v3 voxel pipeline, ported from pete-model-v3.js (authoritative spec).
-- Box regions -> voxel rasterizer -> face bake -> greedy box merge.
-- BUILD-TIME ONLY. Nothing at runtime requires this; it exists so the model can
-- be regenerated from the design spec instead of hand-patched.
local VOX = 0.09
local HW, HH, HD, HEAD_Y = 1.94, 1.78, 1.6, 1.9

local function rotXYZ(x,y,z)
	local a,b = math.cos(x), math.sin(x)
	local c,d = math.cos(y), math.sin(y)
	local e,f = math.cos(z), math.sin(z)
	return { c*e, -c*f, d,   a*f+b*d*e, a*e-b*d*f, -b*c,   b*f-a*d*e, b*e+a*d*f, a*c }
end
local function compose(p, r)
	local R = rotXYZ(r[1], r[2], r[3])
	return { R[1],R[2],R[3],p[1], R[4],R[5],R[6],p[2], R[7],R[8],R[9],p[3] }
end
local function mul(A,B)
	local C = {}
	for i=0,2 do
		for j=0,2 do C[i*4+j+1] = A[i*4+1]*B[j+1] + A[i*4+2]*B[4+j+1] + A[i*4+3]*B[8+j+1] end
		C[i*4+4] = A[i*4+1]*B[4] + A[i*4+2]*B[8] + A[i*4+3]*B[12] + A[i*4+4]
	end
	return C
end
local function apply(M,x,y,z)
	return M[1]*x+M[2]*y+M[3]*z+M[4], M[5]*x+M[6]*y+M[7]*z+M[8], M[9]*x+M[10]*y+M[11]*z+M[12]
end
local function inverse(M)
	local tx,ty,tz = M[4],M[8],M[12]
	local R = { M[1],M[5],M[9], M[2],M[6],M[10], M[3],M[7],M[11] }
	return { R[1],R[2],R[3], -(R[1]*tx+R[2]*ty+R[3]*tz),
	         R[4],R[5],R[6], -(R[4]*tx+R[5]*ty+R[6]*tz),
	         R[7],R[8],R[9], -(R[7]*tx+R[8]*ty+R[9]*tz) }
end

local nodes = {}
local function P(parent, name, mat, size, pos, rot)
	table.insert(nodes, { m = mul(parent, compose(pos, rot or {0,0,0})), mat = mat, size = size, name = name })
end
local ID = compose({0,0,0},{0,0,0})
local head = mul(ID, compose({0, HEAD_Y, 0}, {0,0,0}))

P(head,"skull","skin",{HW,HH,HD},{0,0,0})
P(head,"jaw","skin",{HW*1.04,0.42,HD*0.9},{0,-HH/2+0.1,-0.05})
for i,s in ipairs({-1,1}) do
	local sd = (i==2) and "R" or "L"
	P(head,"cheekBlock_"..sd,"skin",{0.2,0.52,0.72},{s*(HW/2+0.06),-0.34,0.14})
	P(head,"ear_"..sd,"skin",{0.14,0.34,0.26},{s*(HW/2+0.05),0.02,-0.06})
	P(head,"hairSide_"..sd,"hair",{0.16,0.5,HD*0.78},{s*(HW/2+0.005),0.24,-0.16})
end
P(head,"hairSlabBack","hair",{HW*1.01,0.16,HD*0.62},{0,HH/2+0.06,-HD*0.19})
P(head,"hairCrownPatch","hair",{HW*0.62,0.1,HD*0.5},{0,HH/2+0.03,0.06})
P(head,"hairBackPlate","hair",{HW*1.01,0.62,0.14},{0,0.18,-HD/2-0.005})
for i,t in ipairs({{0.02,-0.12,0.46,0.15,0.06},{-0.34,-0.02,0.34,-0.28,0.05},{0.36,-0.22,0.3,0.34,-0.04},{-0.1,0.24,0.22,-0.1,0.1},{0.2,0.3,0.16,0.2,-0.12}}) do
	P(head,"hairTuft_"..i,"hair",{0.13,t[3],0.13},{t[1],HH/2+0.02+t[3]/2,t[2]},{t[5],0,t[4]})
end
for i,s in ipairs({-1,1}) do
	local sd = (i==2) and "R" or "L"
	P(head,"glassTemple_"..sd,"glassFrame",{0.07,0.11,1.1},{s*(HW/2+0.13),0.06,-0.16})
	P(head,"templeHook_"..sd,"glassFrame",{0.07,0.24,0.09},{s*(HW/2+0.13),-0.06,-0.68})
end
P(ID,"shirtStub","shirtBlack",{0.62,0.26,0.44},{0,HEAD_Y-HH/2-0.04,0})
for _,s in ipairs({-1,1}) do
	local sd = (s<0) and "L" or "R"
	P(ID,"arm_"..sd,"skin",{0.66,0.15,0.15},{s*1.24,HEAD_Y-0.44,0.02},{0,0,s*-0.34})
	P(ID,"gloveCuff_"..sd,"rubberGloveCuff",{0.21,0.21,0.21},{s*1.36,HEAD_Y-0.5,0.02},{0,0,s*-0.34})
	P(ID,"glovedHand_"..sd,"rubberGloveYellow",{0.26,0.26,0.22},{s*1.53,HEAD_Y-0.57,0.02})
	P(ID,"leg_"..sd,"skin",{0.19,0.82,0.19},{s*0.38,0.7,0})
end
P(ID,"apronBib","apronBlue",{0.9,0.56,0.1},{0,0.82,0.68})
P(ID,"apronSkirt","apronBlue",{1.02,0.3,0.1},{0,0.48,0.68})
P(ID,"apronPocket","sudsWhite",{0.38,0.18,0.06},{0,0.76,0.75})
local sponge = mul(ID, compose({1.53, HEAD_Y-0.34, 0.02},{0,0,-0.12}))
P(sponge,"spongeBody","spongeYellow",{0.34,0.16,0.28},{0,0,0})
P(sponge,"spongeScourPad","spongeGreen",{0.35,0.07,0.29},{0,0.11,0})
for i,u in ipairs({{0.28,0.26,0.06,0.12},{-0.1,0.42,-0.1,0.09},{0.34,0.58,0.16,0.07},{-0.02,0.7,-0.04,0.055},{0.42,0.84,0.1,0.045}}) do
	P(sponge,"sud_"..i,"sudsWhite",{u[4],u[4],u[4]},{u[1],u[2],u[3]})
end
for _,s in ipairs({-1,1}) do
	local sd = (s<0) and "L" or "R"
	local shoe = mul(ID, compose({s*0.38,0,0.08},{0,s*0.1,0}))
	P(shoe,"sneakerSole_"..sd,"sneakerSole",{0.46,0.13,0.86},{0,0.065,0})
	P(shoe,"sneakerUpper_"..sd,"sneakerBlack",{0.42,0.3,0.56},{0,0.28,-0.1})
	P(shoe,"sneakerToe_"..sd,"sneakerBlack",{0.42,0.18,0.32},{0,0.22,0.26})
	P(shoe,"goldStripe_"..sd,"secretGold",{0.44,0.07,0.6},{0,0.2,-0.04})
	P(shoe,"laceTongue_"..sd,"secretGold",{0.2,0.08,0.2},{0,0.44,0.06})
end

local function boundsOf(m,h)
	local mnx,mny,mnz,mxx,mxy,mxz = math.huge,math.huge,math.huge,-math.huge,-math.huge,-math.huge
	for i=0,7 do
		local x = (i%2>=1) and h[1] or -h[1]
		local y = (math.floor(i/2)%2>=1) and h[2] or -h[2]
		local z = (math.floor(i/4)%2>=1) and h[3] or -h[3]
		local px,py,pz = apply(m,x,y,z)
		mnx=math.min(mnx,px) mny=math.min(mny,py) mnz=math.min(mnz,pz)
		mxx=math.max(mxx,px) mxy=math.max(mxy,py) mxz=math.max(mxz,pz)
	end
	return mnx,mny,mnz,mxx,mxy,mxz
end

local BMNX,BMNY,BMNZ = math.huge,math.huge,math.huge
for _,n in ipairs(nodes) do
	local h = {math.max(n.size[1],VOX)/2, math.max(n.size[2],VOX)/2, math.max(n.size[3],VOX)/2}
	local a,b,c = boundsOf(n.m,h)
	BMNX=math.min(BMNX,a) BMNY=math.min(BMNY,b) BMNZ=math.min(BMNZ,c)
end
local OX,OY,OZ = BMNX-VOX, BMNY-VOX, BMNZ-VOX

local function K(x,y,z) return (x*4096+y)*4096+z end
local grid, nvox = {}, 0
for _,n in ipairs(nodes) do
	local inv = inverse(n.m)
	local h = {math.max(n.size[1],VOX*1.02)/2, math.max(n.size[2],VOX*1.02)/2, math.max(n.size[3],VOX*1.02)/2}
	local a,b,c,d,e,f = boundsOf(n.m,h)
	for x=math.floor((a-OX)/VOX), math.ceil((d-OX)/VOX) do
	for y=math.floor((b-OY)/VOX), math.ceil((e-OY)/VOX) do
	for z=math.floor((c-OZ)/VOX), math.ceil((f-OZ)/VOX) do
		local lx,ly,lz = apply(inv, OX+(x+0.5)*VOX, OY+(y+0.5)*VOX, OZ+(z+0.5)*VOX)
		if math.abs(lx)<=h[1] and math.abs(ly)<=h[2] and math.abs(lz)<=h[3] then
			local k = K(x,y,z)
			if grid[k]==nil then nvox+=1 end
			grid[k] = {mat=n.mat, part=n.name, x=x, y=y, z=z}
		end
	end end end
end

-- Face bake: precomputed from assets/pete-face-toon.png using the spec's rule --
-- average each voxel's footprint, any non-skin colour covering >=30% wins outright.
-- Depends only on the voxel column (x,y), so it stores as a flat table.
--
-- 2026-08-18 RE-BAKED against the v3 bundle's texture ("NEW NEW Secret Pete
-- character model.zip"). The table this replaced was baked from the v2 bundle's
-- pete-face-toon.png -- same filename, DIFFERENT artwork: v3's is redrawn chunky
-- on purpose so the features survive a 0.09 voxel (README: "at least 3 image-pixels
-- per voxel"). Baking the v2 art gave 108 face voxels and thin, broken glasses;
-- the v3 art gives 159 and a solid frame. If the texture is ever redrawn again this
-- table MUST be regenerated -- nothing here reads the PNG at runtime, so a stale
-- table is a silent wrong face, not an error.
local FACE_KEYS = {"skin","glassFrame","lensGlass","eyeWhite","pupilBlack","mouthLine","foreheadCrease","nostril"}
local BAKE_RAW = "10,19,1 10,20,1 10,21,1 10,22,1 10,23,1 10,24,1 10,25,1 11,19,1 11,20,1 11,21,2 11,22,2 11,23,1 11,24,1 11,25,1 12,19,1 12,20,2 12,21,3 12,22,3 12,23,2 12,24,1 12,25,1 13,19,1 13,20,3 13,21,3 13,22,3 13,23,3 13,24,1 13,25,1 14,19,1 14,20,3 14,21,4 14,22,4 14,23,3 14,24,1 14,25,1 14,28,6 15,19,1 15,20,3 15,21,3 15,22,4 15,23,3 15,24,1 15,25,1 15,27,6 15,28,6 16,16,5 16,19,1 16,20,2 16,21,2 16,22,2 16,23,2 16,24,1 16,25,1 16,27,6 16,28,6 17,15,5 17,16,5 17,19,1 17,20,1 17,21,1 17,22,1 17,23,1 17,24,1 17,25,1 17,27,6 17,28,6 18,15,5 18,18,7 18,20,1 18,21,1 18,22,1 18,23,1 18,24,1 18,25,1 18,27,6 18,28,6 19,15,5 19,18,7 19,22,1 19,24,1 19,25,1 19,27,6 19,28,6 20,15,5 20,18,7 20,20,1 20,21,1 20,22,1 20,23,1 20,24,1 20,25,1 20,27,6 20,28,6 21,15,5 21,19,1 21,20,1 21,21,1 21,22,1 21,23,1 21,24,1 21,25,1 21,27,6 21,28,6 22,16,5 22,19,1 22,20,2 22,21,2 22,22,2 22,23,2 22,24,1 22,25,1 22,27,6 22,28,6 23,16,5 23,19,1 23,20,3 23,21,4 23,22,4 23,23,3 23,24,1 23,25,1 23,27,6 23,28,6 24,19,1 24,20,3 24,21,4 24,22,4 24,23,3 24,24,1 24,25,1 24,28,6 25,19,1 25,20,3 25,21,3 25,22,3 25,23,3 25,24,1 25,25,1 26,19,1 26,20,2 26,21,2 26,22,2 26,23,2 26,24,1 26,25,1 27,19,1 27,20,1 27,21,1 27,22,1 27,23,1 27,24,1 27,25,1 28,19,1 28,20,1 28,21,1 28,22,1 28,23,1 28,24,1 28,25,1"
local bake = {}
for sx, sy, si in string.gmatch(BAKE_RAW, "(%-?%d+),(%-?%d+),(%d+)") do
	bake[tonumber(sx)*4096 + tonumber(sy)] = FACE_KEYS[tonumber(si)+1]
end

local skullFrontZ = HD/2
for _,v in pairs(grid) do
	if v.part == "skull" and grid[K(v.x, v.y, v.z+1)] == nil then
		local wz = OZ + (v.z+0.5)*VOX
		if wz >= skullFrontZ - VOX*1.5 then
			local hit = bake[v.x*4096 + v.y]
			if hit then v.mat = hit end
		end
	end
end

-- head top and bottom keep the shaded skin tone
for _,v in pairs(grid) do
	if (v.part=="skull" or v.part=="jaw") and v.mat=="skin" then
		if grid[K(v.x,v.y+1,v.z)]==nil or grid[K(v.x,v.y-1,v.z)]==nil then v.mat = "skinShade" end
	end
end

-- Greedy merge into axis-aligned boxes, one material each. The voxels are a
-- modelling technique, not a build instruction -- 9,756 Parts would be fatal.
local mnx,mny,mnz,mxx,mxy,mxz = math.huge,math.huge,math.huge,-math.huge,-math.huge,-math.huge
for _,v in pairs(grid) do
	mnx=math.min(mnx,v.x) mny=math.min(mny,v.y) mnz=math.min(mnz,v.z)
	mxx=math.max(mxx,v.x) mxy=math.max(mxy,v.y) mxz=math.max(mxz,v.z)
end
local used, boxes = {}, {}
local function free(x,y,z,mat)
	local k = K(x,y,z)
	local v = grid[k]
	return v ~= nil and v.mat == mat and not used[k]
end
for y=mny,mxy do for z=mnz,mxz do for x=mnx,mxx do
	local k = K(x,y,z)
	local v = grid[k]
	if v and not used[k] then
		local mat = v.mat
		local w = 1
		while free(x+w,y,z,mat) do w += 1 end
		local dd = 1
		while true do
			local ok = true
			for i=0,w-1 do if not free(x+i,y,z+dd,mat) then ok=false break end end
			if ok then dd += 1 else break end
		end
		local hh = 1
		while true do
			local ok = true
			for i=0,w-1 do
				for j=0,dd-1 do if not free(x+i,y+hh,z+j,mat) then ok=false break end end
				if not ok then break end
			end
			if ok then hh += 1 else break end
		end
		for i=0,w-1 do for j=0,hh-1 do for l=0,dd-1 do used[K(x+i,y+j,z+l)] = true end end end
		table.insert(boxes, {x=x,y=y,z=z,w=w,h=hh,d=dd,mat=mat})
	end
end end end

return { VOX = VOX, OX = OX, OY = OY, OZ = OZ, grid = grid, nvox = nvox, boxes = boxes,
	span = {mnx,mny,mnz,mxx,mxy,mxz}, HEAD_Y = HEAD_Y, HH = HH }
