--[[
	NOSOI - The Leafless Tree  (client-side boss fight)
	Delta-compatible executor script. Everything is local: only you see it.

	Controls:
	  Hotbar tools: Cmd_Prompt.exe / Task_Manager.bat / Defrag.vbs
	  DASH button (mobile) or Q (PC)
	Walk toward the tree. Cross the 70-stud line to begin.
	Re-running the script cleans up the old run automatically.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

if _G.NosoiCleanup then pcall(_G.NosoiCleanup) end

------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------
local CFG = {
	ORIGIN = Vector3.new(0, 500, 0), -- arena is built high in the sky, away from the map
	TILE = 16,
	HALF = 7, -- grid is (2*HALF+1)^2 tiles
	TRIGGER = 70,
	SPAWN_DIST = 105,
	FLOORS = { 80, 60, 40, 20, 0 }, -- hp% at which phases 2..5 begin
	NODE_DMG = 6,
	CHIP = 0.15,
	SND = { -- swap any of these for your own rbxassetid:// ids
		thump = "rbxasset://sounds/bass.mp3",
		groan = "rbxasset://sounds/uuhhh.mp3",
		crackle = "rbxasset://sounds/electronicpingshort.wav",
		hit = "rbxasset://sounds/impact_explosion_03.mp3",
		swing = "rbxasset://sounds/swordslash.wav",
	},
}
local O = CFG.ORIGIN
local T = CFG.TILE
local floorY = O.Y
local rng = Random.new()

local PHASE_NAMES = {
	"OVERGROWTH & THE SHRAPNEL STORM",
	"RESONANCE & THE SHOCKWAVE LOOP",
	"THE NOY INTRUSION",
	"DATA ERASURE & THE FRAGMENTED VOID",
	"TERMINAL CONNECTION",
}

------------------------------------------------------------------
-- UTILS
------------------------------------------------------------------
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function tween(o, info, goal)
	local t = TweenService:Create(o, info, goal)
	t:Play()
	return t
end

local function sfx(id, vol, speed)
	local s = new("Sound", { SoundId = id, Volume = vol or 1, PlaybackSpeed = speed or 1 }, SoundService)
	s:Play()
	Debris:AddItem(s, 4)
	return s
end

local function hrp()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function hum()
	local c = player.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

------------------------------------------------------------------
-- STATE
------------------------------------------------------------------
local S = {
	run = 0, phase = 0, hp = 100, hpDisp = 100, started = false, triggered = false,
	busy = false, over = false, linked = false, stallUntil = 0, pending = 0,
	playerHP = 100, infection = 0, iframeUntil = 0, dashReady = 0, sweeping = false,
	despawning = 0, timersReset = true, treeLive = false, coreHP = 3,
}
local conns = {}
local origCF = nil
local arena, fx, trunk, treeModel
local tiles, nodes, roots, falling, debris, rings, claws, projs, popups =
	{}, {}, {}, {}, {}, {}, {}, {}, {}
local branches = {}
local startRun -- forward declaration

------------------------------------------------------------------
-- LIGHTING / SKY
------------------------------------------------------------------
local lightProps = { "Ambient", "OutdoorAmbient", "Brightness", "ClockTime", "FogColor", "FogEnd", "FogStart", "ExposureCompensation", "GlobalShadows" }
local savedLight = {}
for _, p in ipairs(lightProps) do savedLight[p] = Lighting[p] end
local removedFx = {}
for _, c in ipairs(Lighting:GetChildren()) do
	if c:IsA("Sky") or c:IsA("Atmosphere") or c:IsA("ColorCorrectionEffect") then
		table.insert(removedFx, c)
		c.Parent = nil
	end
end

local SKY = "rbxasset://textures/sky/sky512_"
local mySky = new("Sky", { StarCount = 0 }, Lighting)
local myAtmo = new("Atmosphere", {}, Lighting)
local myCC = new("ColorCorrectionEffect", {}, Lighting)

local function skybox(on)
	mySky.SkyboxBk = on and (SKY .. "bk.tex") or ""
	mySky.SkyboxDn = on and (SKY .. "dn.tex") or ""
	mySky.SkyboxFt = on and (SKY .. "ft.tex") or ""
	mySky.SkyboxLf = on and (SKY .. "lf.tex") or ""
	mySky.SkyboxRt = on and (SKY .. "rt.tex") or ""
	mySky.SkyboxUp = on and (SKY .. "up.tex") or ""
	mySky.CelestialBodiesShown = on
end

local function skyMode(mode, t)
	local ti = TweenInfo.new(t or 0.4)
	if mode == "blue" then
		skybox(true)
		tween(myAtmo, ti, { Density = 0.25, Offset = 0.25, Color = Color3.fromRGB(199, 215, 255), Decay = Color3.fromRGB(106, 112, 125), Glare = 0, Haze = 0 })
		tween(myCC, ti, { TintColor = Color3.new(1, 1, 1), Saturation = 0, Brightness = 0, Contrast = 0 })
		tween(Lighting, ti, { Ambient = Color3.fromRGB(120, 120, 120), OutdoorAmbient = Color3.fromRGB(140, 140, 140), ClockTime = 14, Brightness = 2 })
	elseif mode == "red" then
		skybox(true)
		tween(myAtmo, ti, { Density = 0.55, Offset = 0.6, Color = Color3.fromRGB(255, 40, 30), Decay = Color3.fromRGB(130, 0, 0), Glare = 2, Haze = 3 })
		tween(myCC, ti, { TintColor = Color3.fromRGB(255, 140, 130), Saturation = 0.2, Contrast = 0.15, Brightness = -0.05 })
		tween(Lighting, ti, { Ambient = Color3.fromRGB(90, 10, 10), OutdoorAmbient = Color3.fromRGB(120, 20, 20), ClockTime = 18.3, Brightness = 1.5 })
	elseif mode == "void" then
		skybox(false)
		tween(myAtmo, ti, { Density = 0.7, Offset = 0, Color = Color3.fromRGB(8, 0, 0), Decay = Color3.fromRGB(0, 0, 0), Glare = 0, Haze = 10 })
		tween(myCC, ti, { TintColor = Color3.fromRGB(255, 190, 190), Brightness = -0.15, Saturation = -0.2, Contrast = 0.2 })
		tween(Lighting, ti, { Ambient = Color3.fromRGB(35, 0, 0), OutdoorAmbient = Color3.fromRGB(40, 0, 6), ClockTime = 0, Brightness = 0.6 })
	end
end

------------------------------------------------------------------
-- HUD
------------------------------------------------------------------
local function mkGui(name, order)
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = order
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local ok = pcall(function() g.Parent = (gethui and gethui()) or CoreGui end)
	if not ok or not g.Parent then g.Parent = player:WaitForChild("PlayerGui") end
	return g
end

local gui = mkGui("NosoiHUD", 50)
local noyGui = mkGui("NoyUI", 60)
local white = Color3.new(1, 1, 1)

local bossFrame = new("Frame", { Size = UDim2.new(0.5, 0, 0, 16), Position = UDim2.new(0.25, 0, 0, 44), BackgroundColor3 = Color3.fromRGB(20, 20, 20), BorderSizePixel = 0, Visible = false }, gui)
local bossFill = new("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(170, 20, 20), BorderSizePixel = 0 }, bossFrame)
new("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2 }, bossFrame)
local bossText = new("TextLabel", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, -22), BackgroundTransparency = 1, Text = "NOSOI", TextColor3 = white, Font = Enum.Font.Code, TextSize = 15, TextStrokeTransparency = 0.5 }, bossFrame)
local statusLabel = new("TextLabel", { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, 2), BackgroundTransparency = 1, Text = "", TextColor3 = Color3.fromRGB(80, 255, 120), Font = Enum.Font.Code, TextSize = 14, TextStrokeTransparency = 0.5 }, bossFrame)

local function bar(y, color, label)
	local f = new("Frame", { Size = UDim2.new(0, 150, 0, 12), Position = UDim2.new(0, 14, 0.2, y), BackgroundColor3 = Color3.fromRGB(20, 20, 20), BorderSizePixel = 0 }, gui)
	new("UIStroke", { Thickness = 2, Color = Color3.new(0, 0, 0) }, f)
	local fill = new("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0 }, f)
	new("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = label, TextColor3 = white, Font = Enum.Font.Code, TextSize = 10, TextStrokeTransparency = 0.5 }, f)
	return fill
end
local hpFill = bar(0, Color3.fromRGB(60, 200, 80), "HP")
local infFill = bar(18, Color3.fromRGB(150, 220, 40), "INFECTION")

local msgLabel = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(0.8, 0, 0, 60), Position = UDim2.new(0.5, 0, 0.14, 0), BackgroundTransparency = 1, Text = "", TextColor3 = white, Font = Enum.Font.Code, TextSize = 22, TextWrapped = true, TextTransparency = 1, TextStrokeTransparency = 1 }, gui)
local msgSeq = 0
local function showMsg(text, dur, color)
	msgSeq += 1
	local my = msgSeq
	msgLabel.Text = text
	msgLabel.TextColor3 = color or white
	msgLabel.TextTransparency = 0
	msgLabel.TextStrokeTransparency = 0.4
	task.delay(dur or 2.5, function()
		if msgSeq == my then
			tween(msgLabel, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
	end)
end

local infOverlay = new("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(40, 90, 10), BackgroundTransparency = 1, BorderSizePixel = 0, Active = false }, gui)
local flashOverlay = new("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Active = false }, gui)

local dashBtn = new("TextButton", { Size = UDim2.fromOffset(70, 70), Position = UDim2.new(1, -95, 1, -210), BackgroundColor3 = Color3.fromRGB(20, 20, 20), BackgroundTransparency = 0.25, Text = "DASH", TextColor3 = white, Font = Enum.Font.Code, TextSize = 16 }, gui)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, dashBtn)
new("UIStroke", { Color = Color3.fromRGB(0, 200, 255), Thickness = 2 }, dashBtn)

------------------------------------------------------------------
-- PLAYER DAMAGE / DEATH
------------------------------------------------------------------
local function die()
	if S.over then return end
	S.over = true
	S.started = false
	showMsg("YOU DIED - THE TREE REMEMBERS", 3, Color3.fromRGB(255, 60, 60))
	local id = S.run
	task.delay(3, function()
		if S.run == id then startRun() end
	end)
end

local function damagePlayer(n, force)
	if S.over then return false end
	local now = os.clock()
	if not force and now < S.iframeUntil then return false end
	S.iframeUntil = math.max(S.iframeUntil, now + 0.45)
	S.playerHP = math.max(0, S.playerHP - n)
	flashOverlay.BackgroundTransparency = 0.6
	tween(flashOverlay, TweenInfo.new(0.35), { BackgroundTransparency = 1 })
	sfx(CFG.SND.hit, 0.5, 1.3)
	if S.playerHP <= 0 then die() end
	return true
end

local function drain(n)
	if S.over then return end
	S.playerHP = math.max(0, S.playerHP - n)
	if S.playerHP <= 0 then die() end
end

------------------------------------------------------------------
-- WORLD HELPERS
------------------------------------------------------------------
local function key(ix, iz) return ix .. "," .. iz end

local function tileAt(pos)
	local ix = math.floor((pos.X - O.X) / T + 0.5)
	local iz = math.floor((pos.Z - O.Z) / T + 0.5)
	return tiles[key(ix, iz)], ix, iz
end

local function tileCenter(ix, iz) return O + Vector3.new(ix * T, 0, iz * T) end

local function safeSpot()
	local best, bd = nil, math.huge
	local want = O + Vector3.new(0, 0, -26)
	for _, t in pairs(tiles) do
		if t.alive and not t.locked then
			local d = (flat(t.part.Position) - flat(want)).Magnitude
			if d < bd then bd = d best = t end
		end
	end
	if best then return best.part.Position + Vector3.new(0, 6, 0) end
	return O + Vector3.new(0, 6, -24)
end

local function teleport(pos)
	local h = hrp()
	if not h then return end
	h.AssemblyLinearVelocity = Vector3.zero
	h.CFrame = CFrame.new(pos)
end

local function shatter(part)
	local pos, col, mat = part.Position, part.Color, part.Material
	for _ = 1, 8 do
		local d = new("Part", {
			Size = Vector3.new(0.9, 0.9, 0.9), Color = col, Material = mat, CanCollide = true,
			Position = pos + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)),
		}, fx)
		d.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-30, 30), rng:NextNumber(10, 35), rng:NextNumber(-30, 30))
		Debris:AddItem(d, 2.5)
	end
	part:Destroy()
