-- ============================================================
--  BACKROOMS - Client-side LocalScript (Delta / Executor)
--  Fixed: PoolRooms generation, materials, exit, UI position.
-- ============================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")
local TweenService     = game:GetService("TweenService")
local InsertService    = game:GetService("InsertService")
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
    ChunkSize              = 120,
    CellSize               = 20,
    WallHeight             = 12,
    RenderDistance         = 2,      -- chunks in each direction
    LightFlickerEvery      = {15, 30},
    BlackoutDuration       = 15,
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
    chunkTypes    = {}, -- stores "backrooms", "pool", "habitable"
    pooledModels  = {},
    lights        = {},
    doors         = {},
    originalPos   = nil,
    originalLighting = {
        Brightness = Lighting.Brightness,
        Ambient    = Lighting.Ambient,
        FogEnd     = Lighting.FogEnd,
        FogStart   = Lighting.FogStart,
        ClockTime  = Lighting.ClockTime,
        FogColor   = Lighting.FogColor,
    },
}

-- ============================================================
--  UTIL
-- ============================================================
local function rng(a, b) return math.random() * (b - a) + a end
local function chance(p) return math.random() < p end

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
    local ok, model = pcall(function() return InsertService:LoadAsset(id) end)
    if ok and model then return model end
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
--  UI (Black screen, VHS, Pixel text, HUD)
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BackroomsUI"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local overlay = Instance.new("Frame")
overlay.Name = "VHSOverlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.ZIndex = 100
overlay.Visible = false
overlay.Parent = screenGui

local scan = Instance.new("Frame")
scan.Size = UDim2.fromScale(1, 0.02)
scan.BackgroundColor3 = Color3.new(1, 1, 1)
scan.BackgroundTransparency = 0.85
scan.BorderSizePixel = 0
scan.ZIndex = 101
scan.Parent = overlay

local distort = Instance.new("Frame")
distort.Size = UDim2.fromScale(1, 0.06)
distort.BackgroundColor3 = Color3.new(1,1,1)
distort.BackgroundTransparency = 0.9
distort.BorderSizePixel = 0
distort.ZIndex = 101
distort.Parent = overlay

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

-- Toast HUD (Top of screen, as requested)
local toast = Instance.new("TextLabel")
toast.BackgroundTransparency = 1
toast.Size = UDim2.fromScale(1, 0.08)
toast.Position = UDim2.new(0.5, 0, 0.1, 0)
toast.AnchorPoint = Vector2.new(0.5, 0.5)
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
            local y = (scan.Position.Y.Scale + 0.06) % 1.2 - 0.1
            scan.Position = UDim2.fromScale(0, y)
            distort.Position = UDim2.fromScale(0, math.random()*1)
            distort.BackgroundTransparency = math.random(85, 98)/100
            if camera then
                camera.CFrame = camera.CFrame * CFrame.new(rng(-0.05, 0.05), rng(-0.05, 0.05), 0)
            end
        end
    end
end)

-- ============================================================
--  UI HELPERS
-- ============================================================
local function fadeOverlay(alpha, time)
    overlay.Visible = true
    TweenService:Create(overlay, TweenInfo.new(time), {BackgroundTransparency = alpha}):Play()
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
    toast.Position = UDim2.new(0.5, 0, 0.05, 0)
    toast.TextTransparency = 1
    local inT = TweenService:Create(toast, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {Position = UDim2.new(0.5, 0, 0.1, 0), TextTransparency = 0})
    inT:Play()
    task.delay(duration or 4, function()
        local outT = TweenService:Create(toast, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
            {Position = UDim2.new(0.5, 0, 0.05, 0), TextTransparency = 1})
        outT:Play()
    end)
end

-- ============================================================
--  LIGHTING PRESETS (Based on images)
-- ============================================================
local function applyBackroomsLighting()
    Lighting.Brightness = 1.5
    Lighting.Ambient    = Color3.fromRGB(80, 75, 50)
    Lighting.OutdoorAmbient = Color3.fromRGB(60, 55, 40)
    Lighting.ClockTime  = 0
    Lighting.FogColor   = Color3.fromRGB(180, 170, 100) -- Yellowish fog
    Lighting.FogStart   = 10
    Lighting.FogEnd     = 180
    Lighting.GlobalShadows = true
end

local function applyPoolRoomsLighting()
    Lighting.Brightness = 1.0
    Lighting.Ambient    = Color3.fromRGB(180, 200, 210) -- Clean white/blue
    Lighting.OutdoorAmbient = Color3.fromRGB(150, 180, 190)
    Lighting.ClockTime  = 0
    Lighting.FogColor   = Color3.fromRGB(200, 230, 240)
    Lighting.FogStart   = 20
    Lighting.FogEnd     = 250
