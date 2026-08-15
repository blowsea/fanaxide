-- ==============================================================================
-- Fanaxide - Rogue Lineage Utility
-- ==============================================================================
-- Features:
--   1. Player Healthview (Humanoid health display above players & mobs)
--   2. Player Chams (Wallhack Highlight + Roblox Username Display)
--   3. Player Intent (Dedicated held weapon / spell indicator above heads)
--   4. Observe / Spectate (Toggle-based: Right-Click any name on Leaderboard)
--   5. Proximity Alert (On-screen alert banner with adjustable range slider)
--   6. Fullbright (Lighting modifier with adjustable brightness slider)
-- ==============================================================================

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait(0.1)
    LocalPlayer = Players.LocalPlayer
end

local Camera = Workspace.CurrentCamera or Workspace:WaitForChild("Camera")
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = Workspace.CurrentCamera or Camera
end)

-- Safe universal GUI parent resolver
local function GetGuiParent()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    local ok, core = pcall(function() return game:GetService("CoreGui") end)
    if ok and core then
        local ok2, robloxGui = pcall(function() return core:FindFirstChild("RobloxGui") end)
        if ok2 and robloxGui then
            local test = Instance.new("Folder")
            local canParent = pcall(function() test.Parent = robloxGui; test:Destroy() end)
            if canParent then return robloxGui end
        end
        local test = Instance.new("Folder")
        local canParent = pcall(function() test.Parent = core; test:Destroy() end)
        if canParent then return core end
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local GuiParent = GetGuiParent()
if GuiParent:FindFirstChild("FanaxideGui") then
    GuiParent.FanaxideGui:Destroy()
end

-- ==============================================================================
-- CONFIGURATION & STATE
-- ==============================================================================
local Config = {
    PlayerHealthview = false,
    PlayerChams = false,
    PlayerIntent = false,
    ChamsColor = Color3.fromRGB(255, 60, 80),
    ProximityAlert = false,
    ProximityRange = 300,
    Fullbright = false,
    BrightnessLevel = 80,
}

local OriginalLighting = {
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    Brightness = Lighting.Brightness,
    FogEnd = Lighting.FogEnd,
    FogStart = Lighting.FogStart,
    FogColor = Lighting.FogColor
}

local SpectatingPlayer = nil
local HealthviewConnection = nil
local LightingConnections = {}
local ChamsTable = {}
local ChamsNameGuis = {}
local IntentGuis = {}
local IntentConnections = {}
local ProximityConnection = nil
local SpectateLoopConnection = nil
local LabelToPlayerCache = {}

-- ==============================================================================
-- ROGUE LINEAGE LEADERBOARD RESOLVER (UPVALUE + REGISTRY EXTRACTOR)
-- ==============================================================================
local function GetPlayerCharacter(player)
    if not player then return nil end
    return player.Character or (Workspace:FindFirstChild("Live") and Workspace.Live:FindFirstChild(player.Name))
end

local function RefreshLeaderboardMap()
    local pgui = LocalPlayer:FindFirstChild("PlayerGui")
    local lbGui = pgui and pgui:FindFirstChild("LeaderboardGui")
    local clientScript = lbGui and lbGui:FindFirstChild("LeaderboardClient")

    if clientScript and getreg and debug and debug.getupvalues then
        for _, v in ipairs(getreg()) do
            if type(v) == "function" and islclosure(v) and not (isourclosure and isourclosure(v)) then
                local env = getfenv(v)
                if env and env.script == clientScript then
                    local ups = debug.getupvalues(v)
                    for _, u in pairs(ups) do
                        if type(u) == "table" then
                            for pk, pv in pairs(u) do
                                if typeof(pv) == "Instance" and pv:IsA("TextLabel") then
                                    local targetPlr = (typeof(pk) == "Instance" and pk) or Players:FindFirstChild(tostring(pk))
                                    if targetPlr then
                                        LabelToPlayerCache[pv] = targetPlr
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function GetLeaderboardPlayer(label)
    if not label or not label:IsA("TextLabel") then return nil end
    if LabelToPlayerCache[label] then return LabelToPlayerCache[label] end

    RefreshLeaderboardMap()
    if LabelToPlayerCache[label] then return LabelToPlayerCache[label] end

    -- Fallback by matching against player names or characters
    local text = label.Text
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name == text or p.DisplayName == text then
            return p
        end
        local char = GetPlayerCharacter(p)
        if char and (char.Name == text or (char:FindFirstChild("Head") and string.find(text, p.Name, 1, true))) then
            return p
        end
    end
    return nil
