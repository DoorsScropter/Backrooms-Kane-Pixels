--[[
	BACKROOMS NOCLIP v3.5 (Enhanced Textures, Dimmed PoolRooms, 5/8-Floor Mega Rooms)
	LocalScript (client-sided) | Delta compatible
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local InsertService = game:GetService("InsertService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
while not player do task.wait() player = Players.LocalPlayer end

--// ================= CONFIG =================
local TICK_CHANCE      = 0.10            -- chance per second to noclip
local WALL_CHANCE      = 0.50            -- chance when walking into a wall
local INTRO_SOUND_ID   = 139682612041479
local AMBIENT_SOUND_ID = 137406302438919
local WALK_SOUND_BACK  = 89575970505811  -- walking on backrooms floor
local WALK_SOUND_POOL  = 96516907071037  -- walking on poolrooms floor
local CHAIR_ASSET_ID   = 74698525718385
local DOOR_ASSET_ID    = 9343670755
local HOUSE_CHANCE     = 0.10            -- chance a house exists in the backrooms
local MEGA_CHANCE      = 0.30            -- chance of a very big multi-floor room (5 or 8 floors)
local POOL_CHANCE      = 0.40            -- chance of THE POOLROOMS (dimmed & detailed)
local HOUSE_MODEL_NAME = nil             -- exact name of house model (nil = auto-detect)
local DOOR_CHANCE      = 0.04            -- chance per zone-border wall piece to be a door
local WINDOW_CHANCE    = 0.10            -- chance per wall piece to have a window
local PIT_CHANCE       = 0.025           -- square floor pits in normal cells
local SHAFT_CHANCE     = 0.02            -- square ceiling shafts in normal cells
local LIGHT_BRIGHTNESS = 0.35            -- reduced ceiling light brightness for eerie atmosphere
local CEILING_GRID     = true            -- ceiling tile lines
local CAMERA_BOB       = true            -- found-footage walking camera
local STEP_VOLUME      = 0.5
local T_TITLE, T_SUB, T_END = 3, 6, 11   -- intro timings
local STOP_INTRO_ON_REVEAL = true

local PROP_CHANCE  = 0.04                -- per cell chance of a copied model
local CHAIR_CHANCE = 0.03                -- per cell chance of a chair

local BASE = Vector3.new(0, 3000, 0)     -- where the backrooms live
local CELL, WALL_H, WALL_T = 12, 13, 0.8
local FH = WALL_H + 1                    -- floor-to-floor height in mega rooms
local DOOR_W, DOOR_H = 7, 9.5
local R = 6                              -- zone size in cells
local LOAD_R, UNLOAD_R = 8, 11
local DIRS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

local C_BOARD = Color3.fromRGB(105, 88, 46)

-- wallpaper / carpet looks per zone (using varied textures)
local PALETTES = {
	{wall = Color3.fromRGB(190, 171, 88),  carpet = Color3.fromRGB(135, 121, 66), ceil = Color3.fromRGB(190, 184, 156), mat = Enum.Material.SmoothPlastic, off = 0.12},
	{wall = Color3.fromRGB(165, 168, 118), carpet = Color3.fromRGB(104, 110, 76), ceil = Color3.fromRGB(180, 182, 160), mat = Enum.Material.Concrete, off = 0.20},
	{wall = Color3.fromRGB(184, 160, 128), carpet = Color3.fromRGB(112, 92, 80),  ceil = Color3.fromRGB(190, 180, 165), mat = Enum.Material.WoodPlanks, off = 0.20},
	{wall = Color3.fromRGB(122, 106, 62),  carpet = Color3.fromRGB(84, 72, 46),   ceil = Color3.fromRGB(150, 142, 118), mat = Enum.Material.Slate, off = 0.38},
}

local LOOKS = {
	back = {amb = Color3.fromRGB(22, 19, 10),  fog = Color3.fromRGB(8, 7, 3),      tint = Color3.fromRGB(255, 235, 190), fs = 12, fe = 85,  ex = -0.4},
	mega = {amb = Color3.fromRGB(22, 19, 10),  fog = Color3.fromRGB(8, 7, 3),      tint = Color3.fromRGB(255, 235, 190), fs = 30, fe = 250, ex = -0.4},
	pool = {amb = Color3.fromRGB(65, 85, 95),  fog = Color3.fromRGB(90, 130, 145),  tint = Color3.fromRGB(180, 215, 235), fs = 30, fe = 240, ex = -0.1},
}

local HOUSE_WORDS = {"house", "home", "cabin", "mansion", "cottage", "apartment"}
local BAD_WORDS = {"wall", "floor", "ceiling", "roof", "baseplate", "terrain", "ground", "map", "spawn", "lobby", "skybox", "border", "barrier", "road", "street", "water"}

--// ================= STATE =================
local env = (getgenv and getgenv()) or _G
if env.__BACKROOMS_STOP then pcall(env.__BACKROOMS_STOP) end

local alive = true
local conns = {}
local function track(c) conns[#conns + 1] = c return c end

local busy, inBackrooms = false, false
local rootFolder, ambience, introSound, overlay, noticeGui
local cells, templates, flicker = {}, {}, {}
local chairTpl, doorTpl
local zone, mega, poolZ
local doorW, doorH = DOOR_W - 0.7, DOOR_H - 0.4
local SEED = 1
local regionCache = {}
local savedLighting, savedWater, look
local waterFills = {}
local stepSounds = {}
local curArea = "back"
local origFov

local startSequence, cleanupBackrooms

--// ================= GENERAL HELPERS =================
local function getChar()
	local c = player.Character
	if not c then return end
	local hum = c:FindFirstChildOfClass("Humanoid")
	local hrp = c:FindFirstChild("HumanoidRootPart")
	if hum and hrp and hum.Health > 0 then return c, hum, hrp end
end

local function shade(c, k)
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end

local function nameHas(n, words)
	n = n:lower()
	for _, w in ipairs(words) do
		if n:find(w, 1, true) then return true end
	end
	return false
end

local function rnd(x, z, salt)
	local n = (x * 73856093 + z * 19349663 + salt * 83492791 + SEED * 2654435761) % 4294967296
	n = bit32.bxor(n, bit32.rshift(n, 15))
	n = (n * 1664525 + 1013904223) % 4294967296
	n = bit32.bxor(n, bit32.rshift(n, 13))
	n = (n * 1664525 + 1013904223) % 4294967296
	return n / 4294967296
end

local function ckey(x, z) return (x + 50000) * 100000 + (z + 50000) end
local function cellPos(x, z) return BASE + Vector3.new(x * CELL, 0, z * CELL) end
local function inRect(r, x, z)
	return r ~= nil and x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1
end
local function inZone(x, z)
	return inRect(zone, x, z) or inRect(mega, x, z) or inRect(poolZ, x, z)
end

local function makeSound(id, vol, looped)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = vol
	s.Looped = looped
	s.Parent = SoundService
	return s
end

local function parentGui(gui)
	pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
	if not gui.Parent then gui.Parent = player:WaitForChild("PlayerGui") end
end

local function mk(parent, name, size, cf, color, mat)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function rampPart(parent, a, b, width, color, mat)
	local thick = 1
	local rot = CFrame.lookAt(Vector3.zero, b - a)
	local center = (a + b) / 2 - rot.UpVector * (thick / 2)
	return mk(parent, "Ramp", Vector3.new(width, thick, (b - a).Magnitude), CFrame.new(center) * rot, color, mat)
end

local function holeBoxes(parent, cx, cz, hs, yc, thick, color, mat)
	local strip = (CELL - hs) / 2
	mk(parent, "Part", Vector3.new(CELL, thick, strip), CFrame.new(cx, yc, cz + hs / 2 + strip / 2), color, mat)
	mk(parent, "Part", Vector3.new(CELL, thick, strip), CFrame.new(cx, yc, cz - hs / 2 - strip / 2), color, mat)
	mk(parent, "Part", Vector3.new(strip, thick, hs), CFrame.new(cx - hs / 2 - strip / 2, yc, cz), color, mat)
	mk(parent, "Part", Vector3.new(strip, thick, hs), CFrame.new(cx + hs / 2 + strip / 2, yc, cz), color, mat)
end

--// ================= MODEL HELPERS =================
local function aabb(model)
	local mnx, mny, mnz = math.huge, math.huge, math.huge
	local mxx, mxy, mxz = -math.huge, -math.huge, -math.huge
	local found = false
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			found = true
			local cf, s = p.CFrame, p.Size
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local ex = (math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z) / 2
			local ey = (math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z) / 2
			local ez = (math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z) / 2
			local pos = cf.Position
			mnx = math.min(mnx, pos.X - ex) mny = math.min(mny, pos.Y - ey) mnz = math.min(mnz, pos.Z - ez)
			mxx = math.max(mxx, pos.X + ex) mxy = math.max(mxy, pos.Y + ey) mxz = math.max(mxz, pos.Z + ez)
		end
	end
	if not found then return Vector3.zero, Vector3.zero, false end
	return Vector3.new(mnx, mny, mnz), Vector3.new(mxx, mxy, mxz), true
end

local function applyCF(model, cf)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then p.CFrame = cf * p.CFrame end
	end
end

local function stretch(model, S)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local cf, sz = p.CFrame, p.Size
			local nx = (cf.RightVector * S).Magnitude * sz.X
			local ny = (cf.UpVector * S).Magnitude * sz.Y
			local nz = (cf.LookVector * S).Magnitude * sz.Z
			p.CFrame = CFrame.new(cf.Position * S) * (cf - cf.Position)
			pcall(function()
				p.Size = Vector3.new(math.clamp(nx, 0.05, 400), math.clamp(ny, 0.05, 400), math.clamp(nz, 0.05, 400))
			end)
		end
	end
end

local function sanitize(m, keepLights)
	local kill = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector")
			or d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Constraint") or d:IsA("BodyMover")
			or d:IsA("Humanoid") or ((not keepLights) and d:IsA("Light")) then
			kill[#kill + 1] = d
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
	for _, d in ipairs(kill) do pcall(function() d:Destroy() end) end
	if m:IsA("Model") then m.PrimaryPart = nil end
end

local function finishTemplate(m, keepLights, capDim)
	sanitize(m, keepLights)
	local mn, mx, found = aabb(m)
	if not found then
		m:Destroy()
		return nil
	end
	applyCF(m, CFrame.new(-(mn + mx) / 2))
	if capDim then
		local s = mx - mn
		local md = math.max(s.X, s.Y, s.Z)
		if md > capDim then
			local k = capDim / md
			stretch(m, Vector3.new(k, k, k))
		end
	end
	return m
end

local function box(parent, name, sx, sy, sz, x, y, z, color, mat)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = Vector3.new(sx, sy, sz)
	p.CFrame = CFrame.new(x, y, z)
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function buildFallbackChair()
	local m = Instance.new("Model")
	m.Name = "Chair"
	local col, mat = Color3.fromRGB(70, 62, 55), Enum.Material.Metal
	box(m, "Seat", 2.2, 0.25, 2.2, 0, 1.7, 0, Color3.fromRGB(120, 90, 55), Enum.Material.WoodPlanks)
	box(m, "Back", 2.2, 2, 0.25, 0, 2.9, -1, Color3.fromRGB(120, 90, 55), Enum.Material.WoodPlanks)
	for _, sx in ipairs({-0.95, 0.95}) do
		for _, sz in ipairs({-0.95, 0.95}) do
			box(m, "Leg", 0.2, 1.7, 0.2, sx, 0.85, sz, col, mat)
		end
	end
	return m
end

local function buildFallbackDoor()
	local m = Instance.new("Model")
	m.Name = "Door"
	box(m, "Slab", 6.3, 9.1, 0.5, 0, 4.55, 0, Color3.fromRGB(110, 78, 45), Enum.Material.WoodPlanks)
	box(m, "Handle", 0.35, 0.35, 0.8, 2.4, 4.3, 0, Color3.fromRGB(190, 170, 90), Enum.Material.Metal)
	return m
end

local function buildFallbackHouse()
	local m = Instance.new("Model")
	m.Name = "House"
	local W, D, H = 26, 22, 10.5
	local wallC, wood = Color3.fromRGB(225, 220, 205), Color3.fromRGB(130, 95, 60)
	box(m, "Floor", W, 1, D, 0, 0.5, 0, wood, Enum.Material.WoodPlanks)
	box(m, "Back", W, H, 1, 0, 1 + H / 2, D / 2, wallC, Enum.Material.SmoothPlastic)
	box(m, "Left", 1, H, D, -W / 2, 1 + H / 2, 0, wallC, Enum.Material.SmoothPlastic)
	box(m, "Right", 1, H, D, W / 2, 1 + H / 2, 0, wallC, Enum.Material.SmoothPlastic)
	local side = (W - 5) / 2
	box(m, "FrontL", side, H, 1, -(2.5 + side / 2), 1 + H / 2, -D / 2, wallC, Enum.Material.SmoothPlastic)
	box(m, "FrontR", side, H, 1, (2.5 + side / 2), 1 + H / 2, -D / 2, wallC, Enum.Material.SmoothPlastic)
	box(m, "Lintel", 5, H - 8, 1, 0, 1 + 8 + (H - 8) / 2, -D / 2, wallC, Enum.Material.SmoothPlastic)
	box(m, "Roof", W + 2, 1, D + 2, 0, 1 + H + 0.5, 0, Color3.fromRGB(90, 70, 60), Enum.Material.Slate)
	box(m, "Divider", 1, H, D * 0.6, 2, 1 + H / 2, D / 2 - D * 0.3, wallC, Enum.Material.SmoothPlastic)
	box(m, "Table", 4, 0.4, 2.5, -7, 3, -4, wood, Enum.Material.WoodPlanks)
	for _, tx in ipairs({-8.6, -5.4}) do
		for _, tz in ipairs({-5, -3}) do
			box(m, "TLeg", 0.3, 2, 0.3, tx, 2, tz, wood, Enum.Material.WoodPlanks)
		end
	end
	for _, lx in ipairs({-6, 8}) do
		local bulb = box(m, "Bulb", 2, 0.3, 2, lx, H + 0.7, 0, Color3.fromRGB(255, 244, 214), Enum.Material.Neon)
		local pl = Instance.new("PointLight")
		pl.Range, pl.Brightness, pl.Shadows = 25, 0.6, false
		pl.Color = Color3.fromRGB(255, 238, 200)
		pl.Parent = bulb
	end
	return m
end

--// ================= TEMPLATES =================
local function collectTemplates()
	templates = {}
	local cands, chosen = {}, {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d ~= player.Character and not (rootFolder and d:IsDescendantOf(rootFolder)) then
			if not d:FindFirstChildWhichIsA("Humanoid") and not Players:GetPlayerFromCharacter(d)
				and not nameHas(d.Name, BAD_WORDS) and not nameHas(d.Name, HOUSE_WORDS)
				and d:FindFirstChildWhichIsA("BasePart", true) then
				local skip, a = false, d.Parent
				while a and a ~= Workspace do
					if chosen[a] then skip = true break end
					a = a.Parent
				end
				if not skip then
					local ok, s = pcall(function() return d:GetExtentsSize() end)
					if ok and s then
						local maxd, mind = math.max(s.X, s.Y, s.Z), math.min(s.X, s.Y, s.Z)
						local plate = (maxd >= 18 and mind <= 2) or (s.Y < 1.2 and maxd > 10)
						if maxd >= 0.8 and maxd <= 40 and not plate then
							chosen[d] = true
							cands[#cands + 1] = d
						end
					end
				end
			end
		end
		if #cands >= 500 then break end
	end
	for i = #cands, 2, -1 do
		local j = math.random(1, i)
		cands[i], cands[j] = cands[j], cands[i]
	end
	for i = 1, math.min(#cands, 24) do
		local ok, c = pcall(function() return cands[i]:Clone() end)
		if ok and c then
			local t = finishTemplate(c, false, 14)
			if t then templates[#templates + 1] = t end
		end
	end
end

local function loadAsset(id)
	local objs
	pcall(function() objs = game:GetObjects("rbxassetid://" .. id) end)
	if not objs or #objs == 0 then
		pcall(function()
			local m = InsertService:LoadAsset(id)
			objs = m:GetChildren()
		end)
	end
	if objs and #objs > 0 then
		local wrapper = Instance.new("Model")
		for _, o in ipairs(objs) do pcall(function() o.Parent = wrapper end) end
		return wrapper
	end
end

local function loadChair()
	chairTpl = nil
	local tpl
	local wrapper = loadAsset(CHAIR_ASSET_ID)
	if wrapper then
		wrapper.Name = "Chair"
		tpl = finishTemplate(wrapper, false, nil)
		if tpl then
			local mn, mx = aabb(tpl)
			local h = (mx - mn).Y
			if h > 5.5 or h < 2.2 then
				local k = 3.6 / math.max(h, 0.1)
				stretch(tpl, Vector3.new(k, k, k))
			end
		end
	end
	if not tpl then tpl = finishTemplate(buildFallbackChair(), false, nil) end
	chairTpl = tpl
end

local function loadDoor()
	doorTpl = nil
	local tpl
	local wrapper = loadAsset(DOOR_ASSET_ID)
	if wrapper then
		wrapper.Name = "Door"
		tpl = finishTemplate(wrapper, false, nil)
	end
	if not tpl then tpl = finishTemplate(buildFallbackDoor(), false, nil) end
	if not tpl then return end

	local mn, mx = aabb(tpl)
	local s = mx - mn
	if s.X >= s.Y and s.X >= s.Z then
		applyCF(tpl, CFrame.Angles(0, 0, math.pi / 2))
	elseif s.Z >= s.Y and s.Z >= s.X then
		applyCF(tpl, CFrame.Angles(math.pi / 2, 0, 0))
	end
	mn, mx = aabb(tpl) s = mx - mn
	if s.Z > s.X then
		applyCF(tpl, CFrame.Angles(0, math.pi / 2, 0))
		mn, mx = aabb(tpl) s = mx - mn
	end
	stretch(tpl, Vector3.new((DOOR_W - 0.7) / s.X, (DOOR_H - 0.4) / s.Y, math.min(1, 0.5 / s.Z)))
	mn, mx = aabb(tpl)
	applyCF(tpl, CFrame.new(-(mn + mx) / 2))
	local fs = mx - mn
	doorW, doorH = fs.X, fs.Y
	doorTpl = tpl
end

local function findHouseModel()
	local best, bestCount = nil, 0
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and not Players:GetPlayerFromCharacter(d) and not d:FindFirstChildWhichIsA("Humanoid")
			and not (rootFolder and d:IsDescendantOf(rootFolder)) then
			local match
			if HOUSE_MODEL_NAME then match = (d.Name == HOUSE_MODEL_NAME) else match = nameHas(d.Name, HOUSE_WORDS) end
			if match then
				local n = 0
				for _, x in ipairs(d:GetDescendants()) do
					if x:IsA("BasePart") then n += 1 end
				end
				if n >= 4 and n > bestCount then best, bestCount = d, n end
			end
		end
	end
	return best
end

--// ================= ZONES + MAZE LAYOUT =================
local function regionInfo(rx, rz)
	local k = ckey(rx, rz)
	local c = regionCache[k]
	if c then return c end
	local s, pal
	if rx == 0 and rz == 0 then
		s, pal = 3, PALETTES[1]
	else
		local r = rnd(rx, rz, 40)
		if r < 0.25 then s = 1 elseif r < 0.55 then s = 2 elseif r < 0.80 then s = 3 else s = 6 end
		local q = rnd(rx, rz, 41)
		if q < 0.55 then pal = PALETTES[1] elseif q < 0.72 then pal = PALETTES[2] elseif q < 0.86 then pal = PALETTES[3] else pal = PALETTES[4] end
	end
	c = {s = s, pal = pal}
	regionCache[k] = c
	return c
end

local function edge(x, z, dir)
	local ox, oz = x, z
	if dir == 1 then ox = x + 1 else oz = z + 1 end
	if inZone(x, z) or inZone(ox, oz) then return 1 end

	local rx, rz = math.floor(x / R), math.floor(z / R)
	local qx, qz = math.floor(ox / R), math.floor(oz / R)
	if rx ~= qx or rz ~= qz then
		local r = rnd(x, z, 30 + dir)
		if r < 0.15 then return 1 end
		if r < 0.40 then return 2 end
		if r < 0.40 + DOOR_CHANCE then return doorTpl and 3 or 2 end
		return 0
	end

	local s = regionInfo(rx, rz).s
	local lx, lz = x - rx * R, z - rz * R
	local mx, mz = lx + (dir == 1 and 1 or 0), lz + (dir == 2 and 1 or 0)
	local ax, az = math.floor(lx / s), math.floor(lz / s)
	local bx, bz = math.floor(mx / s), math.floor(mz / s)
	if ax == bx and az == bz then return 1 end

	local nb = R / s
	local gx, gz = rx * nb + ax, rz * nb + az
	local carve
	if ax == nb - 1 and az == nb - 1 then carve = 0
	elseif ax == nb - 1 then carve = 2
	elseif az == nb - 1 then carve = 1
	else carve = (rnd(gx, gz, 1 + s) < 0.5) and 1 or 2 end
	local open = (carve == dir) or (rnd(gx, gz, 10 + dir + s * 3) < 0.22)
	if not open then return 0 end
	if s == 1 then return (rnd(x, z, 20 + dir) < 0.55) and 2 or 1 end
	return 1
end

local function hasWindow(x, z, dir)
	local ox, oz = x, z
	if dir == 1 then ox += 1 else oz += 1 end
	local boundary = math.floor(x / R) ~= math.floor(ox / R) or math.floor(z / R) ~= math.floor(oz / R)
	return rnd(x, z, 80 + dir) < (boundary and WINDOW_CHANCE * 2.5 or WINDOW_CHANCE)
end

local function needPost(x, z)
	local W = edge(x, z, 2) ~= 1
	local E = edge(x + 1, z, 2) ~= 1
	local S = edge(x, z, 1) ~= 1
	local N = edge(x, z + 1, 1) ~= 1
	if not (W or E or S or N) then return false end
	if W and E and not N and not S then return false end
	if N and S and not W and not E then return false end
	return true
end

local function wallSeg(parent, center, len, alongZ, y0, h, color, mat, board)
	local size = alongZ and Vector3.new(WALL_T, h, len) or Vector3.new(len, h, WALL_T)
	mk(parent, "Wall", size, CFrame.new(center.X, y0 + h / 2, center.Z), color, mat or Enum.Material.SmoothPlastic)
	if board then
		local bs = alongZ and Vector3.new(WALL_T + 0.3, 0.7, len) or Vector3.new(len, 0.7, WALL_T + 0.3)
		mk(parent, "Baseboard", bs, CFrame.new(center.X, y0 + 0.35, center.Z), C_BOARD, Enum.Material.WoodPlanks)
		if len > CELL - 0.2 then
			local fx, fz = math.floor(center.X), math.floor(center.Z)
			if rnd(fx, fz, 90) < 0.06 then
				local sgn = (rnd(fx, fz, 91) < 0.5) and 1 or -1
				local off = (rnd(fx, fz, 92) - 0.5) * (len - 3)
				local d = WALL_T / 2 + 0.06
				local oc = Color3.fromRGB(205, 195, 170)
				if alongZ then
					mk(parent, "Outlet", Vector3.new(0.12, 0.9, 0.55), CFrame.new(center.X + sgn * d, y0 + 1.5, center.Z + off), oc, Enum.Material.SmoothPlastic)
				else
					mk(parent, "Outlet", Vector3.new(0.55, 0.9, 0.12), CFrame.new(center.X + off, y0 + 1.5, center.Z + sgn * d), oc, Enum.Material.SmoothPlastic)
				end
			end
		end
	end
end

local function attachDoor(m, hingeFrame, openAngle)
	local parts = {}
	local biggest, bv = nil, 0
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			parts[#parts + 1] = {p = p, rel = hingeFrame:ToObjectSpace(p.CFrame)}
			p.CanCollide = true
			local v = p.Size.X * p.Size.Y * p.Size.Z
			if v > bv then biggest, bv = p, v end
		end
	end
	if not biggest then return end

	local angle = Instance.new("NumberValue")
	local function apply(a)
		local rot = CFrame.Angles(0, a, 0)
		for _, d in ipairs(parts) do d.p.CFrame = hingeFrame * rot * d.rel end
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open Door"
	prompt.ObjectText = "Door"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = biggest

	local isOpen, moving = false, false
	prompt.Triggered:Connect(function()
		if moving then return end
		moving = true
		isOpen = not isOpen
		local target = isOpen and openAngle or 0
		for _, d in ipairs(parts) do d.p.CanCollide = false end
		local c = angle.Changed:Connect(apply)
		local tw = TweenService:Create(angle, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Value = target})
		tw.Completed:Connect(function()
			c:Disconnect()
			apply(target)
			if not isOpen then
				for _, d in ipairs(parts) do d.p.CanCollide = true end
			end
			prompt.ActionText = isOpen and "Close Door" or "Open Door"
			moving = false
		end)
		tw:Play()
	end)
end

local function windowWall(parent, mid, alongZ, y0, color, mat)
	local WW, SILL, TOP = 6, 3.2, 8.4
	local side = (CELL - WW) / 2
	local off = WW / 2 + side / 2
	local axis = alongZ and Vector3.new(0, 0, 1) or Vector3.new(1, 0, 0)
	wallSeg(parent, mid + axis * off, side, alongZ, y0, WALL_H, color, mat, true)
	wallSeg(parent, mid - axis * off, side, alongZ, y0, WALL_H, color, mat, true)
	wallSeg(parent, mid, WW, alongZ, y0, SILL, color, mat, true)
	wallSeg(parent, mid, WW, alongZ, y0 + TOP, WALL_H - TOP, color, mat, false)

	local gh = TOP - SILL
	local gsize = alongZ and Vector3.new(0.12, gh, WW) or Vector3.new(WW, gh, 0.12)
	local g = mk(parent, "Glass", gsize, CFrame.new(mid.X, y0 + SILL + gh / 2, mid.Z), Color3.fromRGB(170, 190, 175), Enum.Material.Glass)
	g.Transparency = 0.82
	g.CastShadow = false

	local t2 = WALL_T + 0.3
	local function trim(along, h, yc, aoff, thick)
		local size = alongZ and Vector3.new(thick or t2, h, along) or Vector3.new(along, h, thick or t2)
		local c = mid + axis * aoff
		mk(parent, "Trim", size, CFrame.new(c.X, yc, c.Z), C_BOARD, Enum.Material.WoodPlanks)
	end
	trim(WW + 0.6, 0.3, y0 + SILL + 0.15, 0, WALL_T + 0.6)
	trim(0.3, gh, y0 + SILL + 0.3 + (gh - 0.3) / 2 - 0.15, WW / 2 - 0.15)
	trim(0.3, gh, y0 + SILL + 0.3 + (gh - 0.3) / 2 - 0.15, -(WW / 2 - 0.15))
	trim(WW, 0.3, y0 + TOP - 0.15, 0)
end

local function doorway(parent, mid, alongZ, y0, color, mat, withDoor)
	local side = (CELL - DOOR_W) / 2
	local off = DOOR_W / 2 + side / 2
	local axis = alongZ and Vector3.new(0, 0, 1) or Vector3.new(1, 0, 0)
	wallSeg(parent, mid + axis * off, side, alongZ, y0, WALL_H, color, mat, true)
	wallSeg(parent, mid - axis * off, side, alongZ, y0, WALL_H, color, mat, true)
	wallSeg(parent, mid, DOOR_W, alongZ, y0 + DOOR_H, WALL_H - DOOR_H, color, mat, false)
	if not withDoor then return end

	local t2 = WALL_T + 0.3
	local function trim(along, h, yc, aoff)
		local size = alongZ and Vector3.new(t2, h, along) or Vector3.new(along, h, t2)
		local c = mid + axis * aoff
		mk(parent, "Trim", size, CFrame.new(c.X, yc, c.Z), C_BOARD, Enum.Material.WoodPlanks)
	end
	trim(0.3, DOOR_H - 0.3, y0 + (DOOR_H - 0.3) / 2, DOOR_W / 2 - 0.15)
	trim(0.3, DOOR_H - 0.3, y0 + (DOOR_H - 0.3) / 2, -(DOOR_W / 2 - 0.15))
	trim(DOOR_W, 0.3, y0 + DOOR_H - 0.15, 0)

	local dm = doorTpl:Clone()
	if not dm then return end
	local doorCF = CFrame.new(mid.X, y0 + 0.05 + doorH / 2, mid.Z)
	if alongZ then doorCF = doorCF * CFrame.Angles(0, math.pi / 2, 0) end
	applyCF(dm, doorCF)
	dm.Parent = parent
	local hinge = doorCF * CFrame.new(-doorW / 2, 0, 0)
	local sgn = (rnd(math.floor(mid.X), math.floor(mid.Z), 95) < 0.5) and 1 or -1
	attachDoor(dm, hinge, sgn * math.rad(100))
end

local function buildEdgeWall(parent, cx, cz, dir, state, color, mat)
	if state == 1 then return end
	local base = cellPos(cx, cz)
	local alongZ = (dir == 1)
	local mid = alongZ and (base + Vector3.new(CELL / 2, 0, 0)) or (base + Vector3.new(0, 0, CELL / 2))
	local y0 = BASE.Y
	if state == 0 then
		if hasWindow(cx, cz, dir) then
			windowWall(parent, mid, alongZ, y0, color, mat)
		else
			wallSeg(parent, mid, CELL, alongZ, y0, WALL_H, color, mat, true)
		end
	else
		doorway(parent, mid, alongZ, y0, color, mat, state == 3 and doorTpl ~= nil)
	end
end

local function setLit(e, on)
	e.panel.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
	e.panel.Color = on and Color3.fromRGB(240, 225, 180) or Color3.fromRGB(160, 155, 140)
	if e.light then e.light.Enabled = on end
end

local function makeLight(parent, px, ceilWorldY, pz, lit, withPL)
	mk(parent, "LightFrame", Vector3.new(5.2, 0.35, 5.2), CFrame.new(px, ceilWorldY - 0.175, pz), Color3.fromRGB(140, 136, 120), Enum.Material.Metal)
	local panel = mk(parent, "Light", Vector3.new(4.5, 0.22, 4.5), CFrame.new(px, ceilWorldY - 0.29, pz), Color3.fromRGB(240, 225, 180), Enum.Material.Neon)
	local pl
	if lit and withPL then
		pl = Instance.new("PointLight")
		pl.Range, pl.Brightness, pl.Shadows = 20, LIGHT_BRIGHTNESS, false
		pl.Color = Color3.fromRGB(255, 230, 175)
		pl.Parent = panel
	end
	local e = {panel = panel, light = pl, base = lit}
	setLit(e, lit)
	return e
end

--// ================= CELLS =================
local function buildCell(cx, cz)
	if inRect(mega, cx, cz) or inRect(poolZ, cx, cz) then
		local ef = Instance.new("Folder")
		ef.Name = "Empty"
		ef.Parent = rootFolder
		cells[ckey(cx, cz)] = {folder = ef, x = cx, z = cz}
		return
	end

	local f = Instance.new("Folder")
	f.Name = "Cell"
	local pos = cellPos(cx, cz)
	local zin = inRect(zone, cx, cz)
	local ceilY = zin and zone.h or WALL_H
	local info = regionInfo(math.floor(cx / R), math.floor(cz / R))
	local pal = info.pal
	local farFromSpawn = not (math.abs(cx) <= 2 and math.abs(cz) <= 2)

	local fk = 1 + (rnd(cx, cz, 3) - 0.5) * 0.10
	if rnd(cx, cz, 4) < 0.10 then fk = fk * 0.8 end
	local carpet = shade(pal.carpet, fk)
	local pit = (not zin) and farFromSpawn and rnd(cx, cz, 12) < PIT_CHANCE
	if pit then
		holeBoxes(f, pos.X, pos.Z, 6, BASE.Y - 0.5, 1, carpet, Enum.Material.SmoothPlastic)
		local dk = shade(carpet, 0.45)
		mk(f, "PitBottom", Vector3.new(6, 1, 6), CFrame.new(pos.X, BASE.Y - 4.5, pos.Z), dk, Enum.Material.SmoothPlastic)
		mk(f, "PitWall", Vector3.new(6, 4, 0.4), CFrame.new(pos.X, BASE.Y - 2, pos.Z + 2.8), dk, Enum.Material.SmoothPlastic)
		mk(f, "PitWall", Vector3.new(6, 4, 0.4), CFrame.new(pos.X, BASE.Y - 2, pos.Z - 2.8), dk, Enum.Material.SmoothPlastic)
		mk(f, "PitWall", Vector3.new(0.4, 4, 6), CFrame.new(pos.X + 2.8, BASE.Y - 2, pos.Z), dk, Enum.Material.SmoothPlastic)
		mk(f, "PitWall", Vector3.new(0.4, 4, 6), CFrame.new(pos.X - 2.8, BASE.Y - 2, pos.Z), dk, Enum.Material.SmoothPlastic)
	else
		mk(f, "Floor", Vector3.new(CELL, 1, CELL), CFrame.new(pos.X, BASE.Y - 0.5, pos.Z), carpet, pal.mat)
		if rnd(cx, cz, 8) < 0.12 then
			local d = 3 + rnd(cx, cz, 9) * 4
			local sx = pos.X + (rnd(cx, cz, 10) - 0.5) * 4
			local sz = pos.Z + (rnd(cx, cz, 11) - 0.5) * 4
			local st = mk(f, "Stain", Vector3.new(0.05, d, d), CFrame.new(sx, BASE.Y + 0.08, sz) * CFrame.Angles(0, 0, math.pi / 2), shade(carpet, 0.5), Enum.Material.SmoothPlastic)
			st.Shape = Enum.PartType.Cylinder
			st.Transparency = 0.3
			st.CastShadow = false
		end
	end

	local hasLight = (cx + cz) % 2 == 0
	local shaft = (not zin) and farFromSpawn and (not hasLight) and rnd(cx, cz, 13) < SHAFT_CHANCE
	if shaft then
		holeBoxes(f, pos.X, pos.Z, 5, BASE.Y + ceilY + 0.5, 1, pal.ceil, Enum.Material.SmoothPlastic)
		local dk = Color3.fromRGB(35, 32, 22)
		local sy = BASE.Y + ceilY + 7
		mk(f, "ShaftWall", Vector3.new(5, 14, 0.4), CFrame.new(pos.X, sy, pos.Z + 2.3), dk, Enum.Material.SmoothPlastic)
		mk(f, "ShaftWall", Vector3.new(5, 14, 0.4), CFrame.new(pos.X, sy, pos.Z - 2.3), dk, Enum.Material.SmoothPlastic)
		mk(f, "ShaftWall", Vector3.new(0.4, 14, 5), CFrame.new(pos.X + 2.3, sy, pos.Z), dk, Enum.Material.SmoothPlastic)
		mk(f, "ShaftWall", Vector3.new(0.4, 14, 5), CFrame.new(pos.X - 2.3, sy, pos.Z), dk, Enum.Material.SmoothPlastic)
		mk(f, "ShaftCap", Vector3.new(5.4, 0.6, 5.4), CFrame.new(pos.X, BASE.Y + ceilY + 14.3, pos.Z), dk, Enum.Material.SmoothPlastic)
	else
		mk(f, "Ceiling", Vector3.new(CELL, 1, CELL), CFrame.new(pos.X, BASE.Y + ceilY + 0.5, pos.Z), pal.ceil, Enum.Material.SmoothPlastic)
		if CEILING_GRID then
			local sy = BASE.Y + ceilY - 0.06
			local gc = shade(pal.ceil, 0.55)
			local P = Enum.Material.SmoothPlastic
			mk(f, "Grid", Vector3.new(CELL, 0.12, 0.25), CFrame.new(pos.X, sy, pos.Z), gc, P)
			mk(f, "Grid", Vector3.new(0.25, 0.12, CELL), CFrame.new(pos.X, sy, pos.Z), gc, P)
			mk(f, "Grid", Vector3.new(0.25, 0.12, CELL), CFrame.new(pos.X - CELL / 2, sy, pos.Z), gc, P)
			mk(f, "Grid", Vector3.new(CELL, 0.12, 0.25), CFrame.new(pos.X, sy, pos.Z - CELL / 2), gc, P)
		end
	end

	local entry
	if hasLight then
		entry = makeLight(f, pos.X, BASE.Y + ceilY, pos.Z, rnd(cx, cz, 5) > pal.off, true)
	end

	local wcol = shade(pal.wall, 1 + (rnd(cx, cz, 7) - 0.5) * 0.08)
	buildEdgeWall(f, cx, cz, 1, edge(cx, cz, 1), wcol, pal.mat)
	buildEdgeWall(f, cx, cz, 2, edge(cx, cz, 2), wcol, pal.mat)
	if needPost(cx, cz) then
		local pp = pos + Vector3.new(CELL / 2, 0, CELL / 2)
		mk(f, "Post", Vector3.new(WALL_T + 0.2, WALL_H, WALL_T + 0.2), CFrame.new(pp.X, BASE.Y + WALL_H / 2, pp.Z), wcol, pal.mat)
	end

	if not zin and info.s >= 3 and not (math.abs(cx) <= 1 and math.abs(cz) <= 1) then
		if rnd(cx, cz, 60) < (info.s == 6 and 0.16 or 0.06) then
			local ox = (rnd(cx, cz, 61) - 0.5) * 4
			local oz = (rnd(cx, cz, 62) - 0.5) * 4
			mk(f, "Column", Vector3.new(2.4, WALL_H, 2.4), CFrame.new(pos.X + ox, BASE.Y + WALL_H / 2, pos.Z + oz), shade(pal.wall, 0.96), pal.mat)
			mk(f, "ColumnBase", Vector3.new(2.8, 0.7, 2.8), CFrame.new(pos.X + ox, BASE.Y + 0.35, pos.Z + oz), C_BOARD, Enum.Material.WoodPlanks)
		end
	end

	if not zin and not (cx == 0 and cz == 0) then
		local r = rnd(cx, cz, 70)
		pcall(function()
			if chairTpl and r < CHAIR_CHANCE then
				placeProp(f, chairTpl, cx, cz, true)
			elseif #templates > 0 and r < CHAIR_CHANCE + PROP_CHANCE then
				local idx = math.floor(rnd(cx, cz, 71) * #templates) + 1
				placeProp(f, templates[idx], cx, cz, false)
			end
		end)
	end

	f.Parent = rootFolder
	cells[ckey(cx, cz)] = {folder = f, x = cx, z = cz, entry = entry}
end

local function streamCells(cx, cz, budget)
	if not rootFolder then return end
	local missing = {}
	for dz = -LOAD_R, LOAD_R do
		for dx = -LOAD_R, LOAD_R do
			local x, z = cx + dx, cz + dz
			if not cells[ckey(x, z)] then missing[#missing + 1] = {x, z, dx * dx + dz * dz} end
		end
	end
	table.sort(missing, function(a, b) return a[3] < b[3] end)
	for i = 1, math.min(#missing, budget) do buildCell(missing[i][1], missing[i][2]) end
	for k, c in pairs(cells) do
		if math.max(math.abs(c.x - cx), math.abs(c.z - cz)) > UNLOAD_R then
			c.folder:Destroy()
			cells[k] = nil
		end
	end
end

local nextFlicker = 0
local function updateFlicker(now, cx, cz)
	if now >= nextFlicker then
		nextFlicker = now + math.random(4, 12)
		local tx, tz = cx + math.random(-4, 4), cz + math.random(-4, 4)
		for dx = -2, 2 do
			for dz = -2, 2 do
				local c = cells[ckey(tx + dx, tz + dz)]
				if c and c.entry and c.entry.base and ((dx == 0 and dz == 0) or math.random() < 0.5) then
					flicker[c.entry] = {stop = now + 5, nxt = 0}
				end
			end
		end
		if mega and mega.entries and #mega.entries > 0 and math.random() < 0.5 then
			for _ = 1, 5 do
				local e = mega.entries[math.random(#mega.entries)]
				if e.base and e.panel.Parent then flicker[e] = {stop = now + 5, nxt = 0} end
			end
		end
	end
	for e, f in pairs(flicker) do
		if not e.panel.Parent then
			flicker[e] = nil
		elseif now >= f.stop then
			setLit(e, e.base)
			flicker[e] = nil
		elseif now >= f.nxt then
			setLit(e, math.random() < 0.4)
			f.nxt = now + 0.03 + math.random() * 0.22
		end
	end
end

--// ================= HOUSE =================
local function buildHouse(dirIdx)
	local m
	local src = findHouseModel()
	if src then
		local ok, c = pcall(function() return src:Clone() end)
		if ok and c then m = finishTemplate(c, true, 70) end
	end
	if not m then m = finishTemplate(buildFallbackHouse(), true, nil) end
	if not m then return end

	local mn, mx = aabb(m)
	local size = mx - mn
	local ax = math.ceil(size.X / 2 / CELL) + 1
	local az = math.ceil(size.Z / 2 / CELL) + 1
	local dv = DIRS[dirIdx]
	local dist = math.max(ax, az) + 4 + math.random(0, 3)
	local hx, hz = dv[1] * dist, dv[2] * dist
	local Z = {x0 = hx - ax, x1 = hx + ax, z0 = hz - az, z1 = hz + az, h = math.max(WALL_H, size.Y + 4)}

	applyCF(m, CFrame.new(BASE.X + hx * CELL, BASE.Y + 0.08 + size.Y / 2, BASE.Z + hz * CELL))
	m.Name = "House"
	m.Parent = rootFolder

	if Z.h > WALL_H + 0.2 then
		local hh = Z.h - WALL_H
		local xmin, xmax = BASE.X + (Z.x0 - 0.5) * CELL, BASE.X + (Z.x1 + 0.5) * CELL
		local zmin, zmax = BASE.Z + (Z.z0 - 0.5) * CELL, BASE.Z + (Z.z1 + 0.5) * CELL
		local cy = BASE.Y + WALL_H + hh / 2
		local lx, lz = xmax - xmin, zmax - zmin
		local F, wc = Enum.Material.SmoothPlastic, PALETTES[1].wall
		mk(rootFolder, "Skirt", Vector3.new(lx + WALL_T, hh, WALL_T), CFrame.new((xmin + xmax) / 2, cy, zmin), wc, F)
		mk(rootFolder, "Skirt", Vector3.new(lx + WALL_T, hh, WALL_T), CFrame.new((xmin + xmax) / 2, cy, zmax), wc, F)
		mk(rootFolder, "Skirt", Vector3.new(WALL_T, hh, lz + WALL_T), CFrame.new(xmin, cy, (zmin + zmax) / 2), wc, F)
		mk(rootFolder, "Skirt", Vector3.new(WALL_T, hh, lz + WALL_T), CFrame.new(xmax, cy, (zmin + zmax) / 2), wc, F)
	end
	zone = Z
end

--// ================= MEGA ROOM (5 or 8 Floors Liminal Reveal) =================
local function rampCells(M, k)
	local sz = M.z0 + 1 + math.floor(rnd(k, 7, 100) * 7)
	local sx = (k % 2 == 1) and (M.x0 + 1) or (M.x1 - 3)
	return sx, sz
end

local function layered(parent, cx, cz, sx, sz, yTop, pal)
	mk(parent, "FloorTop", Vector3.new(sx, 0.35, sz), CFrame.new(cx, BASE.Y + yTop - 0.175, cz), pal.carpet, pal.mat)
	mk(parent, "FloorUnder", Vector3.new(sx, 0.65, sz), CFrame.new(cx, BASE.Y + yTop - 0.675, cz), pal.ceil, Enum.Material.SmoothPlastic)
end

local function layeredHole(parent, cx, cz, hs, yTop, pal)
	local strip = (CELL - hs) / 2
	layered(parent, cx, cz + hs / 2 + strip / 2, CELL, strip, yTop, pal)
	layered(parent, cx, cz - hs / 2 - strip / 2, CELL, strip, yTop, pal)
	layered(parent, cx - hs / 2 - strip / 2, cz, strip, hs, yTop, pal)
	layered(parent, cx + hs / 2 + strip / 2, cz, strip, hs, yTop, pal)
end

local function buildMega(dirIdx)
	-- Randomly pick between 5 floors or 8 floors for maximum liminal vertical exposure
	local n = (math.random() < 0.5) and 5 or 8
	local dv = DIRS[dirIdx]
	local dist = 8 + math.random(0, 3)
	local hx, hz = dv[1] * dist, dv[2] * dist
	local M = {x0 = hx - 4, x1 = hx + 4, z0 = hz - 4, z1 = hz + 4, n = n, entries = {}}
	local pal = PALETTES[1]
	local f = Instance.new("Folder")
	f.Name = "MegaRoom"

	local xmin, xmax = BASE.X + (M.x0 - 0.5) * CELL, BASE.X + (M.x1 + 0.5) * CELL
	local zmin, zmax = BASE.Z + (M.z0 - 0.5) * CELL, BASE.Z + (M.z1 + 0.5) * CELL
	local W = xmax - xmin
	local mx0, mz0 = (xmin + xmax) / 2, (zmin + zmax) / 2
	local topY = n * FH - 1

	mk(f, "Floor", Vector3.new(W, 1, W), CFrame.new(mx0, BASE.Y - 0.5, mz0), pal.carpet, pal.mat)
	mk(f, "Ceiling", Vector3.new(W, 1, W), CFrame.new(mx0, BASE.Y + topY + 0.5, mz0), pal.ceil, Enum.Material.SmoothPlastic)

	local function state(k, x, z)
		local rs, rz = rampCells(M, k)
		if z == rz and (x == rs or x == rs + 1) then return "hole" end
		if z == rz and x == rs + 2 then return "slab" end
		if k + 1 <= n - 1 then
			local ns, nz = rampCells(M, k + 1)
			if z == nz and (x == ns or x == ns + 1) then return "slab" end
		end
		local r = rnd(x, z, 200 + k)
		if r < 0.06 then return "hole" elseif r < 0.17 then return "sq" end
		return "slab"
	end

	for k = 1, n - 1 do
		for x = M.x0, M.x1 do
			for z = M.z0, M.z1 do
				local st = state(k, x, z)
				local p = cellPos(x, z)
				if st == "slab" then
					layered(f, p.X, p.Z, CELL, CELL, k * FH, pal)
				elseif st == "sq" then
					layeredHole(f, p.X, p.Z, 6, k * FH, pal)
				end
			end
		end
	end

	for k = 0, n - 1 do
		local ceilWorld = BASE.Y + (k + 1) * FH - 1
		for x = M.x0, M.x1 do
			for z = M.z0, M.z1 do
				if (x - M.x0) % 2 == 0 and (z - M.z0) % 2 == 0 then
					local okSlab = (k + 1 > n - 1) or state(k + 1, x, z) == "slab"
					if okSlab then
						local p = cellPos(x, z)
						local pl = (((x - M.x0) / 2 + (z - M.z0) / 2 + k) % 2 == 0)
						local e = makeLight(f, p.X, ceilWorld, p.Z, rnd(x, z, 300 + k) > 0.15, pl)
						M.entries[#M.entries + 1] = e
					end
				end
			end
		end
	end

	for i = 1, 4 do
		for j = 1, 4 do
			local cxp, czp = xmin + 24 * i, zmin + 24 * j
			mk(f, "Column", Vector3.new(2.6, topY, 2.6), CFrame.new(cxp, BASE.Y + topY / 2, czp), shade(pal.wall, 0.95), pal.mat)
		end
	end

	for k = 1, n - 1 do
		local rs, rz = rampCells(M, k)
		local a = Vector3.new(BASE.X + (rs - 0.5) * CELL, BASE.Y + (k - 1) * FH, BASE.Z + rz * CELL)
		local b = Vector3.new(BASE.X + (rs + 1.5) * CELL, BASE.Y + k * FH, BASE.Z + rz * CELL)
		rampPart(f, a, b, 8, pal.carpet, pal.mat)
	end

	local topAbs = BASE.Y + topY + 1
	local hh = topAbs - (BASE.Y + WALL_H)
	local cy = BASE.Y + WALL_H + hh / 2
	local F, wc = Enum.Material.SmoothPlastic, pal.wall
	mk(f, "Skirt", Vector3.new(W + WALL_T, hh, WALL_T), CFrame.new(mx0, cy, zmin), wc, F)
	mk(f, "Skirt", Vector3.new(W + WALL_T, hh, WALL_T), CFrame.new(mx0, cy, zmax), wc, F)
	mk(f, "Skirt", Vector3.new(WALL_T, hh, W + WALL_T), CFrame.new(xmin, cy, mz0), wc, F)
	mk(f, "Skirt", Vector3.new(WALL_T, hh, W + WALL_T), CFrame.new(xmax, cy, mz0), wc, F)

	f.Parent = rootFolder
	M.wxmin, M.wxmax, M.wzmin, M.wzmax = xmin, xmax, zmin, zmax
	mega = M
end

--// ================= POOLROOMS (Dimmed & Detailed) =================
local WATER_PROPS = {"WaterColor", "WaterTransparency", "WaterReflectance", "WaterWaveSize", "WaterWaveSpeed"}

local function buildPool(dirIdx)
	local dv = DIRS[dirIdx]
	local dist = 12 + math.random(0, 3)
	local hx, hz = dv[1] * dist, dv[2] * dist
	local Zr = {x0 = hx - 7, x1 = hx + 7, z0 = hz - 7, z1 = hz + 7}
	local ox, oz, oy = BASE.X + hx * CELL, BASE.Z + hz * CELL, BASE.Y
	local f = Instance.new("Folder")
	f.Name = "PoolRooms"

	local TILE = Color3.fromRGB(195, 210, 215)
	local TILE2 = Color3.fromRGB(135, 175, 185)
	local BANDC = Color3.fromRGB(52, 125, 142)
	local DARK = Color3.fromRGB(35, 65, 75)
	local WHITE = Color3.fromRGB(240, 245, 250)
	local SP, NEON, GLASS = Enum.Material.SmoothPlastic, Enum.Material.Neon, Enum.Material.Glass

	local function P(name, x0, x1, y0, y1, z0, z1, color, mat, refl)
		local p = mk(f, name, Vector3.new(x1 - x0, y1 - y0, z1 - z0),
			CFrame.new(ox + (x0 + x1) / 2, oy + (y0 + y1) / 2, oz + (z0 + z1) / 2), color, mat or SP)
		if refl then p.Reflectance = refl end
		return p
	end
	
	-- Dimmed lighting for PoolRooms (so it's not blindingly bright)
	local function addLight(part, range, bright)
		local pl = Instance.new("PointLight")
		pl.Range, pl.Brightness, pl.Shadows = range, bright * 0.4, false -- dimmed down
		pl.Color = Color3.fromRGB(175, 215, 235)
		pl.Parent = part
	end
	local function glowLight(x, y, z, range, bright)
		local a = P("Glow", x - 0.2, x + 0.2, y - 0.2, y + 0.2, z - 0.2, z + 0.2, WHITE, SP)
		a.Transparency = 1
		a.CanCollide = false
		a.CastShadow = false
		addLight(a, range, bright)
	end

	local function deck(x0, x1, z0, z1) P("Deck", x0, x1, -2, 0, z0, z1, TILE, SP, 0.04) end
	deck(-78, 78, -78, -72) deck(-78, 78, 72, 78) deck(-78, -72, -72, 72) deck(72, 78, -72, 72)
	deck(-72, 72, 32, 40) deck(-72, -32, -32, 32) deck(32, 72, -32, 32)
	deck(-72, 72, -40, -32) deck(-40, 40, -72, -40)
	deck(-90, 90, 80, 88) deck(-90, 90, -88, -80) deck(80, 88, -80, 80) deck(-88, -80, -80, 80)

	P("CorridorRoof", -90, 90, 14, 16, 80, 88, TILE)
	P("CorridorRoof", -90, 90, 14, 16, -88, -80, TILE)
	P("CorridorRoof", 80, 88, 14, 16, -80, 80, TILE)
	P("CorridorRoof", -88, -80, 14, 16, -80, 80, TILE)
	P("HallCeiling", -90, 90, 28, 30, -90, 90, TILE)
	
	for i = -2, 2 do
		for j = -2, 2 do
			local pn = P("CeilPanel", i * 30 - 5, i * 30 + 5, 27.7, 28, j * 30 - 5, j * 30 + 5, WHITE, NEON)
			if (i + j) % 2 == 0 then addLight(pn, 45, 0.35) end
		end
	end

	P("CorridorNeon", -88, 88, 13.6, 14, 83.5, 84.5, WHITE, NEON)
	P("CorridorNeon", -88, 88, 13.6, 14, -84.5, -83.5, WHITE, NEON)
	P("CorridorNeon", 83.5, 84.5, 13.6, 14, -80, 80, WHITE, NEON)
	P("CorridorNeon", -84.5, -83.5, 13.6, 14, -80, 80, WHITE, NEON)
	for _, p in ipairs({{0, 84}, {0, -84}, {84, 0}, {-84, 0}, {50, 84}, {-50, -84}, {84, -50}, {-84, 50}}) do
		glowLight(p[1], 12, p[2], 25, 0.4)
	end

	local function basin(x0, x1, z0, z1)
		P("BasinFloor", x0 - 2, x1 + 2, -14, -12, z0 - 2, z1 + 2, TILE2, SP, 0.08)
		P("BasinW", x0 - 2, x0, -14, -2, z0 - 2, z1 + 2, TILE2)
		P("BasinE", x1, x1 + 2, -14, -2, z0 - 2, z1 + 2, TILE2)
		P("BasinS", x0 - 2, x1 + 2, -14, -2, z0 - 2, z0, TILE2)
		P("BasinN", x0 - 2, x1 + 2, -14, -2, z1, z1 + 2, TILE2)
	end
	local pools = {{-72, 72, 40, 72}, {-72, -40, -72, -40}, {40, 72, -72, -40}}
	for _, q in ipairs(pools) do basin(q[1], q[2], q[3], q[4]) end

	for _, lz in ipairs({48, 56, 64}) do P("Lane", -72, 72, -12, -11.9, lz - 0.3, lz + 0.3, DARK) end
	for _, lz in ipairs({-48, -56, -64}) do
		P("Lane", -72, -40, -12, -11.9, lz - 0.3, lz + 0.3, DARK)
		P("Lane", 40, 72, -12, -11.9, lz - 0.3, lz + 0.3, DARK)
	end

	local UW = Color3.fromRGB(150, 210, 225)
	for _, x in ipairs({-60, -36, -12, 12, 36, 60}) do P("UWLight", x - 1.5, x + 1.5, -9, -7, 71.7, 72, UW, NEON) end
	for _, x in ipairs({-56, 56}) do P("UWLight", x - 1.5, x + 1.5, -9, -7, -72, -71.7, UW, NEON) end

	for _, x in ipairs({-56, 56}) do
		rampPart(f, Vector3.new(ox + x, oy - 12, oz + 60), Vector3.new(ox + x, oy, oz + 40), 8, TILE2, SP)
		rampPart(f, Vector3.new(ox + x, oy - 12, oz - 60), Vector3.new(ox + x, oy, oz - 40), 8, TILE2, SP)
	end

	P("CanalWall", -40, 40, -2, 6, 38, 40, TILE2)
	P("CanalWall", -40, 40, -2, 6, 72, 74, TILE2)
	P("CanalRoof", -40, 40, 4, 6, 38, 74, TILE, SP, 0.04)

	P("PitWall", -34, 34, -122, -2, 32, 34, TILE)
	P("PitWall", -34, 34, -122, -2, -34, -32, TILE)
	P("PitWall", 32, 34, -122, -2, -32, 32, TILE)
	P("PitWall", -34, -32, -122, -2, -32, 32, TILE)
	P("PitFloor", -34, 34, -122, -120, -34, 34, TILE2, SP, 0.08)
	
	for _, y in ipairs({-15, -45, -75, -105}) do glowLight(0, y, 0, 50, 0.5) end

	local corners = {{-29, 29}, {29, 29}, {29, -29}, {-29, -29}}
	local y = 0
	for i = 0, 11 do
		local a = corners[i % 4 + 1]
		local b = corners[(i + 1) % 4 + 1]
		P("Landing", a[1] - 3.5, a[1] + 3.5, y - 1, y, a[2] - 3.5, a[2] + 3.5, TILE)
		rampPart(f, Vector3.new(ox + a[1], oy + y, oz + a[2]), Vector3.new(ox + b[1], oy + y - 10, oz + b[2]), 7, TILE, SP)
		y = y - 10
	end

	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	local function fillWater(cx, cy, cz, sx, sy, sz)
		local cf = CFrame.new(ox + cx, oy + cy, oz + cz)
		local size = Vector3.new(sx, sy, sz)
		if terrain then pcall(function() terrain:FillBlock(cf, size, Enum.Material.Water) end) end
		waterFills[#waterFills + 1] = {cf = cf, size = size}
	end
	fillWater(0, -8, 56, 144, 8, 32)
	fillWater(-56, -8, -56, 32, 8, 32)
	fillWater(56, -8, -56, 32, 8, 32)
	fillWater(0, -110, 0, 64, 20, 64)

	if terrain then
		savedWater = {}
		local newProps = {WaterColor = Color3.fromRGB(50, 130, 150), WaterTransparency = 0.8, WaterReflectance = 0.2, WaterWaveSize = 0.03, WaterWaveSpeed = 4}
		for _, k in ipairs(WATER_PROPS) do
			pcall(function()
				savedWater[k] = terrain[k]
				terrain[k] = newProps[k]
			end)
		end
	end

	f.Parent = rootFolder
	Zr.wx, Zr.wz = ox, oz
	poolZ = Zr
end

--// ================= LIGHTING =================
local LIGHT_PROPS = {"Ambient", "OutdoorAmbient", "Brightness", "ClockTime", "FogColor", "FogStart", "FogEnd",
	"GlobalShadows", "ExposureCompensation", "EnvironmentDiffuseScale", "EnvironmentSpecularScale"}

local function applyLighting()
	savedLighting = {props = {}, restore = {}, extras = {}}
	for _, p in ipairs(LIGHT_PROPS) do
		local ok, v = pcall(function() return Lighting[p] end)
		if ok then savedLighting.props[p] = v end
	end
	for _, d in ipairs(Lighting:GetChildren()) do
		if d:IsA("PostEffect") then
			local old = d.Enabled
			d.Enabled = false
			savedLighting.restore[#savedLighting.restore + 1] = function() d.Enabled = old end
		elseif d:IsA("Atmosphere") then
			local od, oh = d.Density, d.Haze
			d.Density, d.Haze = 0, 0
			savedLighting.restore[#savedLighting.restore + 1] = function() d.Density, d.Haze = od, oh end
		end
	end
	local function set(p, v) pcall(function() Lighting[p] = v end) end
	set("Brightness", 0)
	set("ClockTime", 0)
	set("GlobalShadows", false)
	set("EnvironmentDiffuseScale", 0)
	set("EnvironmentSpecularScale", 0)

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "BR_CC"
	cc.TintColor = LOOKS.back.tint
	cc.Saturation = -0.15
	cc.Contrast = 0.2
	cc.Brightness = -0.06
	cc.Parent = Lighting
	local bl = Instance.new("BloomEffect")
	bl.Name = "BR_Bloom"
	bl.Intensity, bl.Size, bl.Threshold = 0.15, 14, 1.4
	bl.Parent = Lighting
	savedLighting.extras = {cc, bl}
	savedLighting.cc = cc

	local b = LOOKS.back
	look = {amb = b.amb, fog = b.fog, tint = b.tint, fs = b.fs, fe = b.fe, ex = b.ex}
	set("Ambient", look.amb)
	set("OutdoorAmbient", look.amb)
	set("FogColor", look.fog)
	set("FogStart", look.fs)
	set("FogEnd", look.fe)
	set("ExposureCompensation", look.ex)
end

local function lookStep(dt, target)
	if not look then return end
	local a = math.min(1, dt * 2.5)
	look.amb = look.amb:Lerp(target.amb, a)
	look.fog = look.fog:Lerp(target.fog, a)
	look.tint = look.tint:Lerp(target.tint, a)
	look.fs = look.fs + (target.fs - look.fs) * a
	look.fe = look.fe + (target.fe - look.fe) * a
	look.ex = look.ex + (target.ex - look.ex) * a
	pcall(function()
		Lighting.Ambient = look.amb
		Lighting.OutdoorAmbient = look.amb
		Lighting.FogColor = look.fog
		Lighting.FogStart = look.fs
		Lighting.FogEnd = look.fe
		Lighting.ExposureCompensation = look.ex
	end)
	if savedLighting and savedLighting.cc then savedLighting.cc.TintColor = look.tint end
end

local function restoreLighting()
	look = nil
	if not savedLighting then return end
	for _, e in ipairs(savedLighting.extras) do pcall(function() e:Destroy() end) end
	for p, v in pairs(savedLighting.props) do pcall(function() Lighting[p] = v end) end
	for _, fn in ipairs(savedLighting.restore) do pcall(fn) end
	savedLighting = nil
end

local function clearWater()
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		for _, w in ipairs(waterFills) do
			pcall(function() terrain:FillBlock(w.cf, w.size, Enum.Material.Air) end)
		end
		if savedWater then
			for k, v in pairs(savedWater) do pcall(function() terrain[k] = v end) end
		end
	end
	waterFills, savedWater = {}, nil
end

--// ================= NOTICE & OVERLAY =================
local function showLoadedNotice()
	task.spawn(function()
		local cam = Workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local gui = Instance.new("ScreenGui")
		gui.Name = "BR_Notice"
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 999998
		parentGui(gui)
		noticeGui = gui

		local size = math.clamp(math.floor(vp.X / 30), 16, 34)
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0)
		bar.Size = UDim2.new(0.84, 0, 0, size * 2.4)
		bar.Position = UDim2.new(0.5, 0, 0, -120)
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BackgroundTransparency = 0.35
		bar.BorderSizePixel = 0
		bar.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(215, 195, 100)
		stroke.Parent = bar

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.new(1, -20, 1, -10)
		lbl.Position = UDim2.new(0, 10, 0, 5)
		lbl.Font = Enum.Font.Arcade
		lbl.Text = "Backrooms Has Been Loaded. Goodluck Wanderer"
		lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.TextStrokeTransparency = 0.3
		lbl.TextScaled = true
		lbl.Parent = bar
		local lim = Instance.new("UITextSizeConstraint")
		lim.MaxTextSize = size
		lim.Parent = lbl

		local tin = TweenService:Create(bar, TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.new(0.5, 0, 0, 36)})
		tin:Play()
		tin.Completed:Wait()
		task.wait(5)
		if not alive then return end
		local tout = TweenService:Create(bar, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position = UDim2.new(0.5, 0, 0, -120)})
		tout:Play()
		tout.Completed:Wait()
		gui:Destroy()
		noticeGui = nil
	end)
end

print("Backrooms v3.5 loaded successfully!")