end

local function applyHabitableLighting()
    Lighting.Brightness = 0.3
    Lighting.Ambient    = Color3.fromRGB(40, 40, 45)
    Lighting.OutdoorAmbient = Color3.fromRGB(30, 30, 35)
    Lighting.ClockTime  = 0
    Lighting.FogColor   = Color3.fromRGB(50, 50, 55)
    Lighting.FogStart   = 5
    Lighting.FogEnd     = 120
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
    for k, v in pairs(props or {}) do p[k] = v end
    return p
end

local function ensureFolder(name, parent)
    local f = (parent or Workspace):FindFirstChild(name)
    if not f then
        f = Instance.new("Folder")
        f.Name = name
        f.Parent = parent or Workspace
    end
    return f
end

-- ============================================================
--  BACKROOMS / POOLROOMS GENERATOR
-- ============================================================
local backroomsFolder = ensureFolder("Backrooms")

local function generateChunk(cx, cz)
    local key = cx .. ":" .. cz
    if State.generatedChunks[key] then return end
    State.generatedChunks[key] = true

    local originX = cx * CFG.ChunkSize
    local originZ = cz * CFG.ChunkSize
    local gridN   = math.floor(CFG.ChunkSize / CFG.CellSize)

    -- Determine Chunk Type
    local chunkType = "backrooms"
    if chance(CFG.PoolRoomsChance) and (cx ~= 0 or cz ~= 0) then
        chunkType = "pool"
    elseif chance(CFG.HabitableChance) then
        chunkType = "habitable"
    end
    State.chunkTypes[key] = chunkType

    local folderName = chunkType .. "_" .. key
    local folder = ensureFolder(folderName, backroomsFolder)

    -- 1. FLOOR
    local floorColor = Color3.fromRGB(190, 175, 120)
    local floorMat = Enum.Material.Fabric
    if chunkType == "pool" then
        floorColor = Color3.fromRGB(240, 245, 240)
        floorMat = Enum.Material.Marble
    elseif chunkType == "habitable" then
        floorColor = Color3.fromRGB(80, 80, 80)
        floorMat = Enum.Material.Concrete
    end

    local floor = makePart({
        Size = Vector3.new(CFG.ChunkSize, 1, CFG.ChunkSize),
        CFrame = CFrame.new(originX, 0, originZ),
        Material = floorMat,
        Color = floorColor,
    })
    floor.Parent = folder

    -- 2. CEILING
    local ceilColor = Color3.fromRGB(220, 210, 170)
    local ceilMat = Enum.Material.Plaster
    if chunkType == "pool" then
        ceilColor = Color3.fromRGB(240, 245, 240)
        ceilMat = Enum.Material.Marble
    elseif chunkType == "habitable" then
        ceilColor = Color3.fromRGB(60, 60, 60)
        ceilMat = Enum.Material.Concrete
    end

    local ceil = makePart({
        Size = Vector3.new(CFG.ChunkSize, 1, CFG.ChunkSize),
        CFrame = CFrame.new(originX, CFG.WallHeight, originZ),
        Material = ceilMat,
        Color = ceilColor,
    })
    ceil.Parent = folder

    -- 3. LIGHTS (Square, dimmer for backrooms, bright for pool)
    if chunkType ~= "habitable" then
        for i = 1, 3 do
            for j = 1, 3 do
                if chance(0.7) then
                    local lx = originX - CFG.ChunkSize/2 + (i-0.5)*(CFG.ChunkSize/3)
                    local lz = originZ - CFG.ChunkSize/2 + (j-0.5)*(CFG.ChunkSize/3)
                    local lightPart = makePart({
                        Size = Vector3.new(8, 0.4, 8),
                        CFrame = CFrame.new(lx, CFG.WallHeight - 0.3, lz),
                        Material = Enum.Material.Neon,
                        Color = chunkType == "pool" and Color3.fromRGB(220, 245, 255) or Color3.fromRGB(255, 245, 200),
                        CanCollide = false,
                    })
                    lightPart.Parent = folder
                    local pl = Instance.new("PointLight")
                    pl.Range = chunkType == "pool" and 30 or 22
                    pl.Brightness = chunkType == "pool" and 1.5 or 0.8
                    pl.Color = lightPart.Color
                    pl.Parent = lightPart
                    table.insert(State.lights, {part = lightPart, light = pl, base = pl.Brightness, chunk = chunkType})
                end
            end
        end
    end

    -- 4. WALLS (Backrooms maze)
    if chunkType == "backrooms" then
        for gx = 0, gridN do
            for gz = 0, gridN do
                local wx = originX - CFG.ChunkSize/2 + gx * CFG.CellSize
                local wz = originZ - CFG.ChunkSize/2 + gz * CFG.CellSize
                if gx < gridN and chance(0.75) then
                    local w = makePart({
                        Size = Vector3.new(1, CFG.WallHeight, CFG.CellSize),
                        CFrame = CFrame.new(wx + CFG.CellSize/2, CFG.WallHeight/2, wz) * CFrame.Angles(0, math.rad(90), 0),
                        Material = Enum.Material.Concrete,
                        Color = Color3.fromRGB(210, 200, 140),
                    })
                    w.Parent = folder
                end
                if gz < gridN and chance(0.75) then
                    local w = makePart({
                        Size = Vector3.new(1, CFG.WallHeight, CFG.CellSize),
                        CFrame = CFrame.new(wx, CFG.WallHeight/2, wz + CFG.CellSize/2),
                        Material = Enum.Material.Concrete,
                        Color = Color3.fromRGB(210, 200, 140),
                    })
                    w.Parent = folder
                end
            end
        end
    elseif chunkType == "pool" then
        -- PoolRooms Architecture: Arches and Tunnels
        for i = 1, 4 do
            local px = originX + rng(-CFG.ChunkSize/2 + 20, CFG.ChunkSize/2 - 20)
            local pz = originZ + rng(-CFG.ChunkSize/2 + 20, CFG.ChunkSize/2 - 20)
            -- Pool hole
            local poolSize = Vector3.new(rng(30, 50), 6, rng(30, 50))
            local poolFloor = makePart({
                Size = Vector3.new(poolSize.X, 1, poolSize.Z),
                CFrame = CFrame.new(px, -poolSize.Y + 0.5, pz),
                Material = Enum.Material.Marble,
                Color = Color3.fromRGB(200, 220, 230),
            })
            poolFloor.Parent = folder

            -- Water (Swimmable)
            pcall(function()
                local region = Region3.new(
                    Vector3.new(px - poolSize.X/2 + 1, -poolSize.Y + 1, pz - poolSize.Z/2 + 1),
                    Vector3.new(px + poolSize.X/2 - 1, 0, pz + poolSize.Z/2 - 1)
                )
                Workspace.Terrain:FillRegion(region, 4, Enum.Material.Water)
            end)

            -- Archway/Tunnel visuals
            local arch = makePart({
                Size = Vector3.new(poolSize.X, 20, 2),
                CFrame = CFrame.new(px, 10, pz - poolSize.Z/2),
                Material = Enum.Material.Marble,
                Color = Color3.fromRGB(240, 245, 240),
            })
            arch.Parent = folder
        end
    end

    -- 5. DOOR / EXIT SPAWNING
    if chunkType == "backrooms" and chance(0.05) then
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

    -- 6. RANDOM MODELS (Chairs, boxes, ladders) - Only in Backrooms
    if chunkType == "backrooms" then
        for _, m in ipairs(Workspace:GetChildren()) do
            if m:IsA("Model") and m ~= char and chance(0.2) then
                local cloned = m:Clone()
                local primary = cloned.PrimaryPart or cloned:FindFirstChildWhichIsA("BasePart")
                if primary then
                    local px = originX + rng(-40, 40)
                    local pz = originZ + rng(-40, 40)
                    -- Sometimes clip into floor/wall
                    local py = chance(0.4) and -1 or 2
                    cloned:PivotTo(CFrame.new(px, py, pz) * CFrame.Angles(0, rng(0, 6.28), 0))
                    for _, d in ipairs(cloned:GetDescendants()) do
                        if d:IsA("BasePart") then
                            d.Anchored = true
                            if chance(0.1) then -- Stretch weirdly
                                d.Size = d.Size * Vector3.new(rng(0.5,2), rng(0.5,2), rng(0.5,2))
                            end
                        end
                    end
                    cloned.Parent = folder
                else
                    cloned:Destroy()
                end
            end
        end
    end
