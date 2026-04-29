--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer

-- Remote Setup
local enemyRemotes = ReplicatedStorage:WaitForChild("EnemyRemotes")
local reEnemySpawn = enemyRemotes:WaitForChild("EnemySpawn")
local reEnemyDestroy = enemyRemotes:WaitForChild("EnemyDestroy")
local reEnemyBatch = enemyRemotes:WaitForChild("EnemyBatch")
local reEnemyClicked = enemyRemotes:WaitForChild("EnemyClicked")
local reKillAll = enemyRemotes:WaitForChild("KillAll")
local reUpdateSettings = enemyRemotes:WaitForChild("UpdateSettings")
local rfGetAllEnemies = enemyRemotes:WaitForChild("GetAllEnemies")
local reSetPlaying = enemyRemotes:WaitForChild("SetPlaying")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local localizationModule = require(sharedFolder:WaitForChild("Localization"))
local START_SCREEN_BACKGROUND_IMAGE = "rbxassetid://95766142455215"

-- Enemy Registry
local enemyRegistry = {}

local function resolveLanguage(localeId)
	local normalized = string.lower(localeId)
	local localeMap = {
		["de"] = "de",
		["tr"] = "tr",
		["ru"] = "ru",
		["fr"] = "fr",
		["es"] = "es",
		["ko"] = "ko",
		["ja"] = "ja",
		["jp"] = "ja",
		["pt-br"] = "pt-BR",
		["pt"] = "pt-BR",
	}

	if localeMap[normalized] then
		return localeMap[normalized]
	end

	local prefix = string.match(normalized, "^(%a+)")
	if prefix and localeMap[prefix] then
		return localeMap[prefix]
	end

	return "en"
end

local activeLanguage = resolveLanguage(localPlayer.LocaleId or "en")

local function tr(key)
	local langTable = localizationModule[activeLanguage] or localizationModule.en or {}
	local fallbackTable = localizationModule.en or {}
	return langTable[key] or fallbackTable[key] or key
end

local function enemyIdText(id)
	return string.gsub(tr("ui.enemy_id"), "{id}", tostring(id))
end

local function showClickIdPopup(body, id, size)
	local existingPopup = body:FindFirstChild("ClickIdPopup")
	if existingPopup then
		existingPopup:Destroy()
	end

	local popup = Instance.new("BillboardGui")
	popup.Name = "ClickIdPopup"
	popup.Adornee = body
	popup.Size = UDim2.fromScale(1.8, 0.72)
	popup.StudsOffset = Vector3.new(0, size + 2.8, 0)
	popup.AlwaysOnTop = true
	popup.Parent = body

	local popupLabel = Instance.new("TextLabel")
	popupLabel.BackgroundTransparency = 1
	popupLabel.Size = UDim2.fromScale(1, 1)
	popupLabel.TextScaled = true
	popupLabel.Font = Enum.Font.GothamBold
	popupLabel.TextColor3 = Color3.fromRGB(255, 245, 170)
	popupLabel.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
	popupLabel.TextStrokeTransparency = 0.15
	popupLabel.Text = enemyIdText(id)
	popupLabel.Parent = popup

	task.delay(2, function()
		if popup and popup.Parent then
			popup:Destroy()
		end
	end)
end

local function safeLookAt(position, lookDir)
	local direction = Vector3.new(lookDir.X, 0, lookDir.Z)
	if direction.Magnitude < 0.001 then
		direction = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(position, position + direction.Unit)
end

