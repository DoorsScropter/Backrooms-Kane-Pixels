-- CONSOLE_ROOT BOSS FIGHT | Client-side LocalScript (Delta / Free Admin game)
-- Phase 1 Calm -> Phase 2 Enraged -> Phase 3 Maniac

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local plr = Players.LocalPlayer
local cam = workspace.CurrentCamera
local env = (getgenv and getgenv()) or _G

-- re-execute = clean restart
if env.CR_CLEANUP then pcall(env.CR_CLEANUP) end

local CFG = {
	PhaseHP = 100,
	PropHit = 15,            -- damage to boss from thrown-back prop
	SwordHit = 25,           -- damage to clone per slash (4 hits)
	CatchChance = 0.7,
	PropDamage = {6, 10, 15},        -- damage to you per phase
	PropSpeed = {55, 70, 90},
	PropRate = {2.2, 1.4, 0.9},      -- seconds between throws
	CmdRate = {9, 6, 3.5},           -- seconds between boss commands
	CloneSpeed = 15,
	CloneCap = 8,
	CloneSpawnRate = 6,
	RainbowParts = 40,
}

local PHASE_COL = {
	Color3.fromRGB(0, 255, 80),
	Color3.fromRGB(255, 150, 0),
	Color3.fromRGB(255, 0, 60),
}

local S = {phase = 1, hp = CFG.PhaseHP, over = false, ready = false, trans = false,
	shake = 0, bossPos = Vector3.zero, tProp = 0, tCmd = 3, tClone = 0}
local conns, props, clones, rainbow = {}, {}, {}, {}

local function bind(sig, f)
	local c = sig:Connect(f)
	table.insert(conns, c)
	return c
end

local function root()
	local c = plr.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end
local function hum()
	local c = plr.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

local origBright, origGrav = Lighting.Brightness, workspace.Gravity
local origWS = (hum() and hum().WalkSpeed) or 16

local FX = Instance.new("Folder")
FX.Name = "CR_FX"
FX.Parent = workspace

local function mk(p)
	local part = Instance.new("Part")
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in pairs(p) do part[k] = v end
	return part
end

local function boom(pos, size)
	size = size or 8
	local e = Instance.new("Explosion")
	e.Position, e.BlastPressure, e.BlastRadius = pos, 0, size
	e.DestroyJointRadiusPercent = 0
	e.ExplosionType = Enum.ExplosionType.NoCraters
	e.Parent = workspace
	local ring = mk({Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), Material = Enum.Material.Neon,
		Color = PHASE_COL[S.phase], Transparency = 0.2, CFrame = CFrame.new(pos)})
	ring.Parent = FX
	TweenService:Create(ring, TweenInfo.new(0.5), {Size = Vector3.new(size, size, size) * 1.6, Transparency = 1}):Play()
	Debris:AddItem(ring, 0.6)
end

---------------------------------------------------------------- UI
local guiParent = (gethui and gethui()) or plr:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "CONSOLE_ROOT_UI", false, true, 999
gui.Parent = guiParent

-- CRT terminal banner
local term = Instance.new("Frame")
term.Size, term.Position = UDim2.new(0.62, 0, 0, 48), UDim2.new(0.19, 0, 0, 16)
term.BackgroundColor3, term.BackgroundTransparency, term.Visible = Color3.new(0, 0.04, 0), 0.08, false
term.Parent = gui
local ts = Instance.new("UIStroke")
ts.Color, ts.Thickness = Color3.fromRGB(0, 255, 70), 2
ts.Parent = term
local termLabel = Instance.new("TextLabel")
termLabel.Size, termLabel.Position = UDim2.new(1, -16, 1, 0), UDim2.new(0, 8, 0, 0)
termLabel.BackgroundTransparency = 1
termLabel.Font, termLabel.TextSize = Enum.Font.Code, 18
termLabel.TextColor3 = Color3.fromRGB(0, 255, 70)
termLabel.TextXAlignment = Enum.TextXAlignment.Left
termLabel.TextWrapped = true
termLabel.ZIndex = 2
termLabel.Parent = term
for i = 0, 23 do
	local ln = Instance.new("Frame")
	ln.Size, ln.Position = UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 0, i * 2)
	ln.BackgroundColor3, ln.BackgroundTransparency, ln.BorderSizePixel, ln.ZIndex = Color3.new(0, 0, 0), 0.8, 0, 3
	ln.Parent = term
end