end

local function windup(t, id)
	S.pending += 1
	local e = 0
	while e < t do
		local dt = RunService.Heartbeat:Wait()
		if S.run ~= id or S.over then
			S.pending = math.max(0, S.pending - 1)
			return false
		end
		if os.clock() >= S.stallUntil then e += dt end
	end
	S.pending = math.max(0, S.pending - 1)
	return true
end

------------------------------------------------------------------
-- BUILD ARENA + TREE
------------------------------------------------------------------
local function buildArena()
	for ix = -CFG.HALF, CFG.HALF do
		for iz = -CFG.HALF, CFG.HALF do
			local c = ((ix + iz) % 2 == 0) and Color3.fromRGB(99, 99, 99) or Color3.fromRGB(86, 86, 86)
			local p = new("Part", {
				Name = "Tile", Anchored = true, Size = Vector3.new(T, 2, T),
				Position = O + Vector3.new(ix * T, -1, iz * T), Color = c,
				Material = Enum.Material.Plastic,
				TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth,
			}, arena)
			tiles[key(ix, iz)] = { part = p, ix = ix, iz = iz, alive = true, locked = false, progress = 0, immune = 0, baseColor = c }
		end
	end
end

local function buildTree()
	treeModel = new("Model", { Name = "Nosoi" }, arena)
	local black = Color3.fromRGB(8, 8, 8)
	local function bp(size, cf, collide)
		return new("Part", {
			Anchored = true, Size = size, CFrame = cf, Color = black, Material = Enum.Material.Wood,
			CanCollide = collide or false, TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth,
		}, treeModel)
	end
	trunk = bp(Vector3.new(8, 70, 8), CFrame.new(O + Vector3.new(0, 35, 0)), true)
	trunk.Name = "Trunk"
	branches = {}
	for i = 0, 3 do
		local ang = i * math.pi / 2 + math.pi / 4
		local base = CFrame.new(O + Vector3.new(0, 46 + (i % 2) * 9, 0)) * CFrame.Angles(0, ang, 0) * CFrame.Angles(math.rad(-20), 0, 0) * CFrame.new(0, 0, -15)
		local b = bp(Vector3.new(3, 3, 30), base)
		table.insert(branches, { part = b, cf = base })
		bp(Vector3.new(1.6, 1.6, 16), base * CFrame.new(0, 1, -14) * CFrame.Angles(0, math.rad(40), 0) * CFrame.new(0, 0, -7))
		bp(Vector3.new(1.6, 1.6, 14), base * CFrame.new(0, 1, -10) * CFrame.Angles(0, math.rad(-40), 0) * CFrame.new(0, 0, -6))
	end
	for i = 0, 5 do
		local ang = i * math.pi / 3
		bp(Vector3.new(2.5, 2.5, 16), CFrame.new(O + Vector3.new(0, 1, 0)) * CFrame.Angles(0, ang, 0) * CFrame.Angles(math.rad(15), 0, 0) * CFrame.new(0, 0, -8))
	end