end

-- ==============================================================================
-- 1. OBSERVE / SPECTATE ENGINE (TOGGLE-BASED)
-- ==============================================================================
local function ToggleSpectate(targetPlayer)
    if SpectatingPlayer == targetPlayer or targetPlayer == LocalPlayer or not targetPlayer then
        SpectatingPlayer = nil
        if SpectateLoopConnection then
            SpectateLoopConnection:Disconnect()
            SpectateLoopConnection = nil
        end

        local localChar = GetPlayerCharacter(LocalPlayer)
        local hum = localChar and localChar:FindFirstChildOfClass("Humanoid")
        if hum then
            Camera.CameraType = Enum.CameraType.Custom
            Camera.CameraSubject = hum
        end
    else
        SpectatingPlayer = targetPlayer

        if SpectateLoopConnection then
            SpectateLoopConnection:Disconnect()
        end

        SpectateLoopConnection = RunService.RenderStepped:Connect(function()
            if not SpectatingPlayer then return end
            local targetChar = GetPlayerCharacter(SpectatingPlayer)
            local hum = targetChar and targetChar:FindFirstChildOfClass("Humanoid")
            if hum and Camera.CameraSubject ~= hum then
                Camera.CameraType = Enum.CameraType.Custom
                Camera.CameraSubject = hum
            end
        end)
    end
end

-- ==============================================================================
-- 2. LEADERBOARD RIGHT-CLICK OBSERVE HOOKS
-- ==============================================================================
local function AttachLeaderboardButton(label)
    if not label or not label:IsA("TextLabel") then return end
    if label:FindFirstChild("FanaxideSPB") then return end

    local btn = Instance.new("TextButton")
    btn.Name = "FanaxideSPB"
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.Position = UDim2.new(0, 0, 0, 0)
    btn.ZIndex = 50
    btn.Active = true
    btn.Parent = label

    btn.MouseButton2Click:Connect(function()
        local matchedPlayer = GetLeaderboardPlayer(label)
        if matchedPlayer then
            ToggleSpectate(matchedPlayer)
        end
    end)
end

local function InitLeaderboardHook()
    task.spawn(function()
        local playerGui = LocalPlayer:WaitForChild("PlayerGui", 30)
        if not playerGui then return end

        local function ScanLeaderboard()
            local leaderboardGui = playerGui:FindFirstChild("LeaderboardGui")
            if not leaderboardGui then return end

            local mainFrame = leaderboardGui:FindFirstChild("MainFrame")
            local scrollingFrame = mainFrame and mainFrame:FindFirstChild("ScrollingFrame")
            if not scrollingFrame then return end

            RefreshLeaderboardMap()

            for _, frame in ipairs(scrollingFrame:GetChildren()) do
                if frame:IsA("TextLabel") and frame.Name == "PlayerLabel" then
                    AttachLeaderboardButton(frame)
                end
            end
        end

        ScanLeaderboard()

        playerGui.ChildAdded:Connect(function(child)
            if child.Name == "LeaderboardGui" then
                task.wait(0.5)
                ScanLeaderboard()
                local main = child:WaitForChild("MainFrame", 5)
                local scroll = main and main:WaitForChild("ScrollingFrame", 5)
                if scroll then
                    scroll.ChildAdded:Connect(function(lbl)
                        task.wait(0.1)
                        if lbl:IsA("TextLabel") then AttachLeaderboardButton(lbl) end
                    end)
                end
            end
        end)

        local currentLb = playerGui:FindFirstChild("LeaderboardGui")
        if currentLb and currentLb:FindFirstChild("MainFrame") and currentLb.MainFrame:FindFirstChild("ScrollingFrame") then
            currentLb.MainFrame.ScrollingFrame.ChildAdded:Connect(function(lbl)
                task.wait(0.1)
                if lbl:IsA("TextLabel") then AttachLeaderboardButton(lbl) end
            end)
        end
    end)