local termToken = 0
local function cmd(text)
	termToken += 1
	local t = termToken
	term.Visible = true
	termLabel.Text = "root@console:~# " .. text
	task.spawn(function()
		for i = 1, 4 do
			if t ~= termToken then return end
			termLabel.TextTransparency = (i % 2 == 1) and 0.6 or 0
			task.wait(0.04)
		end
		termLabel.TextTransparency = 0
		task.wait(2.6)
		if t == termToken then term.Visible = false end
	end)
end

-- boss health bar
local barBack = Instance.new("Frame")
barBack.Size, barBack.Position = UDim2.new(0.5, 0, 0, 22), UDim2.new(0.25, 0, 1, -50)
barBack.BackgroundColor3, barBack.BorderSizePixel = Color3.fromRGB(15, 15, 15), 0
barBack.Parent = gui
local bs = Instance.new("UIStroke")
bs.Color, bs.Thickness = Color3.new(1, 1, 1), 2
bs.Parent = barBack
local fill = Instance.new("Frame")
fill.Size, fill.BackgroundColor3, fill.BorderSizePixel = UDim2.new(1, 0, 1, 0), PHASE_COL[1], 0
fill.Parent = barBack
local barLabel = Instance.new("TextLabel")
barLabel.Size, barLabel.Position = UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 0, -22)
barLabel.BackgroundTransparency, barLabel.Font, barLabel.TextSize = 1, Enum.Font.Code, 16
barLabel.TextColor3 = Color3.new(1, 1, 1)
barLabel.Parent = barBack

local function refreshBar()
	barLabel.Text = ("CONSOLE_ROOT // PHASE %d/3 // %d HP"):format(S.phase, math.max(0, math.ceil(S.hp)))
	fill.BackgroundColor3 = PHASE_COL[S.phase]
	TweenService:Create(fill, TweenInfo.new(0.15), {Size = UDim2.new(math.max(0, S.hp) / CFG.PhaseHP, 0, 1, 0)}):Play()
end
refreshBar()

-- screen flash
local overlay = Instance.new("Frame")
overlay.Size, overlay.BackgroundColor3, overlay.BackgroundTransparency, overlay.BorderSizePixel =
	UDim2.new(1, 0, 1, 0), Color3.new(1, 1, 1), 1, 0
overlay.ZIndex = 50
overlay.Parent = gui
local function flash(a, col)
	overlay.BackgroundColor3 = col or Color3.new(1, 1, 1)
	overlay.BackgroundTransparency = 1 - (a or 0.8)
	TweenService:Create(overlay, TweenInfo.new(0.6), {BackgroundTransparency = 1}):Play()
end

-- dialogue
local dlg = Instance.new("TextLabel")
dlg.Size, dlg.Position = UDim2.new(0.8, 0, 0, 60), UDim2.new(0.1, 0, 0.72, 0)
dlg.BackgroundTransparency, dlg.Font, dlg.TextSize = 1, Enum.Font.Code, 28
dlg.TextColor3, dlg.TextStrokeTransparency = Color3.fromRGB(255, 40, 40), 0
dlg.TextWrapped, dlg.ZIndex, dlg.Text = true, 20, ""
dlg.Parent = gui
local dlgToken = 0
local function say(text, hold)
	dlgToken += 1
	local t = dlgToken
	for i = 1, #text do
		if t ~= dlgToken or S.over and text == "" then return end
		dlg.Text = text:sub(1, i)
		task.wait(0.025)
	end
	task.wait(hold or 1.5)
	if t == dlgToken then dlg.Text = "" end
end

-- colour grading per phase
local cc = Instance.new("ColorCorrectionEffect")
cc.Parent = Lighting
local function grade(phase)
	local goal = ({
		{TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0},
		{TintColor = Color3.fromRGB(255, 190, 170), Saturation = 0.3, Contrast = 0.15},
		{TintColor = Color3.fromRGB(255, 120, 150), Saturation = -0.5, Contrast = 0.3},
	})[phase]
	TweenService:Create(cc, TweenInfo.new(1.5), goal):Play()
end

---------------------------------------------------------------- BOSS
local boss = Instance.new("Model")
boss.Name = "CONSOLE_ROOT"
local core = mk({Size = Vector3.new(7, 7, 7), Material = Enum.Material.Neon, Color = PHASE_COL[1]})
core.Parent = boss
local eye = mk({Size = Vector3.new(4, 1, 1), Material = Enum.Material.Neon, Color = Color3.new(1, 1, 1)})
eye.Parent = boss
boss.PrimaryPart = core
boss.Parent = FX

