-- ============================================================
--  BACKROOMS - Client-side LocalScript (Delta / Executor)
--  Paste into a LocalScript and execute.
-- ============================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")
local TweenService     = game:GetService("TweenService")
local InsertService    = game:GetService("InsertService")
local Debris           = game:GetService("Debris")
local Workspace        = game:GetService("Workspace")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera    = Workspace.CurrentCamera
local char      = player.Character or player.CharacterAdded:Wait()
local humanoid  = char:WaitForChild("Humanoid")
local rootPart  = char:WaitForChild("HumanoidRootPart")

-- ============================================================
--  CONFIG
-- ============================================================
local CFG = {
    NoclipChancePerSecond  = 0.10,
    NoclipChanceWall       = 0.50,
    PoolRoomsChance        = 0.20,
    HabitableChance        = 0.05,
    BigRoomChance          = 0.10,
    ChunkSize              = 120,
    CellSize               = 20,
    WallHeight             = 12,
    RenderDistance         = 3,      -- chunks in each direction
    LightFlickerEvery      = {20, 45},
    BlackoutDuration       = 20,
}

local SOUNDS = {
    Noclip            = "rbxassetid://139682612041479",
    BackroomsAmbient  = "rbxassetid://137406302438919",
    BackroomsStep     = "rbxassetid://89575970505811",
    PoolRoomsStep     = "rbxassetid://96516907071037",
    PoolRoomsAmbient  = "rbxassetid://94241101968368",
    DoorOpen          = "rbxassetid://125209584906878",
    Flashlight        = "rbxassetid://128570293170805",
    Blackout          = "rbxassetid://78704114462031",
}

local MODEL_IDS = {
    Chair         = 74698525718385,
    Door          = 9343670755,
    HabitableDoor = 10225195309,
}

-- ============================================================
--  STATE
-- ============================================================
local State = {
    inBackrooms   = false,
    inPoolRooms   = false,
    inHabitable   = false,
    transitioning = false,
    flashOn       = false,
    generatedChunks = {},
    pooledModels  = {},
    lights        = {},
    doors         = {},
    originalLighting = {
        Brightness = Lighting.Brightness,
        Ambient    = Lighting.Ambient,
        FogEnd     = Lighting.FogEnd,
        FogStart   = Lighting.FogStart,
        ClockTime  = Lighting.ClockTime,
    },
}

-- ============================================================
--  UTIL
-- ============================================================
local function rng(a, b)
    return math.random() * (b - a) + a
end

local function chance(p)
    return math.random() < p
end

local function playSound(id, parent, vol, looped)
    local s = Instance.new("Sound")
    s.SoundId = id
    s.Volume  = vol or 1
    s.Looped  = looped or false
    s.Parent  = parent or Workspace
    s:Play()
    return s
end

local function yieldLoad(id)
    local ok, model = pcall(function()
        return InsertService:LoadAsset(id)
    end)
    if ok and model then
        return model
    end
    return nil
end

-- ============================================================
--  PLAYER SPAWN GUARD
-- ============================================================
player.CharacterAdded:Connect(function(c)
    char     = c
    humanoid = c:WaitForChild("Humanoid")
    rootPart = c:WaitForChild("HumanoidRootPart")
end)

-- ============================================================
--  UI  (black screen, VHS overlay, pixel text, HUD)
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BackroomsUI"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- VHS / Black overlay
local overlay = Instance.new("Frame")
overlay.Name = "VHSOverlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.ZIndex = 100
overlay.Visible = false
overlay.Parent = screenGui

-- Scanline effect
local scan = Instance.new("Frame")
scan.Size = UDim2.fromScale(1, 0.02)
scan.BackgroundColor3 = Color3.new(1, 1, 1)
scan.BackgroundTransparency = 0.85
scan.BorderSizePixel = 0
scan.ZIndex = 101
scan.Parent = overlay

-- Grain container
local grainHolder = Instance.new("Frame")
grainHolder.Size = UDim2.fromScale(1, 1)
grainHolder.BackgroundTransparency = 1
grainHolder.ZIndex = 101
grainHolder.ClipsDescendants = true
grainHolder.Parent = overlay