local function createRainbowTitle(parent, text)
	local colors = {
		Color3.fromRGB(255, 70, 70),
		Color3.fromRGB(255, 150, 50),
		Color3.fromRGB(255, 235, 70),
		Color3.fromRGB(105, 255, 120),
		Color3.fromRGB(80, 245, 255),
		Color3.fromRGB(90, 145, 255),
		Color3.fromRGB(170, 115, 255),
		Color3.fromRGB(255, 110, 220),
	}

	local titleFrame = Instance.new("Frame")
	titleFrame.Name = "RainbowTitle"
	titleFrame.Size = UDim2.fromScale(0.9, 0.18)
	titleFrame.Position = UDim2.fromScale(0.05, 0.07)
	titleFrame.BackgroundTransparency = 1
	titleFrame.Parent = parent

	local titleLayout = Instance.new("UIListLayout")
	titleLayout.FillDirection = Enum.FillDirection.Horizontal
	titleLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	titleLayout.Padding = UDim.new(0.002, 0)
	titleLayout.Parent = titleFrame

	local colorIndex = 1
	for i = 1, #text do
		local character = string.sub(text, i, i)
		local letterFrame = Instance.new("Frame")
		letterFrame.BackgroundTransparency = 1
		letterFrame.LayoutOrder = i
		if character == " " then
			letterFrame.Size = UDim2.fromScale(0.018, 1)
		else
			letterFrame.Size = UDim2.fromScale(0.03, 1)
		end
		letterFrame.Parent = titleFrame

		if character ~= " " then
			local shadow = Instance.new("TextLabel")
			shadow.BackgroundTransparency = 1
			shadow.Size = UDim2.fromScale(1, 1)
			shadow.Position = UDim2.fromOffset(3, 3)
			shadow.TextScaled = true
			shadow.Font = Enum.Font.GothamBlack
			shadow.TextColor3 = Color3.fromRGB(0, 0, 0)
			shadow.TextTransparency = 0.45
			shadow.Text = character
			shadow.Parent = letterFrame

			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.TextScaled = true
			label.Font = Enum.Font.GothamBlack
			label.TextColor3 = colors[colorIndex]
			label.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
			label.TextStrokeTransparency = 0
			label.Text = character
			label.Parent = letterFrame

			colorIndex += 1
			if colorIndex > #colors then
				colorIndex = 1
			end
		end
	end
end

-- buildEnemy(id, pos, color, material, size)
local function buildEnemy(id, pos, color, material, size)
	local body = Instance.new("Part")
	body.Name = ("Enemy_%d"):format(id)
	body.Shape = Enum.PartType.Ball
	body.Anchored = true
	body.CanCollide = false
	body.Size = Vector3.new(size, size, size)
	body.Color = color
	body.Material = material
	body.CFrame = CFrame.new(pos)
	body.Parent = workspace

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 64
	clickDetector.Parent = body
	clickDetector.MouseClick:Connect(function()
		showClickIdPopup(body, id, size)
		reEnemyClicked:FireServer(id)
	end)

	return body
end

-- spawnEnemy / destroyEnemies
local function spawnEnemy(id, pos, color, material, size)
	local existing = enemyRegistry[id]
	if existing then
		existing.body:Destroy()
		enemyRegistry[id] = nil
	end

	local body = buildEnemy(id, pos, color, material, size)
	enemyRegistry[id] = {
		body = body,
		targetCF = CFrame.new(pos),
		state = 0,
	}
end

local function destroyEnemies(ids)
	for _, id in ipairs(ids) do
		local entry = enemyRegistry[id]
		if entry then
			entry.body:Destroy()
			enemyRegistry[id] = nil
		end
	end
end

-- RE_Batch handler
reEnemyBatch.OnClientEvent:Connect(function(batchData)
	for _, row in ipairs(batchData) do
		local id = tonumber(row[1])
		local px = tonumber(row[2])
		local py = tonumber(row[3])
		local pz = tonumber(row[4])
		local lx = tonumber(row[5])
		local lz = tonumber(row[6])
		local stateCode = tonumber(row[7]) or 0

		if id and px and py and pz and lx and lz then
			local entry = enemyRegistry[id]
			if entry then
				local pos = Vector3.new(px, py, pz)
				local look = Vector3.new(lx, 0, lz)
				entry.targetCF = safeLookAt(pos, look)
				entry.state = stateCode
			end
		end
	end
end)

reEnemySpawn.OnClientEvent:Connect(function(id, pos, color, material, size)
	spawnEnemy(id, pos, color, material, size)
end)

reEnemyDestroy.OnClientEvent:Connect(function(ids)
	destroyEnemies(ids)
end)

