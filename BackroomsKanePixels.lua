--[[
BACKROOMS / POOLROOMS / HABITABLE ZONE
CLIENT-SIDE LOCAL SCRIPT
Place this LocalScript in StarterPlayer > StarterPlayerScripts in your OWN Roblox experience.

What this version includes:
- 10% chance every second to "noclip" through the floor you're standing on.
- 50% chance when a wall is detected directly in front of you.
- VHS transition, pixel text, and teleport into a generated Backrooms.
- Large/infinite streaming-style Backrooms chunks with open spaces, dead ends, square holes,
  occasional tall 5-floor rooms, exposed upper floors, weak/dim square lights, flicker events.
- 20% PoolRooms discovery chance after the opening area, with signs/arrows and a connected entrance.
- Infinite-style PoolRooms chunks, pools, corridors, tunnels, windows, glowing trims and a deep shaft.
- Backrooms-only model copying for grouped Models already present in Workspace.
- Procedural chair/house/door/escalator fallbacks.
- Flashlight toggle button + keyboard F, with sounds.
- Custom loud Backrooms/PoolRooms footsteps while suppressing the default Running sound.
- Camera found-footage bob.
- Habitable Zone transition, garage/road/puddle style, timed flickering/blackout.
- Door interaction using a ProximityPrompt.
- All generated geometry is anchored and intentionally avoids Fabric material.

IMPORTANT LIMITATION:
A normal Roblox LocalScript cannot securely download arbitrary catalog models from an asset ID.
For the four requested model IDs, place the models in ReplicatedStorage and name them:
  ChairTemplate
  HouseTemplate
  DoorTemplate
  EscalatorTemplate
The script will clone those templates when present. Otherwise it uses procedural fallbacks.
The asset IDs are kept below as references.

Requested reference assets:
Chair/Backrooms prop: 74698525718385
Door: 9343670755
Escalator: 18861464725
Habitable prop: 10225195309
Backrooms wall texture: 11734753590
PoolRooms texture: 11384971113

Sound IDs:
Backrooms transition: 139682612041479
Backrooms ambience: 137406302438919
Backrooms footsteps: 89575970505811
PoolRooms footsteps: 96516907071037
PoolRooms ambience: 94241101968368
Door opening: 125209584906878
Flashlight toggle: 128570293170805
Habitable blackout: 78704114462031
]]

--// Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

--// Player
local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

--// References
local character
local humanoid
local root

--// Requested IDs
local IDS = {
    WallTexture = 11734753590,
    PoolTexture = 11384971113,

    ChairModel = 74698525718385,
    HouseModel = 74698525718385,
    DoorModel = 9343670755,
    EscalatorModel = 18861464725,
    HabitablePropModel = 10225195309,

    Transition = 139682612041479,
    BackroomsAmbience = 137406302438919,
    BackroomsFootstep = 89575970505811,
    PoolFootstep = 96516907071037,
    PoolAmbience = 94241101968368,
    DoorOpen = 125209584906878,
    FlashlightToggle = 128570293170805,
    HabitableBlackout = 78704114462031,
}

--// Tuning
local CONFIG = {
    Backrooms = {
        ChunkSize = 150,
        RoomSize = 48,
        Wall = 2.4,
        WallHeight = 16,
        FloorThickness = 1.2,
        CeilingHeight = 17,
        GenerateRadius = 2,
        RemoveRadius = 4,
        OpenRoomChance = 0.27,
        DeadEndChance = 0.18,
        HoleChance = 0.10,
        BigRoomChance = 0.055,
        HouseChance = 0.09,
        ChairChance = 0.16,
        FlickerChance = 0.10,
        DimLightChance = 0.34,
        PoolChance = 0.20,
    },

    PoolRooms = {
        ChunkSize = 160,
        RoomSize = 52,
        Wall = 2.4,
        WallHeight = 15,
        CeilingHeight = 16,
        GenerateRadius = 2,
        RemoveRadius = 4,
        OpenRoomChance = 0.35,
        PoolChance = 0.72,
        TunnelChance = 0.34,
        DeepShaftChance = 0.08,
        WindowChance = 0.35,
    },

    Footsteps = {
        MinInterval = 0.26,
        MaxInterval = 0.42,
        Volume = 1.8,
    },

    CameraBob = {
        Speed = 7.5,
        Amount = 0.055,
        Roll = 0.65,
    }
}

--// State
local mode = "NORMAL" -- NORMAL / BACKROOMS / POOLROOMS / HABITABLE
local loaded = false
local transitioning = false
local flashlightOn = false
local lastStep = 0
local footstepConn
local updateConn
local noclipConn
local bobTime = 0
local generated = {}
local generatedType = {}
local poolDiscovered = false
local firstPoolAttemptDone = false
local habitableBlackoutActive = false
local currentDoor
local vhsGui
local statusGui
local flashlight
local postEffects = {}
local savedLighting = {}

--// Random
local RNG = Random.new()

local function chance(p)
    return RNG:NextNumber() < p
end

local function rInt(a, b)
    return RNG:NextInteger(a, b)
end

local function rFloat(a, b)
    return RNG:NextNumber(a, b)
end

local function round(n, grid)
    return math.floor((n / grid) + 0.5) * grid
end

--// Character refresh
local function refreshCharacter()
    character = player.Character or player.CharacterAdded:Wait()
    humanoid = character:WaitForChild("Humanoid")
    root = character:WaitForChild("HumanoidRootPart")
end

refreshCharacter()

player.CharacterAdded:Connect(function()
    task.wait(0.2)
    refreshCharacter()
end)

--// Folder
local worldFolder = Workspace:FindFirstChild("ClientBackroomsWorld")
if not worldFolder then
    worldFolder = Instance.new("Folder")
    worldFolder.Name = "ClientBackroomsWorld"
    worldFolder.Parent = Workspace
end

--// Utilities
local function setPartPhysical(part, material, color, transparency)
    part.Anchored = true
    part.CanCollide = true
    part.CastShadow = true
    part.Material = material
    part.Color = color
    part.Transparency = transparency or 0
    return part
end

local function makePart(name, size, cf, material, color, parent, transparency)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = size
    p.CFrame = cf
    setPartPhysical(p, material, color, transparency)
    p.Parent = parent
    return p
end

local function addTexture(part, assetId, face, studsU, studsV, color3)
    local tex = Instance.new("Texture")
    tex.Texture = "rbxassetid://" .. tostring(assetId)
    tex.Face = face or Enum.NormalId.Front
    tex.StudsPerTileU = studsU or 8
    tex.StudsPerTileV = studsV or 8
    tex.Color3 = color3 or Color3.new(1, 1, 1)
    tex.Transparency = 0.05
    tex.Parent = part
    return tex
end

local function addSquareLight(parent, cf, brightness, range, enabled)
    local fixture = makePart(
        "SquareLight",
        Vector3.new(7.2, 0.25, 3.1),
        cf,
        Enum.Material.SmoothPlastic,
        Color3.fromRGB(224, 220, 193),
        parent,
        0
    )
    fixture.CanCollide = false

    local light = Instance.new("SurfaceLight")
    light.Face = Enum.NormalId.Bottom
    light.Brightness = brightness
    light.Range = range
    light.Angle = 110
    light.Shadows = true
    light.Enabled = enabled ~= false
    light.Parent = fixture

    return fixture, light
end

local function addCeilingPipes(parent, center, width)
    local y = center.Y - 1.1
    for i = 1, rInt(2, 4) do
        local x = center.X + rFloat(-width * 0.35, width * 0.35)
        local pipe = makePart(
            "CeilingPipe",
            Vector3.new(0.45, 0.45, width * rFloat(0.7, 1.15)),
            CFrame.new(x, y, center.Z) * CFrame.Angles(0, 0, math.rad(rInt(-3, 3))),
            Enum.Material.Metal,
            Color3.fromRGB(126, 126, 120),
            parent
        )
        pipe.CanCollide = false
    end
end

local function addPuddle(parent, cf, size)
    local puddle = makePart(
        "Puddle",
        Vector3.new(size.X, 0.07, size.Z),
        cf,
        Enum.Material.Glass,
        Color3.fromRGB(68, 74, 78),
        parent,
        0.38
    )
    puddle.Reflectance = 0.3
    puddle.CanCollide = false
    return puddle