end

local function shakeBranches()
	task.spawn(function()
		for _ = 1, 22 do
			for _, b in ipairs(branches) do
				if b.part.Parent then
					b.part.CFrame = b.cf * CFrame.Angles(rng:NextNumber(-0.05, 0.05), rng:NextNumber(-0.05, 0.05), 0)
				end
			end
			task.wait(0.03)
		end
		for _, b in ipairs(branches) do
			if b.part.Parent then b.part.CFrame = b.cf end
		end
	end)
end

local function pulseTree()
	if trunk and trunk.Parent then
		tween(trunk, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Size = Vector3.new(9, 70, 9) })
	end
end

------------------------------------------------------------------
-- BOSS DAMAGE / PHASES
------------------------------------------------------------------
local function closePopup(P)
	for i, q in ipairs(popups) do
		if q == P then table.remove(popups, i) break end
	end
	if P.frame then P.frame:Destroy() end
end

local function closePopups()
	for i = #popups, 1, -1 do
		local P = popups[i]
		table.remove(popups, i)
		if P.frame then P.frame:Destroy() end
	end
end

local function dropTile(t)
	if not t.alive then return end
	t.alive = false
	t.locked = false
	sfx(CFG.SND.groan, 0.5, 0.4)
	tween(t.part, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = t.part.Position + Vector3.new(0, -90, 0), Transparency = 1 })
	Debris:AddItem(t.part, 1.8)
end

local function collapseArena()
	local list = {}
	for _, t in pairs(tiles) do
		if t.alive and (math.abs(t.ix) > 1 or math.abs(t.iz) > 1) then
			local d = flat(t.part.Position - O).Magnitude
			if d > 60 or (d > 28 and rng:NextNumber() < 0.3) then
				table.insert(list, { t = t, d = d })
			end
		end
	end
	for _, e in ipairs(list) do
		task.delay(math.max(0, 130 - e.d) / 130, function() dropTile(e.t) end)
	end
	for _, t in pairs(tiles) do
		if t.alive then
			t.baseColor = Color3.fromRGB(60, 8, 12)
			if not t.locked then tween(t.part, TweenInfo.new(1.2), { Color = t.baseColor }) end
		end
	end
end

local function startLink()
	local h = hrp()
	if not h then return end
	S.linked = true
	if S.beam then S.beam:Destroy() end
	local a0 = new("Attachment", { Position = Vector3.new(0, -25, -4.2) }, trunk)
	local a1 = new("Attachment", { Position = Vector3.new(0, 0.8, 0) }, h)
	S.beam = new("Beam", {
		Attachment0 = a0, Attachment1 = a1, Color = ColorSequence.new(Color3.fromRGB(255, 30, 30)),
		LightEmission = 1, Width0 = 0.9, Width1 = 0.9, Segments = 8, FaceCamera = true,
	}, trunk)
	showMsg("THE LIFE-LINK VINE BINDS YOU - JUMP INTO THE VOID!", 4, Color3.fromRGB(255, 60, 60))
end

local function victory()
	if S.over then return end
	S.over = true
	S.started = false
	S.linked = false
	if S.beam then S.beam.Enabled = false end
	local id = S.run
	closePopups()
	sfx(CFG.SND.hit, 1.5, 0.6)
	if S.core and S.core.Parent then shatter(S.core) end
	S.core = nil
	if treeModel then
		for _, p in ipairs(treeModel:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Material = Enum.Material.Neon
				p.Color = Color3.fromRGB(255, 255, 255)
				tween(p, TweenInfo.new(3), { Transparency = 1 })
			end
		end
	end
	skyMode("blue", 3)
	bossFrame.Visible = false
	showMsg("NOSOI DELETED. TERMINAL DISCONNECTED.", 7, Color3.fromRGB(80, 255, 120))
	task.delay(9, function()
		if S.run == id and _G.NosoiCleanup then _G.NosoiCleanup() end
	end)
end

local function breakLink()
	if not S.linked then return end
	local id = S.run
	S.linked = false
	if S.beam then S.beam.Enabled = false end
	teleport(safeSpot())
	S.iframeUntil = os.clock() + 3.5
	S.coreHP = 3
	S.core = new("Part", {
		Name = "Core", Shape = Enum.PartType.Ball, Size = Vector3.new(6, 6, 6), Anchored = true, CanCollide = false,
		Color = Color3.fromRGB(255, 60, 60), Material = Enum.Material.Neon, Position = O + Vector3.new(0, 6, -8),
	}, fx)
	new("PointLight", { Color = Color3.fromRGB(255, 60, 60), Range = 20, Brightness = 3 }, S.core)
	tween(S.core, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Size = Vector3.new(7.2, 7.2, 7.2) })
	showMsg("LINK SEVERED - SMASH THE CORE!", 3, Color3.fromRGB(80, 255, 120))
	task.delay(12, function()
		if S.run ~= id or S.over then return end
		if S.core and S.core.Parent then
			S.core:Destroy()
			S.core = nil
			S.hp = 20
			S.coreHP = 3
			S.linked = true
			if S.beam then S.beam.Enabled = true end
			showMsg("THE VINE REFORMS - JUMP AGAIN!", 3, Color3.fromRGB(255, 60, 60))
		end
	end)
end

local function beginPhase(n, id)
	S.busy = true
	S.phase = n
	S.timersReset = true
	closePopups()
	for i = #roots, 1, -1 do
		if roots[i].part.Parent then roots[i].part:Destroy() end
		table.remove(roots, i)
	end
	showMsg("PHASE " .. n .. ": " .. PHASE_NAMES[n], 3, Color3.fromRGB(255, 80, 80))
	sfx(CFG.SND.groan, 1, 0.5)
	shakeBranches()
	task.spawn(function()
		task.wait(1.5)
		if S.run ~= id or S.over then return end
		if n == 2 then
			showMsg("JUMP on the beat - DASH off the beat", 3.5)
		elseif n == 3 then
			showMsg("Click the glitched X, or equip Defrag and tap to wipe them", 3.5)
		elseif n == 4 then
			showMsg("ARENA COLLAPSING - GET TO THE CENTER", 2.5, Color3.fromRGB(255, 200, 60))
			task.wait(2.5)
			if S.run ~= id then return end
			collapseArena()
			skyMode("void", 1.5)
			for i = #falling, 1, -1 do
				falling[i].part:Destroy()
				if falling[i].shadow then falling[i].shadow:Destroy() end
				table.remove(falling, i)
			end
			for i = #debris, 1, -1 do
				if debris[i].Parent then debris[i]:Destroy() end
				table.remove(debris, i)
			end
			task.wait(1.5)
		elseif n == 5 then
			for i = #nodes, 1, -1 do
				if nodes[i].part.Parent then nodes[i].part:Destroy() end
				table.remove(nodes, i)
			end
			S.hp = 20
			startLink()
		end
		if S.run == id then S.busy = false end
	end)
end

local function damageBoss(n)
	if S.over or S.busy or not S.started or S.phase >= 5 then return end
	local fl = CFG.FLOORS[S.phase]
	S.hp = math.max(fl, S.hp - n)
	if S.hp <= fl then
		beginPhase(S.phase + 1, S.run)
	end
end