-- RenderStepped lerp
RunService.RenderStepped:Connect(function(dt)
	local alpha = 1 - math.exp(-18 * dt)
	for _, entry in pairs(enemyRegistry) do
		entry.body.CFrame = entry.body.CFrame:Lerp(entry.targetCF, alpha)
	end
end)

-- Late-join
task.defer(function()
	local ok, snapshotOrErr = pcall(function()
		return rfGetAllEnemies:InvokeServer()
	end)
	if not ok then
		warn("[CLIENT] Failed to get enemy snapshot:", snapshotOrErr)
		return
	end

	local snapshot = snapshotOrErr
	for _, enemyData in ipairs(snapshot) do
		local id = tonumber(enemyData.id)
		local pos = enemyData.pos
		local color = enemyData.color
		local material = enemyData.material
		local size = tonumber(enemyData.size)
		local lookDir = enemyData.lookDir
		local stateCode = tonumber(enemyData.stateCode) or 0

		if
			id
			and typeof(pos) == "Vector3"
			and typeof(color) == "Color3"
			and typeof(material) == "EnumItem"
			and size
			and typeof(lookDir) == "Vector3"
		then
			spawnEnemy(id, pos, color, material, size)
			local entry = enemyRegistry[id]
			if entry then
				entry.targetCF = safeLookAt(pos, lookDir)
				entry.state = stateCode
				entry.body.CFrame = entry.targetCF
			end
		end
	end
end)

-- UIController
local playerGui = localPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EnemyClientUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local playScreen = Instance.new("Frame")
playScreen.Name = "PlayScreen"
playScreen.Size = UDim2.fromScale(1, 1)
playScreen.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
playScreen.Parent = screenGui

local backgroundImage = Instance.new("ImageLabel")
backgroundImage.Name = "BackgroundImage"
backgroundImage.Visible = true
backgroundImage.Size = UDim2.fromScale(1, 1)
backgroundImage.BackgroundTransparency = 1
backgroundImage.ImageTransparency = 0
backgroundImage.Image = START_SCREEN_BACKGROUND_IMAGE
backgroundImage.ScaleType = Enum.ScaleType.Crop
backgroundImage.ZIndex = 1
backgroundImage.Parent = playScreen

createRainbowTitle(playScreen, tr("ui.game_title"))

local playButton = Instance.new("TextButton")
playButton.Size = UDim2.new(0.36, 0, 0, 56)
playButton.Position = UDim2.fromScale(0.32, 0.69)
playButton.BackgroundColor3 = Color3.fromRGB(90, 255, 150)
playButton.TextColor3 = Color3.new(1, 1, 1)
playButton.TextStrokeColor3 = Color3.fromRGB(0, 80, 0)
playButton.TextStrokeTransparency = 0
playButton.TextScaled = true
playButton.Font = Enum.Font.GothamBold
playButton.Text = tr("ui.play_button")
playButton.ZIndex = 2
playButton.Parent = playScreen

local playButtonCorner = Instance.new("UICorner")
playButtonCorner.CornerRadius = UDim.new(1, 0)
playButtonCorner.Parent = playButton

local playButtonGradient = Instance.new("UIGradient")
playButtonGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(65, 255, 120)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 245, 255)),
})
playButtonGradient.Rotation = 12
playButtonGradient.Parent = playButton

local playButtonStroke = Instance.new("UIStroke")
playButtonStroke.Color = Color3.new(1, 1, 1)
playButtonStroke.Thickness = 3
playButtonStroke.Transparency = 0.15
playButtonStroke.Parent = playButton

local playButtonScale = Instance.new("UIScale")
playButtonScale.Scale = 1
playButtonScale.Parent = playButton

local hoverInTween =
	TweenService:Create(playButtonScale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = 1.05,
	})
local hoverOutTween =
	TweenService:Create(playButtonScale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = 1,
	})

playButton.MouseEnter:Connect(function()
	hoverOutTween:Cancel()
	hoverInTween:Play()
end)

playButton.MouseLeave:Connect(function()
	hoverInTween:Cancel()
	hoverOutTween:Play()
end)