end

local function muteDefaultRunningSounds()
    if not character then return end
    for _, d in ipairs(character:GetDescendants()) do
        if d:IsA("Sound") then
            local n = string.lower(d.Name)
            if string.find(n, "running") or string.find(n, "run") or string.find(n, "foot") then
                d.Volume = 0
            end
        end
    end
end

character.DescendantAdded:Connect(function(d)
    if d:IsA("Sound") then
        task.defer(muteDefaultRunningSounds)
    end
end)

--// Pixel text helpers
local function newTextGui()
    local gui = Instance.new("ScreenGui")
    gui.Name = "BackroomsText"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = player:WaitForChild("PlayerGui")
    return gui
end

local function pixelText(text, size, pos, transparency)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = size
    label.Position = pos
    label.AnchorPoint = Vector2.new(0.5, 0.5)
    label.Text = text
    label.TextScaled = true
    label.Font = Enum.Font.Arcade
    label.TextColor3 = Color3.new(0.92, 0.92, 0.78)
    label.TextStrokeTransparency = 0.72
    label.TextTransparency = transparency or 0
    label.ZIndex = 10
    return label
end

--// VHS
local function destroyPostEffects()
    for _, e in ipairs(postEffects) do
        if e and e.Parent then
            e:Destroy()
        end
    end
    table.clear(postEffects)
end

local function setVHS(enabled, strong)
    if enabled then
        destroyPostEffects()

        local cc = Instance.new("ColorCorrectionEffect")
        cc.Name = "VHSColor"
        cc.Saturation = strong and -0.12 or -0.03
        cc.Contrast = strong and 0.14 or 0.06
        cc.Brightness = strong and -0.08 or -0.02
        cc.TintColor = Color3.fromRGB(226, 224, 198)
        cc.Parent = Lighting
        table.insert(postEffects, cc)

        local blur = Instance.new("BlurEffect")
        blur.Size = strong and 1.5 or 0.35
        blur.Parent = Lighting
        table.insert(postEffects, blur)
    else
        destroyPostEffects()
    end
end

local function buildVHSGui()
    if vhsGui then vhsGui:Destroy() end

    vhsGui = Instance.new("ScreenGui")
    vhsGui.Name = "VHS"
    vhsGui.IgnoreGuiInset = true
    vhsGui.ResetOnSpawn = false
    vhsGui.DisplayOrder = 1000
    vhsGui.Parent = player.PlayerGui

    local black = Instance.new("Frame")
    black.Name = "Black"
    black.Size = UDim2.fromScale(1, 1)
    black.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    black.BackgroundTransparency = 1
    black.ZIndex = 1
    black.Parent = vhsGui

    local lines = Instance.new("Frame")
    lines.Size = UDim2.fromScale(1, 1)
    lines.BackgroundTransparency = 1
    lines.ZIndex = 2
    lines.Parent = vhsGui

    for y = 0, 720, 6 do
        local line = Instance.new("Frame")
        line.BorderSizePixel = 0
        line.BackgroundColor3 = Color3.new(1, 1, 1)
        line.BackgroundTransparency = rFloat(0.86, 0.96)
        line.Size = UDim2.new(1, 0, 0, 1)
        line.Position = UDim2.new(0, 0, 0, y)
        line.Parent = lines
    end

    local noise = Instance.new("Frame")
    noise.Size = UDim2.fromScale(1, 1)
    noise.BackgroundTransparency = 0.94
    noise.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
    noise.ZIndex = 3
    noise.Parent = vhsGui

    return black
end

local function transitionText(text, yScale, parent, holdTime)
    local label = pixelText(
        text,
        UDim2.fromScale(0.78, 0.13),
        UDim2.fromScale(0.5, yScale),
        1
    )
    label.Parent = parent

    local slideStart = UDim2.fromScale(0.62, yScale)
    local slideEnd = UDim2.fromScale(0.5, yScale)
    label.Position = slideStart

    TweenService:Create(
        label,
        TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Position = slideEnd, TextTransparency = 0}
    ):Play()

    task.wait(holdTime or 0)
    return label
end

local function playOneShot(soundId, volume)
    local s = Instance.new("Sound")
    s.SoundId = "rbxassetid://" .. tostring(soundId)
    s.Volume = volume or 1
    s.RollOffMaxDistance = 100000
    s.Parent = camera
    s:Play()
    s.Ended:Connect(function()
        s:Destroy()
    end)
    return s
end

--// Flashlight
local function createFlashlight()
    if flashlight then flashlight:Destroy() end
    flashlight = Instance.new("SpotLight")
    flashlight.Name = "FoundFootageFlashlight"
    flashlight.Brightness = 2.6
    flashlight.Range = 54
    flashlight.Angle = 56
    flashlight.Shadows = true
    flashlight.Enabled = false
    flashlight.Parent = camera
end

local function toggleFlashlight()
    if mode == "NORMAL" then return end
    flashlightOn = not flashlightOn
    if not flashlight then createFlashlight() end
    flashlight.Enabled = flashlightOn
    playOneShot(IDS.FlashlightToggle, 0.8)
end

createFlashlight()

local function buildFlashlightGui()
    local gui = Instance.new("ScreenGui")
    gui.Name = "FlashlightGui"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 50
    gui.Parent = player.PlayerGui

    local button = Instance.new("TextButton")
    button.Name = "OpenFlashlight"
    button.Size = UDim2.fromOffset(185, 52)
    button.Position = UDim2.new(1, -205, 1, -80)
    button.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
    button.BackgroundTransparency = 0.2
    button.TextColor3 = Color3.new(1, 1, 1)
    button.TextScaled = true
    button.Font = Enum.Font.Arcade
    button.Text = "Open Flashlight"
    button.AutoButtonColor = true
    button.Visible = false
    button.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button

    button.Activated:Connect(toggleFlashlight)

    local stroke = Instance.new("UIStroke")
    stroke.Transparency = 0.45
    stroke.Parent = button

    return button
end

local flashlightButton = buildFlashlightGui()

--// Ambience
local ambienceSound
local function stopAmbience()
    if ambienceSound then
        ambienceSound:Stop()
        ambienceSound:Destroy()
        ambienceSound = nil
    end
end

local function startAmbience(soundId, volume)
    stopAmbience()
    ambienceSound = Instance.new("Sound")
    ambienceSound.SoundId = "rbxassetid://" .. tostring(soundId)
    ambienceSound.Volume = volume or 0.55
    ambienceSound.Looped = true
    ambienceSound.Parent = camera
    ambienceSound:Play()
end

--// Footsteps
local function stopFootsteps()
    if footstepConn then
        footstepConn:Disconnect()
        footstepConn = nil
    end
end

local function startFootsteps()
    stopFootsteps()

    footstepConn = RunService.Heartbeat:Connect(function()
        if not humanoid or humanoid.Health <= 0 or not root then return end

        local moving = humanoid.MoveDirection.Magnitude > 0.05
        local grounded = humanoid.FloorMaterial ~= Enum.Material.Air

        if not moving or not grounded then
            return
        end

        local t = os.clock()
        local interval = mode == "POOLROOMS" and 0.31 or 0.34

        if mode == "HABITABLE" then
            interval = 0.33
        end

        if t - lastStep >= interval then
            lastStep = t
            local id = IDS.BackroomsFootstep
            if mode == "POOLROOMS" then
                id = IDS.PoolFootstep
            end

            local s = Instance.new("Sound")
            s.SoundId = "rbxassetid://" .. tostring(id)
            s.Volume = CONFIG.Footsteps.Volume
            s.PlaybackSpeed = rFloat(0.92, 1.06)
            s.Parent = root
            s:Play()
            s.Ended:Connect(function()
                s:Destroy()
            end)
        end
    end)
end