end

InitLeaderboardHook()

-- Global Cursor Right-Click Interceptor
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        local mousePos = UserInputService:GetMouseLocation()
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then return end

        local objects = playerGui:GetGuiObjectsAtPosition(mousePos.X, mousePos.Y)
        for _, obj in ipairs(objects) do
            local label = nil
            if obj:IsA("TextLabel") and obj.Name == "PlayerLabel" then
                label = obj
            elseif obj.Parent and obj.Parent:IsA("TextLabel") and obj.Parent.Name == "PlayerLabel" then
                label = obj.Parent
            end

            if label then
                local matchedPlayer = GetLeaderboardPlayer(label)
                if matchedPlayer then
                    ToggleSpectate(matchedPlayer)
                    break
                end
            end
        end
    end
end)

-- ==============================================================================
-- 3. DEDICATED PLAYER INTENT
-- ==============================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "FanaxideGui"
ScreenGui.DisplayOrder = 9999
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = GuiParent

local function ApplyIntentToCharacter(character)
    if not character or character == GetPlayerCharacter(LocalPlayer) then return end
    local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
    if not head then return end

    if IntentGuis[character] then
        pcall(function() IntentGuis[character]:Destroy() end)
        IntentGuis[character] = nil
    end

    if not Config.PlayerIntent then return end

    local bbg = Instance.new("BillboardGui")
    bbg.Name = "IntentBillboard"
    bbg.Adornee = head
    bbg.Size = UDim2.new(0, 160, 0, 22)
    bbg.StudsOffset = Vector3.new(0, 3.4, 0)
    bbg.AlwaysOnTop = true
    bbg.ResetOnSpawn = false
    bbg.Parent = ScreenGui

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(255, 220, 90)
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.TextStrokeTransparency = 0.2
    label.Font = Enum.Font.GothamBold
    label.TextSize = 12
    label.Parent = bbg

    local function UpdateHeldItem()
        local heldTool = character:FindFirstChildOfClass("Tool")
        if heldTool then
            label.Text = "Holding: " .. heldTool.Name
            label.Visible = true
        else
            label.Text = ""
            label.Visible = false
        end
    end

    UpdateHeldItem()

    local cAdded = character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then UpdateHeldItem() end
    end)
    local cRemoved = character.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") then task.wait(0.05) UpdateHeldItem() end
    end)

    IntentGuis[character] = bbg
    IntentConnections[character] = {cAdded, cRemoved}
end

local function RemoveIntentFromCharacter(character)
    if IntentGuis[character] then
        pcall(function() IntentGuis[character]:Destroy() end)
        IntentGuis[character] = nil
    end
    if IntentConnections[character] then
        for _, c in ipairs(IntentConnections[character]) do
            pcall(function() c:Disconnect() end)
        end
        IntentConnections[character] = nil
    end
end

local function SetPlayerIntent(state)
    Config.PlayerIntent = state
    local liveFolder = Workspace:FindFirstChild("Live") or Workspace

    for _, entity in ipairs(liveFolder:GetChildren()) do
        if state then
            ApplyIntentToCharacter(entity)
        else
            RemoveIntentFromCharacter(entity)
        end
    end
end

-- ==============================================================================
-- 4. PLAYER HEALTHVIEW
-- ==============================================================================
local function ApplyHealthToCharacter(character, enable)
    if not character or character == GetPlayerCharacter(LocalPlayer) then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        if enable then
            humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
            humanoid.HealthDisplayDistance = 120
            humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
            if character:FindFirstChild("MonsterInfo") then
                humanoid.NameDisplayDistance = 0
            end
        else
            humanoid.HealthDisplayDistance = 0
            humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
        end
    end
