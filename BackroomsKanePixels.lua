--[[
	BACKROOMS NOCLIP v5  |  LocalScript (client-sided)  |  Delta compatible
	- every 1s: 10% chance to noclip (only the part you stand on loses collision)
	- walking into a wall: 50% chance (only that wall loses collision)
	- VHS intro -> infinite backrooms, VHS camcorder overlay STAYS ON + found-footage camera bob
	- backrooms: striped yellow wallpaper, carpet, white square lights, pillars, dead ends, few windows,
	  doors (model 9343670755) with "Open Door"
	- big rooms: 2 / 8 floor mega rooms AND a yellow multi-floor ATRIUM TOWER (up to 9 floors, stairs, NO barriers)
	- square holes (pits + ceiling shafts) in normal backrooms
	- THE POOLROOMS: infinite sideways AND infinite floors (every floor is another PoolRooms, stairs between them),
	  small tiles with grout, arches, round lights, portholes, swimmable water, pool halls, tiered atriums
	- no copied game objects inside the PoolRooms, backrooms use no fabric except the carpet
	- Roblox's default walking sound is muted in the backrooms, replaced by your own (loud) walking sounds
	- own ambient sound in the PoolRooms (94241101968368)
	- respawn (reset) = back to the normal game
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
local AMBIENT_SOUND_ID = 137406302438919  -- backrooms ambient
local POOL_AMBIENT_ID  = 94241101968368   -- PoolRooms ambient (only plays in the PoolRooms)
local WALK_SOUND_BACK  = 89575970505811   -- walking on backrooms floor
local WALK_SOUND_POOL  = 96516907071037   -- walking on poolrooms floor
local CHAIR_ASSET_ID   = 74698525718385
local DOOR_ASSET_ID    = 9343670755
local HOUSE_CHANCE     = 0.10            -- chance a house exists in the backrooms
local MEGA_CHANCE      = 0.35            -- chance of a big multi-floor map (half of those are the atrium tower)
local POOL_CHANCE      = 0.50            -- chance the PoolRooms exist (they then go on forever on one side)
local HOUSE_MODEL_NAME = nil             -- exact name of the house model in your game (nil = auto-detect)
local DOOR_CHANCE      = 0.04            -- chance per zone-border wall piece to be a door
local WINDOW_CHANCE    = 0.015           -- windows are rare now (x2.5 on zone borders)
local PIT_CHANCE       = 0.025           -- square floor pits in normal cells
local SHAFT_CHANCE     = 0.02            -- square ceiling shafts in normal cells
local LIGHT_BRIGHTNESS = 0.55            -- backrooms ceiling light brightness (lower = darker)
local CEILING_GRID     = true            -- ceiling tile lines
local WALL_STRIPES     = true            -- vertical wallpaper stripes
local CAMERA_BOB       = true            -- found-footage walking camera
local STEP_VOLUME      = 3               -- walking sounds loudness (Roblox allows up to 10)
local MUTE_DEFAULT_STEPS = true          -- silence Roblox's default walking sound inside the backrooms
local T_TITLE, T_SUB, T_END = 3, 6, 11   -- seconds: BACKROOMS / Produced By Hecker / screen vanishes
local STOP_INTRO_ON_REVEAL = true

-- PoolRooms tile look
local TILE_TEXTURE_ID  = 6372755229      -- square grid image (grout lines / wallpaper stripes). Put another grid texture id here if you like
local TILE_SIZE        = 1.5             -- studs per tile
local TILE_LINE_TRANSPARENCY = 0.35      -- 1 = no grout lines, 0 = strong grout lines
local PH               = 17              -- PoolRooms ceiling height
local PLH              = PH + 3          -- floor-to-floor height of the PoolRooms (stacked floors)

local PROP_CHANCE  = 0.04                -- per cell chance of a copied model (backrooms only)
local CHAIR_CHANCE = 0.03                -- per cell chance of a chair (backrooms only)

local BASE = Vector3.new(0, 3000, 0)     -- where the backrooms live
local CELL, WALL_H, WALL_T = 12, 13, 0.8
local FH = WALL_H + 1                    -- floor-to-floor height in the big backrooms maps
local DOOR_W, DOOR_H = 7, 9.5
local R = 6                              -- zone size in cells
local LOAD_R, UNLOAD_R = 8, 11
local DIRS = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

local C_BOARD = Color3.fromRGB(105, 88, 46)

-- backrooms looks copied from the reference photos
local PALETTES = {
	{wall = Color3.fromRGB(214, 182, 52),  carpet = Color3.fromRGB(186, 148, 38), ceil = Color3.fromRGB(140, 112, 56), off = 0.12}, -- classic bright yellow
	{wall = Color3.fromRGB(196, 192, 84),  carpet = Color3.fromRGB(186, 176, 80), ceil = Color3.fromRGB(150, 148, 96), off = 0.15}, -- green-yellow pillars
	{wall = Color3.fromRGB(222, 204, 140), carpet = Color3.fromRGB(198, 192, 160), ceil = Color3.fromRGB(205, 198, 160), off = 0.15}, -- pale cream
	{wall = Color3.fromRGB(186, 156, 48),  carpet = Color3.fromRGB(96, 88, 80),   ceil = Color3.fromRGB(160, 140, 90), off = 0.30}, -- dark chevron + grey carpet
}

-- PoolRooms colours per floor (soft, not bright). Floor numbers repeat every 3
local POOLPAL = {
	{floor = Color3.fromRGB(190, 186, 178), wall = Color3.fromRGB(198, 194, 186), ceil = Color3.fromRGB(176, 173, 166), basin = Color3.fromRGB(146, 186, 192)},
	{floor = Color3.fromRGB(166, 196, 182), wall = Color3.fromRGB(176, 204, 190), ceil = Color3.fromRGB(150, 178, 164), basin = Color3.fromRGB(120, 190, 170)},
	{floor = Color3.fromRGB(184, 204, 208), wall = Color3.fromRGB(194, 212, 216), ceil = Color3.fromRGB(168, 188, 192), basin = Color3.fromRGB(130, 196, 206)},
}
local P_FLOOR, P_WALL, P_CEIL, P_BASIN = POOLPAL[1].floor, POOLPAL[1].wall, POOLPAL[1].ceil, POOLPAL[1].basin
local P_GLOW = Color3.fromRGB(176, 196, 192)

-- look of each area (lerped while you walk between them)
local LOOKS = {
	back = {amb = Color3.fromRGB(26, 23, 12),  fog = Color3.fromRGB(10, 9, 4),     tint = Color3.fromRGB(255, 240, 200), fs = 12, fe = 92,  ex = -0.3},
	mega = {amb = Color3.fromRGB(26, 23, 12),  fog = Color3.fromRGB(10, 9, 4),     tint = Color3.fromRGB(255, 240, 200), fs = 30, fe = 260, ex = -0.3},
	pool = {amb = Color3.fromRGB(58, 76, 70),  fog = Color3.fromRGB(62, 88, 80),   tint = Color3.fromRGB(205, 236, 225), fs = 20, fe = 115, ex = -0.12},
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
local rootFolder, ambience, poolAmbience, introSound, overlay, noticeGui
local cells, templates, flicker = {}, {}, {}
local chairTpl, doorTpl
local zone, mega                         -- house / big multi-floor map rectangles (in cells)
local poolCfg                            -- infinite PoolRooms side: {axis = 1|2, sign = 1|-1}
local poolRegionCache, poolSites, stairCache = {}, {}, {}
local waterOK = false
local doorW, doorH = DOOR_W - 0.7, DOOR_H - 0.4
local SEED = 1
local LV = 0                             -- PoolRooms floor currently being generated
local playerLv = 0                       -- PoolRooms floor the player is on
local regionCache = {}
local savedLighting, savedWater, look
local stepSounds = {}
local mutedSounds = {}
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
local function ckey3(x, z, lv) return ckey(x, z) * 100 + lv + 50 end
local function cellPos(x, z) return BASE + Vector3.new(x * CELL, 0, z * CELL) end
local function inRect(r, x, z)
	return r ~= nil and x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1
end
local function inZone(x, z)
	return inRect(zone, x, z) or inRect(mega, x, z)
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
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- ramp whose top surface runs exactly from point a to point b
local function rampPart(parent, a, b, width, color, mat)
	local thick = 1
	local rot = CFrame.lookAt(Vector3.zero, b - a)
	local center = (a + b) / 2 - rot.UpVector * (thick / 2)
	return mk(parent, "Ramp", Vector3.new(width, thick, (b - a).Magnitude), CFrame.new(center) * rot, color, mat)
end

-- slab with a square hole in the middle (returns the 4 parts)
local function holeBoxes(parent, cx, cz, hs, yc, thick, color, mat)
	local strip = (CELL - hs) / 2
	return {
		mk(parent, "Part", Vector3.new(CELL, thick, strip), CFrame.new(cx, yc, cz + hs / 2 + strip / 2), color, mat),
		mk(parent, "Part", Vector3.new(CELL, thick, strip), CFrame.new(cx, yc, cz - hs / 2 - strip / 2), color, mat),
		mk(parent, "Part", Vector3.new(strip, thick, hs), CFrame.new(cx - hs / 2 - strip / 2, yc, cz), color, mat),
		mk(parent, "Part", Vector3.new(strip, thick, hs), CFrame.new(cx + hs / 2 + strip / 2, yc, cz), color, mat),
	}
end

-- real stairs (solid steps) running +X for 24 studs
local function buildStairs(parent, xs, y0, zc, rise, steps, width, color, mat, tile)
	local h = rise / steps
	local tread = 24 / steps
	for i = 0, steps - 1 do
		local th = h * (i + 1)
		local p = mk(parent, "Step", Vector3.new(tread, th, width), CFrame.new(xs + tread * (i + 0.5), y0 + th / 2, zc), color, mat)
		if tile then
			local t = Instance.new("Texture")
			t.Texture = "rbxassetid://" .. TILE_TEXTURE_ID
			t.Face = Enum.NormalId.Top
			t.StudsPerTileU = TILE_SIZE
			t.StudsPerTileV = TILE_SIZE
			t.Transparency = TILE_LINE_TRANSPARENCY
			t.Parent = p
		end
	end
end

--// ================= TEXTURES =================
local NTOP, NBOT = Enum.NormalId.Top, Enum.NormalId.Bottom
local NFRONT, NBACK = Enum.NormalId.Front, Enum.NormalId.Back
local NLEFT, NRIGHT = Enum.NormalId.Left, Enum.NormalId.Right

-- small tiles with grout lines (PoolRooms)
local function tiled(part, ...)
	for _, face in ipairs({...}) do
		local t = Instance.new("Texture")
		t.Texture = "rbxassetid://" .. TILE_TEXTURE_ID
		t.Face = face
		t.StudsPerTileU = TILE_SIZE
		t.StudsPerTileV = TILE_SIZE
		t.Transparency = TILE_LINE_TRANSPARENCY
		t.Parent = part
	end
	return part
end

-- vertical wallpaper stripes (backrooms)
local function stripes(part, alongZ, wallColor)
	if not WALL_STRIPES then return end
	local faces = alongZ and {NRIGHT, NLEFT} or {NFRONT, NBACK}
	for _, face in ipairs(faces) do
		local t = Instance.new("Texture")
		t.Texture = "rbxassetid://" .. TILE_TEXTURE_ID
		t.Face = face
		t.StudsPerTileU = 0.45
		t.StudsPerTileV = 60
		t.Transparency = 0.72
		t.Color3 = shade(wallColor, 0.55)
		t.Parent = part
	end
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

-- non-uniform scale around the origin (model must be centered at origin)
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
	p.Material = mat or Enum.Material.Plastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function buildFallbackChair()
	local m = Instance.new("Model")
	m.Name = "Chair"
	local col, mat = Color3.fromRGB(70, 62, 55), Enum.Material.Metal
	box(m, "Seat", 2.2, 0.25, 2.2, 0, 1.7, 0, Color3.fromRGB(120, 90, 55), Enum.Material.Wood)
	box(m, "Back", 2.2, 2, 0.25, 0, 2.9, -1, Color3.fromRGB(120, 90, 55), Enum.Material.Wood)
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
	box(m, "Slab", 6.3, 9.1, 0.5, 0, 4.55, 0, Color3.fromRGB(110, 78, 45), Enum.Material.Wood)
	box(m, "Handle", 0.35, 0.35, 0.8, 2.4, 4.3, 0, Color3.fromRGB(190, 170, 90), Enum.Material.Metal)
	return m
end

local function buildFallbackHouse()
	local m = Instance.new("Model")
	m.Name = "House"
	local W, D, H = 26, 22, 10.5
	local wallC, wood = Color3.fromRGB(225, 220, 205), Color3.fromRGB(130, 95, 60)
	box(m, "Floor", W, 1, D, 0, 0.5, 0, wood, Enum.Material.Wood)
	box(m, "Back", W, H, 1, 0, 1 + H / 2, D / 2, wallC)
	box(m, "Left", 1, H, D, -W / 2, 1 + H / 2, 0, wallC)
	box(m, "Right", 1, H, D, W / 2, 1 + H / 2, 0, wallC)
	local side = (W - 5) / 2
	box(m, "FrontL", side, H, 1, -(2.5 + side / 2), 1 + H / 2, -D / 2, wallC)
	box(m, "FrontR", side, H, 1, (2.5 + side / 2), 1 + H / 2, -D / 2, wallC)
	box(m, "Lintel", 5, H - 8, 1, 0, 1 + 8 + (H - 8) / 2, -D / 2, wallC)
	box(m, "Roof", W + 2, 1, D + 2, 0, 1 + H + 0.5, 0, Color3.fromRGB(90, 70, 60), Enum.Material.Slate)
	box(m, "Divider", 1, H, D * 0.6, 2, 1 + H / 2, D / 2 - D * 0.3, wallC)
	box(m, "Table", 4, 0.4, 2.5, -7, 3, -4, wood, Enum.Material.Wood)
	for _, tx in ipairs({-8.6, -5.4}) do
		for _, tz in ipairs({-5, -3}) do
			box(m, "TLeg", 0.3, 2, 0.3, tx, 2, tz, wood, Enum.Material.Wood)
		end
	end
	for _, lx in ipairs({-6, 8}) do
		local bulb = box(m, "Bulb", 2, 0.3, 2, lx, H + 0.7, 0, Color3.fromRGB(255, 244, 214), Enum.Material.Neon)
		local pl = Instance.new("PointLight")
		pl.Range, pl.Brightness, pl.Shadows = 30, 1.0, false
		pl.Color = Color3.fromRGB(255, 238, 200)
		pl.Parent = bulb
	end
	return m
end

--// ================= TEMPLATES (copied game models, backrooms only) =================
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

	-- height on Y
	local mn, mx = aabb(tpl)
	local s = mx - mn
	if s.X >= s.Y and s.X >= s.Z then
		applyCF(tpl, CFrame.Angles(0, 0, math.pi / 2))
	elseif s.Z >= s.Y and s.Z >= s.X then
		applyCF(tpl, CFrame.Angles(math.pi / 2, 0, 0))
	end
	mn, mx = aabb(tpl) s = mx - mn
	-- width on X, thickness on Z
	if s.Z > s.X then
		applyCF(tpl, CFrame.Angles(0, math.pi / 2, 0))
		mn, mx = aabb(tpl) s = mx - mn
	end
	-- fit the doorway
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
-- each zone (R x R cells) picks a block size: 1 = tight corridors, 2 = normal, 3 = wide, 6 = huge open hall
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
		if q < 0.50 then pal = PALETTES[1] elseif q < 0.68 then pal = PALETTES[2] elseif q < 0.84 then pal = PALETTES[3] else pal = PALETTES[4] end
	end
	c = {s = s, pal = pal}
	regionCache[k] = c
	return c
end

-- the PoolRooms are one whole side of the map (infinite sideways, and infinite floors up and down)
local function isPoolCell(x, z)
	if not poolCfg then return false end
	local k = math.floor((poolCfg.axis == 1 and x or z) / R)
	if poolCfg.sign == 1 then return k >= 2 end
	return k <= -3
end

-- PoolRooms zone types: "maze" (corridors, rooms, small pools), "hall" (big pool), "atrium" (tiers + skylight)
local function poolRegion(rx, rz)
	local k = ckey(rx, rz)
	local c = poolRegionCache[k]
	if c then return c end
	local kind, s = "maze", 2
	local v = rnd(rx, rz, 140)
	local special = v < 0.4
	if special then
		for dx = -1, 1 do
			for dz = -1, 1 do
				if (dx ~= 0 or dz ~= 0) and rnd(rx + dx, rz + dz, 140) < v then special = false end
			end
		end
	end
	if special then
		kind = (rnd(rx, rz, 141) < 0.5) and "atrium" or "hall"
	else
		local q = rnd(rx, rz, 142)
		if q < 0.3 then s = 2 elseif q < 0.7 then s = 3 else s = 6 end
	end
	c = {kind = kind, s = s}
	poolRegionCache[k] = c
	return c
end

local function isSpecialCell(x, z)
	return isPoolCell(x, z) and poolRegion(math.floor(x / R), math.floor(z / R)).kind ~= "maze"
end

-- floors that collide with the big pool halls / atriums on floor 0 stay empty above/below them
local function blockedLv(lv) return lv == -1 or lv == 1 or lv == 2 end

local function adjSpecial(cx, cz, dir)
	local ox, oz = cx, cz
	if dir == 1 then ox = cx + 1 else oz = cz + 1 end
	return isSpecialCell(cx, cz) or isSpecialCell(ox, oz)
end

-- dir 1 = east edge of cell, dir 2 = north edge. returns 0 wall, 1 open, 2 doorway, 3 door
local function edge(x, z, dir)
	local ox, oz = x, z
	if dir == 1 then ox = x + 1 else oz = z + 1 end
	if inZone(x, z) or inZone(ox, oz) then return 1 end

	local rx, rz = math.floor(x / R), math.floor(z / R)
	local qx, qz = math.floor(ox / R), math.floor(oz / R)
	local pa, pb = isPoolCell(x, z), isPoolCell(ox, oz)
	local ls = (pa or pb) and LV * 977 or 0 -- every PoolRooms floor has its own layout
	if rx ~= qx or rz ~= qz then
		-- border between two zones
		if pa or pb then
			if LV ~= 0 and pa ~= pb then return 0 end
			local r = rnd(x, z, 130 + dir + ls)
			if r < 0.22 then return 1 end
			if r < 0.55 then return 2 end
			return 0
		end
		local r = rnd(x, z, 30 + dir)
		if r < 0.15 then return 1 end
		if r < 0.40 then return 2 end
		if r < 0.40 + DOOR_CHANCE then return doorTpl and 3 or 2 end
		return 0
	end

	local s
	if pa then
		local info = poolRegion(rx, rz)
		if info.kind ~= "maze" then return 1 end
		s = info.s
	else
		s = regionInfo(rx, rz).s
	end
	local lx, lz = x - rx * R, z - rz * R
	local mx, mz = lx + (dir == 1 and 1 or 0), lz + (dir == 2 and 1 or 0)
	local ax, az = math.floor(lx / s), math.floor(lz / s)
	local bx, bz = math.floor(mx / s), math.floor(mz / s)
	if ax == bx and az == bz then return 1 end -- inside one block

	local nb = R / s
	local gx, gz = rx * nb + ax, rz * nb + az
	local carve
	if ax == nb - 1 and az == nb - 1 then carve = 0
	elseif ax == nb - 1 then carve = 2
	elseif az == nb - 1 then carve = 1
	else carve = (rnd(gx, gz, 1 + s + ls) < 0.5) and 1 or 2 end
	-- few extra openings => lots of dead ends
	local open = (carve == dir) or (rnd(gx, gz, 10 + dir + s * 3 + ls) < 0.12)
	if not open then return 0 end
	if s == 1 then return (rnd(x, z, 20 + dir + ls) < 0.55) and 2 or 1 end
	return 1
end

local function hasWindow(x, z, dir)
	local ox, oz = x, z
	if dir == 1 then ox += 1 else oz += 1 end
	local boundary = math.floor(x / R) ~= math.floor(ox / R) or math.floor(z / R) ~= math.floor(oz / R)
	return rnd(x, z, 80 + dir) < (boundary and WINDOW_CHANCE * 2.5 or WINDOW_CHANCE)
end

-- a post is only needed at corners / wall ends, not on straight walls
local function needPost(x, z, lv)
	if (lv or 0) == 0 and (isSpecialCell(x, z) or isSpecialCell(x + 1, z) or isSpecialCell(x, z + 1) or isSpecialCell(x + 1, z + 1)) then
		return false
	end
	local W = edge(x, z, 2) ~= 1
	local E = edge(x + 1, z, 2) ~= 1
	local S = edge(x, z, 1) ~= 1
	local N = edge(x, z + 1, 1) ~= 1
	if not (W or E or S or N) then return false end
	if W and E and not N and not S then return false end
	if N and S and not W and not E then return false end
	return true
end

-- stairs between PoolRooms floors: anchor cell (even x) .. +1 climb from floor lv to floor lv+1, landing at +2
local function withLevel(l, fn, ...)
	local old = LV
	LV = l
	local ok, r = pcall(fn, ...)
	LV = old
	if ok then return r end
	return nil
end

local function stairAt(ax, cz, lv)
	if ax % 2 ~= 0 then return false end
	local key = ckey3(ax, cz, lv)
	local c = stairCache[key]
	if c ~= nil then return c end
	local res = false
	if rnd(ax, cz, 180 + lv * 31) < 0.03 then
		res = true
		for dx = 0, 2 do
			if not isPoolCell(ax + dx, cz) or poolRegion(math.floor((ax + dx) / R), math.floor(cz / R)).kind ~= "maze" then
				res = false
			end
		end
		if res and withLevel(lv, edge, ax, cz, 1) ~= 1 then res = false end
		if res and withLevel(lv + 1, edge, ax + 1, cz, 1) ~= 1 then res = false end
	end
	stairCache[key] = res
	return res
end

--// ================= BACKROOMS WALLS (no fabric, only the carpet is fabric) =================
local function wallSeg(parent, center, len, alongZ, y0, h, color, board)
	local size = alongZ and Vector3.new(WALL_T, h, len) or Vector3.new(len, h, WALL_T)
	local w = mk(parent, "Wall", size, CFrame.new(center.X, y0 + h / 2, center.Z), color, Enum.Material.Plastic)
	if h > 4 then stripes(w, alongZ, color) end
	if board then
		local bs = alongZ and Vector3.new(WALL_T + 0.3, 0.7, len) or Vector3.new(len, 0.7, WALL_T + 0.3)
		mk(parent, "Baseboard", bs, CFrame.new(center.X, y0 + 0.35, center.Z), C_BOARD, Enum.Material.Wood)
		-- the odd wall outlet
		if len > CELL - 0.2 then
			local fx, fz = math.floor(center.X), math.floor(center.Z)
			if rnd(fx, fz, 90) < 0.06 then
				local sgn = (rnd(fx, fz, 91) < 0.5) and 1 or -1
				local off = (rnd(fx, fz, 92) - 0.5) * (len - 3)
				local d = WALL_T / 2 + 0.06
				local oc = Color3.fromRGB(205, 195, 170)
				if alongZ then
					mk(parent, "Outlet", Vector3.new(0.12, 0.9, 0.55), CFrame.new(center.X + sgn * d, y0 + 1.5, center.Z + off), oc, Enum.Material.Plastic)
				else
					mk(parent, "Outlet", Vector3.new(0.55, 0.9, 0.12), CFrame.new(center.X + off, y0 + 1.5, center.Z + sgn * d), oc, Enum.Material.Plastic)
				end
			end
		end
	end
end

-- door swing (hinge on one side) with an "Open Door" prompt
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

local function windowWall(parent, mid, alongZ, y0, color)
	local WW, SILL, TOP = 6, 3.2, 8.4
	local side = (CELL - WW) / 2
	local off = WW / 2 + side / 2
	local axis = alongZ and Vector3.new(0, 0, 1) or Vector3.new(1, 0, 0)
	wallSeg(parent, mid + axis * off, side, alongZ, y0, WALL_H, color, true)
	wallSeg(parent, mid - axis * off, side, alongZ, y0, WALL_H, color, true)
	wallSeg(parent, mid, WW, alongZ, y0, SILL, color, true)
	wallSeg(parent, mid, WW, alongZ, y0 + TOP, WALL_H - TOP, color, false)

	local gh = TOP - SILL
	local gsize = alongZ and Vector3.new(0.12, gh, WW) or Vector3.new(WW, gh, 0.12)
	local g = mk(parent, "Glass", gsize, CFrame.new(mid.X, y0 + SILL + gh / 2, mid.Z), Color3.fromRGB(170, 190, 175), Enum.Material.Glass)
	g.Transparency = 0.82
	g.CastShadow = false

	local t2 = WALL_T + 0.3
	local function trim(along, h, yc, aoff, thick)
		local size = alongZ and Vector3.new(thick or t2, h, along) or Vector3.new(along, h, thick or t2)
		local c = mid + axis * aoff
		mk(parent, "Trim", size, CFrame.new(c.X, yc, c.Z), C_BOARD, Enum.Material.Wood)
	end
	trim(WW + 0.6, 0.3, y0 + SILL + 0.15, 0, WALL_T + 0.6)                      -- sill
	trim(0.3, gh, y0 + SILL + 0.3 + (gh - 0.3) / 2 - 0.15, WW / 2 - 0.15)       -- left
	trim(0.3, gh, y0 + SILL + 0.3 + (gh - 0.3) / 2 - 0.15, -(WW / 2 - 0.15))    -- right
	trim(WW, 0.3, y0 + TOP - 0.15, 0)                                           -- header
end

local function doorway(parent, mid, alongZ, y0, color, withDoor)
	local side = (CELL - DOOR_W) / 2
	local off = DOOR_W / 2 + side / 2
	local axis = alongZ and Vector3.new(0, 0, 1) or Vector3.new(1, 0, 0)
	wallSeg(parent, mid + axis * off, side, alongZ, y0, WALL_H, color, true)
	wallSeg(parent, mid - axis * off, side, alongZ, y0, WALL_H, color, true)
	wallSeg(parent, mid, DOOR_W, alongZ, y0 + DOOR_H, WALL_H - DOOR_H, color, false)
	if not withDoor then return end

	local t2 = WALL_T + 0.3
	local function trim(along, h, yc, aoff)
		local size = alongZ and Vector3.new(t2, h, along) or Vector3.new(along, h, t2)
		local c = mid + axis * aoff
		mk(parent, "Trim", size, CFrame.new(c.X, yc, c.Z), C_BOARD, Enum.Material.Wood)
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

local function buildEdgeWall(parent, cx, cz, dir, state, color)
	if state == 1 then return end
	local base = cellPos(cx, cz)
	local alongZ = (dir == 1)
	local mid = alongZ and (base + Vector3.new(CELL / 2, 0, 0)) or (base + Vector3.new(0, 0, CELL / 2))
	local y0 = BASE.Y
	if state == 0 then
		if hasWindow(cx, cz, dir) then
			windowWall(parent, mid, alongZ, y0, color)
		else
			wallSeg(parent, mid, CELL, alongZ, y0, WALL_H, color, true)
		end
	else
		doorway(parent, mid, alongZ, y0, color, state == 3 and doorTpl ~= nil)
	end
end

local function setLit(e, on)
	e.panel.Material = on and Enum.Material.Neon or Enum.Material.Plastic
	e.panel.Color = on and e.onColor or e.offColor
	if e.light then e.light.Enabled = on end
end

-- ceiling light. backrooms = white square panel, "pool" = soft round disc
local function makeLight(parent, px, ceilWorldY, pz, lit, withPL, kind)
	local pool = (kind == "pool")
	local on = pool and P_GLOW or Color3.fromRGB(246, 242, 218)
	local panel
	if pool then
		panel = mk(parent, "Light", Vector3.new(0.25, 5, 5), CFrame.new(px, ceilWorldY - 0.15, pz) * CFrame.Angles(0, 0, math.pi / 2), on, Enum.Material.Neon)
		panel.Shape = Enum.PartType.Cylinder
	else
		mk(parent, "LightFrame", Vector3.new(5.2, 0.35, 5.2), CFrame.new(px, ceilWorldY - 0.175, pz), Color3.fromRGB(150, 146, 130), Enum.Material.Metal)
		panel = mk(parent, "Light", Vector3.new(4.5, 0.22, 4.5), CFrame.new(px, ceilWorldY - 0.29, pz), on, Enum.Material.Neon)
	end
	local pl
	if lit and withPL then
		pl = Instance.new("PointLight")
		pl.Range = pool and 28 or 24
		pl.Brightness = pool and 0.45 or LIGHT_BRIGHTNESS
		pl.Shadows = false
		pl.Color = pool and Color3.fromRGB(200, 232, 222) or Color3.fromRGB(255, 240, 200)
		pl.Parent = panel
	end
	local e = {panel = panel, light = pl, base = lit, onColor = on, offColor = Color3.fromRGB(170, 166, 150)}
	setLit(e, lit)
	return e
end

--// ================= WATER (terrain, swimmable) =================
local function getTerrain() return Workspace:FindFirstChildOfClass("Terrain") end

local function addWater(owner, x, y, z, sx, sy, sz)
	local cf, size = CFrame.new(x, y, z), Vector3.new(sx, sy, sz)
	local t = getTerrain()
	if t then pcall(function() t:FillBlock(cf, size, Enum.Material.Water) end) end
	owner.water[#owner.water + 1] = {cf = cf, size = size}
end

local function clearWaterList(list)
	local t = getTerrain()
	if not t or not list then return end
	for _, w in ipairs(list) do
		pcall(function() t:FillBlock(w.cf, w.size, Enum.Material.Air) end)
	end
end

local function fakeWater(parent, x, y, z, sx, sy, sz)
	local w = mk(parent, "Water", Vector3.new(sx, sy, sz), CFrame.new(x, y, z), Color3.fromRGB(60, 160, 150), Enum.Material.SmoothPlastic)
	w.Transparency = 0.55
	w.CanCollide = false
	w.CastShadow = false
end

local function testWater()
	local t = getTerrain()
	if not t then return false end
	local ok = false
	pcall(function()
		local c = BASE + Vector3.new(0, -300, 0)
		t:FillBlock(CFrame.new(c), Vector3.new(4, 4, 4), Enum.Material.Water)
		local region = Region3.new(c - Vector3.new(2, 2, 2), c + Vector3.new(2, 2, 2)):ExpandToGrid(4)
		local mats = t:ReadVoxels(region, 4)
		ok = (mats[1][1][1] == Enum.Material.Water)
		t:FillBlock(CFrame.new(c), Vector3.new(4, 4, 4), Enum.Material.Air)
	end)
	return ok
end

local WATER_PROPS = {"WaterColor", "WaterTransparency", "WaterReflectance", "WaterWaveSize", "WaterWaveSpeed"}
local function applyWaterLook()
	local t = getTerrain()
	if not t then return end
	savedWater = {}
	local new = {WaterColor = Color3.fromRGB(65, 170, 150), WaterTransparency = 0.6, WaterReflectance = 0.15, WaterWaveSize = 0.04, WaterWaveSpeed = 4}
	for _, k in ipairs(WATER_PROPS) do
		pcall(function()
			savedWater[k] = t[k]
			t[k] = new[k]
		end)
	end
end

--// ================= POOLROOMS PIECES =================
local function poolWallSeg(parent, center, len, alongZ, y0, h, pp)
	if h < 0.05 or len < 0.05 then return end
	local size = alongZ and Vector3.new(WALL_T, h, len) or Vector3.new(len, h, WALL_T)
	local p = mk(parent, "PWall", size, CFrame.new(center.X, y0 + h / 2, center.Z), pp.wall, Enum.Material.SmoothPlastic)
	if alongZ then tiled(p, NRIGHT, NLEFT) else tiled(p, NFRONT, NBACK) end
	return p
end

-- rounded (stepped) arch doorway
local function poolArch(parent, mid, alongZ, y0, pp)
	local axis = alongZ and Vector3.new(0, 0, 1) or Vector3.new(1, 0, 0)
	local gw = DOOR_W
	local side = (CELL - gw) / 2
	local off = gw / 2 + side / 2
	poolWallSeg(parent, mid + axis * off, side, alongZ, y0, 7, pp)
	poolWallSeg(parent, mid - axis * off, side, alongZ, y0, 7, pp)
	local r = gw / 2
	for i = 0, 4 do
		local ym = 0.35 + i * 0.7
		local gap = math.sqrt(math.max(r * r - ym * ym, 0.01))
		local len = CELL / 2 - gap
		local c = (CELL / 2 + gap) / 2
		poolWallSeg(parent, mid + axis * c, len, alongZ, y0 + 7 + i * 0.7, 0.7, pp)
		poolWallSeg(parent, mid - axis * c, len, alongZ, y0 + 7 + i * 0.7, 0.7, pp)
	end
	poolWallSeg(parent, mid, CELL, alongZ, y0 + 10.5, PH - 10.5, pp)
end

local function poolWindow(parent, mid, alongZ, y0, pp)
	local WW, SILL, TOP = 6, 3, 9
	local side = (CELL - WW) / 2
	local off = WW / 2 + side / 2
	local axis = alongZ and Vector3.new(0, 0, 1) or Vector3.new(1, 0, 0)
	poolWallSeg(parent, mid + axis * off, side, alongZ, y0, PH, pp)
	poolWallSeg(parent, mid - axis * off, side, alongZ, y0, PH, pp)
	poolWallSeg(parent, mid, WW, alongZ, y0, SILL, pp)
	poolWallSeg(parent, mid, WW, alongZ, y0 + TOP, PH - TOP, pp)
	local gh = TOP - SILL
	local gsize = alongZ and Vector3.new(0.12, gh, WW) or Vector3.new(WW, gh, 0.12)
	local g = mk(parent, "Glass", gsize, CFrame.new(mid.X, y0 + SILL + gh / 2, mid.Z), Color3.fromRGB(190, 215, 210), Enum.Material.Glass)
	g.Transparency = 0.8
	g.CastShadow = false
	for _, sg in ipairs({-1, 1}) do
		local c = mid + axis * (sg * (WW / 2 + 0.45))
		local size = alongZ and Vector3.new(WALL_T + 0.3, 8, 0.5) or Vector3.new(0.5, 8, WALL_T + 0.3)
		mk(parent, "WindowGlow", size, CFrame.new(c.X, y0 + 6, c.Z), P_GLOW, Enum.Material.Neon)
	end
end

-- three dark round portholes low on a wall
local function poolPortholes(parent, mid, alongZ, y0)
	local fx, fz = math.floor(mid.X), math.floor(mid.Z)
	local sgn = (rnd(fx, fz, 175) < 0.5) and 1 or -1
	local normal = alongZ and Vector3.new(sgn, 0, 0) or Vector3.new(0, 0, sgn)
	local along = alongZ and Vector3.new(0, 0, 1) or Vector3.new(1, 0, 0)
	for i = -1, 1 do
		local pos = Vector3.new(mid.X, y0 + 2.6, mid.Z) + normal * (WALL_T / 2 + 0.06) + along * (i * 3.6)
		local cf = CFrame.lookAt(pos, pos + normal)
		local p = mk(parent, "Porthole", Vector3.new(0.1, 3, 3), cf * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(28, 50, 46), Enum.Material.SmoothPlastic)
		p.Shape = Enum.PartType.Cylinder
	end
end

local function poolShower(parent, mid, alongZ, y0)
	local fx, fz = math.floor(mid.X), math.floor(mid.Z)
	local sgn = (rnd(fx, fz, 170) < 0.5) and 1 or -1
	local off = (rnd(fx, fz, 171) - 0.5) * 6
	local normal = alongZ and Vector3.new(sgn, 0, 0) or Vector3.new(0, 0, sgn)
	local along = alongZ and Vector3.new(0, 0, 1) or Vector3.new(1, 0, 0)
	local pos = Vector3.new(mid.X, y0, mid.Z) + normal * (WALL_T / 2) + along * off
	local cf = CFrame.lookAt(pos, pos + normal) -- local -Z points into the room
	local METAL = Color3.fromRGB(190, 195, 200)
	local function cyl(size, offset, rot)
		local p = mk(parent, "Shower", size, cf * CFrame.new(offset) * rot, METAL, Enum.Material.Metal)
		p.Shape = Enum.PartType.Cylinder
	end
	cyl(Vector3.new(7, 0.25, 0.25), Vector3.new(0, 4.5, -0.25), CFrame.Angles(0, 0, math.pi / 2))
	cyl(Vector3.new(1.2, 0.25, 0.25), Vector3.new(0, 8, -0.85), CFrame.Angles(0, math.pi / 2, 0))
	cyl(Vector3.new(0.25, 1.4, 1.4), Vector3.new(0, 7.8, -1.5), CFrame.Angles(0, 0, math.pi / 2))
	mk(parent, "Towel", Vector3.new(1.2, 2.6, 0.12), cf * CFrame.new(-3, 4.5, -0.1), Color3.fromRGB(35, 40, 48), Enum.Material.SmoothPlastic)
end

local function buildPoolEdge(parent, cx, cz, dir, state, y0, pp)
	if state == 1 then return end
	local base = cellPos(cx, cz)
	local alongZ = (dir == 1)
	local mid = alongZ and (base + Vector3.new(CELL / 2, 0, 0)) or (base + Vector3.new(0, 0, CELL / 2))
	if state == 0 then
		local w = rnd(cx, cz, 81 + dir + LV * 977)
		if w < 0.03 then
			poolWindow(parent, mid, alongZ, y0, pp)
		else
			poolWallSeg(parent, mid, CELL, alongZ, y0, PH, pp)
			if w > 0.95 then
				poolShower(parent, mid, alongZ, y0)
			elseif w > 0.84 then
				poolPortholes(parent, mid, alongZ, y0)
			end
		end
	else
		poolArch(parent, mid, alongZ, y0, pp)
	end
end

-- big pool hall / tiered atrium (a whole zone built in one go, floor 0 only)
local function buildPoolSite(site, rx, rz, info)
	local f = Instance.new("Folder")
	f.Name = "PoolSite"
	site.folder = f
	local atrium = (info.kind == "atrium")
	local ox = BASE.X + (rx * R + (R - 1) / 2) * CELL
	local oz = BASE.Z + (rz * R + (R - 1) / 2) * CELL
	local oy = BASE.Y
	local top = atrium and 45 or (PH + 2)   -- top of the ceiling slab
	local cb = top - 2                      -- underside of the ceiling
	local ph = atrium and 18 or 22          -- half size of the pool
	local sh = atrium and 12 or 10          -- half size of the skylight
	local SPM = Enum.Material.SmoothPlastic

	local function B(name, x0, x1, y0, y1, z0, z1, color, mat, ...)
		local p = mk(f, name, Vector3.new(x1 - x0, y1 - y0, z1 - z0),
			CFrame.new(ox + (x0 + x1) / 2, oy + (y0 + y1) / 2, oz + (z0 + z1) / 2), color, mat or SPM)
		tiled(p, ...)
		return p
	end
	local function glow(x, y, z, range, bright)
		local a = B("Glow", x - 0.2, x + 0.2, y - 0.2, y + 0.2, z - 0.2, z + 0.2, P_GLOW, SPM)
		a.Transparency = 1
		a.CanCollide = false
		a.CastShadow = false
		local pl = Instance.new("PointLight")
		pl.Range, pl.Brightness, pl.Shadows = range, bright, false
		pl.Color = Color3.fromRGB(200, 232, 222)
		pl.Parent = a
	end

	-- deck around the pool
	B("Deck", -36, 36, -2, 0, ph, 36, P_FLOOR, nil, NTOP)
	B("Deck", -36, 36, -2, 0, -36, -ph, P_FLOOR, nil, NTOP)
	B("Deck", -36, -ph, -2, 0, -ph, ph, P_FLOOR, nil, NTOP)
	B("Deck", ph, 36, -2, 0, -ph, ph, P_FLOOR, nil, NTOP)

	-- basin, ramp out, water
	B("BasinFloor", -ph - 2, ph + 2, -14, -12, -ph - 2, ph + 2, P_BASIN, nil, NTOP)
	B("BasinW", -ph - 2, -ph, -14, -2, -ph - 2, ph + 2, P_BASIN)
	B("BasinE", ph, ph + 2, -14, -2, -ph - 2, ph + 2, P_BASIN)
	B("BasinS", -ph - 2, ph + 2, -14, -2, -ph - 2, -ph, P_BASIN)
	B("BasinN", -ph - 2, ph + 2, -14, -2, ph, ph + 2, P_BASIN)
	rampPart(f, Vector3.new(ox, oy - 12, oz - (ph - 16)), Vector3.new(ox, oy, oz - ph), 8, P_BASIN, SPM)
	addWater(site, ox, oy - 8, oz, 2 * ph, 8, 2 * ph)
	if not waterOK then fakeWater(f, ox, oy - 8, oz, 2 * ph, 8, 2 * ph) end

	-- ceiling with a skylight + soft light shaft
	B("Ceil", -36, 36, cb, top, sh, 36, P_CEIL, nil, NBOT)
	B("Ceil", -36, 36, cb, top, -36, -sh, P_CEIL, nil, NBOT)
	B("Ceil", -36, -sh, cb, top, -sh, sh, P_CEIL, nil, NBOT)
	B("Ceil", sh, 36, cb, top, -sh, sh, P_CEIL, nil, NBOT)
	B("ShaftWall", -sh - 0.5, sh + 0.5, top, top + 12, sh, sh + 0.5, P_CEIL)
	B("ShaftWall", -sh - 0.5, sh + 0.5, top, top + 12, -sh - 0.5, -sh, P_CEIL)
	B("ShaftWall", -sh - 0.5, -sh, top, top + 12, -sh, sh, P_CEIL)
	B("ShaftWall", sh, sh + 0.5, top, top + 12, -sh, sh, P_CEIL)
	B("ShaftCap", -sh - 0.5, sh + 0.5, top + 12, top + 12.4, -sh - 0.5, sh + 0.5, P_GLOW, Enum.Material.Neon)
	glow(0, top + 8, 0, 90, 0.8)
	glow(0, cb - 4, 0, 70, 0.5)

	if atrium then
		-- tiered balconies + two long ramps up (no railings)
		for _, t in ipairs({{y = 15, inner = 26}, {y = 29, inner = 20}}) do
			local yt, ib = t.y, t.inner
			B("Balcony", -36, 36, yt - 2, yt, ib, 36, P_FLOOR, nil, NTOP, NBOT)
			B("Balcony", -36, 36, yt - 2, yt, -36, -ib, P_FLOOR, nil, NTOP, NBOT)
			B("Balcony", -36, -ib, yt - 2, yt, -ib, ib, P_FLOOR, nil, NTOP, NBOT)
			B("Balcony", ib, 36, yt - 2, yt, -ib, ib, P_FLOOR, nil, NTOP, NBOT)
			glow(0, yt - 3, 0, 50, 0.3)
		end
		rampPart(f, Vector3.new(ox - 22, oy, oz - 30), Vector3.new(ox - 22, oy + 15, oz + 30), 8, P_FLOOR, SPM)
		rampPart(f, Vector3.new(ox + 14, oy + 15, oz - 30), Vector3.new(ox + 14, oy + 29, oz + 30), 8, P_FLOOR, SPM)
	else
		-- round columns around the hall pool
		local cpos = (ph + 36) / 2
		for _, c in ipairs({{-cpos, -cpos}, {cpos, -cpos}, {-cpos, cpos}, {cpos, cpos}, {0, cpos}, {0, -cpos}, {cpos, 0}, {-cpos, 0}}) do
			local col = mk(f, "Column", Vector3.new(cb + 2, 2.8, 2.8), CFrame.new(ox + c[1], oy + (cb - 2) / 2, oz + c[2]) * CFrame.Angles(0, 0, math.pi / 2), P_WALL, SPM)
			col.Shape = Enum.PartType.Cylinder
		end
		for _, c in ipairs({{-24, -24}, {24, -24}, {-24, 24}, {24, 24}}) do glow(c[1], cb - 2, c[2], 36, 0.35) end
	end

	-- boundary walls (the zone owns them, so they are as tall as the room)
	local function wallPiece(alongX, fixed, a, b, y0, y1)
		if b - a < 0.05 or y1 - y0 < 0.05 then return end
		if alongX then
			B("BWall", a, b, y0, y1, fixed - WALL_T / 2, fixed + WALL_T / 2, P_WALL, nil, NFRONT, NBACK)
		else
			B("BWall", fixed - WALL_T / 2, fixed + WALL_T / 2, y0, y1, a, b, P_WALL, nil, NLEFT, NRIGHT)
		end
	end
	local function boundarySeg(alongX, fixed, c, state)
		local a, b = c - CELL / 2, c + CELL / 2
		if state == 0 then
			wallPiece(alongX, fixed, a, b, -2, top)
		elseif state == 2 then
			wallPiece(alongX, fixed, a, c - DOOR_W / 2, -2, top)
			wallPiece(alongX, fixed, c + DOOR_W / 2, b, -2, top)
			wallPiece(alongX, fixed, c - DOOR_W / 2, c + DOOR_W / 2, 10, top)
		end
	end
	for j = 0, R - 1 do
		local c = (j - (R - 1) / 2) * CELL
		boundarySeg(false, -36, c, edge(rx * R - 1, rz * R + j, 1))
		boundarySeg(false, 36, c, edge(rx * R + R - 1, rz * R + j, 1))
		boundarySeg(true, -36, c, edge(rx * R + j, rz * R - 1, 2))
		boundarySeg(true, 36, c, edge(rx * R + j, rz * R + R - 1, 2))
	end
	for _, c in ipairs({{-36, -36}, {36, -36}, {-36, 36}, {36, 36}}) do
		B("Post", c[1] - 0.5, c[1] + 0.5, -2, top, c[2] - 0.5, c[2] + 0.5, P_WALL)
	end

	f.Parent = rootFolder
end

local function ensurePoolSite(rx, rz, info)
	local key = ckey(rx, rz)
	local site = poolSites[key]
	if not site then
		site = {count = 0, water = {}, key = key}
		poolSites[key] = site
		buildPoolSite(site, rx, rz, info)
	end
	return site
end

local function releaseSite(site)
	site.count -= 1
	if site.count <= 0 then
		if site.folder then site.folder:Destroy() end
		clearWaterList(site.water)
		poolSites[site.key] = nil
	end
end

local function buildPoolCell(cx, cz, lv)
	local rx, rz = math.floor(cx / R), math.floor(cz / R)
	local info = poolRegion(rx, rz)
	local special = info.kind ~= "maze"
	if special and (lv == 0 or blockedLv(lv)) then
		local ef = Instance.new("Folder")
		ef.Name = "Empty"
		ef.Parent = rootFolder
		local rec = {folder = ef, x = cx, z = cz, lv = lv}
		if lv == 0 then
			local site = ensurePoolSite(rx, rz, info)
			site.count += 1
			rec.site = site
		end
		cells[ckey3(cx, cz, lv)] = rec
		return
	end

	local oy = BASE.Y + lv * PLH
	local pp = POOLPAL[lv % 3 + 1]
	local L = lv * 977
	local s = special and 6 or info.s
	local f = Instance.new("Folder")
	f.Name = "PoolCell"
	local pos = cellPos(cx, cz)
	local data = {folder = f, x = cx, z = cz, lv = lv, water = {}}
	local SPM = Enum.Material.SmoothPlastic

	local ax = cx - (cx % 2)
	local up = stairAt(ax, cz, lv)         -- a staircase leaves this floor here
	local down = stairAt(ax, cz, lv - 1)   -- a staircase from the floor below arrives here

	-- floor, sometimes with a small swimming pool
	if down then
		-- open stairwell, no floor
	elseif (not up) and rnd(cx, cz, 150 + L) < 0.13 then
		for _, p in ipairs(holeBoxes(f, pos.X, pos.Z, 8, oy - 1, 2, pp.floor, SPM)) do tiled(p, NTOP) end
		tiled(mk(f, "BasinFloor", Vector3.new(8, 1, 8), CFrame.new(pos.X, oy - 8.5, pos.Z), pp.basin, SPM), NTOP)
		mk(f, "BasinWall", Vector3.new(8, 6, 0.4), CFrame.new(pos.X, oy - 5, pos.Z + 3.8), pp.basin, SPM)
		mk(f, "BasinWall", Vector3.new(8, 6, 0.4), CFrame.new(pos.X, oy - 5, pos.Z - 3.8), pp.basin, SPM)
		mk(f, "BasinWall", Vector3.new(0.4, 6, 8), CFrame.new(pos.X + 3.8, oy - 5, pos.Z), pp.basin, SPM)
		mk(f, "BasinWall", Vector3.new(0.4, 6, 8), CFrame.new(pos.X - 3.8, oy - 5, pos.Z), pp.basin, SPM)
		tiled(mk(f, "Step", Vector3.new(2, 4, 8), CFrame.new(pos.X + 3, oy - 6, pos.Z), pp.basin, SPM), NTOP)
		addWater(data, pos.X, oy - 6, pos.Z, 8, 4, 8)
		if not waterOK then fakeWater(f, pos.X, oy - 6, pos.Z, 8, 4, 8) end
	else
		local fl = mk(f, "Floor", Vector3.new(CELL, 2, CELL), CFrame.new(pos.X, oy - 1, pos.Z), pp.floor, SPM)
		fl.Reflectance = 0.04
		tiled(fl, NTOP)
	end

	-- stairs up to the next PoolRooms floor
	if up and cx == ax then
		buildStairs(f, pos.X - CELL / 2, oy, pos.Z, PLH, 20, CELL, pp.floor, SPM, true)
	end

	-- ceiling, round soft lights, skylight shafts
	local hasLight = (not up) and ((cx + 2 * cz + lv) % 3 == 0)
	local shaft = (not up) and (not hasLight) and rnd(cx, cz, 152 + L) < 0.06
	if up then
		-- open stairwell, no ceiling
	elseif shaft then
		for _, p in ipairs(holeBoxes(f, pos.X, pos.Z, 6, oy + PH + 0.5, 1, pp.ceil, SPM)) do tiled(p, NBOT) end
		local sy = oy + PH + 6
		mk(f, "ShaftWall", Vector3.new(6, 10, 0.4), CFrame.new(pos.X, sy, pos.Z + 2.8), pp.ceil, SPM)
		mk(f, "ShaftWall", Vector3.new(6, 10, 0.4), CFrame.new(pos.X, sy, pos.Z - 2.8), pp.ceil, SPM)
		mk(f, "ShaftWall", Vector3.new(0.4, 10, 6), CFrame.new(pos.X + 2.8, sy, pos.Z), pp.ceil, SPM)
		mk(f, "ShaftWall", Vector3.new(0.4, 10, 6), CFrame.new(pos.X - 2.8, sy, pos.Z), pp.ceil, SPM)
		local cap = mk(f, "ShaftCap", Vector3.new(6.4, 0.4, 6.4), CFrame.new(pos.X, oy + PH + 11.2, pos.Z), P_GLOW, Enum.Material.Neon)
		local pl = Instance.new("PointLight")
		pl.Range, pl.Brightness, pl.Shadows = 34, 0.6, false
		pl.Color = Color3.fromRGB(200, 232, 222)
		pl.Parent = cap
	else
		tiled(mk(f, "Ceiling", Vector3.new(CELL, 1, CELL), CFrame.new(pos.X, oy + PH + 0.5, pos.Z), pp.ceil, SPM), NBOT)
	end
	if hasLight then
		data.entry = makeLight(f, pos.X, oy + PH, pos.Z, rnd(cx, cz, 153 + L) > 0.1, true, "pool")
	end

	-- walls (owned by this cell: east + north edge)
	local function edgeState(dir)
		local st = edge(cx, cz, dir)
		if lv ~= 0 and blockedLv(lv) then
			local ox, oz = cx, cz
			if dir == 1 then ox = cx + 1 else oz = cz + 1 end
			if isSpecialCell(ox, oz) then st = 0 end
		end
		return st
	end
	if lv ~= 0 or not adjSpecial(cx, cz, 1) then buildPoolEdge(f, cx, cz, 1, edgeState(1), oy, pp) end
	if lv ~= 0 or not adjSpecial(cx, cz, 2) then buildPoolEdge(f, cx, cz, 2, edgeState(2), oy, pp) end
	if lv ~= 0 and blockedLv(lv) then
		-- the empty floors above/below big halls need a wall around them
		if isSpecialCell(cx - 1, cz) then buildPoolEdge(f, cx - 1, cz, 1, 0, oy, pp) end
		if isSpecialCell(cx, cz - 1) then buildPoolEdge(f, cx, cz - 1, 2, 0, oy, pp) end
	end
	if needPost(cx, cz, lv) then
		local pp2 = pos + Vector3.new(CELL / 2, 0, CELL / 2)
		mk(f, "PPost", Vector3.new(WALL_T + 0.2, PH, WALL_T + 0.2), CFrame.new(pp2.X, oy + PH / 2, pp2.Z), pp.wall, SPM)
	end

	-- round columns in the bigger rooms
	if s >= 3 and (not up) and (not down) and rnd(cx, cz, 160 + L) < (s == 6 and 0.12 or 0.05) then
		local dx = (rnd(cx, cz, 161) - 0.5) * 4
		local dz = (rnd(cx, cz, 162) - 0.5) * 4
		local col = mk(f, "Column", Vector3.new(PH, 2.6, 2.6), CFrame.new(pos.X + dx, oy + PH / 2, pos.Z + dz) * CFrame.Angles(0, 0, math.pi / 2), pp.wall, SPM)
		col.Shape = Enum.PartType.Cylinder
	end

	f.Parent = rootFolder
	cells[ckey3(cx, cz, lv)] = data
end

--// ================= PROPS (backrooms only) =================
local function pickSide(cx, cz, rng)
	local sides = {}
	if edge(cx, cz, 1) == 0 then sides[#sides + 1] = Vector3.new(1, 0, 0) end
	if edge(cx, cz, 2) == 0 then sides[#sides + 1] = Vector3.new(0, 0, 1) end
	if edge(cx - 1, cz, 1) == 0 then sides[#sides + 1] = Vector3.new(-1, 0, 0) end
	if edge(cx, cz - 1, 2) == 0 then sides[#sides + 1] = Vector3.new(0, 0, -1) end
	if #sides == 0 then return nil end
	return sides[rng:NextInteger(1, #sides)]
end

local function placeProp(parent, tpl, cx, cz, isChair)
	local rng = Random.new((cx * 7919 + cz * 104729 + SEED * 31) % 2147483647)
	local m = tpl:Clone()
	if not m then return end

	-- sometimes stretched / weird
	if rng:NextNumber() < (isChair and 0.15 or 0.30) then
		local k, S = rng:NextInteger(1, 3), nil
		if k == 1 then
			S = Vector3.new(rng:NextNumber(0.6, 1.2), rng:NextNumber(1.8, 3.2), rng:NextNumber(0.6, 1.2))
		elseif k == 2 then
			S = Vector3.new(rng:NextNumber(1.8, 3), rng:NextNumber(0.4, 0.8), rng:NextNumber(1.2, 2.4))
		else
			S = Vector3.new(rng:NextNumber(0.4, 0.7), rng:NextNumber(0.8, 1.3), rng:NextNumber(1.8, 3))
		end
		stretch(m, S)
	end

	local roll, yaw = rng:NextNumber(), rng:NextNumber(0, math.pi * 2)
	local mode
	if roll < 0.30 then mode = "floor"
	elseif roll < 0.55 then mode = "sunk"
	elseif roll < 0.75 then mode = "wall"
	elseif roll < 0.90 then mode = "tilt"
	else mode = "flip" end

	local rot
	if mode == "tilt" then
		rot = CFrame.Angles(rng:NextNumber(-0.8, 0.8), yaw, rng:NextNumber(-0.8, 0.8))
	elseif mode == "flip" then
		rot = CFrame.Angles(math.pi, yaw, 0)
	else
		rot = CFrame.Angles(0, yaw, 0)
	end
	applyCF(m, rot)

	local mn, mx = aabb(m)
	local ctr, sz = (mn + mx) / 2, mx - mn
	local pos = cellPos(cx, cz)
	local tx = pos.X + rng:NextNumber(-CELL / 2 + 3, CELL / 2 - 3)
	local tz = pos.Z + rng:NextNumber(-CELL / 2 + 3, CELL / 2 - 3)
	local sink = 0
	if mode == "sunk" then sink = sz.Y * rng:NextNumber(0.3, 0.65)
	elseif mode == "tilt" then sink = sz.Y * rng:NextNumber(0.05, 0.3)
	elseif mode == "flip" then sink = sz.Y * rng:NextNumber(0, 0.12) end

	if mode == "wall" then
		local n = pickSide(cx, cz, rng)
		if n then
			local half = (n.X ~= 0) and sz.X / 2 or sz.Z / 2
			local depth = half * 2 * rng:NextNumber(0.15, 0.7)
			local dist = CELL / 2 - half + depth
			if n.X ~= 0 then
				tx = pos.X + n.X * dist
			else
				tz = pos.Z + n.Z * dist
			end
		end
	end

	applyCF(m, CFrame.new(tx - ctr.X, BASE.Y - sink - mn.Y, tz - ctr.Z))
	m.Parent = parent
end

--// ================= CELLS =================
local function buildCell(cx, cz, lv)
	-- big multi-floor map is built as one piece, its cells stay empty
	if lv == 0 and inRect(mega, cx, cz) then
		local ef = Instance.new("Folder")
		ef.Name = "Empty"
		ef.Parent = rootFolder
		cells[ckey3(cx, cz, 0)] = {folder = ef, x = cx, z = cz, lv = 0}
		return
	end
	-- the infinite PoolRooms (every floor)
	if isPoolCell(cx, cz) then
		buildPoolCell(cx, cz, lv)
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

	-- carpet (damp, uneven, the only fabric), square pits, stains
	local fk = 1 + (rnd(cx, cz, 3) - 0.5) * 0.10
	if rnd(cx, cz, 4) < 0.10 then fk = fk * 0.8 end
	local carpet = shade(pal.carpet, fk)
	local pit = (not zin) and farFromSpawn and rnd(cx, cz, 12) < PIT_CHANCE
	if pit then
		holeBoxes(f, pos.X, pos.Z, 6, BASE.Y - 0.5, 1, carpet, Enum.Material.Fabric)
		local dk = shade(carpet, 0.45)
		mk(f, "PitBottom", Vector3.new(6, 1, 6), CFrame.new(pos.X, BASE.Y - 4.5, pos.Z), dk, Enum.Material.Fabric)
		mk(f, "PitWall", Vector3.new(6, 4, 0.4), CFrame.new(pos.X, BASE.Y - 2, pos.Z + 2.8), dk, Enum.Material.Fabric)
		mk(f, "PitWall", Vector3.new(6, 4, 0.4), CFrame.new(pos.X, BASE.Y - 2, pos.Z - 2.8), dk, Enum.Material.Fabric)
		mk(f, "PitWall", Vector3.new(0.4, 4, 6), CFrame.new(pos.X + 2.8, BASE.Y - 2, pos.Z), dk, Enum.Material.Fabric)
		mk(f, "PitWall", Vector3.new(0.4, 4, 6), CFrame.new(pos.X - 2.8, BASE.Y - 2, pos.Z), dk, Enum.Material.Fabric)
	else
		mk(f, "Floor", Vector3.new(CELL, 1, CELL), CFrame.new(pos.X, BASE.Y - 0.5, pos.Z), carpet, Enum.Material.Fabric)
		if rnd(cx, cz, 8) < 0.12 then
			local d = 3 + rnd(cx, cz, 9) * 4
			local sx = pos.X + (rnd(cx, cz, 10) - 0.5) * 4
			local sz = pos.Z + (rnd(cx, cz, 11) - 0.5) * 4
			local st = mk(f, "Stain", Vector3.new(0.05, d, d), CFrame.new(sx, BASE.Y + 0.08, sz) * CFrame.Angles(0, 0, math.pi / 2), shade(carpet, 0.6), Enum.Material.Fabric)
			st.Shape = Enum.PartType.Cylinder
			st.Transparency = 0.25
			st.CastShadow = false
		end
	end

	-- ceiling (+ square shafts) + tile grid
	local hasLight = (cx + cz) % 2 == 0
	local shaft = (not zin) and farFromSpawn and (not hasLight) and rnd(cx, cz, 13) < SHAFT_CHANCE
	if shaft then
		holeBoxes(f, pos.X, pos.Z, 5, BASE.Y + ceilY + 0.5, 1, pal.ceil, Enum.Material.Plastic)
		local dk = Color3.fromRGB(35, 32, 22)
		local sy = BASE.Y + ceilY + 7
		mk(f, "ShaftWall", Vector3.new(5, 14, 0.4), CFrame.new(pos.X, sy, pos.Z + 2.3), dk, Enum.Material.Plastic)
		mk(f, "ShaftWall", Vector3.new(5, 14, 0.4), CFrame.new(pos.X, sy, pos.Z - 2.3), dk, Enum.Material.Plastic)
		mk(f, "ShaftWall", Vector3.new(0.4, 14, 5), CFrame.new(pos.X + 2.3, sy, pos.Z), dk, Enum.Material.Plastic)
		mk(f, "ShaftWall", Vector3.new(0.4, 14, 5), CFrame.new(pos.X - 2.3, sy, pos.Z), dk, Enum.Material.Plastic)
		mk(f, "ShaftCap", Vector3.new(5.4, 0.6, 5.4), CFrame.new(pos.X, BASE.Y + ceilY + 14.3, pos.Z), dk, Enum.Material.Plastic)
	else
		mk(f, "Ceiling", Vector3.new(CELL, 1, CELL), CFrame.new(pos.X, BASE.Y + ceilY + 0.5, pos.Z), pal.ceil, Enum.Material.Plastic)
		if CEILING_GRID then
			local sy = BASE.Y + ceilY - 0.06
			local gc = shade(pal.ceil, 0.55)
			local P = Enum.Material.Plastic
			mk(f, "Grid", Vector3.new(CELL, 0.12, 0.25), CFrame.new(pos.X, sy, pos.Z), gc, P)
			mk(f, "Grid", Vector3.new(0.25, 0.12, CELL), CFrame.new(pos.X, sy, pos.Z), gc, P)
			mk(f, "Grid", Vector3.new(0.25, 0.12, CELL), CFrame.new(pos.X - CELL / 2, sy, pos.Z), gc, P)
			mk(f, "Grid", Vector3.new(CELL, 0.12, 0.25), CFrame.new(pos.X, sy, pos.Z - CELL / 2), gc, P)
		end
	end

	-- square fluorescent light (checkerboard spacing, some dead)
	local entry
	if hasLight then
		entry = makeLight(f, pos.X, BASE.Y + ceilY, pos.Z, rnd(cx, cz, 5) > pal.off, true)
	end

	-- walls (owned by this cell: east + north edge)
	local wcol = shade(pal.wall, 1 + (rnd(cx, cz, 7) - 0.5) * 0.08)
	if not adjSpecial(cx, cz, 1) then buildEdgeWall(f, cx, cz, 1, edge(cx, cz, 1), wcol) end
	if not adjSpecial(cx, cz, 2) then buildEdgeWall(f, cx, cz, 2, edge(cx, cz, 2), wcol) end
	if needPost(cx, cz, 0) then
		local pp = pos + Vector3.new(CELL / 2, 0, CELL / 2)
		mk(f, "Post", Vector3.new(WALL_T + 0.2, WALL_H, WALL_T + 0.2), CFrame.new(pp.X, BASE.Y + WALL_H / 2, pp.Z), wcol, Enum.Material.Plastic)
	end

	-- big square pillars in wide / huge zones (like the reference photos)
	if not zin and info.s >= 3 and not (math.abs(cx) <= 1 and math.abs(cz) <= 1) then
		if rnd(cx, cz, 60) < (info.s == 6 and 0.20 or 0.07) then
			local ox = (rnd(cx, cz, 61) - 0.5) * 4
			local oz = (rnd(cx, cz, 62) - 0.5) * 4
			local pc = shade(pal.wall, 0.96)
			local pil = mk(f, "Pillar", Vector3.new(3.2, WALL_H, 3.2), CFrame.new(pos.X + ox, BASE.Y + WALL_H / 2, pos.Z + oz), pc, Enum.Material.Plastic)
			stripes(pil, true, pc)
			stripes(pil, false, pc)
		end
	end

	-- props (backrooms only)
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
	cells[ckey3(cx, cz, 0)] = {folder = f, x = cx, z = cz, lv = 0, entry = entry}
end

local function streamCells(cx, cz, lvP, budget)
	if not rootFolder then return end
	local missing = {}
	for dz = -LOAD_R, LOAD_R do
		for dx = -LOAD_R, LOAD_R do
			local x, z = cx + dx, cz + dz
			local d2 = dx * dx + dz * dz
			if isPoolCell(x, z) then
				for lv = lvP - 1, lvP + 1 do
					if (lv == lvP or d2 <= 16) and not cells[ckey3(x, z, lv)] then
						missing[#missing + 1] = {x, z, lv, d2 + (lv == lvP and 0 or 1000)}
					end
				end
			elseif math.abs(lvP) <= 1 and not cells[ckey3(x, z, 0)] then
				missing[#missing + 1] = {x, z, 0, d2}
			end
		end
	end
	table.sort(missing, function(a, b) return a[4] < b[4] end)
	for i = 1, math.min(#missing, budget) do
		local m = missing[i]
		LV = m[3]
		local ok, err = pcall(buildCell, m[1], m[2], m[3])
		LV = 0
		if not ok then
			warn("[Backrooms] cell error: " .. tostring(err))
			local ef = Instance.new("Folder")
			ef.Parent = rootFolder
			cells[ckey3(m[1], m[2], m[3])] = {folder = ef, x = m[1], z = m[2], lv = m[3]}
		end
	end
	for k, c in pairs(cells) do
		if math.max(math.abs(c.x - cx), math.abs(c.z - cz)) > UNLOAD_R or math.abs(c.lv - lvP) > 1 then
			c.folder:Destroy()
			if c.water then clearWaterList(c.water) end
			if c.site then releaseSite(c.site) end
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
				local c = cells[ckey3(tx + dx, tz + dz, playerLv)]
				local e = c and c.entry
				if e and e.base and ((dx == 0 and dz == 0) or math.random() < 0.5) then
					flicker[e] = {stop = now + 5, nxt = 0}
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
		local F, wc = Enum.Material.Plastic, PALETTES[1].wall
		mk(rootFolder, "Skirt", Vector3.new(lx + WALL_T, hh, WALL_T), CFrame.new((xmin + xmax) / 2, cy, zmin), wc, F)
		mk(rootFolder, "Skirt", Vector3.new(lx + WALL_T, hh, WALL_T), CFrame.new((xmin + xmax) / 2, cy, zmax), wc, F)
		mk(rootFolder, "Skirt", Vector3.new(WALL_T, hh, lz + WALL_T), CFrame.new(xmin, cy, (zmin + zmax) / 2), wc, F)
		mk(rootFolder, "Skirt", Vector3.new(WALL_T, hh, lz + WALL_T), CFrame.new(xmax, cy, (zmin + zmax) / 2), wc, F)
	end
	zone = Z
end

--// ================= BIG MULTI-FLOOR MAPS (mega room / atrium tower) =================
local function stairCells(M, k)
	if M.tower then
		local sx = (k % 2 == 1) and (M.x0 + 1) or (M.x1 - 3)
		local sz = (k % 2 == 1) and M.z1 or (M.z1 - 1)
		return sx, sz
	end
	local sz = M.z0 + 1 + math.floor(rnd(k, 7, 100) * 7)
	local sx = (k % 2 == 1) and (M.x0 + 1) or (M.x1 - 3)
	return sx, sz
end

local function layered(parent, cx, cz, sx, sz, yTop, pal)
	mk(parent, "FloorTop", Vector3.new(sx, 0.35, sz), CFrame.new(cx, BASE.Y + yTop - 0.175, cz), pal.carpet, Enum.Material.Fabric)
	mk(parent, "FloorUnder", Vector3.new(sx, 0.65, sz), CFrame.new(cx, BASE.Y + yTop - 0.675, cz), pal.ceil, Enum.Material.Plastic)
end

local function layeredHole(parent, cx, cz, hs, yTop, pal)
	local strip = (CELL - hs) / 2
	layered(parent, cx, cz + hs / 2 + strip / 2, CELL, strip, yTop, pal)
	layered(parent, cx, cz - hs / 2 - strip / 2, CELL, strip, yTop, pal)
	layered(parent, cx - hs / 2 - strip / 2, cz, strip, hs, yTop, pal)
	layered(parent, cx + hs / 2 + strip / 2, cz, strip, hs, yTop, pal)
end

local function buildMega(dirIdx, tower)
	local n
	if tower then n = math.random(5, 9) else n = (math.random() < 0.55) and 2 or 8 end
	local dv = DIRS[dirIdx]
	local dist = 8 + math.random(0, 3)
	local hx, hz = dv[1] * dist, dv[2] * dist
	local M = {x0 = hx - 4, x1 = hx + 4, z0 = hz - 4, z1 = hz + 4, n = n, entries = {}, tower = tower}
	local pal = PALETTES[1]
	local f = Instance.new("Folder")
	f.Name = tower and "AtriumTower" or "MegaRoom"

	local xmin, xmax = BASE.X + (M.x0 - 0.5) * CELL, BASE.X + (M.x1 + 0.5) * CELL
	local zmin, zmax = BASE.Z + (M.z0 - 0.5) * CELL, BASE.Z + (M.z1 + 0.5) * CELL
	local W = xmax - xmin
	local mx0, mz0 = (xmin + xmax) / 2, (zmin + zmax) / 2
	local topY = n * FH - 1

	mk(f, "Floor", Vector3.new(W, 1, W), CFrame.new(mx0, BASE.Y - 0.5, mz0), pal.carpet, Enum.Material.Fabric)
	mk(f, "Ceiling", Vector3.new(W, 1, W), CFrame.new(mx0, BASE.Y + topY + 0.5, mz0), pal.ceil, Enum.Material.Plastic)

	-- what each floor cell looks like: slab / full hole / square hole (no railings anywhere)
	local function state(k, x, z)
		local rs, rz = stairCells(M, k)
		if z == rz and (x == rs or x == rs + 1) then return "hole" end
		if z == rz and x == rs + 2 then return "slab" end
		if k + 1 <= n - 1 then
			local ns, nz = stairCells(M, k + 1)
			if z == nz and (x == ns or x == ns + 1) then return "slab" end
		end
		if tower and x >= M.x0 + 2 and x <= M.x1 - 2 and z >= M.z0 + 2 and z <= M.z1 - 2 then return "hole" end
		local r = rnd(x, z, 200 + k)
		if tower then
			if r < 0.04 then return "hole" elseif r < 0.09 then return "sq" end
		else
			if r < 0.06 then return "hole" elseif r < 0.17 then return "sq" end
		end
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

	-- white square lights under every ceiling
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

	-- columns (only in the normal mega room, the tower stays open)
	if not tower then
		for i = 1, 4 do
			for j = 1, 4 do
				local cxp, czp = xmin + 24 * i, zmin + 24 * j
				mk(f, "Column", Vector3.new(2.6, topY, 2.6), CFrame.new(cxp, BASE.Y + topY / 2, czp), shade(pal.wall, 0.95), Enum.Material.Plastic)
			end
		end
	end

	-- real stairs between floors
	for k = 1, n - 1 do
		local rs, rz = stairCells(M, k)
		buildStairs(f, BASE.X + (rs - 0.5) * CELL, BASE.Y + (k - 1) * FH, BASE.Z + rz * CELL, FH, 16, 10, pal.carpet, Enum.Material.Fabric, false)
	end

	-- outer skirt closes the upper floors
	local topAbs = BASE.Y + topY + 1
	local hh = topAbs - (BASE.Y + WALL_H)
	local cy = BASE.Y + WALL_H + hh / 2
	local F, wc = Enum.Material.Plastic, pal.wall
	local sk = {
		mk(f, "Skirt", Vector3.new(W + WALL_T, hh, WALL_T), CFrame.new(mx0, cy, zmin), wc, F),
		mk(f, "Skirt", Vector3.new(W + WALL_T, hh, WALL_T), CFrame.new(mx0, cy, zmax), wc, F),
		mk(f, "Skirt", Vector3.new(WALL_T, hh, W + WALL_T), CFrame.new(xmin, cy, mz0), wc, F),
		mk(f, "Skirt", Vector3.new(WALL_T, hh, W + WALL_T), CFrame.new(xmax, cy, mz0), wc, F),
	}
	stripes(sk[1], false, wc) stripes(sk[2], false, wc) stripes(sk[3], true, wc) stripes(sk[4], true, wc)

	-- tower: dark room doors on every floor along the inner walls
	if tower then
		local dc = Color3.fromRGB(72, 54, 36)
		for k = 1, n - 1 do
			local yc = BASE.Y + k * FH + 4.5
			for i = 0, 2 do
				local p = cellPos(M.x0 + 1 + i * 3, M.z0 + 1 + i * 3)
				mk(f, "RoomDoor", Vector3.new(4, 9, 0.3), CFrame.new(p.X, yc, zmin + 0.55), dc, Enum.Material.Wood)
				mk(f, "RoomDoor", Vector3.new(4, 9, 0.3), CFrame.new(p.X, yc, zmax - 0.55), dc, Enum.Material.Wood)
				mk(f, "RoomDoor", Vector3.new(0.3, 9, 4), CFrame.new(xmin + 0.55, yc, p.Z), dc, Enum.Material.Wood)
				mk(f, "RoomDoor", Vector3.new(0.3, 9, 4), CFrame.new(xmax - 0.55, yc, p.Z), dc, Enum.Material.Wood)
			end
		end
	end

	f.Parent = rootFolder
	M.wxmin, M.wxmax, M.wzmin, M.wzmax = xmin, xmax, zmin, zmax
	mega = M
end

--// ================= LIGHTING (dark + creepy, per area) =================
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
	cc.Saturation = -0.12
	cc.Contrast = 0.18
	cc.Brightness = -0.04
	cc.Parent = Lighting
	local bl = Instance.new("BloomEffect")
	bl.Name = "BR_Bloom"
	bl.Intensity, bl.Size, bl.Threshold = 0.2, 16, 1.3
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

local function clearAllWater()
	for _, c in pairs(cells) do
		if c.water then clearWaterList(c.water) end
	end
	for _, s in pairs(poolSites) do clearWaterList(s.water) end
	poolSites = {}
	local t = getTerrain()
	if t and savedWater then
		for k, v in pairs(savedWater) do pcall(function() t[k] = v end) end
	end
	savedWater = nil
end

--// ================= "LOADED" NOTICE =================
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

--// ================= VHS OVERLAY (stays on in the backrooms) =================
local function createOverlay()
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)

	local gui = Instance.new("ScreenGui")
	gui.Name = "BR_Overlay"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 999999
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	parentGui(gui)

	local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
	local function F(parent, size, pos, color, tr, z)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.Size, f.Position, f.BackgroundColor3 = size, pos, color
		f.BackgroundTransparency, f.ZIndex = tr, z
		f.Parent = parent
		return f
	end

	local bg = F(gui, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), BLACK, 0, 1)

	-- vignette (camcorder lens), only when the screen is not black
	local vigHolder = F(gui, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), WHITE, 1, 3)
	local function vig(size, pos, rot)
		local v = F(vigHolder, size, pos, BLACK, 0, 3)
		local g = Instance.new("UIGradient")
		g.Rotation = rot
		g.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1)})
		g.Parent = v
	end
	vig(UDim2.new(1, 0, 0.22, 0), UDim2.new(0, 0, 0, 0), 90)
	vig(UDim2.new(1, 0, 0.22, 0), UDim2.new(0, 0, 0.78, 0), 270)
	vig(UDim2.new(0.18, 0, 1, 0), UDim2.new(0, 0, 0, 0), 0)
	vig(UDim2.new(0.18, 0, 1, 0), UDim2.new(0.82, 0, 0, 0), 180)

	-- scanlines (slowly crawling)
	local lineHolder = F(gui, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), WHITE, 1, 5)
	local lines = {}
	for i = -1, math.floor(vp.Y / 4) do
		lines[#lines + 1] = F(lineHolder, UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 0, i * 4), WHITE, 0.93, 5)
	end

	-- tape noise
	local noiseHolder = F(gui, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), WHITE, 1, 6)
	local noise = {}
	for i = 1, 30 do noise[i] = F(noiseHolder, UDim2.fromOffset(60, 1), UDim2.fromOffset(0, 0), WHITE, 0.9, 6) end

	-- tracking bands
	local function band(h, tr, z)
		local b = F(gui, UDim2.new(1, 0, 0, h), UDim2.fromOffset(0, -100), WHITE, 0, z)
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, tr), NumberSequenceKeypoint.new(1, 1)})
		g.Parent = b
		return b
	end
	local band1, band2 = band(46, 0.87, 7), band(5, 0.8, 7)

	-- OSD
	local function osd(text, size, pos, anchor, align)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Arcade
		l.Text = text
		l.TextSize = size
		l.TextColor3 = WHITE
		l.TextXAlignment = align
		l.AnchorPoint = anchor
		l.Position = pos
		l.Size = UDim2.fromOffset(300, size + 6)
		l.ZIndex = 9
		l.Parent = gui
		return l
	end
	local mode = osd("PLAY >", 26, UDim2.new(0, 36, 0, 28), Vector2.new(0, 0), Enum.TextXAlignment.Left)
	local recDot = F(gui, UDim2.fromOffset(14, 14), UDim2.new(0, 36, 0, 36), Color3.fromRGB(235, 30, 30), 0, 9)
	local dc = Instance.new("UICorner")
	dc.CornerRadius = UDim.new(1, 0)
	dc.Parent = recDot
	osd(string.upper(os.date("%b. %d %Y")), 22, UDim2.new(0, 36, 1, -34), Vector2.new(0, 1), Enum.TextXAlignment.Left)
	osd("SP", 22, UDim2.new(1, -36, 1, -34), Vector2.new(1, 1), Enum.TextXAlignment.Right)
	local counter = osd("0:00:00", 22, UDim2.new(1, -36, 0, 30), Vector2.new(1, 0), Enum.TextXAlignment.Right)

	-- titles (main + red/cyan ghosts)
	local big = math.clamp(math.floor(vp.X / 9), 34, 100)
	local small = math.clamp(math.floor(big * 0.42), 18, 42)
	local function title(text, size, yOff)
		local set = {y = yOff}
		local function lbl(color, tr)
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Font = Enum.Font.Arcade
			l.Text = text
			l.TextSize = size
			l.TextColor3 = color
			l.TextTransparency = tr
			l.TextStrokeTransparency = 1
			l.AnchorPoint = Vector2.new(0.5, 0.5)
			l.Position = UDim2.new(0.5, 0, 0.5, yOff)
			l.Size = UDim2.new(1, 0, 0, size * 1.3)
			l.ZIndex = 10
			l.Visible = false
			l.Parent = gui
			return l
		end
		set.r = lbl(Color3.fromRGB(255, 40, 40), 0.55)
		set.c = lbl(Color3.fromRGB(40, 255, 255), 0.55)
		set.m = lbl(WHITE, 0)
		return set
	end
	local tMain = title("BACKROOMS", big, 0)
	local tSub = title("Produced By Hecker", small, math.floor(big * 0.95))

	local isBlack = true
	local destroyed = false
	local t0 = os.clock()
	local conn
	local acc, nextTear, tearUntil = 0, 3, 0

	local function setBlack(b)
		isBlack = b
		bg.BackgroundTransparency = b and 0 or 1
		for _, l in ipairs(lines) do
			l.BackgroundColor3 = b and WHITE or BLACK
			l.BackgroundTransparency = b and 0.93 or 0.86
		end
		for i, n in ipairs(noise) do n.Visible = b or i <= 12 end
		vigHolder.Visible = not b
		mode.Text = b and "PLAY >" or "REC"
		recDot.Visible = not b
	end
	setBlack(true)

	local function animTitle(t)
		if not t.m.Visible then return end
		local j = (math.random() < 0.04) and math.random(-8, 8) or 0
		local g = math.random(2, 4)
		t.m.Position = UDim2.new(0.5, j, 0.5, t.y)
		t.r.Position = UDim2.new(0.5, j - g, 0.5, t.y)
		t.c.Position = UDim2.new(0.5, j + g, 0.5, t.y)
		t.m.TextTransparency = (math.random() < 0.06) and (0.15 + math.random() * 0.3) or 0
	end

	conn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - t0
		lineHolder.Position = UDim2.fromOffset(0, math.floor(t * 20) % 4)

		-- tracking band 1: constant on black, a slow sweep every few seconds otherwise
		if isBlack then
			band1.Visible = true
			band1.Position = UDim2.fromOffset(0, ((t * 140) % (vp.Y + 200)) - 100)
		else
			local cyc = t % 8
			band1.Visible = cyc < 2
			band1.Position = UDim2.fromOffset(0, (cyc / 2) * (vp.Y + 100) - 50)
		end
		-- band 2: thin glitch tear
		if isBlack then
			band2.Visible = true
			band2.Position = UDim2.fromOffset((math.random() < 0.1) and math.random(-6, 6) or 0, ((t * 310 + 200) % (vp.Y + 200)) - 100)
		else
			if t > nextTear then
				tearUntil = t + 0.12
				nextTear = t + 2 + math.random() * 5
				band2.Position = UDim2.fromOffset(math.random(-8, 8), math.random(0, math.floor(vp.Y)))
			end
			band2.Visible = t < tearUntil
		end

		acc += dt
		if acc >= 1 / 18 then
			acc = 0
			for _, n in ipairs(noise) do
				if n.Visible then
					n.Position = UDim2.fromOffset(math.random(0, math.floor(vp.X)), math.random(0, math.floor(vp.Y)))
					n.Size = UDim2.fromOffset(math.random(30, 320), math.random() < 0.2 and math.random(2, 4) or 1)
					n.BackgroundTransparency = (isBlack and 0.72 or 0.9) + math.random() * 0.07
				end
			end
			local s = math.floor(t)
			counter.Text = string.format("%d:%02d:%02d", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60)
		end
		recDot.BackgroundTransparency = (math.floor(t * 1.2) % 2 == 0) and 0 or 1
		animTitle(tMain)
		animTitle(tSub)
	end)

	local o = {}
	local function show(t) t.m.Visible, t.r.Visible, t.c.Visible = true, true, true end
	local function hide(t) t.m.Visible, t.r.Visible, t.c.Visible = false, false, false end
	function o.showTitle() show(tMain) end
	function o.showSub() show(tSub) end
	function o.hideTitles() hide(tMain) hide(tSub) end
	o.setBlack = setBlack

	-- "The PoolRooms" / "The Backrooms" text when you change area
	function o.areaTitle(text)
		task.spawn(function()
			local yOff = -math.floor(vp.Y * 0.22)
			local set = title(text, math.clamp(math.floor(big * 0.8), 28, 80), yOff)
			local items = {{set.r, 0.55}, {set.c, 0.55}, {set.m, 0}}
			for _, it in ipairs(items) do
				it[1].TextTransparency = 1
				it[1].Visible = true
			end
			for _, it in ipairs(items) do
				TweenService:Create(it[1], TweenInfo.new(0.4), {TextTransparency = it[2]}):Play()
			end
			local ts = os.clock()
			while os.clock() - ts < 2.8 and not destroyed do
				local j = (math.random() < 0.08) and math.random(-6, 6) or 0
				local g = math.random(2, 4)
				set.m.Position = UDim2.new(0.5, j, 0.5, yOff)
				set.r.Position = UDim2.new(0.5, j - g, 0.5, yOff)
				set.c.Position = UDim2.new(0.5, j + g, 0.5, yOff)
				task.wait(0.05)
			end
			for _, it in ipairs(items) do
				TweenService:Create(it[1], TweenInfo.new(0.6), {TextTransparency = 1}):Play()
			end
			task.wait(0.65)
			for _, it in ipairs(items) do pcall(function() it[1]:Destroy() end) end
		end)
	end

	function o.destroy()
		if destroyed then return end
		destroyed = true
		if conn then conn:Disconnect() conn = nil end
		gui:Destroy()
	end
	return o
end

--// ================= FOOTSTEPS + AMBIENCE + FOUND-FOOTAGE CAMERA =================
local function startFootsteps()
	for _, s in pairs(stepSounds) do pcall(function() s:Destroy() end) end
	stepSounds = {
		back = makeSound(WALK_SOUND_BACK, STEP_VOLUME, true),
		pool = makeSound(WALK_SOUND_POOL, STEP_VOLUME, true),
	}
end

local function stopFootsteps()
	for _, s in pairs(stepSounds) do pcall(function() s:Destroy() end) end
	stepSounds = {}
end

local function updateFootsteps(hum, hrp)
	local v = hrp.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local walking = hum.MoveDirection.Magnitude > 0.1 and speed > 2
		and hum.FloorMaterial ~= Enum.Material.Air
		and hum:GetState() ~= Enum.HumanoidStateType.Swimming
	local want = walking and (curArea == "pool" and "pool" or "back") or nil
	for k, s in pairs(stepSounds) do
		if k == want then
			if not s.IsPlaying then s:Play() end
		elseif s.IsPlaying then
			s:Pause()
		end
	end
end

-- backrooms ambient everywhere, PoolRooms ambient only inside the PoolRooms
local function updateAmbience()
	if not ambience then return end
	if curArea == "pool" and poolAmbience then
		if ambience.IsPlaying then ambience:Pause() end
		if not poolAmbience.IsPlaying then poolAmbience:Play() end
	else
		if poolAmbience and poolAmbience.IsPlaying then poolAmbience:Pause() end
		if not ambience.IsPlaying then ambience:Play() end
	end
end

-- silence Roblox's default walking sound ("Running") while in the backrooms
local function muteDefaultSteps(char)
	if not MUTE_DEFAULT_STEPS or not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local s = hrp:FindFirstChild("Running")
	if s and s:IsA("Sound") then
		if mutedSounds[s] == nil then mutedSounds[s] = s.Volume end
		s.Volume = 0
	end
end

local function restoreDefaultSteps()
	for s, v in pairs(mutedSounds) do
		if s.Parent then pcall(function() s.Volume = v end) end
	end
	mutedSounds = {}
end

local bobT, bobAmp, idleT = 0, 0, 0
local function camStep(dt)
	if not inBackrooms or not CAMERA_BOB then return end
	local cam = Workspace.CurrentCamera
	local _, hum, hrp = getChar()
	if not cam or not hum then return end
	local v = hrp.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local moving = hum.MoveDirection.Magnitude > 0.1 and speed > 1.5
	local target = moving and math.clamp(speed / 14, 0.4, 1.5) or 0
	bobAmp += (target - bobAmp) * math.min(1, dt * 7)
	bobT += dt * (5 + speed * 0.45)
	idleT += dt
	local x = math.sin(bobT) * 0.16 * bobAmp + math.sin(idleT * 1.3) * 0.035 + math.sin(idleT * 3.1) * 0.015
	local y = math.abs(math.sin(bobT)) * 0.22 * bobAmp + math.cos(idleT * 1.1) * 0.03
	local roll = math.sin(bobT) * 0.014 * bobAmp + math.sin(idleT * 0.8) * 0.006 + math.noise(idleT * 6, 3.3) * 0.004
	cam.CFrame = cam.CFrame * CFrame.new(x, y, 0) * CFrame.Angles(0, 0, roll)
end

local function bindCamera()
	pcall(function() RunService:UnbindFromRenderStep("BR_Cam") end)
	local cam = Workspace.CurrentCamera
	if cam then
		origFov = cam.FieldOfView
		cam.FieldOfView = 78
	end
	RunService:BindToRenderStep("BR_Cam", Enum.RenderPriority.Camera.Value + 1, camStep)
end

local function unbindCamera()
	pcall(function() RunService:UnbindFromRenderStep("BR_Cam") end)
	local cam = Workspace.CurrentCamera
	if cam and origFov then cam.FieldOfView = origFov end
	origFov = nil
end

--// ================= ENTER / LEAVE =================
cleanupBackrooms = function()
	inBackrooms = false
	flicker = {}
	clearAllWater()
	for k in pairs(cells) do cells[k] = nil end
	if rootFolder then pcall(function() rootFolder:Destroy() end) rootFolder = nil end
	zone, mega, poolCfg = nil, nil, nil
	regionCache, poolRegionCache, stairCache = {}, {}, {}
	curArea, LV, playerLv = "back", 0, 0
	restoreLighting()
	restoreDefaultSteps()
	stopFootsteps()
	unbindCamera()
	if overlay then pcall(overlay.destroy) overlay = nil end
	if ambience then ambience:Destroy() ambience = nil end
	if poolAmbience then poolAmbience:Destroy() poolAmbience = nil end
end

local function enterBackrooms()
	local char, hum, hrp = getChar()
	if not char then error("no character") end

	SEED = math.random(1, 99999)
	regionCache, poolRegionCache, poolSites, stairCache = {}, {}, {}, {}
	LV, playerLv = 0, 0
	rootFolder = Instance.new("Folder")
	rootFolder.Name = "BR_" .. math.random(1000, 9999)
	rootFolder.Parent = Workspace
	cells, flicker = {}, {}
	zone, mega, poolCfg = nil, nil, nil

	pcall(collectTemplates)
	pcall(loadChair)
	pcall(loadDoor)

	-- every special area gets its own side of the map so they never overlap
	local order = {1, 2, 3, 4}
	for i = 4, 2, -1 do
		local j = math.random(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local used = 0
	local function nextDir()
		used += 1
		return order[used]
	end
	local function try(fn)
		local ok, err = pcall(fn, nextDir())
		if not ok then warn("[Backrooms] " .. tostring(err)) end
	end

	if math.random() < POOL_CHANCE then
		-- the PoolRooms take one whole side of the map, forever (and infinite floors)
		local dv = DIRS[nextDir()]
		poolCfg = {axis = (dv[1] ~= 0) and 1 or 2, sign = (dv[1] ~= 0) and dv[1] or dv[2]}
		waterOK = testWater()
		applyWaterLook()
	end
	if math.random() < MEGA_CHANCE then
		local tower = math.random() < 0.5
		try(function(d) buildMega(d, tower) end)
	end
	if math.random() < HOUSE_CHANCE then try(buildHouse) end

	applyLighting()
	streamCells(0, 0, 0, 1e9)

	char:PivotTo(CFrame.new(BASE + Vector3.new(0, 4, 0)))
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then
			p.AssemblyLinearVelocity = Vector3.zero
			p.AssemblyAngularVelocity = Vector3.zero
		end
	end
	curArea = "back"
	startFootsteps()
	bindCamera()
	inBackrooms = true
end

local function waitUntil(t0, t)
	local r = t - (os.clock() - t0)
	if r > 0 then task.wait(r) end
end

startSequence = function(culprit)
	if busy or inBackrooms or not alive then return end
	busy = true

	local original
	if culprit and culprit:IsA("BasePart") and not culprit:IsA("Terrain") then
		original = culprit.CanCollide
		culprit.CanCollide = false -- only this one part
	end

	task.spawn(function()
		local t0 = os.clock()
		pcall(function()
			introSound = makeSound(INTRO_SOUND_ID, 1, false)
			introSound:Play()
		end)
		local ov = createOverlay()
		overlay = ov

		task.wait(0.8)
		local ok, err = pcall(enterBackrooms)
		if not ok then
			warn("[Backrooms] " .. tostring(err))
			cleanupBackrooms()
		end
		if culprit and original ~= nil and culprit.Parent then culprit.CanCollide = original end

		waitUntil(t0, T_TITLE)
		pcall(ov.showTitle)
		waitUntil(t0, T_SUB)
		pcall(ov.showSub)
		waitUntil(t0, T_END)
		pcall(ov.hideTitles)
		if inBackrooms and alive then
			pcall(ov.setBlack, false) -- black screen goes away, the VHS camcorder look stays
		else
			pcall(ov.destroy)
			if overlay == ov then overlay = nil end
		end

		if STOP_INTRO_ON_REVEAL and introSound then introSound:Destroy() introSound = nil end
		if inBackrooms and alive then
			pcall(function()
				ambience = makeSound(AMBIENT_SOUND_ID, 0.8, true)
				ambience:Play()
				if poolCfg then poolAmbience = makeSound(POOL_AMBIENT_ID, 0.8, true) end
			end)
		end
		busy = false
	end)
end

--// ================= NOCLIP TRIGGERS =================
local function rayParams(char)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = {char}
	pcall(function() rp.RespectCanCollide = true end)
	return rp
end

local function getGround(char, hum, hrp)
	if hum.FloorMaterial == Enum.Material.Air then return nil end
	local res = Workspace:Raycast(hrp.Position, Vector3.new(0, -10, 0), rayParams(char))
	return res and res.Instance or nil
end

local wallTouching, wallLastHit = false, 0
local function checkWall(now)
	local char, hum, hrp = getChar()
	if not char then return end
	local md = hum.MoveDirection
	local flat = Vector3.new(md.X, 0, md.Z)
	if flat.Magnitude < 0.1 then
		if now - wallLastHit > 0.35 then wallTouching = false end
		return
	end
	local v = hrp.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local rp = rayParams(char)
	local dir = flat.Unit * 2.4
	local hit
	for _, off in ipairs({0, -1.6}) do
		local res = Workspace:Raycast(hrp.Position + Vector3.new(0, off, 0), dir, rp)
		if res and res.Instance and not res.Instance:IsA("Terrain") and math.abs(res.Normal.Y) < 0.4 then
			local mdl = res.Instance:FindFirstAncestorOfClass("Model")
			if not (mdl and mdl:FindFirstChildOfClass("Humanoid")) then
				hit = res.Instance
				break
			end
		end
	end
	if hit and speed < math.max(hum.WalkSpeed * 0.3, 2) then
		wallLastHit = now
		if not wallTouching then
			wallTouching = true
			if math.random() < WALL_CHANCE then startSequence(hit) end
		end
	elseif now - wallLastHit > 0.35 then
		wallTouching = false
	end
end

-- 10% every second (only if standing on something)
task.spawn(function()
	while alive do
		task.wait(1)
		if alive and not busy and not inBackrooms then
			local char, hum, hrp = getChar()
			if char and math.random() < TICK_CHANCE then
				local g = getGround(char, hum, hrp)
				if g then startSequence(g) end
			end
		end
	end
end)

-- which area is the player in?
local function detectArea(pos, cx, cz)
	if isPoolCell(cx, cz) and pos.Y > BASE.Y - 600 then return "pool" end
	if mega and pos.X > mega.wxmin and pos.X < mega.wxmax and pos.Z > mega.wzmin and pos.Z < mega.wzmax then
		return "mega"
	end
	return "back"
end

-- streaming / flicker / areas / sounds / wall check
local lastCX, lastCZ, acc = 0, 0, 0
track(RunService.Heartbeat:Connect(function(dt)
	if not alive then return end
	local now = os.clock()
	if inBackrooms and rootFolder then
		local char, hum, hrp = getChar()
		if hrp then
			local rel = hrp.Position - BASE
			lastCX = math.floor(rel.X / CELL + 0.5)
			lastCZ = math.floor(rel.Z / CELL + 0.5)
			if isPoolCell(lastCX, lastCZ) then
				playerLv = math.floor((rel.Y + 3) / PLH)
			else
				playerLv = 0
			end

			acc += dt
			if acc >= 0.2 then
				acc = 0
				streamCells(lastCX, lastCZ, playerLv, 8)
			end

			local newArea = detectArea(hrp.Position, lastCX, lastCZ)
			if newArea ~= curArea then
				if newArea == "pool" and overlay then
					overlay.areaTitle("The PoolRooms")
				elseif curArea == "pool" and overlay then
					overlay.areaTitle("The Backrooms")
				end
				curArea = newArea
			end
			lookStep(dt, LOOKS[curArea] or LOOKS.back)
			muteDefaultSteps(char)
			updateAmbience()
			if hum then updateFootsteps(hum, hrp) end
		end
		updateFlicker(now, lastCX, lastCZ)
	elseif not busy and not inBackrooms then
		checkWall(now)
	end
end))

-- reset/respawn = leave the backrooms
track(player.CharacterAdded:Connect(function()
	wallTouching = false
	if inBackrooms then cleanupBackrooms() end
end))

env.__BACKROOMS_STOP = function()
	alive = false
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	if noticeGui then pcall(function() noticeGui:Destroy() end) noticeGui = nil end
	if introSound then introSound:Destroy() introSound = nil end
	cleanupBackrooms()
end

showLoadedNotice()
print("[Backrooms] loaded - walk around and don't hit walls...")