do
	local r = root()
	S.bossPos = r and (r.Position + r.CFrame.LookVector * 45 + Vector3.new(0, 14, 0)) or Vector3.new(0, 30, 0)
end

local function hitBoss(n)
	if S.over or S.trans or not S.ready then return end
	S.hp -= n
	S.shake = math.max(S.shake, 0.8)
	boom(S.bossPos, 8)
	core.Color = Color3.new(1, 1, 1)
	task.delay(0.1, function() if core.Parent then core.Color = PHASE_COL[S.phase] end end)
	if S.hp <= 0 then
		S.hp = 0
		refreshBar()
		S.hitDone = true
	else
		refreshBar()
	end
end

---------------------------------------------------------------- PROPS
local function givePropTool()
	local t = Instance.new("Tool")
	t.Name, t.RequiresHandle, t.CanBeDropped = "Prop", true, false
	local h = Instance.new("Part")
	h.Name, h.Shape, h.Size, h.Material, h.Color = "Handle", Enum.PartType.Ball, Vector3.new(2, 2, 2), Enum.Material.Neon, PHASE_COL[S.phase]
	h.CanCollide = false
	h.Parent = t
	t.Activated:Connect(function()
		local r = root()
		if not r or S.over then return end
		t:Destroy()
		local p = mk({Shape = Enum.PartType.Ball, Size = Vector3.new(2.5, 2.5, 2.5), Material = Enum.Material.Neon,
			Color = Color3.new(1, 1, 1), CFrame = r.CFrame * CFrame.new(0, 1, -3)})
		p.Parent = FX
		table.insert(props, {p = p, t = 0, friendly = true})
	end)
	t.Parent = plr:WaitForChild("Backpack")
end

local function spawnProp()
	local r = root()
	if not r or S.over then return end
	local p = mk({Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), Material = Enum.Material.Neon,
		Color = PHASE_COL[S.phase], CFrame = CFrame.new(S.bossPos)})
	p.Parent = FX
	local aim = r.Position + r.AssemblyLinearVelocity * 0.35
	table.insert(props, {p = p, t = 0, friendly = false, dir = (aim - S.bossPos).Unit, speed = CFG.PropSpeed[S.phase]})
end

local function propTouched(o)
	local h = hum()
	if not h then return end
	if math.random() < CFG.CatchChance then
		givePropTool()
		cmd("catch(prop) -> OK  [added to inventory]")
	else
		local dmg = CFG.PropDamage[S.phase]
		h:TakeDamage(dmg)
		boom(o.p.Position, 6)
		S.shake = math.max(S.shake, 1.4)
		flash(0.35, Color3.fromRGB(255, 0, 0))
		cmd(("segfault: prop collision  -%d HP"):format(dmg))
	end
end

---------------------------------------------------------------- PHASE 2: RAINBOW MAP
local function isChar(d)
	local m = d
	repeat
		m = m:FindFirstAncestorOfClass("Model")
		if m and m:FindFirstChildOfClass("Humanoid") then return true end
	until not m
	return false
end