end

local function SetPlayerHealthview(state)
    Config.PlayerHealthview = state
    local liveFolder = Workspace:FindFirstChild("Live") or Workspace

    for _, entity in ipairs(liveFolder:GetChildren()) do
        ApplyHealthToCharacter(entity, state)
    end

    if state then
        if not HealthviewConnection then
            HealthviewConnection = liveFolder.ChildAdded:Connect(function(child)
                task.wait(0.2)
                if Config.PlayerHealthview then
                    ApplyHealthToCharacter(child, true)
                end
                if Config.PlayerIntent then
                    ApplyIntentToCharacter(child)
                end
            end)
        end
    else
        if HealthviewConnection then
            HealthviewConnection:Disconnect()
            HealthviewConnection = nil
        end
    end
end

-- ==============================================================================
-- 5. PLAYER CHAMS (ESP + USERNAME DISPLAY)
-- ==============================================================================
local function RemoveChams(player)
    if ChamsTable[player] then
        pcall(function() ChamsTable[player]:Destroy() end)
        ChamsTable[player] = nil
    end
    if ChamsNameGuis[player] then
        pcall(function() ChamsNameGuis[player]:Destroy() end)
        ChamsNameGuis[player] = nil
    end
end

local function ApplyChams(player)
    if player == LocalPlayer then return end
    local char = GetPlayerCharacter(player)
    if not char then return end

    RemoveChams(player)

    if Config.PlayerChams then
        local highlight = Instance.new("Highlight")
        highlight.Name = "FanaxideHighlight"
        highlight.Adornee = char
        highlight.FillColor = Config.ChamsColor
        highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
        highlight.FillTransparency = 0.55
        highlight.OutlineTransparency = 0.1
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Parent = char
        ChamsTable[player] = highlight

        local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
        if head then
            local bbg = Instance.new("BillboardGui")
            bbg.Name = "ChamsNameTag"
            bbg.Adornee = head
            bbg.Size = UDim2.new(0, 150, 0, 20)
            bbg.StudsOffset = Vector3.new(0, 2.2, 0)
            bbg.AlwaysOnTop = true
            bbg.ResetOnSpawn = false
            bbg.Parent = ScreenGui

            local nameLabel = Instance.new("TextLabel")
            nameLabel.Size = UDim2.new(1, 0, 1, 0)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Text = player.Name
            nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
            nameLabel.TextStrokeTransparency = 0.2
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.TextSize = 11
            nameLabel.Parent = bbg

            ChamsNameGuis[player] = bbg
        end
    end
end

local function SetPlayerChams(state)
    Config.PlayerChams = state
    for _, p in ipairs(Players:GetPlayers()) do
        if state then
            ApplyChams(p)
        else
            RemoveChams(p)
        end
    end
end

Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function(char)
        task.wait(0.5)
        if Config.PlayerChams then ApplyChams(p) end
        if Config.PlayerIntent then ApplyIntentToCharacter(char) end
    end)
end)

for _, p in ipairs(Players:GetPlayers()) do
    p.CharacterAdded:Connect(function(char)
        task.wait(0.5)
        if Config.PlayerChams then ApplyChams(p) end
        if Config.PlayerIntent then ApplyIntentToCharacter(char) end
    end)
end

Players.PlayerRemoving:Connect(function(p)
    RemoveChams(p)
    if p.Character then RemoveIntentFromCharacter(p.Character) end
    if SpectatingPlayer == p then ToggleSpectate(nil) end
end)

-- ==============================================================================
-- 6. PROXIMITY ALERT
-- ==============================================================================
local AlertBanner = Instance.new("Frame")
AlertBanner.Name = "AlertBanner"
AlertBanner.Size = UDim2.new(0, 320, 0, 38)
AlertBanner.Position = UDim2.new(0.5, -160, 0.05, 0)
AlertBanner.BackgroundColor3 = Color3.fromRGB(180, 30, 30)
AlertBanner.BorderSizePixel = 0
AlertBanner.Visible = false
AlertBanner.Parent = ScreenGui