--// Camera bob
local function updateCameraBob(dt)
    if not humanoid or humanoid.Health <= 0 then return end
    if mode == "NORMAL" then
        humanoid.CameraOffset = humanoid.CameraOffset:Lerp(Vector3.zero, 0.18)
        return
    end

    local moving = humanoid.MoveDirection.Magnitude > 0.05
    local grounded = humanoid.FloorMaterial ~= Enum.Material.Air

    if moving and grounded then
        bobTime += dt * CONFIG.CameraBob.Speed * math.clamp(humanoid.WalkSpeed / 16, 0.7, 1.4)
        local y = math.sin(bobTime) * CONFIG.CameraBob.Amount
        local x = math.cos(bobTime * 0.5) * (CONFIG.CameraBob.Amount * 0.5)
        humanoid.CameraOffset = humanoid.CameraOffset:Lerp(Vector3.new(x, y, 0), 0.18)

        camera.CFrame = camera.CFrame * CFrame.Angles(
            0,
            0,
            math.rad(math.sin(bobTime * 0.7) * CONFIG.CameraBob.Roll * 0.055)
        )
    else
        humanoid.CameraOffset = humanoid.CameraOffset:Lerp(Vector3.zero, 0.11)
    end
end

--// Lighting
local function saveLighting()
    savedLighting = {
        ClockTime = Lighting.ClockTime,
        Brightness = Lighting.Brightness,
        ExposureCompensation = Lighting.ExposureCompensation,
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart,
        ColorShift_Top = Lighting.ColorShift_Top,
        ColorShift_Bottom = Lighting.ColorShift_Bottom,
    }
end

local function applyModeLighting()
    saveLighting()

    if mode == "NORMAL" then
        for k, v in pairs(savedLighting) do
            Lighting[k] = v
        end
        setVHS(false)
        return
    end

    Lighting.Brightness = 0.75
    Lighting.ExposureCompensation = -0.9
    Lighting.Ambient = Color3.fromRGB(104, 98, 78)
    Lighting.OutdoorAmbient = Color3.fromRGB(80, 76, 64)
    Lighting.FogStart = 180
    Lighting.FogEnd = 900
    Lighting.ColorShift_Top = Color3.fromRGB(255, 243, 202)
    Lighting.ColorShift_Bottom = Color3.fromRGB(90, 85, 69)
    setVHS(true, false)
end

--// Door / house / chair helpers
local function findTemplate(name)
    return ReplicatedStorage:FindFirstChild(name, true)
end

local function cloneAnchoredTemplate(name, pivot, scaleFactor, parent)
    local template = findTemplate(name)
    if not template or not template:IsA("Model") then
        return nil
    end

    local clone = template:Clone()
    clone.Name = name .. "_ClientClone"
    clone.Parent = parent

    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
            d:Destroy()
        elseif d:IsA("BasePart") then
            d.Anchored = true
        elseif d:IsA("Sound") then
            d:Destroy()
        end
    end

    pcall(function()
        clone:ScaleTo(scaleFactor or 1)
    end)

    pcall(function()
        clone:PivotTo(pivot)
    end)

    return clone
end

local function proceduralChair(parent, cf, scale)
    local model = Instance.new("Model")
    model.Name = "Chair_WeirdProp"
    model.Parent = parent

    scale = scale or 1
    local wood = Color3.fromRGB(91, 75, 55)

    local seat = makePart(
        "Seat",
        Vector3.new(2.8, 0.4, 2.8) * scale,
        cf * CFrame.new(0, 2.25 * scale, 0),
        Enum.Material.Wood,
        wood,
        model
    )

    local back = makePart(
        "Back",
        Vector3.new(2.7, 3.6, 0.38) * scale,
        cf * CFrame.new(0, 4.0 * scale, 1.2 * scale),
        Enum.Material.Wood,
        wood,
        model
    )

    for x = -1, 1, 2 do
        for z = -1, 1, 2 do
            makePart(
                "Leg",
                Vector3.new(0.34, 2.25, 0.34) * scale,
                cf * CFrame.new(x * 1.0 * scale, 1.12 * scale, z * 0.95 * scale),
                Enum.Material.Wood,
                wood,
                model
            )
        end
    end

    return model
end

local function proceduralHouse(parent, origin)
    local m = Instance.new("Model")
    m.Name = "HabitableHouse"
    m.Parent = parent

    local w, d, h = 52, 44, 18
    local c = Color3.fromRGB(108, 104, 93)

    makePart("HouseFloor", Vector3.new(w, 1, d), CFrame.new(origin.X, origin.Y, origin.Z),
        Enum.Material.Concrete, Color3.fromRGB(83, 81, 75), m)

    makePart("BackWall", Vector3.new(w, h, 2), CFrame.new(origin.X, origin.Y + h/2, origin.Z + d/2),
        Enum.Material.Concrete, c, m)

    makePart("LeftWall", Vector3.new(2, h, d), CFrame.new(origin.X - w/2, origin.Y + h/2, origin.Z),
        Enum.Material.Concrete, c, m)

    makePart("RightWall", Vector3.new(2, h, d), CFrame.new(origin.X + w/2, origin.Y + h/2, origin.Z),
        Enum.Material.Concrete, c, m)

    makePart("FrontWallA", Vector3.new(18, h, 2), CFrame.new(origin.X - 17, origin.Y + h/2, origin.Z - d/2),
        Enum.Material.Concrete, c, m)

    makePart("FrontWallB", Vector3.new(18, h, 2), CFrame.new(origin.X + 17, origin.Y + h/2, origin.Z - d/2),
        Enum.Material.Concrete, c, m)

    makePart("FrontHeader", Vector3.new(16, 5.5, 2), CFrame.new(origin.X, origin.Y + h - 2.75, origin.Z - d/2),
        Enum.Material.Concrete, c, m)

    for i = 1, 4 do
        makePart("InteriorWall" .. i, Vector3.new(1.2, h, 8), CFrame.new(
            origin.X + rFloat(-18, 18), origin.Y + h/2, origin.Z + rFloat(-12, 12)
        ), Enum.Material.Concrete, Color3.fromRGB(98, 95, 87), m)
    end

    for i = 1, rInt(2, 6) do
        addPuddle(m, CFrame.new(
            origin.X + rFloat(-w/2 + 4, w/2 - 4),
            origin.Y + 0.55,
            origin.Z + rFloat(-d/2 + 4, d/2 - 4)
        ), Vector3.new(rFloat(3, 10), 0, rFloat(2, 7)))
    end

    return m
end

local function makeDoor(parent, cf, callback)
    local template = cloneAnchoredTemplate("DoorTemplate", cf, rFloat(0.95, 1.05), parent)

    if template then
        currentDoor = template
    else
        currentDoor = Instance.new("Model")
        currentDoor.Name = "DoorTemplate_Fallback"
        currentDoor.Parent = parent

        makePart("Door", Vector3.new(5, 9, 1),
            cf * CFrame.new(0, 4.5, 0),
            Enum.Material.Metal,
            Color3.fromRGB(66, 66, 62),
            currentDoor)

        makePart("FrameL", Vector3.new(0.5, 10, 1.2),
            cf * CFrame.new(-2.75, 5, 0),
            Enum.Material.Concrete,
            Color3.fromRGB(94, 92, 84),
            currentDoor)

        makePart("FrameR", Vector3.new(0.5, 10, 1.2),
            cf * CFrame.new(2.75, 5, 0),
            Enum.Material.Concrete,
            Color3.fromRGB(94, 92, 84),
            currentDoor)
    end

    local basePart = currentDoor:FindFirstChildWhichIsA("BasePart", true)
    if basePart then
        local prompt = Instance.new("ProximityPrompt")
        prompt.ActionText = "Open Door"
        prompt.ObjectText = "Door"
        prompt.HoldDuration = 0.15
        prompt.MaxActivationDistance = 9
        prompt.RequiresLineOfSight = false
        prompt.Parent = basePart

        prompt.Triggered:Connect(function()
            playOneShot(IDS.DoorOpen, 1.1)
            if callback then callback() end
        end)
    end

    return currentDoor
end

local function proceduralEscalator(parent, baseCF)
    local model = Instance.new("Model")
    model.Name = "EscalatorToExposedFloor"
    model.Parent = parent

    local base = baseCF
    for i = 1, 18 do
        local step = makePart(
            "Step",
            Vector3.new(6.6, 0.45, 1.45),
            base * CFrame.new(0, i * 0.48, i * -1.2),
            Enum.Material.Metal,
            Color3.fromRGB(194, 183, 118),
            model
        )
        step.CanCollide = true
    end

    makePart("SideL", Vector3.new(0.35, 10, 23),
        base * CFrame.new(-3.35, 4.3, -10),
        Enum.Material.Metal, Color3.fromRGB(159, 153, 121), model)

    makePart("SideR", Vector3.new(0.35, 10, 23),
        base * CFrame.new(3.35, 4.3, -10),
        Enum.Material.Metal, Color3.fromRGB(159, 153, 121), model)

    return model