local function startRainbow()
	local r = root()
	local cands = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and not d:IsA("Terrain") and d.Size.Magnitude > 2
			and not d:IsDescendantOf(FX) and not isChar(d)
			and (not r or (d.Position - r.Position).Magnitude < 220) then
			table.insert(cands, d)
		end
	end
	for i = #cands, 2, -1 do
		local j = math.random(i)
		cands[i], cands[j] = cands[j], cands[i]
	end
	for i = 1, math.min(CFG.RainbowParts, #cands) do
		local p = cands[i]
		pcall(function()
			table.insert(rainbow, {p = p, c = p.Color, m = p.Material, cf = p.CFrame, a = p.Anchored})
			p.Anchored = true
			p.Material = Enum.Material.Neon
		end)
	end
end

local function stopRainbow()
	for _, o in ipairs(rainbow) do
		pcall(function()
			o.p.Color, o.p.Material, o.p.CFrame, o.p.Anchored = o.c, o.m, o.cf, o.a
		end)
	end
	table.clear(rainbow)
end

---------------------------------------------------------------- PHASE 3: SWORD + CLONES
local function damageClone(c, n)
	c.hp -= n
	local hl = c.m:FindFirstChildOfClass("Highlight")
	if hl then
		hl.OutlineColor = Color3.new(1, 1, 1)
		task.delay(0.12, function() if hl.Parent then hl.OutlineColor = Color3.fromRGB(170, 0, 255) end end)
	end
	if c.hp <= 0 then
		boom(c.root.Position, 7)
		c.m:Destroy()
		table.remove(clones, table.find(clones, c))
		S.shake = math.max(S.shake, 0.6)
		cmd("kill -9 clone_" .. math.random(100, 999))
	end
end

local function giveSword()
	local t = Instance.new("Tool")
	t.Name, t.CanBeDropped, t.RequiresHandle = "SystemSword", false, true
	t.GripPos = Vector3.new(0, 0, -1.5)
	t.GripForward, t.GripRight, t.GripUp = Vector3.new(-1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1)
	local h = Instance.new("Part")
	h.Name, h.Size, h.Material, h.Color, h.CanCollide = "Handle", Vector3.new(1, 0.8, 4), Enum.Material.Neon, Color3.fromRGB(0, 255, 255), false
	h.Parent = t
	local cd = false
	t.Activated:Connect(function()
		if cd or S.over then return end
		cd = true
		local anim = Instance.new("StringValue")
		anim.Name, anim.Value = "toolanim", "Slash"
		anim.Parent = t
		local r = root()
		if r then
			for i = #clones, 1, -1 do
				local c = clones[i]
				if c and c.root and c.root.Parent then
					local off = c.root.Position - r.Position
					if off.Magnitude < 9 and off.Unit:Dot(r.CFrame.LookVector) > -0.1 then
						damageClone(c, CFG.SwordHit)
					end
				end
			end
		end
		task.delay(0.45, function() cd = false end)
	end)
	t.Parent = plr:WaitForChild("Backpack")
end

local function spawnClone()
	local ch, r = plr.Character, root()
	if not ch or not r or #clones >= CFG.CloneCap or S.over then return end
	ch.Archivable = true
	local m = ch:Clone()
	if not m then return end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Tool") or d:IsA("Shirt") or d:IsA("Pants")
			or d:IsA("ShirtGraphic") or d:IsA("Decal") or d:IsA("Sound") then
			d:Destroy()
		end
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Color, d.Material, d.Anchored = Color3.new(0, 0, 0), Enum.Material.Neon, false
			if d:IsA("MeshPart") then d.TextureID = "" end
		elseif d:IsA("SpecialMesh") then
			d.TextureId = ""
		end
	end
	m.Name = "CR_CLONE"
	local h = m:FindFirstChildOfClass("Humanoid")
	local cr = m:FindFirstChild("HumanoidRootPart")
	if not h or not cr then m:Destroy() return end
	h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	h.WalkSpeed = CFG.CloneSpeed
	local hl = Instance.new("Highlight")
	hl.FillColor, hl.OutlineColor, hl.FillTransparency = Color3.new(0, 0, 0), Color3.fromRGB(170, 0, 255), 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = m
	local ang = math.random() * math.pi * 2
	m:PivotTo(CFrame.new(r.Position + Vector3.new(math.cos(ang) * 40, 3, math.sin(ang) * 40)))
	m.Parent = FX
	boom(cr.Position, 5)
	table.insert(clones, {m = m, root = cr, hum = h, hp = 100, hitcd = 0, nt = 0})
end

---------------------------------------------------------------- BOSS COMMANDS
local CMDS = {
	{1, ";shake all 5", function() S.shake = 3 end},
	{1, ";flash all", function() flash(0.9) end},
	{2, ";blackout", function()
		Lighting.Brightness = 0
		task.delay(2.5, function() if not S.over then Lighting.Brightness = origBright end end)
	end},
	{2, ";gravity me 40", function()
		workspace.Gravity = 40
		task.delay(4, function() workspace.Gravity = origGrav end)
	end},
	{3, ";speed me 6", function()
		local h = hum()
		if h then
			h.WalkSpeed = 6
			task.delay(3, function() local hh = hum() if hh and not S.over then hh.WalkSpeed = origWS end end)
		end
	end},
	{3, ";sit me", function() local h = hum() if h then h.Sit = true end end},
}

local function runCommand()
	local pool = {}
	for _, c in ipairs(CMDS) do
		if c[1] <= S.phase then table.insert(pool, c) end
	end
	local c = pool[math.random(#pool)]
	cmd(c[2])
	pcall(c[3])
end

---------------------------------------------------------------- FLOW
local cleanup

local function nextPhase()
	S.trans = true
	S.phase += 1
	S.hp = CFG.PhaseHP
	S.hitDone = false
	flash(1)
	S.shake = 4
	boom(S.bossPos, 16)
	core.Color = PHASE_COL[S.phase]
	grade(S.phase)
	refreshBar()
	cmd("sudo escalate --phase " .. S.phase)
	if S.phase == 2 then
		startRainbow()
		task.spawn(say, "YOU SHOULDN'T HAVE CAUGHT THAT.", 1.5)
	else
		giveSword()
		task.spawn(say, "FINE. I WILL RUN YOU DOWN MYSELF.", 1.5)
	end
	task.delay(2, function() S.trans = false end)
end

local function win()
	S.over = true
	for _, o in ipairs(props) do o.p:Destroy() end
	table.clear(props)
	for _, c in ipairs(clones) do c.m:Destroy() end
	table.clear(clones)
	task.spawn(function()
		for i = 1, 6 do
			boom(S.bossPos + Vector3.new(math.random(-5, 5), math.random(-4, 4), math.random(-5, 5)), 12)
			S.shake = 3
			task.wait(0.25)
		end
		flash(1)
		for _, p in ipairs(boss:GetChildren()) do p.Transparency = 1 end
		cmd("rm -rf CONSOLE_ROOT  ... DONE")
		say("ROOT ACCESS REVOKED.", 2.5)
		task.wait(1)
		cleanup()
	end)
end

local function intro()
	local h, r = hum(), root()
	if h then h.WalkSpeed = 0 end
	cam.CameraType = Enum.CameraType.Scriptable
	local barTop, barBot = Instance.new("Frame"), Instance.new("Frame")
	for _, b in ipairs({barTop, barBot}) do
		b.BackgroundColor3, b.BorderSizePixel, b.ZIndex = Color3.new(0, 0, 0), 0, 30
		b.Parent = gui
	end
	barTop.Size, barTop.Position = UDim2.new(1, 0, 0, 0), UDim2.new(0, 0, 0, 0)
	barBot.Size, barBot.Position = UDim2.new(1, 0, 0, 0), UDim2.new(0, 0, 1, 0)
	TweenService:Create(barTop, TweenInfo.new(0.8), {Size = UDim2.new(1, 0, 0.12, 0)}):Play()
	TweenService:Create(barBot, TweenInfo.new(0.8), {Size = UDim2.new(1, 0, 0.12, 0), Position = UDim2.new(0, 0, 0.88, 0)}):Play()
	if r then
		local toward = (r.Position - S.bossPos).Unit
		local goal = CFrame.lookAt(S.bossPos + toward * 22 + Vector3.new(0, 4, 0), S.bossPos)
		TweenService:Create(cam, TweenInfo.new(2.5, Enum.EasingStyle.Sine), {CFrame = goal}):Play()
	end
	cmd("./console_root --boot")
	say("SYSTEM BREACH DETECTED...", 0.8)
	S.shake = 2
	say("I AM CONSOLE_ROOT. I RUN THIS PLACE.", 0.9)
	say("YOUR ADMIN PANEL WON'T SAVE YOU.", 0.9)
	say("CATCH WHAT I THROW. THROW IT BACK.", 1)
	cam.CameraType = Enum.CameraType.Custom
	TweenService:Create(barTop, TweenInfo.new(0.6), {Size = UDim2.new(1, 0, 0, 0)}):Play()
	TweenService:Create(barBot, TweenInfo.new(0.6), {Size = UDim2.new(1, 0, 0, 0), Position = UDim2.new(0, 0, 1, 0)}):Play()
	Debris:AddItem(barTop, 0.7)
	Debris:AddItem(barBot, 0.7)
	h = hum()
	if h then h.WalkSpeed = origWS end
	S.ready = true
	cmd("fight.start()  // catch props, throw them back")
end

cleanup = function()
	S.over = true
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	stopRainbow()
	Lighting.Brightness = origBright
	workspace.Gravity = origGrav
	local h = hum()
	if h then h.CameraOffset = Vector3.zero h.WalkSpeed = origWS end
	cam.CameraType = Enum.CameraType.Custom
	pcall(function() gui:Destroy() end)
	pcall(function() FX:Destroy() end)
	pcall(function() cc:Destroy() end)
	for _, holder in ipairs({plr:FindFirstChild("Backpack"), plr.Character}) do
		if holder then
			for _, n in ipairs({"Prop", "SystemSword"}) do
				local t = holder:FindFirstChild(n)
				if t then t:Destroy() end
			end
		end
	end
	env.CR_CLEANUP = nil
end
env.CR_CLEANUP = cleanup

---------------------------------------------------------------- MAIN LOOPS
bind(RunService.Heartbeat, function(dt)
	if S.over then return end
	local r = root()
	if not r then return end

	-- boss hover / orbit
	local a = tick() * 0.4
	local target = r.Position + Vector3.new(math.cos(a) * 45, 14 + math.sin(tick()) * 2, math.sin(a) * 45)
	S.bossPos = S.bossPos:Lerp(target, math.min(1, dt * 1.5))
	core.CFrame = CFrame.lookAt(S.bossPos, r.Position)
	eye.CFrame = core.CFrame * CFrame.new(0, 0.5, -3.6)

	-- phase advance check
	if S.hitDone and S.ready and not S.trans then
		S.hitDone = false
		if S.phase < 3 then nextPhase() else win() return end
	end

	-- props
	for i = #props, 1, -1 do
		local o = props[i]
		local p = o.p
		o.t += dt
		local remove = false
		if o.friendly then
			local dir = (S.bossPos - p.Position)
			p.CFrame = p.CFrame + dir.Unit * 100 * dt
			if dir.Magnitude < 6 then
				hitBoss(CFG.PropHit)
				remove = true
			end
		else
			p.CFrame = p.CFrame * CFrame.Angles(dt * 4, dt * 3, 0) + o.dir * o.speed * dt
			if (p.Position - r.Position).Magnitude < 4 then
				propTouched(o)
				remove = true
			end
		end
		if remove or o.t > 6 then
			p:Destroy()
			table.remove(props, i)
		end
	end

	-- rainbow spin
	if S.phase >= 2 then
		local t = tick()
		for i, o in ipairs(rainbow) do
			pcall(function()
				o.p.Color = Color3.fromHSV((t * 0.6 + i * 0.08) % 1, 1, 1)
				o.p.CFrame = o.p.CFrame * CFrame.Angles(0, dt * (1.5 + (i % 3)), 0)
			end)
		end
	end

	-- clones hunt
	for i = #clones, 1, -1 do
		local c = clones[i]
		if not c.root.Parent or c.root.Position.Y < r.Position.Y - 120 then
			c.m:Destroy()
			table.remove(clones, i)
		else
			c.nt += dt
			if c.nt > 0.15 then
				c.nt = 0
				c.hum:MoveTo(r.Position)
				if r.Position.Y - c.root.Position.Y > 4 then c.hum.Jump = true end
			end
			if (c.root.Position - r.Position).Magnitude < 4.5 and tick() > c.hitcd then
				c.hitcd = tick() + 1
				local h = hum()
				if h then h:TakeDamage(8) end
				S.shake = math.max(S.shake, 0.9)
			end
		end
	end

	-- timers
	if S.ready and not S.trans then
		S.tProp -= dt
		S.tCmd -= dt
		if S.tProp <= 0 then
			S.tProp = CFG.PropRate[S.phase]
			spawnProp()
		end
		if S.tCmd <= 0 then
			S.tCmd = CFG.CmdRate[S.phase]
			runCommand()
		end
		if S.phase == 3 then
			S.tClone -= dt
			if S.tClone <= 0 then
				S.tClone = CFG.CloneSpawnRate
				spawnClone()
			end
		end
	end
end)

-- smooth camera shake
bind(RunService.RenderStepped, function(dt)
	local h = hum()
	if not h then return end
	if S.shake > 0.02 then
		local t = tick() * 35
		h.CameraOffset = Vector3.new(math.noise(t, 0, 0), math.noise(0, t, 0), 0) * S.shake * 0.6
		S.shake = math.max(0, S.shake - dt * 2.2)
	elseif h.CameraOffset.Magnitude > 0 then
		h.CameraOffset = Vector3.zero
	end
end)

-- player death ends the fight
do
	local h = hum()
	if h then
		bind(h.Died, function()
			if S.over then return end
			S.over = true
			cmd("fatal: player process terminated")
			task.spawn(function()
				say("TERMINATED.", 2)
				cleanup()
			end)
		end)
	end
end

task.spawn(function()
	grade(1)
	intro()
end)