local AlertCorner = Instance.new("UICorner", AlertBanner)
AlertCorner.CornerRadius = UDim.new(0, 8)

local AlertStroke = Instance.new("UIStroke", AlertBanner)
AlertStroke.Color = Color3.fromRGB(255, 100, 100)
AlertStroke.Thickness = 1.5

local AlertText = Instance.new("TextLabel")
AlertText.Size = UDim2.new(1, 0, 1, 0)
AlertText.BackgroundTransparency = 1
AlertText.Text = "ALERT: Player Nearby!"
AlertText.TextColor3 = Color3.fromRGB(255, 255, 255)
AlertText.Font = Enum.Font.GothamBold
AlertText.TextSize = 13
AlertText.Parent = AlertBanner

local function SetProximityAlert(state)
    Config.ProximityAlert = state
    if not state then
        AlertBanner.Visible = false
        if ProximityConnection then
            ProximityConnection:Disconnect()
            ProximityConnection = nil
        end
        return
    end

    if not ProximityConnection then
        ProximityConnection = RunService.Heartbeat:Connect(function()
            if not Config.ProximityAlert then return end
            local myChar = GetPlayerCharacter(LocalPlayer)
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
            if not myRoot then
                AlertBanner.Visible = false
                return
            end

            local closestDist = math.huge
            local closestPlayer = nil

            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then
                    local char = GetPlayerCharacter(p)
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    if root then
                        local dist = (myRoot.Position - root.Position).Magnitude
                        if dist < Config.ProximityRange and dist < closestDist then
                            closestDist = dist
                            closestPlayer = p
                        end
                    end
                end
            end

            if closestPlayer then
                AlertBanner.Visible = true
                AlertText.Text = string.format("NEARBY: %s (%d studs)", closestPlayer.Name, math.floor(closestDist))
            else
                AlertBanner.Visible = false
            end
        end)
    end
end

-- ==============================================================================
-- 7. FULLBRIGHT & BRIGHTNESS CONTROL
-- ==============================================================================
local function ApplyFullbright()
    if not Config.Fullbright then return end

    local areaColor = Lighting:FindFirstChild("areacolor")
    if areaColor and areaColor:IsA("ColorCorrectionEffect") then
        areaColor.Enabled = false
    end

    local mult = (Config.BrightnessLevel or 80) / 100
    local color = Color3.new(mult, mult, mult)

    Lighting.Ambient = color
    Lighting.OutdoorAmbient = color
    Lighting.Brightness = 1 + (mult * 2)
    Lighting.FogColor = Color3.fromRGB(255, 255, 255)
    Lighting.FogEnd = 100000
    Lighting.FogStart = 50
end

local function RestoreAmbience()
    local areaColor = Lighting:FindFirstChild("areacolor")
    if areaColor and areaColor:IsA("ColorCorrectionEffect") then
        areaColor.Enabled = true
    end

    Lighting.Ambient = OriginalLighting.Ambient
    Lighting.OutdoorAmbient = OriginalLighting.OutdoorAmbient
    Lighting.Brightness = OriginalLighting.Brightness
    Lighting.FogEnd = OriginalLighting.FogEnd
    Lighting.FogStart = OriginalLighting.FogStart
    Lighting.FogColor = OriginalLighting.FogColor
end

local function SetFullbright(state)
    Config.Fullbright = state

    for _, conn in ipairs(LightingConnections) do
        if conn then conn:Disconnect() end
    end
    table.clear(LightingConnections)

    if state then
        ApplyFullbright()

        local isUpdating = false
        local function SafeApply()
            if isUpdating or not Config.Fullbright then return end
            isUpdating = true
            ApplyFullbright()
            task.defer(function() isUpdating = false end)
        end

        table.insert(LightingConnections, Lighting:GetPropertyChangedSignal("Ambient"):Connect(SafeApply))
        table.insert(LightingConnections, Lighting:GetPropertyChangedSignal("Brightness"):Connect(SafeApply))
        table.insert(LightingConnections, Lighting:GetPropertyChangedSignal("FogEnd"):Connect(SafeApply))
    else
        RestoreAmbience()
    end