------------------------------------------------------------------
-- ATTACKS
------------------------------------------------------------------
local function rootSprout(id)
	local h = hrp()
	if not h then return end
	local tl, ix, iz = tileAt(h.Position)
	if not tl or not tl.alive then return end
	local center = tileCenter(ix, iz)
	local box = new("Part", {
		Anchored = true, CanCollide = false, CanQuery = false, Size = Vector3.new(T, 0.4, T),
		Position = center + Vector3.new(0, 0.25, 0), Color = Color3.fromRGB(255, 20, 20),
		Material = Enum.Material.Neon, Transparency = 0.55,
	}, fx)
	new("SelectionBox", { Adornee = box, Color3 = Color3.fromRGB(255, 40, 40), LineThickness = 0.08, SurfaceTransparency = 0.7, SurfaceColor3 = Color3.fromRGB(255, 0, 0) }, box)
	local ok = windup(0.85, id)
	box:Destroy()
	if not ok then return end
	sfx(CFG.SND.groan, 0.6, 0.45)
	local offs = { Vector3.new(0, 0, 0), Vector3.new(4.5, 0, 4.5), Vector3.new(-4.5, 0, 4.5), Vector3.new(4.5, 0, -4.5), Vector3.new(-4.5, 0, -4.5) }
	local mine = {}
	for _, o in ipairs(offs) do
		local base = center + o
		local sp = new("Part", {
			Name = "RootSpike", Anchored = true, Size = Vector3.new(3, 0.5, 3), Position = base + Vector3.new(0, 0.25, 0),
			Color = Color3.fromRGB(14, 8, 6), Material = Enum.Material.Wood, CanCollide = true,
		}, fx)
		tween(sp, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Size = Vector3.new(3, 14, 3), Position = base + Vector3.new(0, 7, 0) })
		local r = { part = sp }
		table.insert(roots, r)
		table.insert(mine, r)
	end
	local h2 = hrp()
	if h2 then
		local rel = h2.Position - center
		if math.abs(rel.X) < T / 2 + 1 and math.abs(rel.Z) < T / 2 + 1 and h2.Position.Y - floorY < 9 then
			damagePlayer(18)
		end
	end
	task.delay(2.4, function()
		for _, r in ipairs(mine) do
			if r.part.Parent then
				tween(r.part, TweenInfo.new(0.3), { Size = Vector3.new(3, 0.5, 3), Position = r.part.Position - Vector3.new(0, 6.7, 0) })
				Debris:AddItem(r.part, 0.35)
			end
			for i, q in ipairs(roots) do
				if q == r then table.remove(roots, i) break end
			end
		end
	end)
end

local function splinterHail(id)
	shakeBranches()
	sfx(CFG.SND.groan, 0.8, 0.6)
	for _ = 1, 16 do
		if S.run ~= id or S.over then return end
		local ang = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(14, 62)
		local pos = O + Vector3.new(math.cos(ang) * r, 70 + rng:NextNumber(0, 20), math.sin(ang) * r)
		local b = new("Part", {
			Name = "Splinter", Anchored = true, CanCollide = false, Size = Vector3.new(4, 4, 4), Position = pos,
			Color = Color3.fromRGB(22, 13, 9), Material = Enum.Material.Wood,
		}, fx)
		local sh = new("Part", {
			Anchored = true, CanCollide = false, CanQuery = false, Size = Vector3.new(4, 0.15, 4),
			Position = Vector3.new(pos.X, floorY + 0.12, pos.Z), Color = Color3.new(0, 0, 0), Transparency = 0.35,
			Material = Enum.Material.SmoothPlastic,
		}, fx)
		table.insert(falling, { part = b, shadow = sh, vy = 0, hit = false })
		task.wait(0.08)
	end
end