end

-- ============================================================
--  INFINITE CHUNK LOADER
-- ============================================================
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
            generateChunk(cx + dx, cz + dz)
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
            local flickerCount = math.random(3, 8)
            for i = 1, flickerCount do
                for _, L in ipairs(State.lights) do
                    if L.light and L.light.Parent then
                        L.light.Brightness = chance(0.5) and 0 or L.base
                    end
                end
                task.wait(rng(0.05, 0.15))
            end
            task.wait(1.5)
            for _, L in ipairs(State.lights) do
                if L.light and L.light.Parent then L.light.Brightness = L.base end
            end

            -- Habitable Zone Blackout
            if State.inHabitable then
                playSound(SOUNDS.Blackout, Workspace, 1)
                for _, L in ipairs(State.lights) do
                    if L.light and L.light.Parent then L.light.Brightness = 0 end
                end
                Lighting.Brightness = 0.02
                task.wait(CFG.BlackoutDuration)
                for _, L in ipairs(State.lights) do
                    if L.light and L.light.Parent then L.light.Brightness = L.base end
                end
                Lighting.Brightness = 0.3
            end
        end
    end
end)

-- ============================================================
--  FOOTSTEP SOUNDS & AREA DETECTION
-- ============================================================
local stepAccum = 0
local lastArea = "backrooms"