end

-- ==============================================================================
-- 8. MAIN CONTROL GUI
-- ==============================================================================
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 260, 0, 275)
MainFrame.Position = UDim2.new(0.04, 0, 0.22, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner", MainFrame)
MainCorner.CornerRadius = UDim.new(0, 8)

local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Color = Color3.fromRGB(45, 45, 55)
MainStroke.Thickness = 1.2

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 32)
Title.BackgroundTransparency = 1
Title.Text = "  Fanaxide"
Title.TextColor3 = Color3.fromRGB(240, 240, 245)
Title.TextSize = 14
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = MainFrame

local function CreateToggleButton(name, yPos, defaultState, callback)
    local button = Instance.new("TextButton")
    button.Name = name .. "Toggle"
    button.Size = UDim2.new(0.9, 0, 0, 26)
    button.Position = UDim2.new(0.05, 0, 0, yPos)
    button.BackgroundColor3 = defaultState and Color3.fromRGB(40, 140, 70) or Color3.fromRGB(30, 30, 36)
    button.TextColor3 = Color3.fromRGB(240, 240, 240)
    button.Text = name .. ": " .. (defaultState and "ON" or "OFF")
    button.Font = Enum.Font.GothamMedium
    button.TextSize = 11
    button.BorderSizePixel = 0
    button.Parent = MainFrame

    local corner = Instance.new("UICorner", button)
    corner.CornerRadius = UDim.new(0, 6)

    local state = defaultState
    button.MouseButton1Click:Connect(function()
        state = not state
        button.BackgroundColor3 = state and Color3.fromRGB(40, 140, 70) or Color3.fromRGB(30, 30, 36)
        button.Text = name .. ": " .. (state and "ON" or "OFF")
        callback(state)
    end)
    return button
end

-- Toggles
CreateToggleButton("Player Healthview", 34, Config.PlayerHealthview, function(state)
    SetPlayerHealthview(state)
end)

CreateToggleButton("Player Chams (ESP + Names)", 64, Config.PlayerChams, function(state)
    SetPlayerChams(state)
end)

CreateToggleButton("Player Intent (Held Item)", 94, Config.PlayerIntent, function(state)
    SetPlayerIntent(state)
end)

CreateToggleButton("Proximity Alert", 124, Config.ProximityAlert, function(state)
    SetProximityAlert(state)
end)

-- Proximity Range Slider
local ProxSliderContainer = Instance.new("Frame")
ProxSliderContainer.Size = UDim2.new(0.9, 0, 0, 34)
ProxSliderContainer.Position = UDim2.new(0.05, 0, 0, 154)
ProxSliderContainer.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
ProxSliderContainer.BorderSizePixel = 0
ProxSliderContainer.Parent = MainFrame
Instance.new("UICorner", ProxSliderContainer).CornerRadius = UDim.new(0, 6)

local ProxSliderLabel = Instance.new("TextLabel")
ProxSliderLabel.Size = UDim2.new(1, 0, 0, 16)
ProxSliderLabel.BackgroundTransparency = 1
ProxSliderLabel.Text = " Alert Range: " .. tostring(Config.ProximityRange) .. " studs"
ProxSliderLabel.TextColor3 = Color3.fromRGB(190, 190, 200)
ProxSliderLabel.TextSize = 10
ProxSliderLabel.Font = Enum.Font.Gotham
ProxSliderLabel.TextXAlignment = Enum.TextXAlignment.Left
ProxSliderLabel.Parent = ProxSliderContainer