local function spawnPopup(id)
	if #popups >= 5 then return end
	local f = new("Frame", {
		Size = UDim2.fromOffset(270, 112), Position = UDim2.new(rng:NextInteger(8, 62) / 100, 0, rng:NextInteger(15, 58) / 100, 0),
		BackgroundColor3 = Color3.fromRGB(192, 192, 192), BorderSizePixel = 2, BorderColor3 = Color3.new(0, 0, 0), Active = true,
	}, noyGui)
	local title = new("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = Color3.fromRGB(0, 0, 128), BorderSizePixel = 0 }, f)
	new("TextLabel", { Size = UDim2.new(1, -30, 1, 0), Position = UDim2.new(0, 4, 0, 0), BackgroundTransparency = 1, Text = "Noy.exe - not responding", TextColor3 = white, Font = Enum.Font.Code, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left }, title)
	local xb = new("TextButton", { Size = UDim2.fromOffset(24, 18), Position = UDim2.new(1, -26, 0, 2), BackgroundColor3 = Color3.fromRGB(210, 0, 0), Text = "X", TextColor3 = white, Font = Enum.Font.Code, TextSize = 14, BorderSizePixel = 1 }, title)
	local lbl = new("TextLabel", { Size = UDim2.new(1, -16, 1, -32), Position = UDim2.new(0, 8, 0, 28), BackgroundTransparency = 1, Text = "", TextColor3 = Color3.new(0, 0, 0), Font = Enum.Font.Code, TextSize = 18, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, f)
	local P = { frame = f }
	table.insert(popups, P)
	xb.Activated:Connect(function() closePopup(P) end)
	task.spawn(function()
		local msgs = { "It is just a tree.", "SPREAD", "Noy is watching.", "Do not look at the roots.", "Delete yourself." }
		local m = msgs[rng:NextInteger(1, #msgs)]
		for i = 1, #m do
			if not f.Parent then return end
			lbl.Text = m:sub(1, i)
			sfx(CFG.SND.crackle, 0.15, 2.2)
			task.wait(0.05)
		end
	end)
	task.spawn(function()
		local t0 = os.clock()
		while f.Parent and S.run == id do
			xb.Position = UDim2.new(1, -26 + rng:NextInteger(-3, 3), 0, 2 + rng:NextInteger(-2, 2))
			xb.TextColor3 = (rng:NextInteger(0, 1) == 0) and white or Color3.fromRGB(0, 255, 120)
			if os.clock() - t0 > 12 then closePopup(P) break end
			task.wait(0.1)
		end
	end)
end

local function branchSweep(id)
	if S.sweeping then return end
	S.sweeping = true
	S.pending += 1
	local len = 74
	local ang = rng:NextNumber(0, math.pi * 2)
	local sgn = (rng:NextInteger(0, 1) == 0) and 1 or -1
	local function dirOf(a) return Vector3.new(math.cos(a), 0, math.sin(a)) end
	local branch = new("Part", { Anchored = true, CanCollide = false, Color = Color3.fromRGB(5, 5, 5), Material = Enum.Material.Wood, Size = Vector3.new(3.4, 3.4, len) }, fx)
	local shadow = new("Part", { Anchored = true, CanCollide = false, CanQuery = false, Color = Color3.new(0, 0, 0), Material = Enum.Material.SmoothPlastic, Size = Vector3.new(7, 0.2, len) }, fx)
	local function cfs(a, hgt)
		local d = dirOf(a)
		local c = O + d * (len / 2 + 3)
		local bc = Vector3.new(c.X, O.Y + hgt, c.Z)
		local sc = Vector3.new(c.X, floorY + 0.15, c.Z)
		return CFrame.lookAt(bc, bc + d), CFrame.lookAt(sc, sc + d)
	end
	local bcf, scf = cfs(ang, 28)
	branch.CFrame = bcf
	shadow.CFrame = scf
	local lowCF = cfs(ang, 5)
	tween(branch, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = lowCF })
	S.pending -= 1
	local ok = windup(1.3, id)
	S.pending += 1
	if ok then
		local dur, t = 2.7, 0
		local total = math.rad(130) * sgn
		while t < dur and S.run == id and not S.over do
			local dt = RunService.Heartbeat:Wait()
			if os.clock() >= S.stallUntil then t += dt end
			local a = ang + total * (t / dur)
			local b2, s2 = cfs(a, 5)
			branch.CFrame = b2
			shadow.CFrame = s2
			local h = hrp()
			if h then
				local rel = h.Position - O
				local d = dirOf(a)
				local along = rel.X * d.X + rel.Z * d.Z
				local lat = math.abs(rel.X * -d.Z + rel.Z * d.X)
				if along > 3 and along < len + 3 and lat < 3.2 and h.Position.Y - floorY < 6.3 then
					damagePlayer(16)
				end
			end
		end
	end
	S.pending = math.max(0, S.pending - 1)
	branch:Destroy()
	shadow:Destroy()
	S.sweeping = false
end

local function fireClaw()
	local h = hrp()
	if not h or S.over then return end
	local dir0 = flat(h.Position - O)
	dir0 = dir0.Magnitude > 0.1 and dir0.Unit or Vector3.new(0, 0, -1)
	local pos = O + dir0 * 6 + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(14, 34), rng:NextNumber(-2, 2))
	local p = new("Part", { Name = "Claw", Anchored = true, CanCollide = false, Size = Vector3.new(0.8, 0.8, 4), Color = Color3.fromRGB(150, 10, 10), Material = Enum.Material.Neon, Position = pos }, fx)
	table.insert(claws, { part = p, dir = (h.Position - pos).Unit, born = os.clock() })
end

local function spawnRing()
	local segs = {}
	for i = 1, 24 do
		segs[i] = new("Part", { Anchored = true, CanCollide = false, CanQuery = false, Size = Vector3.new(3, 2.4, 6), Color = Color3.fromRGB(255, 40, 40), Material = Enum.Material.Neon, Transparency = 0.15 }, fx)
	end
	table.insert(rings, { R = 6, segs = segs, hit = false })
end

local function pickTile()
	local h = hrp()
	if not h then return nil end
	local c = {}
	for _, t in pairs(tiles) do
		if t.alive and not t.locked and os.clock() > t.immune and (math.abs(t.ix) > 1 or math.abs(t.iz) > 1) then
			table.insert(c, t)
		end
	end
	if #c < 12 then return nil end
	table.sort(c, function(a, b) return (a.part.Position - h.Position).Magnitude < (b.part.Position - h.Position).Magnitude end)
	return c[rng:NextInteger(1, math.min(6, #c))]
end

local function despawnTile(id)
	local t = pickTile()
	if not t then return end
	S.despawning += 1
	t.locked = true
	t.progress = 0
	local p = t.part
	tween(p, TweenInfo.new(0.4), { Transparency = 0.6 })
	local remaining, acc = 3, 0
	while S.run == id and remaining > 0 and t.progress < 2 and not S.over do
		local dt = RunService.Heartbeat:Wait()
		if os.clock() >= S.stallUntil then remaining -= dt end
		acc += dt
		if acc > 0.18 then
			acc = 0
			sfx(CFG.SND.crackle, 0.3, rng:NextNumber(1.6, 2.4))
		end
		local v = rng:NextNumber(0.1, 0.9)
		p.Color = Color3.new(v, v, v):Lerp(Color3.fromRGB(180, 255, 255), math.clamp(t.progress / 2, 0, 1))
	end
	S.despawning = math.max(0, S.despawning - 1)
	if S.run ~= id then return end
	t.locked = false
	if t.progress >= 2 then
		t.immune = os.clock() + 12
		p.Transparency = 0
		tween(p, TweenInfo.new(0.4), { Color = t.baseColor })
		showMsg("TILE PATCHED", 1, Color3.fromRGB(150, 255, 255))
	else
		dropTile(t)
	end
end

local function spawnNode()
	local lo, hi = 4, 11
	if S.phase == 1 then lo, hi = 15, 27 end
	local ang = rng:NextNumber(0, math.pi * 2)
	local y = rng:NextNumber(lo, hi)
	local pos = O + Vector3.new(math.cos(ang) * 4.6, y, math.sin(ang) * 4.6)
	local part = new("Part", { Name = "GlitchNode", Anchored = true, CanCollide = false, Size = Vector3.new(3, 3, 3), Position = pos, Color = Color3.fromRGB(255, 0, 200), Material = Enum.Material.Neon }, fx)
	new("PointLight", { Color = Color3.fromRGB(255, 0, 200), Range = 14, Brightness = 3 }, part)
	table.insert(nodes, { part = part })
	sfx(CFG.SND.crackle, 0.4, 1.5)
end

local function onTreeHit()
	local now = os.clock()
	if S.started and not S.over and S.pending > 0 then
		S.stallUntil = math.max(S.stallUntil, now + 1.5)
		if trunk and trunk.Parent then
			trunk.Color = Color3.fromRGB(0, 110, 30)
			tween(trunk, TweenInfo.new(1.5), { Color = Color3.fromRGB(8, 8, 8) })
		end
		sfx(CFG.SND.crackle, 0.5, 0.8)
	end
	damageBoss(CFG.CHIP)
end

------------------------------------------------------------------
-- SCHEDULERS / LOOPS
------------------------------------------------------------------
local function scheduler(id)
	local nxt = { sprout = 0, hail = 0, popup = 0, sweep = 0, despawn = 0, claw = 0 }
	while S.run == id do
		task.wait(0.2)
		if S.over or not S.started or S.busy then continue end
		local now = os.clock()
		if S.timersReset then
			S.timersReset = false
			for k in pairs(nxt) do nxt[k] = now + 2.5 end
		end
		local function due(k, gap)
			if now >= nxt[k] then nxt[k] = now + gap return true end
			return false
		end
		local ph = S.phase
		if ph == 1 then
			if due("sprout", 2.6) then task.spawn(rootSprout, id) end
			if due("hail", 9.5) then task.spawn(splinterHail, id) end
		elseif ph == 3 then
			if due("sprout", 4.5) then task.spawn(rootSprout, id) end
			if due("popup", 3.6) then spawnPopup(id) end
			if due("sweep", 8) and not S.sweeping then task.spawn(branchSweep, id) end
		elseif ph == 4 then
			if S.despawning < 2 and due("despawn", 3.2) then task.spawn(despawnTile, id) end
			if due("claw", 4.5) then fireClaw() end
		elseif ph == 5 and S.linked then
			if due("claw", 5) then fireClaw() end
		end
	end
end

local function nodeLoop(id)
	while S.run == id do
		task.wait(0.7)
		if S.started and not S.busy and not S.over and S.phase < 5 and #nodes < 3 then spawnNode() end
	end
end

local function beatLoop(id)
	while S.run == id do
		local h = hrp()
		local period, vol, speed = 1.2, 0.5, 0.8
		if not S.triggered then
			local d = h and flat(h.Position - O).Magnitude or CFG.SPAWN_DIST
			local c = math.clamp((CFG.SPAWN_DIST + 10 - d) / (CFG.SPAWN_DIST + 10 - CFG.TRIGGER), 0, 1)
			period = 1.6 - 0.9 * c
			vol = 0.15 + 0.85 * c
			speed = 1.15 - 0.55 * c
		else
			local p = math.max(S.phase, 1)
			period = ({ 0.95, 0.8, 0.7, 0.62, 0.55 })[p]
			speed = ({ 0.65, 1.35, 0.7, 0.6, 0.5 })[p]
			vol = 1
		end
		if not S.over then
			sfx(CFG.SND.thump, vol, speed)
			task.delay(0.16, function() sfx(CFG.SND.thump, vol * 0.7, speed * 0.9) end)
			pulseTree()
			if S.triggered and S.started and not S.busy and S.phase == 2 then
				spawnRing()
				task.delay(period * 0.5, function()
					if S.run == id and S.phase == 2 and not S.over and not S.busy then fireClaw() end
				end)
			end
		end
		task.wait(period)
	end
end

local function trigger(id)
	S.triggered = true
	S.busy = true
	sfx(CFG.SND.groan, 1.5, 0.35)
	skyMode("red", 0.15)
	showMsg("N O S O I", 3, Color3.fromRGB(255, 40, 40))
	local infC = Color3.fromRGB(110, 18, 18)
	for _, t in pairs(tiles) do
		local d = (t.part.Position - O).Magnitude
		if d <= CFG.TRIGGER + 8 then
			task.delay(d / 70, function()
				if S.run == id and t.alive then
					t.baseColor = infC
					if not t.locked then tween(t.part, TweenInfo.new(0.4), { Color = infC }) end
				end
			end)
		end
	end
	task.spawn(function()
		local hu = hum()
		for _ = 1, 25 do
			if hu then hu.CameraOffset = Vector3.new(rng:NextNumber(-0.6, 0.6), rng:NextNumber(-0.6, 0.6), 0) end
			task.wait(0.04)
		end
		if hu then hu.CameraOffset = Vector3.zero end
		task.wait(1.5)
		if S.run ~= id then return end
		S.started = true
		S.phase = 1
		S.hp = 100
		S.busy = false
		S.treeLive = true
		S.timersReset = true
		bossFrame.Visible = true
	end)
end

------------------------------------------------------------------
-- TOOLS
------------------------------------------------------------------
local cmdHold, cmdEquipped, cmdNext = false, false, 0
local dfHold, dfEquipped = false, false
local swinging = false

local function toolPart(props, parent)
	props.Anchored = false
	props.CanCollide = false
	props.Massless = true
	props.TopSurface = Enum.SurfaceType.Smooth
	props.BottomSurface = Enum.SurfaceType.Smooth
	return new("Part", props, parent)
end

local function weld(a, b)
	new("WeldConstraint", { Part0 = a, Part1 = b }, a)
end

-- Cmd_Prompt.exe
local cmdTool = new("Tool", { Name = "Cmd_Prompt.exe", RequiresHandle = true, CanBeDropped = false, ToolTip = "Ranged Disrupter: stalls Nosoi's attacks" })
do
	local h = toolPart({ Name = "Handle", Size = Vector3.new(1.8, 2.2, 0.25), Color = Color3.fromRGB(6, 6, 6), Material = Enum.Material.SmoothPlastic }, cmdTool)
	local sg = new("SurfaceGui", { Face = Enum.NormalId.Front, AlwaysOnTop = false }, h)
	new("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(0, 10, 0), BorderSizePixel = 0, Text = "C:\\> kill nosoi\n01101110\n10010110_", TextColor3 = Color3.fromRGB(0, 255, 70), Font = Enum.Font.Code, TextScaled = true }, sg)
end

-- Task_Manager.bat
local tmTool = new("Tool", { Name = "Task_Manager.bat", RequiresHandle = true, CanBeDropped = false, ToolTip = "Heavy Striker: END TASK exposed Glitch Nodes" })
local gripBase = CFrame.new(0, 0, -1.2)
do
	local h = toolPart({ Name = "Handle", Size = Vector3.new(0.4, 0.4, 3.6), Color = Color3.fromRGB(0, 170, 255), Material = Enum.Material.Neon }, tmTool)
	local head = toolPart({ Name = "Head", Size = Vector3.new(2.6, 0.6, 0.9), Color = Color3.fromRGB(80, 200, 255), Material = Enum.Material.Neon, Transparency = 0.3 }, tmTool)
	head.CFrame = h.CFrame * CFrame.new(0, 0, -1.55)
	weld(h, head)
	for _, o in ipairs({ Vector3.new(1.1, 0.7, -0.9), Vector3.new(-1.1, 0.7, -1.4) }) do
		local pn = toolPart({ Size = Vector3.new(1.1, 1.1, 0.1), Color = Color3.fromRGB(120, 220, 255), Material = Enum.Material.Neon, Transparency = 0.5 }, tmTool)
		pn.CFrame = h.CFrame * CFrame.new(o)
		weld(h, pn)
	end
	tmTool.Grip = gripBase
end

-- Defrag.vbs
local dfTool = new("Tool", { Name = "Defrag.vbs", RequiresHandle = true, CanBeDropped = false, ToolTip = "Support: hold to patch tiles / cleanse infection. Click wipes pop-ups" })
do
	local h = toolPart({ Name = "Handle", Size = Vector3.new(1.5, 0.15, 1.6), Color = Color3.fromRGB(240, 240, 250), Material = Enum.Material.SmoothPlastic }, dfTool)
	new("PointLight", { Color = Color3.new(1, 1, 1), Range = 10, Brightness = 2 }, h)
	local sg = new("SurfaceGui", { Face = Enum.NormalId.Top }, h)
	new("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "DEFRAG", TextColor3 = Color3.fromRGB(20, 20, 20), Font = Enum.Font.Code, TextScaled = true }, sg)
end

for _, n in ipairs({ "Cmd_Prompt.exe", "Task_Manager.bat", "Defrag.vbs" }) do
	local old = player.Backpack:FindFirstChild(n)
	if old then old:Destroy() end
end
cmdTool.Parent = player:WaitForChild("Backpack")
tmTool.Parent = player.Backpack
dfTool.Parent = player.Backpack

local dfBeam = new("Part", { Anchored = true, CanCollide = false, CanQuery = false, Material = Enum.Material.Neon, Color = Color3.new(1, 1, 1), Size = Vector3.new(0.3, 0.3, 1), Transparency = 1 }, workspace)

cmdTool.Equipped:Connect(function() cmdEquipped = true end)
cmdTool.Unequipped:Connect(function() cmdEquipped = false cmdHold = false end)
cmdTool.Activated:Connect(function() cmdHold = true end)
cmdTool.Deactivated:Connect(function() cmdHold = false end)
dfTool.Equipped:Connect(function() dfEquipped = true end)
dfTool.Unequipped:Connect(function() dfEquipped = false dfHold = false end)
dfTool.Activated:Connect(function()
	dfHold = true
	for i = #popups, 1, -1 do closePopup(popups[i]) end
end)
dfTool.Deactivated:Connect(function() dfHold = false end)

local function fireCmd(h)
	if #projs > 60 then return end
	local handle = cmdTool:FindFirstChild("Handle")
	local origin = (handle and handle.Position) or (h.Position + Vector3.new(0, 1, 0))
	local aim = mouse.Hit and mouse.Hit.Position or (camera.CFrame.Position + camera.CFrame.LookVector * 100)
	local v = aim - origin
	if v.Magnitude < 0.5 then return end
	local dir = v.Unit
	local p = new("Part", { Anchored = true, CanCollide = false, CanQuery = false, Size = Vector3.new(0.4, 0.4, 1.4), Color = Color3.fromRGB(0, 255, 70), Material = Enum.Material.Neon, CFrame = CFrame.lookAt(origin, origin + dir) }, fx)
	local bb = new("BillboardGui", { Size = UDim2.fromOffset(30, 18), AlwaysOnTop = false }, p)
	new("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = (rng:NextInteger(0, 1) == 0) and "01" or "10", TextColor3 = Color3.fromRGB(0, 255, 70), Font = Enum.Font.Code, TextScaled = true }, bb)
	table.insert(projs, { part = p, dir = dir, born = os.clock() })
end

local function destroyFalling(i)
	local f = falling[i]
	if f.part then f.part:Destroy() end
	if f.shadow then f.shadow:Destroy() end
	table.remove(falling, i)
end

local function endTask(n, idx)
	table.remove(nodes, idx)
	shatter(n.part)
	sfx(CFG.SND.hit, 0.8, 1.1)
	showMsg("END TASK", 1, Color3.fromRGB(0, 200, 255))
	damageBoss(CFG.NODE_DMG)
end

local function doSwingHit()
	local h = hrp()
	if not h then return end
	local hitSomething = false
	for i = #roots, 1, -1 do
		local r = roots[i]
		if r.part.Parent and (r.part.Position - h.Position).Magnitude <= 11 then
			shatter(r.part)
			table.remove(roots, i)
			hitSomething = true
		end
	end
	if S.core and S.core.Parent and (S.core.Position - h.Position).Magnitude <= 13 then
		hitSomething = true
		S.coreHP -= 1
		S.hp = 20 * math.max(S.coreHP, 0) / 3
		sfx(CFG.SND.hit, 1, 0.8)
		S.core.Color = white
		tween(S.core, TweenInfo.new(0.3), { Color = Color3.fromRGB(255, 60, 60) })
		if S.coreHP <= 0 then victory() return end
	end
	for i = #nodes, 1, -1 do
		local n = nodes[i]
		if n.part.Parent and (n.part.Position - h.Position).Magnitude <= 11.5 then
			endTask(n, i)
			hitSomething = true
		end
	end
	if not hitSomething and S.treeLive then
		local d = flat(h.Position - O).Magnitude
		if d <= 10.5 then
			sfx(CFG.SND.hit, 0.4, 2)
			showMsg("BARK BLOCKED - hit a Glitch Node", 1, Color3.fromRGB(200, 200, 200))
		end
	end
end

tmTool.Activated:Connect(function()
	if swinging or S.over then return end
	swinging = true
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.28 do
			local a = (os.clock() - t0) / 0.28
			tmTool.Grip = gripBase * CFrame.Angles(math.rad(-70 * a), 0, 0)
			task.wait()
		end
		t0 = os.clock()
		sfx(CFG.SND.swing, 0.6, 0.8)
		while os.clock() - t0 < 0.1 do
			local a = (os.clock() - t0) / 0.1
			tmTool.Grip = gripBase * CFrame.Angles(math.rad(-70 + 140 * a), 0, 0)
			task.wait()
		end
		doSwingHit()
		t0 = os.clock()
		while os.clock() - t0 < 0.25 do
			local a = (os.clock() - t0) / 0.25
			tmTool.Grip = gripBase * CFrame.Angles(math.rad(70 * (1 - a)), 0, 0)
			task.wait()
		end
		tmTool.Grip = gripBase
		swinging = false
	end)
end)

------------------------------------------------------------------
-- DASH
------------------------------------------------------------------
local function dash()
	if S.over or os.clock() < S.dashReady then return end
	local h, hu = hrp(), hum()
	if not h or not hu then return end
	local dir = hu.MoveDirection
	if dir.Magnitude < 0.1 then dir = h.CFrame.LookVector end
	dir = flat(dir)
	if dir.Magnitude < 0.01 then return end
	dir = dir.Unit
	S.dashReady = os.clock() + 1.1
	S.iframeUntil = math.max(S.iframeUntil, os.clock() + 0.35)
	task.spawn(function()
		for _ = 1, 12 do
			if h.Parent then
				h.AssemblyLinearVelocity = dir * 80 + Vector3.new(0, h.AssemblyLinearVelocity.Y, 0)
			end
			task.wait()
		end
	end)
end
dashBtn.Activated:Connect(dash)
table.insert(conns, UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.Q then dash() end
end))

------------------------------------------------------------------
-- MAIN UPDATE
------------------------------------------------------------------
local function updateProjectiles(dt, now)
	for i = #projs, 1, -1 do
		local p = projs[i]
		local pos = p.part.Position + p.dir * 130 * dt
		p.part.CFrame = CFrame.lookAt(pos, pos + p.dir)
		local dead = (now - p.born) > 1.6
		for j = #falling, 1, -1 do
			if (falling[j].part.Position - pos).Magnitude < 4 then
				destroyFalling(j)
				dead = true
				break
			end
		end
		for j = #claws, 1, -1 do
			if (claws[j].part.Position - pos).Magnitude < 3 then
				claws[j].part:Destroy()
				table.remove(claws, j)
				dead = true
				break
			end
		end
		if not dead and S.treeLive then
			local dx, dz = pos.X - O.X, pos.Z - O.Z
			if dx * dx + dz * dz < 25 and pos.Y > floorY and pos.Y < floorY + 72 then
				dead = true
				onTreeHit()
			end
		end
		if dead then
			p.part:Destroy()
			table.remove(projs, i)
		end
	end
end

local function updateFalling(dt, h)
	for i = #falling, 1, -1 do
		local f = falling[i]
		f.vy -= 110 * dt
		local pos = f.part.Position + Vector3.new(0, f.vy * dt, 0)
		local tl = tileAt(pos)
		local top = (tl and tl.alive) and floorY or nil
		for _, d in ipairs(debris) do
			if d.Parent then
				local dp = d.Position
				if math.abs(dp.X - pos.X) < 4 and math.abs(dp.Z - pos.Z) < 4 then
					local t2 = dp.Y + 2
					if not top or t2 > top then top = t2 end
				end
			end
		end
		f.part.Position = pos
		f.shadow.Position = Vector3.new(pos.X, floorY + 0.12, pos.Z)
		if h and not f.hit then
			local dx, dz = h.Position.X - pos.X, h.Position.Z - pos.Z
			if dx * dx + dz * dz < 13 and math.abs(h.Position.Y - pos.Y) < 5 then
				if damagePlayer(14) then f.hit = true end
			end
		end
		if top and pos.Y - 2 <= top then
			f.part.Position = Vector3.new(pos.X, top + 2, pos.Z)
			f.part.CanCollide = true
			f.shadow:Destroy()
			table.insert(debris, f.part)
			table.remove(falling, i)
			if #debris > 36 then
				local o = table.remove(debris, 1)
				if o then o:Destroy() end
			end
		elseif pos.Y < floorY - 60 then
			destroyFalling(i)
		end
	end
end

local function updateRings(dt, h)
	for i = #rings, 1, -1 do
		local r = rings[i]
		r.R += 38 * dt
		local n = #r.segs
		local chord = 2 * r.R * math.sin(math.pi / n) * 1.08
		for k, s in ipairs(r.segs) do
			local a = (k / n) * math.pi * 2
			local pos = Vector3.new(O.X + math.cos(a) * r.R, floorY + 1.2, O.Z + math.sin(a) * r.R)
			s.Size = Vector3.new(3, 2.4, chord)
			s.CFrame = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a)))
		end
		if h and not r.hit then
			local d = flat(h.Position - O).Magnitude
			if math.abs(d - r.R) < 2.4 and h.Position.Y - floorY < 5.2 then
				if damagePlayer(12) then r.hit = true end
			end
		end
		if r.R > 125 then
			for _, s in ipairs(r.segs) do s:Destroy() end
			table.remove(rings, i)
		end
	end
end

local function updateClaws(dt, h, now)
	for i = #claws, 1, -1 do
		local c = claws[i]
		local pos = c.part.Position
		local dead = (now - c.born) > 5
		if h then
			local to = h.Position - pos
			if to.Magnitude > 0.1 then
				c.dir = (c.dir + to.Unit * 2.2 * dt).Unit
			end
			if to.Magnitude < 3.2 and damagePlayer(10) then dead = true end
		end
		local np = pos + c.dir * 34 * dt
		c.part.CFrame = CFrame.lookAt(np, np + c.dir)
		if dead then
			c.part:Destroy()
			table.remove(claws, i)
		end
	end
end

local function updateDefrag(dt, h)
	local active = dfHold and dfEquipped and not S.over
	if not active then
		dfBeam.Transparency = 1
		return
	end
	local handle = dfTool:FindFirstChild("Handle")
	local from = handle and handle.Position or h.Position
	local aim = mouse.Hit and mouse.Hit.Position or h.Position
	local target = aim
	local tl = tileAt(aim)
	if tl and tl.alive and tl.locked and (tl.part.Position - h.Position).Magnitude < 70 then
		tl.progress += dt
		target = tl.part.Position + Vector3.new(0, 0.5, 0)
	elseif (aim - h.Position).Magnitude < 12 then
		S.infection = math.max(0, S.infection - 40 * dt)
		target = h.Position
	end
	local dist = (target - from).Magnitude
	if dist < 0.2 then
		dfBeam.Transparency = 1
		return
	end
	dfBeam.Size = Vector3.new(0.3, 0.3, dist)
	dfBeam.CFrame = CFrame.lookAt((from + target) / 2, target)
	dfBeam.Transparency = 0.2
end

local function updateInfection(dt, h)
	if S.started and not S.over and S.phase <= 4 then
		local dx, dz = h.Position.X - O.X, h.Position.Z - O.Z
		if dx * dx + dz * dz < CFG.TRIGGER * CFG.TRIGGER and h.Position.Y > floorY - 10 then
			S.infection = math.min(100, S.infection + 2.4 * dt)
		else
			S.infection = math.max(0, S.infection - 4 * dt)
		end
		if S.infection >= 100 then drain(4 * dt) end
	else
		S.infection = math.max(0, S.infection - 6 * dt)
	end
end

local function updateHud(dt, now)
	S.hpDisp += (S.hp - S.hpDisp) * math.min(1, dt * 8)
	bossFill.Size = UDim2.new(math.clamp(S.hpDisp / 100, 0, 1), 0, 1, 0)
	bossText.Text = "NOSOI" .. (S.phase > 0 and ("  -  PHASE " .. S.phase) or "")
	hpFill.Size = UDim2.new(math.clamp(S.playerHP / 100, 0, 1), 0, 1, 0)
	infFill.Size = UDim2.new(math.clamp(S.infection / 100, 0, 1), 0, 1, 0)
	infOverlay.BackgroundTransparency = 1 - math.clamp(S.infection / 100, 0, 1) * 0.28
	if now < S.stallUntil then
		statusLabel.Text = "[ SCRIPT STALLED ]"
	elseif S.linked then
		statusLabel.Text = "[ LINKED - BOSS INVULNERABLE ]"
	else
		statusLabel.Text = ""
	end
	if now < S.dashReady then
		dashBtn.Text = string.format("%.1f", S.dashReady - now)
	else
		dashBtn.Text = "DASH"
	end
end

local function onVoid()
	if S.phase == 5 and S.linked then
		breakLink()
	else
		damagePlayer(10, true)
		if not S.over then
			teleport(safeSpot())
			S.iframeUntil = math.max(S.iframeUntil, os.clock() + 1)
		end
	end
end

table.insert(conns, RunService.Heartbeat:Connect(function(dt)
	if not arena then return end
	local h = hrp()
	if not h then return end
	local now = os.clock()

	if not S.triggered and not S.over then
		if flat(h.Position - O).Magnitude <= CFG.TRIGGER then trigger(S.run) end
	end

	updateProjectiles(dt, now)
	updateFalling(dt, h)
	updateRings(dt, h)
	updateClaws(dt, h, now)
	updateDefrag(dt, h)
	updateInfection(dt, h)

	if cmdHold and cmdEquipped and not S.over and now >= cmdNext then
		cmdNext = now + 0.11
		fireCmd(h)
	end

	-- node flicker
	for _, n in ipairs(nodes) do
		if n.part.Parent then
			n.part.Color = (math.sin(now * 30) > 0) and Color3.fromRGB(255, 0, 200) or Color3.fromRGB(0, 255, 255)
		end
	end

	-- life-link
	if S.linked and S.beam and S.beam.Parent then
		local dist = (h.Position - trunk.Position).Magnitude
		local c = math.clamp(dist / 5, 0, 14) * math.sin(now * 3)
		S.beam.CurveSize0 = c
		S.beam.CurveSize1 = -c
		drain(3.2 * dt)
		S.hp = math.min(20, S.hp + 3 * dt)
	elseif not S.over and S.playerHP < 100 and S.infection < 100 then
		S.playerHP = math.min(100, S.playerHP + 0.7 * dt)
	end

	-- void
	if S.triggered and not S.over and h.Position.Y < floorY - 28 then onVoid() end

	updateHud(dt, now)
end))

------------------------------------------------------------------
-- RUN START / CLEANUP
------------------------------------------------------------------
startRun = function()
	S.run += 1
	local id = S.run
	closePopups()
	if arena then arena:Destroy() end
	arena = new("Folder", { Name = "NosoiArena" }, workspace)
	fx = new("Folder", { Name = "FX" }, arena)
	tiles, nodes, roots, falling, debris, rings, claws, projs, popups = {}, {}, {}, {}, {}, {}, {}, {}, {}
	S.phase, S.hp, S.hpDisp = 0, 100, 100
	S.started, S.triggered, S.busy, S.over, S.linked = false, false, false, false, false
	S.stallUntil, S.pending, S.playerHP, S.infection = 0, 0, 100, 0
	S.iframeUntil, S.dashReady, S.sweeping, S.despawning = 0, 0, false, 0
	S.timersReset, S.treeLive, S.coreHP, S.core = true, false, 3, nil
	if S.beam then S.beam:Destroy() S.beam = nil end
	bossFrame.Visible = false
	skyMode("blue", 0.05)
	buildArena()
	buildTree()
	local h = hrp()
	if h then
		local from = O + Vector3.new(0, 5, -CFG.SPAWN_DIST)
		h.AssemblyLinearVelocity = Vector3.zero
		h.CFrame = CFrame.lookAt(from, O + Vector3.new(0, 5, 0))
	end
	showMsg("Walk toward the tree...", 4)
	task.spawn(beatLoop, id)
	task.spawn(scheduler, id)
	task.spawn(nodeLoop, id)
end

local function cleanup()
	S.run += 1
	S.over = true
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	for _, o in ipairs({ arena, gui, noyGui, cmdTool, tmTool, dfTool, dfBeam, mySky, myAtmo, myCC }) do
		pcall(function() o:Destroy() end)
	end
	for _, p in ipairs(lightProps) do pcall(function() Lighting[p] = savedLight[p] end) end
	for _, c in ipairs(removedFx) do pcall(function() c.Parent = Lighting end) end
	local hu = hum()
	if hu then hu.CameraOffset = Vector3.zero end
	local h = hrp()
	if h and origCF then h.CFrame = origCF end
	_G.NosoiCleanup = nil
end
_G.NosoiCleanup = cleanup

local h0 = hrp() or (player.Character or player.CharacterAdded:Wait()):WaitForChild("HumanoidRootPart")
origCF = h0.CFrame
startRun()