end

--// Copy grouped models from Workspace
local function copyWorkspaceModels(parent, origin)
    local candidates = {}

    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Model")
            and child ~= character
            and child ~= worldFolder
            and child.Name ~= "ClientBackroomsWorld"
        then
            local hasParts = child:FindFirstChildWhichIsA("BasePart", true)
            local primary = child.PrimaryPart or hasParts

            if primary then
                table.insert(candidates, child)
            end
        end
    end

    if #candidates == 0 then
        return
    end

    local count = math.min(#candidates, rInt(1, math.min(4, #candidates)))

    for i = 1, count do
        local src = candidates[rInt(1, #candidates)]
        local clone = src:Clone()
        clone.Parent = parent

        local baseScale = rFloat(0.65, 1.3)
        if chance(0.18) then
            baseScale = rFloat(1.7, 3.0)
        elseif chance(0.15) then
            baseScale = rFloat(0.35, 0.6)
        end

        for _, d in ipairs(clone:GetDescendants()) do
            if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
                d:Destroy()
            elseif d:IsA("Sound") then
                d:Destroy()
            elseif d:IsA("BasePart") then
                d.Anchored = true
            end
        end

        pcall(function()
            clone:ScaleTo(baseScale)
        end)

        local offset = Vector3.new(
            rFloat(-22, 22),
            rFloat(-2.5, 10),
            rFloat(-22, 22)
        )

        -- Deliberately allow occasional wall/ground clipping.
        pcall(function()
            clone:PivotTo(CFrame.new(origin + offset) * CFrame.Angles(
                math.rad(rInt(-8, 8)),
                math.rad(rInt(0, 359)),
                math.rad(rInt(-8, 8))
            ))
        end)
    end
end

--// Wall/room builders
local function backWall(parent, center, z, width)
    local p = makePart(
        "BackroomsWall",
        Vector3.new(width, CONFIG.Backrooms.WallHeight, CONFIG.Backrooms.Wall),
        CFrame.new(center.X, CONFIG.Backrooms.WallHeight/2, z),
        Enum.Material.Concrete,
        Color3.fromRGB(204, 193, 118),
        parent
    )
    addTexture(p, IDS.WallTexture, Enum.NormalId.Front, 6, 5, Color3.fromRGB(255, 221, 120))
    addTexture(p, IDS.WallTexture, Enum.NormalId.Back, 6, 5, Color3.fromRGB(255, 221, 120))
    return p
end

local function sideWall(parent, x, center, depth)
    local p = makePart(
        "BackroomsWall",
        Vector3.new(CONFIG.Backrooms.Wall, CONFIG.Backrooms.WallHeight, depth),
        CFrame.new(x, CONFIG.Backrooms.WallHeight/2, center.Z),
        Enum.Material.Concrete,
        Color3.fromRGB(201, 190, 114),
        parent
    )
    addTexture(p, IDS.WallTexture, Enum.NormalId.Left, 5, 5, Color3.fromRGB(255, 220, 120))
    addTexture(p, IDS.WallTexture, Enum.NormalId.Right, 5, 5, Color3.fromRGB(255, 220, 120))
    return p
end

local function buildBackroomsRoom(parent, center, openRoom)
    local size = CONFIG.Backrooms.RoomSize
    local wall = CONFIG.Backrooms.Wall
    local h = CONFIG.Backrooms.WallHeight

    local makeHole = chance(CONFIG.Backrooms.HoleChance)
    local holeSize = makeHole and rFloat(5, 10) or 0

    if makeHole then
        local half = size / 2
        local hh = holeSize / 2

        makePart("BackroomsFloor_N",
            Vector3.new(size, CONFIG.Backrooms.FloorThickness, half - hh),
            CFrame.new(center.X, -0.6, center.Z - (half + hh) / 2),
            Enum.Material.SmoothPlastic,
            Color3.fromRGB(116, 110, 83),
            parent)

        makePart("BackroomsFloor_S",
            Vector3.new(size, CONFIG.Backrooms.FloorThickness, half - hh),
            CFrame.new(center.X, -0.6, center.Z + (half + hh) / 2),
            Enum.Material.SmoothPlastic,
            Color3.fromRGB(116, 110, 83),
            parent)

        makePart("BackroomsFloor_W",
            Vector3.new(half - hh, CONFIG.Backrooms.FloorThickness, holeSize),
            CFrame.new(center.X - (half + hh) / 2, -0.6, center.Z),
            Enum.Material.SmoothPlastic,
            Color3.fromRGB(116, 110, 83),
            parent)

        makePart("BackroomsFloor_E",
            Vector3.new(half - hh, CONFIG.Backrooms.FloorThickness, holeSize),
            CFrame.new(center.X + (half + hh) / 2, -0.6, center.Z),
            Enum.Material.SmoothPlastic,
            Color3.fromRGB(116, 110, 83),
            parent)

        local holeVisual = makePart(
            "SquareHole",
            Vector3.new(holeSize, 0.2, holeSize),
            CFrame.new(center.X, -1.8, center.Z),
            Enum.Material.SmoothPlastic,
            Color3.fromRGB(9, 9, 9),
            parent,
            0
        )
        holeVisual.CanCollide = false
    else
        makePart("BackroomsFloor",
            Vector3.new(size, CONFIG.Backrooms.FloorThickness, size),
            CFrame.new(center.X, -0.6, center.Z),
            Enum.Material.SmoothPlastic,
            Color3.fromRGB(116, 110, 83),
            parent)
    end

    local carpet = makePart("CarpetPatch",
        Vector3.new(size - 7, 0.12, size - 7),
        CFrame.new(center.X, 0.07, center.Z),
        Enum.Material.SmoothPlastic,
        Color3.fromRGB(145, 132, 79),
        parent,
        0.03)
    carpet.CanCollide = false

    -- Avoid overlapping full walls when a room is intentionally open.
    if openRoom then
        if chance(0.55) then backWall(parent, center, center.Z + size/2, size) end
        if chance(0.55) then sideWall(parent, center.X - size/2, center, size) end
    else
        if not chance(0.18) then backWall(parent, center, center.Z - size/2, size) end
        if not chance(0.18) then backWall(parent, center, center.Z + size/2, size) end
        if not chance(0.18) then sideWall(parent, center.X - size/2, center, size) end
        if not chance(0.18) then sideWall(parent, center.X + size/2, center, size) end
    end

    local ceiling = makePart("BackroomsCeiling",
        Vector3.new(size, 1.1, size),
        CFrame.new(center.X, CONFIG.Backrooms.CeilingHeight, center.Z),
        Enum.Material.Concrete,
        Color3.fromRGB(160, 156, 135),
        parent)

    addCeilingPipes(parent, center + Vector3.new(0, CONFIG.Backrooms.CeilingHeight, 0), size)

    local lightCount = openRoom and rInt(2, 4) or rInt(1, 2)
    for i = 1, lightCount do
        local lx = center.X + ((i - (lightCount + 1)/2) * (size / math.max(lightCount, 1)))
        local lightOff = chance(CONFIG.Backrooms.DimLightChance)
        addSquareLight(
            parent,
            CFrame.new(lx, CONFIG.Backrooms.CeilingHeight - 0.6, center.Z + rFloat(-10, 10)),
            lightOff and rFloat(0.3, 0.65) or rFloat(0.65, 1.25),
            lightOff and 24 or 34,
            not lightOff
        )
    end

    if chance(CONFIG.Backrooms.ChairChance) then
        local cp = center + Vector3.new(rFloat(-16, 16), 0, rFloat(-16, 16))
        local weird = chance(0.28)
        local cf = CFrame.new(cp.X, weird and -1.0 or 0, cp.Z)
        local cloned = cloneAnchoredTemplate("ChairTemplate", cf, rFloat(0.75, 1.5), parent)
        if not cloned then
            proceduralChair(parent, cf, rFloat(0.75, 1.45))
        end
    end

    if chance(0.08) then
        copyWorkspaceModels(parent, center)
    end

    return {
        center = center,
        size = size,
    }
end

local function buildTallRoom(parent, center)
    local roomW = 96
    local roomD = 96
    local floorHeight = 18

    for level = 0, 4 do
        local y = level * floorHeight

        makePart(
            "TallFloor" .. level,
            Vector3.new(roomW, 1, roomD),
            CFrame.new(center.X, y, center.Z),
            Enum.Material.SmoothPlastic,
            Color3.fromRGB(112, 108, 84),
            parent
        )

        if level < 4 then
            for i = 1, rInt(2, 5) do
                addSquareLight(
                    parent,
                    CFrame.new(
                        center.X + rFloat(-30, 30),
                        y + 16.5,
                        center.Z + rFloat(-30, 30)
                    ),
                    rFloat(0.32, 0.9),
                    30,
                    chance(0.75)
                )
            end
        end
    end

    -- No safety railings by design: falling is possible.
    for i = 1, 8 do
        local x = center.X - roomW/2 + (i - 0.5) * (roomW/8)
        backWall(parent, center, x * 0 + center.Z + roomD/2, roomW)
        break
    end

    for i = 0, 4 do
        local y = i * floorHeight + 8
        if chance(0.7) then
            makePart(
                "TallRoomSupport",
                Vector3.new(1.8, 16, 1.8),
                CFrame.new(center.X + roomW/2 - 2, y, center.Z + roomD/2 - 2),
                Enum.Material.Concrete,
                Color3.fromRGB(103, 100, 86),
                parent
            )
        end
    end

    if chance(0.45) then
        proceduralEscalator(parent, CFrame.new(center.X - 17, 0, center.Z + 28))
    end
end

--// PoolRooms
local function poolWall(parent, size, cf)
    local wall = makePart(
        "PoolWall",
        size,
        cf,
        Enum.Material.Concrete,
        Color3.fromRGB(212, 215, 209),
        parent
    )
    addTexture(wall, IDS.PoolTexture, Enum.NormalId.Front, 6, 6, Color3.fromRGB(216, 218, 213))
    return wall
end

local function buildPoolRoom(parent, center)
    local size = CONFIG.PoolRooms.RoomSize
    local h = CONFIG.PoolRooms.WallHeight
    local waterDepth = 4.2

    -- Floor slabs around the pool
    makePart("PoolFloor",
        Vector3.new(size, 1, size),
        CFrame.new(center.X, -0.6, center.Z),
        Enum.Material.SmoothPlastic,
        Color3.fromRGB(192, 201, 198),
        parent)

    local poolW = rFloat(20, 32)
    local poolD = rFloat(20, 32)
    local poolX = center.X + rFloat(-5, 5)
    local poolZ = center.Z + rFloat(-5, 5)

    -- Pool floor
    makePart("PoolBottom",
        Vector3.new(poolW, 1, poolD),
        CFrame.new(poolX, -waterDepth, poolZ),
        Enum.Material.SmoothPlastic,
        Color3.fromRGB(143, 184, 187),
        parent)

    -- Water
    local water = makePart(
        "RealisticWater",
        Vector3.new(poolW - 1, waterDepth, poolD - 1),
        CFrame.new(poolX, -waterDepth/2 + 0.25, poolZ),
        Enum.Material.Water,
        Color3.fromRGB(75, 147, 154),
        parent,
        0.08
    )
    water.CanCollide = false
    water.CastShadow = false
    water.Reflectance = 0.15

    local waterVolume = makePart(
        "WaterVolume",
        Vector3.new(poolW - 2, waterDepth + 1, poolD - 2),
        CFrame.new(poolX, -waterDepth/2 + 0.4, poolZ),
        Enum.Material.SmoothPlastic,
        Color3.fromRGB(20, 80, 90),
        parent,
        1
    )
    waterVolume.CanCollide = false
    waterVolume.CanTouch = true

    if chance(CONFIG.PoolRooms.WindowChance) then
        for side = -1, 1, 2 do
            local window = makePart(
                "UnnecessaryWindow",
                Vector3.new(10, 7, 0.35),
                CFrame.new(center.X + side * (size/2 - 0.2), 6.6, center.Z + rFloat(-10, 10)),
                Enum.Material.Glass,
                Color3.fromRGB(186, 192, 188),
                parent,
                0.5
            )
            window.CanCollide = false

            makePart(
                "GlowingWindowTrim",
                Vector3.new(10.8, 7.6, 0.18),
                CFrame.new(center.X + side * (size/2 - 0.35), 6.6, center.Z + window.Position.Z - center.Z),
                Enum.Material.Neon,
                Color3.fromRGB(222, 229, 225),
                parent,
                0.08
            )
        end
    end

    -- Full square ceiling light style, but kept dim.
    for i = 1, rInt(1, 3) do
        addSquareLight(
            parent,
            CFrame.new(center.X + rFloat(-13, 13), h - 0.6, center.Z + rFloat(-13, 13)),
            rFloat(0.25, 0.55),
            25,
            true
        )
    end

    poolWall(parent, Vector3.new(size, h, 2.2),
        CFrame.new(center.X, h/2, center.Z - size/2))
    poolWall(parent, Vector3.new(size, h, 2.2),
        CFrame.new(center.X, h/2, center.Z + size/2))
    poolWall(parent, Vector3.new(2.2, h, size),
        CFrame.new(center.X - size/2, h/2, center.Z))
    poolWall(parent, Vector3.new(2.2, h, size),
        CFrame.new(center.X + size/2, h/2, center.Z))

    -- Liminal tunnel opening
    if chance(CONFIG.PoolRooms.TunnelChance) then
        local tunnelX = center.X + rFloat(-12, 12)
        local tunnelZ = center.Z - size/2 - 5
        makePart("TunnelFloor", Vector3.new(13, 1, 34),
            CFrame.new(tunnelX, -0.6, tunnelZ - 17),
            Enum.Material.SmoothPlastic,
            Color3.fromRGB(188, 194, 190),
            parent)
        poolWall(parent, Vector3.new(2.2, h, 34),
            CFrame.new(tunnelX - 6.5, h/2, tunnelZ - 17))
        poolWall(parent, Vector3.new(2.2, h, 34),
            CFrame.new(tunnelX + 6.5, h/2, tunnelZ - 17))
        poolWall(parent, Vector3.new(13, h, 2.2),
            CFrame.new(tunnelX, h/2, tunnelZ - 34))
    end

    -- Very deep open shaft; no barrier.
    if chance(CONFIG.PoolRooms.DeepShaftChance) then
        local shaftW = 14
        local shaftD = 14
        makePart("DeepShaftDark",
            Vector3.new(shaftW, 0.2, shaftD),
            CFrame.new(center.X + 15, -42, center.Z + 14),
            Enum.Material.SmoothPlastic,
            Color3.fromRGB(6, 9, 11),
            parent)
        makePart("ShaftWater",
            Vector3.new(shaftW - 1, 2.5, shaftD - 1),
            CFrame.new(center.X + 15, -43, center.Z + 14),
            Enum.Material.Water,
            Color3.fromRGB(41, 92, 100),
            parent,
            0.15).CanCollide = false
    end

    return waterVolume
end

--// Habitable Zone
local function buildHabitableChunk(parent, center)
    local size = 180
    local roadY = 0

    makePart("GarageFloor",
        Vector3.new(size, 1, size),
        CFrame.new(center.X, roadY - 0.5, center.Z),
        Enum.Material.Concrete,
        Color3.fromRGB(72, 72, 67),
        parent)

    -- Roads / lane strips
    for z = -60, 60, 30 do
        makePart("RoadStrip",
            Vector3.new(size - 25, 0.08, 1.1),
            CFrame.new(center.X, 0.03, center.Z + z),
            Enum.Material.SmoothPlastic,
            Color3.fromRGB(119, 116, 104),
            parent,
            0.08)
    end

    for x = -60, 60, 30 do
        makePart("RoadStrip2",
            Vector3.new(1.1, 0.08, size - 25),
            CFrame.new(center.X + x, 0.04, center.Z),
            Enum.Material.SmoothPlastic,
            Color3.fromRGB(112, 109, 99),
            parent,
            0.12)
    end

    for i = 1, 5 do
        makePart("GarageColumn",
            Vector3.new(5, 18, 5),
            CFrame.new(center.X + rFloat(-65, 65), 9, center.Z + rFloat(-65, 65)),
            Enum.Material.Concrete,
            Color3.fromRGB(91, 90, 86),
            parent)
    end

    for i = 1, rInt(4, 10) do
        addPuddle(parent,
            CFrame.new(center.X + rFloat(-68, 68), 0.08, center.Z + rFloat(-68, 68)),
            Vector3.new(rFloat(3, 18), 0, rFloat(2, 10)))
    end

    for i = 1, rInt(5, 12) do
        addSquareLight(
            parent,
            CFrame.new(center.X + rFloat(-65, 65), 17.2, center.Z + rFloat(-65, 65)),
            rFloat(0.35, 0.7),
            30,
            true
        )
    end

    local prop = cloneAnchoredTemplate(
        "HabitablePropTemplate",
        CFrame.new(center.X + rFloat(-25, 25), 0, center.Z + rFloat(-25, 25)),
        rFloat(0.8, 1.5),
        parent
    )

    if not prop then
        for i = 1, rInt(1, 4) do
            makePart("AbandonedGarageObject",
                Vector3.new(rFloat(3, 8), rFloat(2, 5), rFloat(2, 7)),
                CFrame.new(
                    center.X + rFloat(-55, 55),
                    rFloat(1, 3),
                    center.Z + rFloat(-55, 55)
                ) * CFrame.Angles(
                    math.rad(rInt(-12, 12)),
                    math.rad(rInt(0, 359)),
                    math.rad(rInt(-12, 12))
                ),
                Enum.Material.Metal,
                Color3.fromRGB(72, 70, 65),
                parent)
        end
    end

    return true
end

--// Chunk keys
local function key(x, z)
    return tostring(x) .. ":" .. tostring(z)
end

local function coordsFromKey(k)
    local a, b = string.match(k, "([^:]+):([^:]+)")
    return tonumber(a), tonumber(b)
end

local function chunkCenter(cx, cz, chunkSize)
    return Vector3.new(cx * chunkSize, 0, cz * chunkSize)
end

--// Build one Backrooms chunk
local function generateBackroomsChunk(cx, cz)
    local k = "B:" .. key(cx, cz)
    if generated[k] then return end
    generated[k] = true
    generatedType[k] = "BACKROOMS"

    local folder = Instance.new("Folder")
    folder.Name = "Backrooms_" .. key(cx, cz)
    folder.Parent = worldFolder

    local center = chunkCenter(cx, cz, CONFIG.Backrooms.ChunkSize)

    local huge = chance(CONFIG.Backrooms.BigRoomChance)
    if huge then
        buildTallRoom(folder, center)
    else
        local rows = huge and 1 or 3
        local cols = huge and 1 or 3
        local step = CONFIG.Backrooms.RoomSize + 3

        for x = 1, cols do
            for z = 1, rows do
                local open = chance(CONFIG.Backrooms.OpenRoomChance)
                local c = center + Vector3.new(
                    (x - (cols+1)/2) * step,
                    0,
                    (z - (rows+1)/2) * step
                )

                buildBackroomsRoom(folder, c, open)

                -- Extra partition pieces create a maze feel without duplicating the floor.
                if chance(0.34) then
                    if chance(0.5) then
                        makePart("MazePartition",
                            Vector3.new(rFloat(8, 20), CONFIG.Backrooms.WallHeight, CONFIG.Backrooms.Wall),
                            CFrame.new(c.X + rFloat(-12, 12), CONFIG.Backrooms.WallHeight/2, c.Z + rFloat(-9, 9)),
                            Enum.Material.Concrete,
                            Color3.fromRGB(194, 183, 110),
                            folder)
                    else
                        makePart("MazePartition",
                            Vector3.new(CONFIG.Backrooms.Wall, CONFIG.Backrooms.WallHeight, rFloat(8, 20)),
                            CFrame.new(c.X + rFloat(-9, 9), CONFIG.Backrooms.WallHeight/2, c.Z + rFloat(-12, 12)),
                            Enum.Material.Concrete,
                            Color3.fromRGB(194, 183, 110),
                            folder)
                    end
                end
            end
        end
    end

    -- House chance
    if chance(CONFIG.Backrooms.HouseChance) then
        local housePos = center + Vector3.new(rFloat(-32, 32), 0, rFloat(-32, 32))
        local house = cloneAnchoredTemplate("HouseTemplate", CFrame.new(housePos), rFloat(0.9, 1.15), folder)
        if not house then
            proceduralHouse(folder, housePos)
        end
    end

    -- Escalator chance
    if chance(0.08) and not huge then
        proceduralEscalator(folder, CFrame.new(center.X + 34, 0, center.Z - 38))
    end

    -- Arrow toward future PoolRooms
    if poolDiscovered and chance(0.12) then
        local arrowPart = makePart(
            "PoolArrowSign",
            Vector3.new(5.5, 3.4, 0.35),
            CFrame.new(center.X + rFloat(-30, 30), 4, center.Z + rFloat(-30, 30)),
            Enum.Material.Wood,
            Color3.fromRGB(178, 164, 112),
            folder
        )

        local sg = Instance.new("SurfaceGui")
        sg.Face = Enum.NormalId.Front
        sg.Parent = arrowPart

        local tl = Instance.new("TextLabel")
        tl.BackgroundTransparency = 1
        tl.Size = UDim2.fromScale(1, 1)
        tl.Text = "→ POOLROOMS"
        tl.Font = Enum.Font.Arcade
        tl.TextScaled = true
        tl.TextColor3 = Color3.fromRGB(215, 230, 220)
        tl.Parent = sg
    end

    -- Door leading to Habitable Zone
    if chance(0.025) then
        local doorPos = center + Vector3.new(
            rFloat(-35, 35),
            0,
            rFloat(-35, 35)
        )

        makeDoor(folder, CFrame.new(doorPos) * CFrame.Angles(0, math.rad(90), 0), function()
            enterHabitableZone()
        end)
    end

    return folder
end

--// PoolRooms chunk
local function generatePoolChunk(cx, cz)
    local k = "P:" .. key(cx, cz)
    if generated[k] then return end
    generated[k] = true
    generatedType[k] = "POOLROOMS"

    local folder = Instance.new("Folder")
    folder.Name = "PoolRooms_" .. key(cx, cz)
    folder.Parent = worldFolder

    local center = chunkCenter(cx, cz, CONFIG.PoolRooms.ChunkSize)
    local rows = chance(CONFIG.PoolRooms.OpenRoomChance) and 2 or 3
    local cols = 2
    local step = CONFIG.PoolRooms.RoomSize + 4

    for x = 1, cols do
        for z = 1, rows do
            local c = center + Vector3.new(
                (x - (cols+1)/2) * step,
                0,
                (z - (rows+1)/2) * step
            )
            local volume = buildPoolRoom(folder, c)
            if volume then
                table.insert(waterVolumes, volume)
            end
        end
    end

    return folder
end

--// Pool discovery
local function attemptPoolDiscovery(cx, cz)
    if poolDiscovered then return end
    if not firstPoolAttemptDone and math.abs(cx) + math.abs(cz) < 2 then
        return
    end

    firstPoolAttemptDone = true

    if chance(CONFIG.Backrooms.PoolChance) then
        poolDiscovered = true

        -- The actual PoolRooms are generated on demand near a doorway/threshold
        -- rather than spawning in the starting chunk.
        local px = cx + rInt(-1, 1)
        local pz = cz + rInt(-1, 1)

        generatePoolChunk(px, pz)
        generatePoolChunk(px + 1, pz)
        generatePoolChunk(px - 1, pz)
    end
end

--// Mode UI
local function buildStatusGui()
    if statusGui then statusGui:Destroy() end

    statusGui = Instance.new("ScreenGui")
    statusGui.Name = "ZoneStatus"
    statusGui.IgnoreGuiInset = true
    statusGui.ResetOnSpawn = false
    statusGui.DisplayOrder = 150
    statusGui.Parent = player.PlayerGui

    local label = pixelText("", UDim2.fromScale(0.6, 0.085), UDim2.fromScale(0.5, 0.1), 1)
    label.TextColor3 = Color3.fromRGB(225, 225, 210)
    label.Parent = statusGui

    return label
end

local statusLabel = buildStatusGui()

local function zoneMessage(text)
    if not statusLabel then return end
    statusLabel.Text = text
    statusLabel.Position = UDim2.fromScale(0.58, 0.1)
    statusLabel.TextTransparency = 1

    TweenService:Create(
        statusLabel,
        TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {
            Position = UDim2.fromScale(0.5, 0.1),
            TextTransparency = 0
        }
    ):Play()

    task.delay(2.3, function()
        if statusLabel and statusLabel.Parent then
            TweenService:Create(
                statusLabel,
                TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
                {
                    Position = UDim2.fromScale(0.42, 0.1),
                    TextTransparency = 1
                }
            ):Play()
        end
    end)
end

--// Initial loaded message
local function initialMessage()
    zoneMessage("Backrooms Has Been Loaded. Goodluck Wanderer")
end

--// Water swimming simulation
local waterVolumes = {}

local function updateSwimming()
    if not root or not humanoid then return end
    if mode ~= "POOLROOMS" then return end

    local pos = root.Position

    for _, volume in ipairs(waterVolumes) do
        if volume and volume.Parent then
            local lp = volume.CFrame:PointToObjectSpace(pos)
            local half = volume.Size / 2

            if math.abs(lp.X) <= half.X
                and math.abs(lp.Y) <= half.Y
                and math.abs(lp.Z) <= half.Z
            then
                humanoid:ChangeState(Enum.HumanoidStateType.Swimming)

                -- Gentle buoyancy. No barriers are created around the pool.
                local currentY = root.AssemblyLinearVelocity.Y
                local surfaceY = volume.Position.Y + volume.Size.Y * 0.42
                local desired = math.clamp((surfaceY - pos.Y) * 3.0, -7, 10)

                root.AssemblyLinearVelocity = Vector3.new(
                    root.AssemblyLinearVelocity.X * 0.88,
                    currentY * 0.35 + desired,
                    root.AssemblyLinearVelocity.Z * 0.88
                )

                break
            end
        end
    end
end

--// Habitable transition
function enterHabitableZone()
    if transitioning then return end
    transitioning = true

    local oldMode = mode
    mode = "HABITABLE"

    flashlightOn = true
    if flashlight then flashlight.Enabled = true end

    if vhsGui then vhsGui:Destroy() end
    local black = buildVHSGui()
    black.BackgroundTransparency = 0

    setVHS(true, true)
    playOneShot(IDS.Transition, 0.9)

    if humanoid then humanoid.WalkSpeed = 0 end

    task.wait(2.2)

    local habText = pixelText(
        "Habitable Zone",
        UDim2.fromScale(0.7, 0.16),
        UDim2.fromScale(0.5, 0.5),
        0
    )
    habText.Parent = vhsGui

    task.wait(1.5)

    local spawn = Vector3.new(0, 5, 0)
    if root then
        root.CFrame = CFrame.new(spawn)
    end

    -- Wipe the streamed zone and build the garage.
    worldFolder:ClearAllChildren()
    table.clear(generated)
    table.clear(generatedType)
    table.clear(waterVolumes)

    local habFolder = Instance.new("Folder")
    habFolder.Name = "HabitableZone"
    habFolder.Parent = worldFolder

    buildHabitableChunk(habFolder, Vector3.zero)

    black.BackgroundTransparency = 1
    habText.TextTransparency = 1

    task.wait(0.05)
    vhsGui:Destroy()
    vhsGui = nil

    if humanoid then humanoid.WalkSpeed = 16 end

    applyModeLighting()
    startAmbience(IDS.BackroomsAmbience, 0.34)
    flashlightButton.Visible = true
    zoneMessage("HABITABLE ZONE")

    transitioning = false

    task.spawn(function()
        while mode == "HABITABLE" do
            task.wait(20)

            if mode ~= "HABITABLE" then break end

            -- Flicker phase
            local savedLights = {}

            for _, d in ipairs(worldFolder:GetDescendants()) do
                if d:IsA("SurfaceLight") or d:IsA("PointLight") or d:IsA("SpotLight") then
                    table.insert(savedLights, {d, d.Enabled})
                end
            end

            for i = 1, 16 do
                for _, pair in ipairs(savedLights) do
                    if pair[1] and pair[1].Parent then
                        pair[1].Enabled = chance(0.52)
                    end
                end
                task.wait(0.12 + rFloat(0, 0.09))
            end

            -- Full shutdown
            for _, pair in ipairs(savedLights) do
                if pair[1] and pair[1].Parent then
                    pair[1].Enabled = false
                end
            end

            playOneShot(IDS.HabitableBlackout, 1.0)
            habitableBlackoutActive = true

            task.wait(20)

            for _, pair in ipairs(savedLights) do
                if pair[1] and pair[1].Parent then
                    pair[1].Enabled = pair[2]
                end
            end

            habitableBlackoutActive = false
        end
    end)
end

--// Enter Backrooms
local function enterBackrooms()
    if transitioning then return end
    transitioning = true

    mode = "BACKROOMS"
    flashlightOn = false

    if flashlight then
        flashlight.Enabled = false
    end

    flashlightButton.Visible = true

    if humanoid then
        humanoid.WalkSpeed = 0
    end

    if vhsGui then
        vhsGui:Destroy()
    end

    local black = buildVHSGui()
    black.BackgroundTransparency = 0

    playOneShot(IDS.Transition, 1.0)
    setVHS(true, true)

    task.wait(3)

    transitionText(
        "BACKROOMS",
        0.48,
        vhsGui,
        3
    )

    transitionText(
        "Produced By Hecker",
        0.60,
        vhsGui,
        5
    )

    -- Generate starting area only after the title sequence.
    worldFolder:ClearAllChildren()
    table.clear(generated)
    table.clear(generatedType)
    table.clear(waterVolumes)

    local startFolder = Instance.new("Folder")
    startFolder.Name = "Backrooms_Start"
    startFolder.Parent = worldFolder

    generateBackroomsChunk(0, 0)

    if root then
        root.CFrame = CFrame.new(0, 3.4, 0)
    end

    task.wait(0.05)

    if vhsGui then
        vhsGui:Destroy()
        vhsGui = nil
    end

    if humanoid then humanoid.WalkSpeed = 16 end

    applyModeLighting()
    startAmbience(IDS.BackroomsAmbience, 0.48)
    zoneMessage("THE BACKROOMS")

    transitioning = false
    initialMessage()
end

--// Enter PoolRooms from an actual generated portal
local function enterPoolRooms()
    if transitioning then return end
    transitioning = true

    mode = "POOLROOMS"
    flashlightOn = false
    if flashlight then flashlight.Enabled = false end

    if humanoid then humanoid.WalkSpeed = 0 end

    if vhsGui then vhsGui:Destroy() end
    local black = buildVHSGui()
    black.BackgroundTransparency = 0

    playOneShot(IDS.Transition, 0.85)
    setVHS(true, true)

    task.wait(1.5)

    local text = pixelText(
        "The PoolRooms",
        UDim2.fromScale(0.72, 0.15),
        UDim2.fromScale(0.5, 0.5),
        0
    )
    text.Parent = vhsGui

    task.wait(1.6)

    worldFolder:ClearAllChildren()
    table.clear(generated)
    table.clear(generatedType)
    table.clear(waterVolumes)

    generatePoolChunk(0, 0)
    generatePoolChunk(1, 0)
    generatePoolChunk(0, 1)
    generatePoolChunk(-1, 0)

    if root then
        root.CFrame = CFrame.new(0, 3, 0)
    end

    task.wait(0.05)

    black.BackgroundTransparency = 1
    text.TextTransparency = 1

    task.wait(0.05)
    vhsGui:Destroy()
    vhsGui = nil

    if humanoid then humanoid.WalkSpeed = 16 end

    applyModeLighting()
    startAmbience(IDS.PoolAmbience, 0.5)
    flashlightButton.Visible = true
    zoneMessage("The PoolRooms")

    transitioning = false
end

--// Random pool entrance in Backrooms
local function makePoolEntrance(parent, center)
    local arch = Instance.new("Model")
    arch.Name = "PoolRoomsEntrance"
    arch.Parent = parent

    local c = Color3.fromRGB(174, 176, 165)

    makePart("PillarL", Vector3.new(2.5, 12, 2.5),
        CFrame.new(center.X - 7, 6, center.Z),
        Enum.Material.Concrete, c, arch)

    makePart("PillarR", Vector3.new(2.5, 12, 2.5),
        CFrame.new(center.X + 7, 6, center.Z),
        Enum.Material.Concrete, c, arch)

    makePart("ArchTop", Vector3.new(16.5, 2.5, 2.5),
        CFrame.new(center.X, 11.2, center.Z),
        Enum.Material.Concrete, c, arch)

    local promptPart = makePart(
        "PoolEntrancePrompt",
        Vector3.new(10, 9, 2),
        CFrame.new(center.X, 4.5, center.Z),
        Enum.Material.SmoothPlastic,
        Color3.fromRGB(220, 220, 220),
        arch,
        1
    )
    promptPart.CanCollide = false

    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Enter"
    prompt.ObjectText = "POOLROOMS"
    prompt.HoldDuration = 0.2
    prompt.MaxActivationDistance = 10
    prompt.RequiresLineOfSight = false
    prompt.Parent = promptPart

    prompt.Triggered:Connect(function()
        enterPoolRooms()
    end)

    return arch
end

--// Streaming generation
local function cleanupFarChunks(px, pz)
    local maxBack = CONFIG.Backrooms.RemoveRadius
    local maxPool = CONFIG.PoolRooms.RemoveRadius

    for k, folder in pairs(generated) do
        -- generated[k] is currently true; folder lookup is done by child name when needed.
    end

    for _, folder in ipairs(worldFolder:GetChildren()) do
        local name = folder.Name

        local kind, sx, sz = string.match(name, "^(Backrooms|PoolRooms)_([^:]+):([^:]+)$")
        if kind and sx and sz then
            local cx = tonumber(sx)
            local cz = tonumber(sz)

            if kind == "Backrooms" then
                if math.abs(cx - px) > maxBack or math.abs(cz - pz) > maxBack then
                    generated["B:" .. key(cx, cz)] = nil
                    generatedType["B:" .. key(cx, cz)] = nil
                    folder:Destroy()
                end
            else
                if math.abs(cx - px) > maxPool or math.abs(cz - pz) > maxPool then
                    generated["P:" .. key(cx, cz)] = nil
                    generatedType["P:" .. key(cx, cz)] = nil
                    folder:Destroy()
                end
            end
        end
    end
end

local function getCurrentChunk()
    if not root then return 0, 0 end

    if mode == "POOLROOMS" then
        return
            math.floor(root.Position.X / CONFIG.PoolRooms.ChunkSize + 0.5),
            math.floor(root.Position.Z / CONFIG.PoolRooms.ChunkSize + 0.5)
    else
        return
            math.floor(root.Position.X / CONFIG.Backrooms.ChunkSize + 0.5),
            math.floor(root.Position.Z / CONFIG.Backrooms.ChunkSize + 0.5)
    end
end

local function streamWorld()
    if transitioning or not root then return end
    if mode == "NORMAL" or mode == "HABITABLE" then return end

    local cx, cz = getCurrentChunk()

    if mode == "BACKROOMS" then
        for dx = -CONFIG.Backrooms.GenerateRadius, CONFIG.Backrooms.GenerateRadius do
            for dz = -CONFIG.Backrooms.GenerateRadius, CONFIG.Backrooms.GenerateRadius do
                generateBackroomsChunk(cx + dx, cz + dz)
            end
        end

        attemptPoolDiscovery(cx, cz)

        if poolDiscovered and not worldFolder:FindFirstChild("PoolRoomsEntranceCreated") then
            local folder = worldFolder:FindFirstChild("Backrooms_" .. key(cx, cz))
            if folder then
                local marker = Instance.new("BoolValue")
                marker.Name = "PoolRoomsEntranceCreated"
                marker.Parent = worldFolder

                makePoolEntrance(
                    folder,
                    chunkCenter(cx, cz, CONFIG.Backrooms.ChunkSize)
                        + Vector3.new(rFloat(-25, 25), 0, rFloat(-25, 25))
                )
            end
        end

        cleanupFarChunks(cx, cz)

    elseif mode == "POOLROOMS" then
        for dx = -CONFIG.PoolRooms.GenerateRadius, CONFIG.PoolRooms.GenerateRadius do
            for dz = -CONFIG.PoolRooms.GenerateRadius, CONFIG.PoolRooms.GenerateRadius do
                generatePoolChunk(cx + dx, cz + dz)
            end
        end

        cleanupFarChunks(cx, cz)
    end
end

--// Noclip chance
local lastNoclipTick = 0

local function tryFloorNoclip()
    if transitioning or not root or mode == "NORMAL" then return end
    if os.clock() - lastNoclipTick < 1 then return end

    lastNoclipTick = os.clock()

    if not chance(0.10) then
        return
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character, worldFolder}

    local hit = Workspace:Raycast(
        root.Position + Vector3.new(0, 2, 0),
        Vector3.new(0, -8, 0),
        params
    )

    if hit and hit.Instance and hit.Instance:IsA("BasePart") then
        local part = hit.Instance

        if part.CanCollide then
            local old = part.CanCollide
            part.CanCollide = false
            task.delay(0.7, function()
                if part and part.Parent then
                    part.CanCollide = old
                end
            end)

            enterBackrooms()
        end
    end
end

local function tryWallNoclip()
    if transitioning or not root or mode == "NORMAL" then return end
    if humanoid.MoveDirection.Magnitude < 0.2 then return end
    if not chance(0.50) then return end

    local direction = humanoid.MoveDirection.Unit
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character}

    local hit = Workspace:Raycast(
        root.Position + Vector3.new(0, 2.2, 0),
        direction * 2.4,
        params
    )

    if hit and hit.Instance and hit.Instance:IsA("BasePart") and hit.Instance.CanCollide then
        local wall = hit.Instance
        wall.CanCollide = false

        task.delay(0.55, function()
            if wall and wall.Parent then
                wall.CanCollide = true
            end
        end)

        enterBackrooms()
    end
end

--// Hazard-free local state updater
local function updateModeSpecific()
    if mode == "BACKROOMS" then
        -- Random brief light flickers in nearby lights.
        if chance(0.010) then
            task.spawn(function()
                local candidates = {}
                for _, d in ipairs(worldFolder:GetDescendants()) do
                    if d:IsA("SurfaceLight") then
                        table.insert(candidates, d)
                    end
                end

                if #candidates > 0 then
                    local chosen = candidates[rInt(1, #candidates)]
                    local was = chosen.Enabled
                    for _ = 1, rInt(12, 25) do
                        if chosen and chosen.Parent then
                            chosen.Enabled = not chosen.Enabled
                        end
                        task.wait(rFloat(0.06, 0.18))
                    end
                    if chosen and chosen.Parent then
                        chosen.Enabled = was
                    end
                end
            end)
        end

    elseif mode == "POOLROOMS" then
        updateSwimming()
    end
end

--// Hotkeys
player:GetMouse().KeyDown:Connect(function(keyPressed)
    if string.lower(keyPressed) == "f" then
        toggleFlashlight()
    end
end)

--// Start
applyModeLighting()
muteDefaultRunningSounds()
startFootsteps()

updateConn = RunService.RenderStepped:Connect(function(dt)
    updateCameraBob(dt)

    if mode ~= "NORMAL" then
        muteDefaultRunningSounds()
    end
end)

noclipConn = RunService.Heartbeat:Connect(function()
    if mode == "NORMAL" then
        -- 10% floor chance can start the whole experience.
        tryFloorNoclip()
        tryWallNoclip()
    elseif mode == "BACKROOMS" or mode == "POOLROOMS" then
        streamWorld()
        updateModeSpecific()
    end
end)

--// Small cleanup when player dies
humanoid.Died:Connect(function()
    transitioning = false
    stopAmbience()
    stopFootsteps()

    if flashlight then
        flashlight.Enabled = false
    end

    if statusGui then
        statusGui.Enabled = true
    end
end)

--// The script starts in the normal map. The first successful noclip begins the journey.
--// This matches the requested "every 1 second, 0.1 chance" behavior.
flashlightButton.Visible = false
loaded = true