local gameContainer = Instance.new("Frame")
gameContainer.Name = "GameContainer"
gameContainer.Size = UDim2.fromScale(1, 1)
gameContainer.BackgroundTransparency = 1
gameContainer.Visible = false
gameContainer.Parent = screenGui

local panel = Instance.new("Frame")
panel.Name = "ControlPanel"
panel.Size = UDim2.fromScale(0.28, 0.56)
panel.Position = UDim2.fromScale(0.69, 0.22)
panel.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
panel.BackgroundTransparency = 0.1
panel.Parent = gameContainer

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0.06, 0)
corner.Parent = panel

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0.035, 0)
panelPadding.PaddingBottom = UDim.new(0.035, 0)
panelPadding.PaddingLeft = UDim.new(0.05, 0)
panelPadding.PaddingRight = UDim.new(0.05, 0)
panelPadding.Parent = panel

local panelLayout = Instance.new("UIListLayout")
panelLayout.Padding = UDim.new(0.025, 0)
panelLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
panelLayout.Parent = panel

local function createLabel(text, order)
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.fromScale(1, 0.09)
	label.BackgroundTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextScaled = true
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text
	label.Parent = panel
	return label
end

local function createInput(order, initialValue)
	local input = Instance.new("TextBox")
	input.LayoutOrder = order
	input.Size = UDim2.fromScale(1, 0.11)
	input.BackgroundColor3 = Color3.fromRGB(36, 38, 46)
	input.TextColor3 = Color3.new(1, 1, 1)
	input.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
	input.TextScaled = true
	input.Font = Enum.Font.Gotham
	input.Text = initialValue
	input.ClearTextOnFocus = false
	input.Parent = panel
	return input
end

local function createSlider(order, minValue, maxValue, initialValue)
	local container = Instance.new("Frame")
	container.LayoutOrder = order
	container.Size = UDim2.fromScale(1, 0.08)
	container.BackgroundTransparency = 1
	container.Parent = panel

	local track = Instance.new("Frame")
	track.Size = UDim2.fromScale(1, 0.45)
	track.Position = UDim2.fromScale(0, 0.275)
	track.BackgroundColor3 = Color3.fromRGB(52, 56, 66)
	track.Parent = container

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(70, 130, 255)
	fill.Parent = track

	local dragging = false
	local value = initialValue

	local function setFromPercent(percent)
		local clamped = math.clamp(percent, 0, 1)
		value = minValue + (maxValue - minValue) * clamped
		fill.Size = UDim2.fromScale(clamped, 1)
	end

	local function setValue(newValue)
		local clampedValue = math.clamp(newValue, minValue, maxValue)
		local percent = (clampedValue - minValue) / (maxValue - minValue)
		setFromPercent(percent)
	end

	local function updateFromX(x)
		local startX = track.AbsolutePosition.X
		local width = math.max(track.AbsoluteSize.X, 1)
		setFromPercent((x - startX) / width)
	end

	track.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			updateFromX(input.Position.X)
		end
	end)

	track.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			updateFromX(input.Position.X)
		end
	end)

	setValue(initialValue)

	return container, function()
		return value
	end, setValue
end

local spawnRateValue = 1.0
local maxEnemiesValue = 20

createLabel(tr("ui.spawn_rate"), 1)
local _, getSpawnRate, setSpawnRate = createSlider(2, 0.1, 10, spawnRateValue)
local spawnRateInput = createInput(3, string.format("%.1f", spawnRateValue))

createLabel(tr("ui.max_enemies"), 4)
local _, getMaxEnemiesRaw, setMaxEnemies = createSlider(5, 1, 100, maxEnemiesValue)
local maxEnemiesInput = createInput(6, tostring(maxEnemiesValue))

local applyButton = Instance.new("TextButton")
applyButton.LayoutOrder = 7
applyButton.Size = UDim2.new(1, 0, 0, 44)
applyButton.BackgroundColor3 = Color3.fromRGB(44, 132, 78)
applyButton.TextColor3 = Color3.new(1, 1, 1)
applyButton.TextScaled = true
applyButton.Font = Enum.Font.GothamBold
applyButton.Text = tr("ui.apply")
applyButton.Parent = panel