local ProxSliderBar = Instance.new("Frame")
ProxSliderBar.Size = UDim2.new(0.9, 0, 0, 5)
ProxSliderBar.Position = UDim2.new(0.05, 0, 0, 20)
ProxSliderBar.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
ProxSliderBar.BorderSizePixel = 0
ProxSliderBar.Parent = ProxSliderContainer

local ProxSliderFill = Instance.new("Frame")
ProxSliderFill.Size = UDim2.new(Config.ProximityRange / 800, 0, 1, 0)
ProxSliderFill.BackgroundColor3 = Color3.fromRGB(240, 90, 90)
ProxSliderFill.BorderSizePixel = 0
ProxSliderFill.Parent = ProxSliderBar

local isDraggingProx = false
local function UpdateProxSlider(input)
    local relX = math.clamp((input.Position.X - ProxSliderBar.AbsolutePosition.X) / ProxSliderBar.AbsoluteSize.X, 0.05, 1)
    local val = math.floor(relX * 800)
    Config.ProximityRange = val
    ProxSliderFill.Size = UDim2.new(relX, 0, 1, 0)
    ProxSliderLabel.Text = " Alert Range: " .. tostring(val) .. " studs"
end

ProxSliderBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        isDraggingProx = true
        UpdateProxSlider(input)
    end
end)

-- Fullbright Toggle
CreateToggleButton("Fullbright", 196, Config.Fullbright, function(state)
    SetFullbright(state)
end)

-- Brightness Slider
local SliderContainer = Instance.new("Frame")
SliderContainer.Size = UDim2.new(0.9, 0, 0, 34)
SliderContainer.Position = UDim2.new(0.05, 0, 0, 226)
SliderContainer.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
SliderContainer.BorderSizePixel = 0
SliderContainer.Parent = MainFrame
Instance.new("UICorner", SliderContainer).CornerRadius = UDim.new(0, 6)

local SliderLabel = Instance.new("TextLabel")
SliderLabel.Size = UDim2.new(1, 0, 0, 16)
SliderLabel.BackgroundTransparency = 1
SliderLabel.Text = " Brightness: " .. tostring(Config.BrightnessLevel) .. "%"
SliderLabel.TextColor3 = Color3.fromRGB(190, 190, 200)
SliderLabel.TextSize = 10
SliderLabel.Font = Enum.Font.Gotham
SliderLabel.TextXAlignment = Enum.TextXAlignment.Left
SliderLabel.Parent = SliderContainer

local SliderBar = Instance.new("Frame")
SliderBar.Size = UDim2.new(0.9, 0, 0, 5)
SliderBar.Position = UDim2.new(0.05, 0, 0, 20)
SliderBar.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
SliderBar.BorderSizePixel = 0
SliderBar.Parent = SliderContainer

local SliderFill = Instance.new("Frame")
SliderFill.Size = UDim2.new(Config.BrightnessLevel / 100, 0, 1, 0)
SliderFill.BackgroundColor3 = Color3.fromRGB(90, 160, 255)
SliderFill.BorderSizePixel = 0
SliderFill.Parent = SliderBar

local isDraggingSlider = false
local function UpdateSlider(input)
    local relX = math.clamp((input.Position.X - SliderBar.AbsolutePosition.X) / SliderBar.AbsoluteSize.X, 0, 1)
    local val = math.floor(relX * 100)
    Config.BrightnessLevel = val
    SliderFill.Size = UDim2.new(relX, 0, 1, 0)
    SliderLabel.Text = " Brightness: " .. tostring(val) .. "%"
    if Config.Fullbright then ApplyFullbright() end
end

SliderBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        isDraggingSlider = true
        UpdateSlider(input)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        isDraggingSlider = false
        isDraggingProx = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if isDraggingSlider and input.UserInputType == Enum.UserInputType.MouseMovement then
        UpdateSlider(input)
    elseif isDraggingProx and input.UserInputType == Enum.UserInputType.MouseMovement then
        UpdateProxSlider(input)
    end
end)

-- Keybind to toggle GUI visibility (Right Control)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.RightControl then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

print("[Fanaxide] Loaded successfully! Press RightControl to toggle UI.")