local grainDots = {}
for i = 1, 40 do
    local d = Instance.new("Frame")
    d.Size = UDim2.fromOffset(math.random(1,3), math.random(1,3))
    d.Position = UDim2.fromScale(math.random(), math.random())
    d.BackgroundColor3 = Color3.new(1,1,1)
    d.BackgroundTransparency = math.random(60, 95)/100
    d.BorderSizePixel = 0
    d.ZIndex = 101
    d.Parent = grainHolder
    grainDots[#grainDots+1] = d
end

-- Distortion bar
local distort = Instance.new("Frame")
distort.Size = UDim2.fromScale(1, 0.06)
distort.BackgroundColor3 = Color3.new(1,1,1)
distort.BackgroundTransparency = 0.9
distort.BorderSizePixel = 0
distort.ZIndex = 101
distort.Parent = overlay

-- Pixel text label (BACKROOMS / Produced By Hecker / area names)
local pixelText = Instance.new("TextLabel")
pixelText.BackgroundTransparency = 1
pixelText.Size = UDim2.fromScale(1, 0.12)
pixelText.Position = UDim2.fromScale(0, 0.42)
pixelText.Font = Enum.Font.Arcade
pixelText.TextScaled = true
pixelText.TextColor3 = Color3.new(1,1,1)
pixelText.TextTransparency = 1
pixelText.Text = ""
pixelText.ZIndex = 102
pixelText.Parent = overlay

local subText = Instance.new("TextLabel")
subText.BackgroundTransparency = 1
subText.Size = UDim2.fromScale(1, 0.06)
subText.Position = UDim2.fromScale(0, 0.54)
subText.Font = Enum.Font.Arcade
subText.TextScaled = true
subText.TextColor3 = Color3.new(1,1,1)
subText.TextTransparency = 1
subText.Text = ""
subText.ZIndex = 102
subText.Parent = overlay

-- Toast HUD (for "Backrooms Has Been Loaded. Goodluck Wanderer", area names)
local toast = Instance.new("TextLabel")
toast.BackgroundTransparency = 1
toast.Size = UDim2.fromScale(1, 0.08)
toast.Position = UDim2.new(0, 0, 1, -80)
toast.Font = Enum.Font.Arcade
toast.TextScaled = true
toast.TextColor3 = Color3.new(1,1,1)
toast.TextStrokeTransparency = 0
toast.TextTransparency = 1
toast.Text = ""
toast.ZIndex = 103
toast.Parent = screenGui

-- ============================================================
--  VHS EFFECT LOOP
-- ============================================================
local vhsActive = false

task.spawn(function()
    while true do
        local dt = task.wait(0.05)
        if vhsActive then
            -- scanline moves down
            local y = (scan.Position.Y.Scale + 0.06) % 1.2 - 0.1
            scan.Position = UDim2.fromScale(0, y)
            -- distortion bar
            distort.Position = UDim2.fromScale(0, math.random()*1)
            distort.BackgroundTransparency = math.random(85, 98)/100
            -- grain
            for _, d in ipairs(grainDots) do
                if math.random() < 0.4 then
                    d.Position = UDim2.fromScale(math.random(), math.random())
                    d.BackgroundTransparency = math.random(60, 95)/100
                end
            end
            -- subtle camera shake
            if camera then
                camera.CFrame = camera.CFrame * CFrame.new(
                    rng(-0.08, 0.08),
                    rng(-0.08, 0.08),
                    0
                )
            end
        end
    end
end)

-- ============================================================
--  UI HELPERS
-- ============================================================
local function fadeOverlay(alpha, time)
    overlay.Visible = true
    local t = TweenService:Create(overlay, TweenInfo.new(time), {BackgroundTransparency = alpha})
    t:Play()
    return t
end

local function showText(label, text, time, posY)
    label.Text = text
    if posY then label.Position = UDim2.fromScale(0, posY) end
    TweenService:Create(label, TweenInfo.new(time), {TextTransparency = 0}):Play()
end

local function hideText(label, time)
    TweenService:Create(label, TweenInfo.new(time), {TextTransparency = 1}):Play()
end

local function slideToast(text, duration)
    toast.Text = text
    toast.Position = UDim2.new(0, 0, 1, 40)
    toast.TextTransparency = 1
    local inT = TweenService:Create(toast, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {Position = UDim2.new(0, 0, 1, -80), TextTransparency = 0})
    inT:Play()
    task.delay(duration or 4, function()
        local outT = TweenService:Create(toast, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
            {Position = UDim2.new(0, 0, 1, 40), TextTransparency = 1})
        outT:Play()
    end)
end

-- ============================================================
--  LIGHTING PRESETS
-- ============================================================
local function applyBackroomsLighting()
    Lighting.Brightness = 1.2
    Lighting.Ambient    = Color3.fromRGB(70, 65, 40)
    Lighting.OutdoorAmbient = Color3.fromRGB(50, 45, 30)
    Lighting.ClockTime  = 0
    Lighting.FogColor   = Color3.fromRGB(120, 110, 70)
    Lighting.FogStart   = 20
    Lighting.FogEnd     = 220
    Lighting.GlobalShadows = true
    Lighting.EnvironmentDiffuseScale = 0.2
    Lighting.EnvironmentSpecularScale = 0.1
end

local function applyPoolRoomsLighting()
    Lighting.Brightness = 0.9
    Lighting.Ambient    = Color3.fromRGB(50, 60, 70)
    Lighting.OutdoorAmbient = Color3.fromRGB(40, 50, 60)
    Lighting.ClockTime  = 0
    Lighting.FogColor   = Color3.fromRGB(150, 190, 200)
    Lighting.FogStart   = 20
    Lighting.FogEnd     = 260
end

local function applyHabitableLighting()
    Lighting.Brightness = 0.5
    Lighting.Ambient    = Color3.fromRGB(35, 35, 40)
    Lighting.OutdoorAmbient = Color3.fromRGB(25, 25, 30)
    Lighting.ClockTime  = 0
    Lighting.FogColor   = Color3.fromRGB(40, 40, 45)
    Lighting.FogStart   = 10
    Lighting.FogEnd     = 160
end

local function restoreLighting()
    for k, v in pairs(State.originalLighting) do
        Lighting[k] = v
    end
end

-- ============================================================
--  MATERIAL HELPERS
-- ============================================================
local function makePart(props)
    local p = Instance.new("Part")
    p.Anchored = true
    p.CanCollide = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    for k, v in pairs(props or {}) do
        p[k] = v
    end
    return p
end

-- ============================================================
--  BACKROOMS CELL / WALL GENERATOR
-- ============================================================
local backroomsFolder

local function ensureFolder(name, parent)
    local f = (parent or Workspace):FindFirstChild(name)
    if not f then
        f = Instance.new("Folder")
        f.Name = name
        f.Parent = parent or Workspace
    end
    return f
end

-- Wallpaper-y wall
local function makeWallCFrame(cf)
    local w = makePart({
        Size = Vector3.new(1, CFG.WallHeight, CFG.CellSize),
        CFrame = cf,
        Material = Enum.Material.Concrete,
        Color = Color3.fromRGB(202, 188, 130),
        Reflectance = 0.02,
    })
    return w
end

-- Generate one backrooms chunk (grid of cells)
local function generateBackroomsChunk(cx, cz)
    local key = cx .. ":" .. cz
    if State.generatedChunks[key] then return end
    State.generatedChunks[key] = true

    backroomsFolder = backroomsFolder or ensureFolder("Backrooms")

    local originX = cx * CFG.ChunkSize
    local originZ = cz * CFG.ChunkSize
    local gridN   = math.floor(CFG.ChunkSize / CFG.CellSize)

    local poolChunk = chance(CFG.PoolRoomsChance) and (cx ~= 0 or cz ~= 0)
    local folderName = poolChunk and ("PoolRooms_"..key) or ("Backrooms_"..key)
    local folder = ensureFolder(folderName, backroomsFolder)

    -- Floor & ceiling
    local floor = makePart({
        Size = Vector3.new(CFG.ChunkSize, 1, CFG.ChunkSize),
        CFrame = CFrame.new(originX, 0, originZ),
        Material = poolChunk and Enum.Material.Marble or Enum.Material.Fabric,
        Color = poolChunk and Color3.fromRGB(210, 230, 235) or Color3.fromRGB(190, 175, 120),
    })
    floor.Parent = folder

    local ceil = makePart({
        Size = Vector3.new(CFG.ChunkSize, 1, CFG.ChunkSize),
        CFrame = CFrame.new(originX, CFG.WallHeight, originZ),
        Material = Enum.Material.Plaster,
        Color = poolChunk and Color3.fromRGB(230, 240, 245) or Color3.fromRGB(220, 210, 170),
    })
    ceil.Parent = folder

    -- Light fixtures (square, dimmer)
    for i = 1, 4 do
        for j = 1, 4 do
            if chance(poolChunk and 0.9 or 0.55) then
                local lx = originX - CFG.ChunkSize/2 + (i-0.5)*(CFG.ChunkSize/4)
                local lz = originZ - CFG.ChunkSize/2 + (j-0.5)*(CFG.ChunkSize/4)
                local lightPart = makePart({
                    Size = Vector3.new(6, 0.4, 6),
                    CFrame = CFrame.new(lx, CFG.WallHeight - 0.3, lz),
                    Material = Enum.Material.Neon,
                    Color = poolChunk and Color3.fromRGB(200, 240, 255) or Color3.fromRGB(255, 245, 200),
                    CanCollide = false,
                })
                lightPart.Parent = folder
                local pl = Instance.new("PointLight")
                pl.Range = 28
                pl.Brightness = poolChunk and 1.2 or 0.9
                pl.Color = lightPart.Color
                pl.Parent = lightPart
                table.insert(State.lights, {part = lightPart, light = pl, base = pl.Brightness})
            end
        end
    end

    -- Walls on grid
    for gx = 0, gridN do
        for gz = 0, gridN do
            local wx = originX - CFG.ChunkSize/2 + gx * CFG.CellSize
            local wz = originZ - CFG.ChunkSize/2 + gz * CFG.CellSize
            -- vertical wall segments (Z axis)
            if gx < gridN and chance(0.72) then
                local cf = CFrame.new(wx + CFG.CellSize/2, CFG.WallHeight/2, wz) * CFrame.Angles(0, math.rad(90), 0)
                local w = makeWallCFrame(cf)
                w.Parent = folder
            end
            -- horizontal wall segments (X axis)
            if gz < gridN and chance(0.72) then
                local cf = CFrame.new(wx, CFG.WallHeight/2, wz + CFG.CellSize/2)
                local w = makeWallCFrame(cf)
                w.Parent = folder
            end
        end
    end

    -- Occasional door model
    if not poolChunk and chance(0.05) then
        local m = yieldLoad(MODEL_IDS.Door)
        if m then
            local primary = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
            if primary then
                m:PivotTo(CFrame.new(originX + rng(-20,20), 3, originZ + rng(-20,20)))
                for _, d in ipairs(m:GetDescendants()) do
                    if d:IsA("BasePart") then d.Anchored = true end
                end
                m.Parent = folder
                table.insert(State.doors, m)
            end
        end
    end

    -- Random grouped models copied from workspace (only in backrooms chunks)
    if not poolChunk then
        for _, m in ipairs(Workspace:GetChildren()) do
            if m:IsA("Model") and m ~= char and chance(0.35) then
                local cloned = m:Clone()
                local primary = cloned.PrimaryPart or cloned:FindFirstChildWhichIsA("BasePart")
                if primary then
                    local px = originX + rng(-40, 40)
                    local pz = originZ + rng(-40, 40)
                    local py = chance(0.3) and 0.5 or 3
                    -- sometimes clip into floor / wall
                    cloned:PivotTo(CFrame.new(px, py, pz) * CFrame.Angles(0, rng(0, 6.28), 0))
                    for _, d in ipairs(cloned:GetDescendants()) do
                        if d:IsA("BasePart") then
                            d.Anchored = true
                            -- occasional weird stretch
                            if chance(0.15) then
                                d.Size = d.Size * Vector3.new(rng(0.5,2), rng(0.5,2), rng(0.5,2))
                            end
                        end
                    end
                    cloned.Parent = folder
                    State.pooledModels[#State.pooledModels+1] = cloned
                else
                    cloned:Destroy()
                end
            end
        end

        -- Chair model
        if chance(0.5) then
            local chair = yieldLoad(MODEL_IDS.Chair)
            if chair then
                local primary = chair.PrimaryPart or chair:FindFirstChildWhichIsA("BasePart")
                if primary then
                    local px = originX + rng(-40, 40)
                    local pz = originZ + rng(-40, 40)
                    local py = chance(0.4) and -1 or 2
                    chair:PivotTo(CFrame.new(px, py, pz) * CFrame.Angles(0, rng(0,6.28), 0))
                    for _, d in ipairs(chair:GetDescendants()) do
                        if d:IsA("BasePart") then d.Anchored = true end
                    end
                    chair.Parent = folder
                end
            end
        end
    end

    -- PoolRooms: add water pools and windows with neon
    if poolChunk then
        -- big pools
        for i = 1, 3 do
            local px = originX + rng(-CFG.ChunkSize/2 + 20, CFG.ChunkSize/2 - 20)
            local pz = originZ + rng(-CFG.ChunkSize/2 + 20, CFG.ChunkSize/2 - 20)
            local poolSize = Vector3.new(rng(30, 50), 6, rng(30, 50))
            -- dig hole: build pool walls (visual)
            local poolFloor = makePart({
                Size = Vector3.new(poolSize.X, 1, poolSize.Z),
                CFrame = CFrame.new(px, -poolSize.Y + 0.5, pz),
                Material = Enum.Material.Marble,
                Color = Color3.fromRGB(180, 220, 230),
            })
            poolFloor.Parent = folder

            -- water surface (transparent glass-like)
            local water = makePart({
                Size = Vector3.new(poolSize.X - 2, 1, poolSize.Z - 2),
                CFrame = CFrame.new(px, -0.2, pz),
                Material = Enum.Material.Glass,
                Color = Color3.fromRGB(120, 200, 220),
                Transparency = 0.4,
                CanCollide = false,
            })
            water.Parent = folder

            -- fill terrain water for swimming
            pcall(function()
                local region = Region3.new(
                    Vector3.new(px - poolSize.X/2 + 1, -poolSize.Y + 1, pz - poolSize.Z/2 + 1),
                    Vector3.new(px + poolSize.X/2 - 1, 0, pz + poolSize.Z/2 - 1)
                )
                Workspace.Terrain:FillRegion(region, 4, Enum.Material.Water)
            end)
        end

        -- windows with neon behind
        for i = 1, 4 do
            local wx = originX + rng(-CFG.ChunkSize/2, CFG.ChunkSize/2)
            local wz = originZ + rng(-CFG.ChunkSize/2, CFG.ChunkSize/2)
            local frame = makePart({
                Size = Vector3.new(8, 6, 0.5),
                CFrame = CFrame.new(wx, 6, wz),
                Material = Enum.Material.Metal,
                Color = Color3.fromRGB(200, 200, 200),
                Transparency = 0.2,
            })
            frame.Parent = folder
            local neon = makePart({
                Size = Vector3.new(8.2, 6.2, 0.3),
                CFrame = CFrame.new(wx, 6, wz) * CFrame.new(0, 0, 0.3),
                Material = Enum.Material.Neon,
                Color = Color3.fromRGB(220, 245, 255),
                CanCollide = false,
            })
            neon.Parent = folder
            local pl = Instance.new("PointLight")
            pl.Range = 18
            pl.Brightness = 1.5
            pl.Color = Color3.fromRGB(200, 230, 255)
            pl.Parent = neon
        end
    end
end

-- Infinite chunk loader
local lastChunkKey = ""

local function updateChunks()
    if not State.inBackrooms then return end
    local px, pz = rootPart.Position.X, rootPart.Position.Z
    local cx = math.floor(px / CFG.ChunkSize)
    local cz = math.floor(pz / CFG.ChunkSize)
    local key = cx .. ":" .. cz
    if key == lastChunkKey then return end
    lastChunkKey = key

    for dx = -CFG.RenderDistance, CFG.RenderDistance do
        for dz = -CFG.RenderDistance, CFG.RenderDistance do
            generateBackroomsChunk(cx + dx, cz + dz)
        end
    end
end

-- ============================================================
--  LIGHT FLICKER / BLACKOUT LOOP
-- ============================================================
task.spawn(function()
    while true do
        task.wait(rng(CFG.LightFlickerEvery[1], CFG.LightFlickerEvery[2]))
        if #State.lights > 0 and State.inBackrooms then
            -- flicker sequence
            local flickerCount = math.random(4, 10)
            for i = 1, flickerCount do
                for _, L in ipairs(State.lights) do
                    if L.light and L.light.Parent then
                        L.light.Brightness = chance(0.5) and 0 or L.base
                    end
                end
                task.wait(rng(0.05, 0.2))
            end
            -- pick some to stay off
            for _, L in ipairs(State.lights) do
                if L.light and L.light.Parent and chance(0.15) then
                    L.light.Brightness = 0
                end
            end
            -- restore
            task.wait(2)
            for _, L in ipairs(State.lights) do
                if L.light and L.light.Parent then
                    L.light.Brightness = L.base
                end
            end

            -- Habitable zone blackout
            if State.inHabitable then
                playSound(SOUNDS.Blackout, Workspace, 1)
                for _, L in ipairs(State.lights) do
                    if L.light and L.light.Parent then L.light.Brightness = 0 end
                end
                Lighting.Brightness = 0.05
                task.wait(CFG.BlackoutDuration)
                for _, L in ipairs(State.lights) do
                    if L.light and L.light.Parent then L.light.Brightness = L.base end
                end
                Lighting.Brightness = 0.5
            end
        end
    end
end)

-- ============================================================
--  FOOTSTEP SOUNDS
-- ============================================================
local stepAccum = 0
local lastStepSound = nil

RunService.Heartbeat:Connect(function(dt)
    if not State.inBackrooms then return end
    local speed = humanoid and humanoid.MoveDirection.Magnitude or 0
    if speed > 0.1 then
        stepAccum = stepAccum + dt
        if stepAccum >= 0.45 then
            stepAccum = 0
            local id = State.inPoolRooms and SOUNDS.PoolRoomsStep or SOUNDS.BackroomsStep
            local s = playSound(id, rootPart, 3, false)
            s.RollOffMaxDistance = 40
        end
    end
end)

-- ============================================================
--  AMBIENT SOUND MANAGER
-- ============================================================
local ambientSound = nil

local function setAmbient(id)
    if ambientSound then ambientSound:Destroy() end
    ambientSound = playSound(id, Workspace, 1.5, true)
end

-- ============================================================
--  WALL-BUMP DETECTION (50% chance noclip)
-- ============================================================
local lastPos = rootPart.Position
local bumpTimer = 0

RunService.Heartbeat:Connect(function(dt)
    if State.transitioning or State.inBackrooms then
        lastPos = rootPart.Position
        return
    end
    local moved = (rootPart.Position - lastPos).Magnitude
    lastPos = rootPart.Position

    local trying = humanoid and humanoid.MoveDirection.Magnitude > 0.1
    -- try moving but not actually moving = bumped into something
    if trying and moved < 0.05 then
        bumpTimer = bumpTimer + dt
        if bumpTimer > 0.15 then
            bumpTimer = 0
            if chance(CFG.NoclipChanceWall) then
                triggerNoclip()
            end
        end
    else
        bumpTimer = 0
    end
end)

-- ============================================================
--  RANDOM NOCLIP TIMER
-- ============================================================
task.spawn(function()
    while true do
        task.wait(1)
        if not State.inBackrooms and not State.transitioning then
            if chance(CFG.NoclipChancePerSecond) then
                triggerNoclip()
            end
        end
    end
end)

-- ============================================================
--  NOCLIP SEQUENCE
-- ============================================================
function triggerNoclip()
    if State.transitioning then return end
    State.transitioning = true

    -- sound
    playSound(SOUNDS.Noclip, Workspace, 1.2, false)

    -- turn off collision under player's feet
    task.spawn(function()
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
        task.wait(1.5)
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = true end
        end
    end)

    -- black screen + VHS
    overlay.BackgroundTransparency = 1
    overlay.Visible = true
    vhsActive = true
    fadeOverlay(0, 1.2)

    task.wait(1.2)

    -- BACKROOMS
    showText(pixelText, "BACKROOMS", 0.8, 0.42)
    task.wait(3)

    -- Produced By Hecker
    showText(subText, "Produced By Hecker", 0.8, 0.56)
    task.wait(5)

    -- fade out
    hideText(pixelText, 0.01)
    hideText(subText, 0.01)
    overlay.BackgroundTransparency = 1
    -- keep VHS visible during backrooms (per request)
    vhsActive = true
    overlay.BackgroundTransparency = 1
    overlay.Visible = true

    -- enter backrooms
    enterBackrooms()

    State.transitioning = false
end

-- ============================================================
--  ENTER BACKROOMS
-- ============================================================
function enterBackrooms()
    State.inBackrooms = true
    State.inPoolRooms = false
    State.inHabitable = false

    applyBackroomsLighting()
    setAmbient(SOUNDS.BackroomsAmbient)

    -- teleport player far away (to an empty area)
    local spawnPos = Vector3.new(5000, 5, 5000)
    rootPart.CFrame = CFrame.new(spawnPos)

    -- generate first chunks
    State.generatedChunks = {}
    lastChunkKey = ""
    updateChunks()

    slideToast("Backrooms Has Been Loaded. Goodluck Wanderer", 5)
end

-- ============================================================
--  POOLROOMS DETECTION (when player enters a PoolRooms chunk)
-- ============================================================
local lastArea = "backrooms"
RunService.Heartbeat:Connect(function()
    if not State.inBackrooms then return end
    local px, pz = rootPart.Position.X, rootPart.Position.Z
    local cx = math.floor(px / CFG.ChunkSize)
    local cz = math.floor(pz / CFG.ChunkSize)
    local key = ("PoolRooms_"..cx..":"..cz)
    local isPool = backroomsFolder and backroomsFolder:FindFirstChild(key) ~= nil

    if isPool and lastArea ~= "pool" then
        lastArea = "pool"
        State.inPoolRooms = true
        applyPoolRoomsLighting()
        setAmbient(SOUNDS.PoolRoomsAmbient)
        slideToast("The PoolRooms", 4)
    elseif not isPool and lastArea ~= "backrooms" then
        lastArea = "backrooms"
        State.inPoolRooms = false
        applyBackroomsLighting()
        setAmbient(SOUNDS.BackroomsAmbient)
        slideToast("The Backrooms", 3)
    end
end)

-- ============================================================
--  FLASHLIGHT
-- ============================================================
local flashlight = Instance.new("SpotLight")
flashlight.Brightness = 3
flashlight.Range = 90
flashlight.Angle = 60
flashlight.Face = Enum.NormalId.Front
flashlight.Enabled = false
flashlight.Parent = camera

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.F then
        State.flashOn = not State.flashOn
        flashlight.Enabled = State.flashOn
        playSound(SOUNDS.Flashlight, Workspace, 1)
    end
end)

-- ============================================================
--  DOOR INTERACTION (ProximityPrompt on doors)
-- ============================================================
local function attachDoorPrompt(model)
    local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if not primary then return end
    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Open Door"
    prompt.ObjectText = "Door"
    prompt.MaxActivationDistance = 10
    prompt.RequiresLineOfSight = false
    prompt.Parent = primary
    prompt.Triggered:Connect(function()
        playSound(SOUNDS.DoorOpen, Workspace, 1.5)
        -- teleport to a new location (simulate entering another part of backrooms)
        local nx = rootPart.Position.X + rng(-200, 200)
        local nz = rootPart.Position.Z + rng(-200, 200)
        rootPart.CFrame = CFrame.new(nx, 5, nz)
        State.generatedChunks = {}
        lastChunkKey = ""
    end)
end

-- periodically attach prompts to any new door models
task.spawn(function()
    while true do
        task.wait(2)
        for _, f in ipairs(backroomsFolder and backroomsFolder:GetChildren() or {}) do
            for _, m in ipairs(f:GetChildren()) do
                if m:IsA("Model") and not m:GetAttribute("PromptAttached") then
                    local ok = pcall(attachDoorPrompt, m)
                    if ok then m:SetAttribute("PromptAttached", true) end
                end
            end
        end
    end
end)

-- ============================================================
--  CHUNK UPDATE LOOP
-- ============================================================
RunService.Heartbeat:Connect(function()
    if State.inBackrooms then
        updateChunks()
    end
end)

-- ============================================================
--  INITIAL TOAST
-- ============================================================
slideToast("Script Loaded. Goodluck Wanderer", 3)