RunService.Heartbeat:Connect(function(dt)
    if not State.inBackrooms then return end
    
    -- Area Detection
    local px, pz = rootPart.Position.X, rootPart.Position.Z
    local cx = math.floor(px / CFG.ChunkSize)
    local cz = math.floor(pz / CFG.ChunkSize)
    local key = cx .. ":" .. cz
    local currentType = State.chunkTypes[key] or "backrooms"

    if currentType ~= lastArea then
        lastArea = currentType
        if currentType == "pool" then
            State.inPoolRooms = true
            State.inHabitable = false
            applyPoolRoomsLighting()
            setAmbient(SOUNDS.PoolRoomsAmbient)
            slideToast("The PoolRooms", 4)
        elseif currentType == "habitable" then
            State.inPoolRooms = false
            State.inHabitable = true
            applyHabitableLighting()
            setAmbient(SOUNDS.BackroomsAmbient) -- Or a specific habitable sound
            slideToast("Habitable Zone", 4)
        else
            State.inPoolRooms = false
            State.inHabitable = false
            applyBackroomsLighting()
            setAmbient(SOUNDS.BackroomsAmbient)
            slideToast("The Backrooms", 3)
        end
    end

    -- Footsteps
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
function setAmbient(id)
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
    State.originalPos = rootPart.CFrame

    playSound(SOUNDS.Noclip, Workspace, 1.2, false)

    -- Turn off collision under player's feet
    task.spawn(function()
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
        task.wait(1.5)
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = true end
        end
    end)

    -- Black screen + VHS
    overlay.BackgroundTransparency = 1
    overlay.Visible = true
    vhsActive = true
    fadeOverlay(0, 1.2)

    task.wait(1.2)
    showText(pixelText, "BACKROOMS", 0.8, 0.42)
    task.wait(3)
    showText(subText, "Produced By Hecker", 0.8, 0.56)
    task.wait(5)

    hideText(pixelText, 0.01)
    hideText(subText, 0.01)
    overlay.BackgroundTransparency = 1
    vhsActive = true -- Keep VHS active in the backrooms

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

    local spawnPos = Vector3.new(5000, 5, 5000)
    rootPart.CFrame = CFrame.new(spawnPos)

    State.generatedChunks = {}
    State.chunkTypes = {}
    lastChunkKey = ""
    updateChunks()

    slideToast("Backrooms Has Been Loaded. Goodluck Wanderer", 5)
end

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
--  DOOR INTERACTION (Exit & Enter)
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
        
        -- Check if it's an exit door (random chance or specific model)
        if chance(0.3) then -- 30% chance this door is an exit
            slideToast("Exiting Backrooms...", 3)
            task.wait(1)
            restoreLighting()
            if State.originalPos then
                rootPart.CFrame = State.originalPos
            else
                rootPart.CFrame = CFrame.new(0, 5, 0)
            end
            State.inBackrooms = false
            vhsActive = false
            overlay.Visible = false
            if ambientSound then ambientSound:Destroy() end
        else
            -- Teleport to a new location within the backrooms
            local nx = rootPart.Position.X + rng(-200, 200)
            local nz = rootPart.Position.Z + rng(-200, 200)
            rootPart.CFrame = CFrame.new(nx, 5, nz)
            State.generatedChunks = {}
            State.chunkTypes = {}
            lastChunkKey = ""
        end
    end)
end

task.spawn(function()
    while true do
        task.wait(2)
        for _, f in ipairs(backroomsFolder:GetChildren() or {}) do
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