local killAllButton = Instance.new("TextButton")
killAllButton.LayoutOrder = 8
killAllButton.Size = UDim2.new(1, 0, 0, 44)
killAllButton.BackgroundColor3 = Color3.fromRGB(190, 40, 40)
killAllButton.TextColor3 = Color3.new(1, 1, 1)
killAllButton.TextScaled = true
killAllButton.Font = Enum.Font.GothamBold
killAllButton.Text = tr("ui.kill_all")
killAllButton.Parent = panel

local deathScreen = Instance.new("Frame")
deathScreen.Name = "DeathScreen"
deathScreen.Size = UDim2.fromScale(1, 1)
deathScreen.BackgroundColor3 = Color3.new(0, 0, 0)
deathScreen.BackgroundTransparency = 0.35
deathScreen.Visible = false
deathScreen.Parent = screenGui

local deathLabel = Instance.new("TextLabel")
deathLabel.BackgroundTransparency = 1
deathLabel.Size = UDim2.fromScale(0.7, 0.18)
deathLabel.Position = UDim2.fromScale(0.15, 0.34)
deathLabel.TextScaled = true
deathLabel.Font = Enum.Font.GothamBlack
deathLabel.TextColor3 = Color3.fromRGB(255, 65, 65)
deathLabel.Text = tr("ui.you_died")
deathLabel.Parent = deathScreen

local restartButton = Instance.new("TextButton")
restartButton.Size = UDim2.new(0.3, 0, 0, 44)
restartButton.Position = UDim2.fromScale(0.35, 0.62)
restartButton.BackgroundColor3 = Color3.fromRGB(35, 95, 210)
restartButton.TextColor3 = Color3.new(1, 1, 1)
restartButton.TextScaled = true
restartButton.Font = Enum.Font.GothamBold
restartButton.Text = tr("ui.restart")
restartButton.Parent = deathScreen

playButton.Activated:Connect(function()
	reSetPlaying:FireServer(true)
	playScreen.Visible = false
	gameContainer.Visible = true
end)

spawnRateInput.FocusLost:Connect(function()
	local numeric = tonumber(spawnRateInput.Text)
	if numeric then
		spawnRateValue = math.clamp(numeric, 0.1, 10)
		setSpawnRate(spawnRateValue)
	end
	spawnRateValue = getSpawnRate()
	spawnRateInput.Text = string.format("%.1f", spawnRateValue)
end)

maxEnemiesInput.FocusLost:Connect(function()
	local numeric = tonumber(maxEnemiesInput.Text)
	if numeric then
		maxEnemiesValue = math.floor(math.clamp(numeric, 1, 100))
		setMaxEnemies(maxEnemiesValue)
	end
	maxEnemiesValue = math.floor(getMaxEnemiesRaw() + 0.5)
	maxEnemiesInput.Text = tostring(maxEnemiesValue)
end)

RunService.RenderStepped:Connect(function()
	local newSpawnRate = getSpawnRate()
	if math.abs(newSpawnRate - spawnRateValue) > 0.001 then
		spawnRateValue = newSpawnRate
		spawnRateInput.Text = string.format("%.1f", spawnRateValue)
	end

	local newMaxEnemies = math.floor(getMaxEnemiesRaw() + 0.5)
	if newMaxEnemies ~= maxEnemiesValue then
		maxEnemiesValue = newMaxEnemies
		maxEnemiesInput.Text = tostring(maxEnemiesValue)
	end
end)

applyButton.Activated:Connect(function()
	reUpdateSettings:FireServer(spawnRateValue, maxEnemiesValue)
end)

killAllButton.Activated:Connect(function()
	reKillAll:FireServer()
end)

local function onCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		reSetPlaying:FireServer(false)
		deathScreen.Visible = true
	end)
end

if localPlayer.Character then
	onCharacter(localPlayer.Character)
end

localPlayer.CharacterAdded:Connect(onCharacter)

restartButton.Activated:Connect(function()
	reSetPlaying:FireServer(true)
	reKillAll:FireServer(true)
	deathScreen.Visible = false
	gameContainer.Visible = true
	playScreen.Visible = false
end)
