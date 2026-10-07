--[[
    BACKROOMS, POOLROOMS & HABITABLE ZONE (LEVEL 1) CLIENT-SIDE SCRIPT
    Compatible with Delta Executors (Luau)
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

-- Audio IDs provided
local SOUND_NOCLIP = 139682612041479
local SOUND_BACKROOMS_AMBIENT = 137406302438919
local SOUND_POOLROOMS_AMBIENT = 94241101968368
local SOUND_WALK_BACKROOMS = 89575970505811
local SOUND_WALK_POOLROOMS = 96516907071037
local SOUND_OPEN_DOOR = 125209584906878
local SOUND_FLASHLIGHT = 128570293170805
local SOUND_LIGHT_BLACKOUT = 78704114462031

-- Model & Texture IDs provided
local TEXTURE_BACKROOMS_WALL = "rbxassetid://11734753590"
local TEXTURE_POOLROOMS = "rbxassetid://11384971113"
local MODEL_CHAIR = 74698525718385
local MODEL_DOOR = 9343670755
local MODEL_LEVEL1_DOOR = 10225195309
local MODEL_ESCALATOR = 18861464725

-- States
local isInBackrooms = false
local isInPoolrooms = false
local isInHabitableZone = false
local flashlightOn = false

--------------------------------------------------------------------------------
-- UI SETUP (VHS, CRT, Text, Flashlight Button)
--------------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BackroomsUI"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = CoreGui

-- Black Screen / VHS Overlay
local blackScreen = Instance.new("Frame")
blackScreen.Name = "BlackScreen"
blackScreen.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
blackScreen.BackgroundTransparency = 1
blackScreen.Size = UDim2.new(1, 0, 1, 0)
blackScreen.Parent = screenGui

local vhsLines = Instance.new("Frame")
vhsLines.Name = "VHSEffect"
vhsLines.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
vhsLines.BackgroundTransparency = 0.92
vhsLines.Size = UDim2.new(1, 0, 1, 0)
vhsLines.Parent = blackScreen

-- Main Pixelated Text (Center)
local centerText = Instance.new("TextLabel")
centerText.Name = "CenterText"
centerText.AnchorPoint = Vector2.new(0.5, 0.5)
centerText.Position = UDim2.new(0.5, 0, 0.45, 0)
centerText.Size = UDim2.new(0.8, 0, 0.1, 0)
centerText.BackgroundTransparency = 1
centerText.Font = Enum.Font.Code
centerText.TextColor3 = Color3.fromRGB(220, 220, 200)
centerText.TextScaled = true
centerText.TextTransparency = 1
centerText.Parent = screenGui

-- Sub Text (Bottom of Center)
local subText = Instance.new("TextLabel")
subText.Name = "SubText"
subText.AnchorPoint = Vector2.new(0.5, 0.5)
subText.Position = UDim2.new(0.5, 0, 0.55, 0)
subText.Size = UDim2.new(0.8, 0, 0.06, 0)
subText.BackgroundTransparency = 1
subText.Font = Enum.Font.Code
subText.TextColor3 = Color3.fromRGB(180, 180, 160)
subText.TextScaled = true
subText.TextTransparency = 1
subText.Parent = screenGui

-- Flashlight Toggle Button
local flashlightBtn = Instance.new("TextButton")
flashlightBtn.Name = "FlashlightButton"
flashlightBtn.AnchorPoint = Vector2.new(1, 0)
flashlightBtn.Position = UDim2.new(1, -20, 0, 20)
flashlightBtn.Size = UDim2.new(0, 140, 0, 45)
flashlightBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
flashlightBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
flashlightBtn.Font = Enum.Font.Code
flashlightBtn.TextSize = 14
flashlightBtn.Text = "Open Flashlight"
flashlightBtn.Visible = false
flashlightBtn.Parent = screenGui

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 8)
btnCorner.Parent = flashlightBtn

-- Camera bobbing setup for found footage effect
local cam = workspace.CurrentCamera
local tickVal = 0

RunService.RenderStepped:Connect(function(dt)
    if isInBackrooms or isInPoolrooms or isInHabitableZone then
        local vel = character and character:FindFirstChild("Humanoid") and character.Humanoid.MoveDirection.Magnitude or 0
        if vel > 0 then
            tickVal = tickVal + dt * 10
            local bobX = math.cos(tickVal) * 0.15
            local bobY = math.sin(tickVal * 2) * 0.15
            cam.CFrame = cam.CFrame * CFrame.Angles(bobY * 0.02, bobX * 0.02, 0)
        end
    end
end)

--------------------------------------------------------------------------------
-- NOTIFICATION / SLIDING TEXT HELPER
--------------------------------------------------------------------------------
local function showSlidingText(mainMsg, subMsg, duration)
    centerText.Text = mainMsg
    subText.Text = subMsg or ""
    
    centerText.TextTransparency = 1
    subText.TextTransparency = 1
    blackScreen.BackgroundTransparency = 0.2
    
    local tweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    TweenService:Create(centerText, tweenInfo, {TextTransparency = 0}):Play()
    if subMsg ~= "" then
        TweenService:Create(subText, tweenInfo, {TextTransparency = 0}):Play()
    end
    
    task.wait(duration or 3)
    
    local fadeInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
    TweenService:Create(centerText, fadeInfo, {TextTransparency = 1}):Play()
    TweenService:Create(subText, fadeInfo, {TextTransparency = 1}):Play()
    TweenService:Create(blackScreen, fadeInfo, {BackgroundTransparency = 1}):Play()
end

--------------------------------------------------------------------------------
-- WORLD GENERATION: BACKROOMS, POOLROOMS, HABITABLE ZONE
--------------------------------------------------------------------------------
local backroomsFolder = Instance.new("Folder")
backroomsFolder.Name = "BackroomsDimension"
backroomsFolder.Parent = workspace

local function createProceduralBackrooms()
    isInBackrooms = true
    flashlightBtn.Visible = true
    
    Lighting.Brightness = 1.2
    Lighting.ClockTime = 0
    Lighting.FogColor = Color3.fromRGB(180, 160, 100)
    Lighting.FogEnd = 150
    
    local ambientSound = Instance.new("Sound")
    ambientSound.SoundId = "rbxassetid://" .. SOUND_BACKROOMS_AMBIENT
    ambientSound.Looped = true
    ambientSound.Volume = 1
    ambientSound.Parent = SoundService
    ambientSound:Play()
    
    local origin = Vector3.new(0, -500, 0)
    
    for floor = 0, 7 do
        local floorY = origin.Y + (floor * 12)
        
        for x = -5, 5 do
            for z = -5, 5 do
                local chunk = Instance.new("Part")
                chunk.Size = Vector3.new(40, 1, 40)
                chunk.Position = origin + Vector3.new(x * 40, floorY, z * 40)
                chunk.Anchored = true
                chunk.Material = Enum.Material.SmoothPlastic
                chunk.Color = Color3.fromRGB(210, 190, 110)
                chunk.Parent = backroomsFolder
                
                local surfaceTex = Instance.new("Texture")
                surfaceTex.Texture = TEXTURE_BACKROOMS_WALL
                surfaceTex.Face = Enum.NormalId.Top
                surfaceTex.Parent = chunk
                
                local ceiling = Instance.new("Part")
                ceiling.Size = Vector3.new(40, 1, 40)
                ceiling.Position = origin + Vector3.new(x * 40, floorY + 11, z * 40)
                ceiling.Anchored = true
                ceiling.Material = Enum.Material.SmoothPlastic
                ceiling.Color = Color3.fromRGB(230, 220, 150)
                ceiling.Parent = backroomsFolder
                
                if math.random() > 0.3 then
                    local lightPart = Instance.new("Part")
                    lightPart.Size = Vector3.new(4, 0.2, 4)
                    lightPart.Position = ceiling.Position - Vector3.new(0, 0.6, 0)
                    lightPart.Anchored = true
                    lightPart.Material = Enum.Material.Neon
                    lightPart.Color = Color3.fromRGB(255, 255, 200)
                    lightPart.Parent = backroomsFolder
                    
                    local pointLight = Instance.new("PointLight")
                    pointLight.Brightness = 0.8
                    pointLight.Range = 18
                    pointLight.Color = Color3.fromRGB(255, 240, 180)
                    pointLight.Parent = lightPart
                end
            end
        end
    end
    
    humanoidRootPart.CFrame = CFrame.new(origin + Vector3.new(0, 2, 0))
    showSlidingText("Backrooms Has Been Loaded.\nGoodluck Wanderer", "", 3)
end

local function enterPoolrooms()
    isInBackrooms = false
    isInPoolrooms = true
    
    local activeAmbient = SoundService:FindFirstChildOfClass("Sound")
    if activeAmbient then activeAmbient:Destroy() end
    
    local poolSound = Instance.new("Sound")
    poolSound.SoundId = "rbxassetid://" .. SOUND_POOLROOMS_AMBIENT
    poolSound.Looped = true
    poolSound.Volume = 1
    poolSound.Parent = SoundService
    poolSound:Play()
    
    Lighting.Brightness = 0.8
    Lighting.FogColor = Color3.fromRGB(150, 180, 190)
    Lighting.FogEnd = 120
    
    showSlidingText("The PoolRooms", "The Backrooms", 3)
    
    local poolOrigin = Vector3.new(0, -800, 0)
    humanoidRootPart.CFrame = CFrame.new(poolOrigin + Vector3.new(0, 5, 0))
    
    for x = -3, 3 do
        for z = -3, 3 do
            local tile = Instance.new("Part")
            tile.Size = Vector3.new(50, 1, 50)
            tile.Position = poolOrigin + Vector3.new(x * 50, 0, z * 50)
            tile.Anchored = true
            tile.Material = Enum.Material.SmoothPlastic
            tile.Color = Color3.fromRGB(220, 225, 220)
            tile.Parent = backroomsFolder
            
            local tex = Instance.new("Texture")
            tex.Texture = TEXTURE_POOLROOMS
            tex.Face = Enum.NormalId.Top
            tex.Parent = tile
            
            if math.random() > 0.4 then
                local water = Instance.new("Part")
                water.Size = Vector3.new(30, 2, 30)
                water.Position = tile.Position - Vector3.new(0, 1, 0)
                water.Anchored = true
                water.CanCollide = false
                water.Material = Enum.Material.Glass
                water.Color = Color3.fromRGB(100, 170, 185)
                water.Transparency = 0.4
                water.Parent = backroomsFolder
            end
        end
    end
end

local function enterHabitableZone()
    isInPoolrooms = false
    isInBackrooms = false
    isInHabitableZone = true
    
    showSlidingText("Habitable Zone", "Level 1", 3)
    
    Lighting.Brightness = 0.4
    Lighting.FogColor = Color3.fromRGB(50, 50, 50)
    Lighting.FogEnd = 80
    
    humanoidRootPart.CFrame = CFrame.new(Vector3.new(0, -1000, 0))
    
    for x = -4, 4 do
        for z = -4, 4 do
            local floor = Instance.new("Part")
            floor.Size = Vector3.new(40, 1, 40)
            floor.Position = Vector3.new(x * 40, -1000, z * 40)
            floor.Anchored = true
            floor.Material = Enum.Material.Concrete
            floor.Color = Color3.fromRGB(80, 80, 80)
            floor.Parent = backroomsFolder
        end
    end
    
    task.spawn(function()
        while isInHabitableZone do
            task.wait(20)
            local blackoutSound = Instance.new("Sound")
            blackoutSound.SoundId = "rbxassetid://" .. SOUND_LIGHT_BLACKOUT
            blackoutSound.Parent = SoundService
            blackoutSound:Play()
            Lighting.Brightness = 0
            task.wait(20)
            Lighting.Brightness = 0.4
        end
    end)
end

--------------------------------------------------------------------------------
-- NOCLIP TRIGGER & STEPPED LOGIC
--------------------------------------------------------------------------------
local function triggerNoclipTransition()
    local noclipSound = Instance.new("Sound")
    noclipSound.SoundId = "rbxassetid://" .. SOUND_NOCLIP
    noclipSound.Volume = 2
    noclipSound.Parent = SoundService
    noclipSound:Play()
    
    blackScreen.BackgroundTransparency = 0
    
    task.wait(3)
    centerText.Text = "BACKROOMS"
    centerText.TextTransparency = 0
    
    task.wait(3)
    subText.Text = "Produced By Hecker"
    subText.TextTransparency = 0
    
    task.wait(5)
    centerText.TextTransparency = 1
    subText.TextTransparency = 1
    blackScreen.BackgroundTransparency = 1
    
    createProceduralBackrooms()
end

task.spawn(function()
    while true do
        task.wait(1)
        if not isInBackrooms and not isInPoolrooms and not isInHabitableZone then
            if math.random(1, 1000) == 1 then
                triggerNoclipTransition()
            end
        end
    end
end)

humanoidRootPart.Touched:Connect(function(hit)
    if not isInBackrooms and not isInPoolrooms and not isInHabitableZone then
        if hit and hit.CanCollide and not hit:IsDescendantOf(character) then
            hit.CanCollide = false
            if math.random() <= 0.5 then
                triggerNoclipTransition()
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- FLASHLIGHT TOGGLE BUTTON & FOOTSTEP AUDIO EMITTER
--------------------------------------------------------------------------------
flashlightBtn.MouseButton1Click:Connect(function()
    flashlightOn = not flashlightOn
    local fsSound = Instance.new("Sound")
    fsSound.SoundId = "rbxassetid://" .. SOUND_FLASHLIGHT
    fsSound.Parent = SoundService
    fsSound:Play()
    
    if flashlightOn then
        local userFl = Instance.new("SpotLight")
        userFl.Brightness = 3
        userFl.Range = 40
        userFl.Angle = 60
        userFl.Color = Color3.fromRGB(255, 255, 240)
        userFl.Parent = cam
        userFl.Name = "UserFlashlight"
        flashlightBtn.Text = "Close Flashlight"
    else
        if cam:FindFirstChild("UserFlashlight") then
            cam.UserFlashlight:Destroy()
        end
        flashlightBtn.Text = "Open Flashlight"
    end
end)

local lastFootstep = tick()
RunService.Stepped:Connect(function()
    if character and character:FindFirstChild("Humanoid") then
        local speed = character.Humanoid.MoveDirection.Magnitude
        if speed > 0 and (tick() - lastFootstep > 0.4) then
            lastFootstep = tick()
            local walkSound = Instance.new("Sound")
            walkSound.Volume = 3
            if isInBackrooms then
                walkSound.SoundId = "rbxassetid://" .. SOUND_WALK_BACKROOMS
            elseif isInPoolrooms then
                walkSound.SoundId = "rbxassetid://" .. SOUND_WALK_POOLROOMS
            elseif isInHabitableZone then
                walkSound.SoundId = "rbxassetid://" .. SOUND_WALK_BACKROOMS
            end
            if walkSound.SoundId ~= "" then
                walkSound.Parent = SoundService
                walkSound:Play()
                game.Debris:AddItem(walkSound, 2)
            end
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(60)
        if isInBackrooms and math.random(1, 100) <= 20 then
            enterPoolrooms()
        end
    end
end)
