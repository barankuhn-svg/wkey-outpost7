--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer

-- Remote Setup
local enemyRemotes = ReplicatedStorage:WaitForChild("EnemyRemotes")
local reEnemySpawn = enemyRemotes:WaitForChild("EnemySpawn") :: RemoteEvent
local reEnemyDestroy = enemyRemotes:WaitForChild("EnemyDestroy") :: RemoteEvent
local reEnemyBatch = enemyRemotes:WaitForChild("EnemyBatch") :: RemoteEvent
local reEnemyClicked = enemyRemotes:WaitForChild("EnemyClicked") :: RemoteEvent
local reKillAll = enemyRemotes:WaitForChild("KillAll") :: RemoteEvent
local reUpdateSettings = enemyRemotes:WaitForChild("UpdateSettings") :: RemoteEvent
local rfGetAllEnemies = enemyRemotes:WaitForChild("GetAllEnemies") :: RemoteFunction

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local localizationModule = require(sharedFolder:WaitForChild("Localization")) :: { [string]: { [string]: string } }

-- Enemy Registry
type RegistryEntry = {
	body: Part,
	targetCF: CFrame,
	state: number,
}

local enemyRegistry: { [number]: RegistryEntry } = {}

local function resolveLanguage(localeId: string): string
	local normalized = string.lower(localeId)
	local localeMap: { [string]: string } = {
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

local function tr(key: string): string
	local langTable = localizationModule[activeLanguage] or localizationModule.en or {}
	local fallbackTable = localizationModule.en or {}
	return langTable[key] or fallbackTable[key] or key
end

local function enemyIdText(id: number): string
	return string.gsub(tr("ui.enemy_id"), "{id}", tostring(id))
end

local function safeLookAt(position: Vector3, lookDir: Vector3): CFrame
	local direction = Vector3.new(lookDir.X, 0, lookDir.Z)
	if direction.Magnitude < 0.001 then
		direction = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(position, position + direction.Unit)
end

-- buildEnemy(id, pos, color, material, size)
local function buildEnemy(id: number, pos: Vector3, color: Color3, material: Enum.Material, size: number): Part
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

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "EnemyId"
	billboard.Adornee = body
	billboard.Size = UDim2.fromScale(0.2, 0.08)
	billboard.StudsOffset = Vector3.new(0, size + 1.25, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = body

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.5
	label.Text = enemyIdText(id)
	label.Parent = billboard

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 64
	clickDetector.Parent = body
	clickDetector.MouseClick:Connect(function()
		print(("[CLIENT] Enemy clicked: ID = %d"):format(id))
		reEnemyClicked:FireServer(id)
	end)

	return body
end

-- spawnEnemy / destroyEnemies
local function spawnEnemy(id: number, pos: Vector3, color: Color3, material: Enum.Material, size: number)
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

local function destroyEnemies(ids: { number })
	for _, id in ipairs(ids) do
		local entry = enemyRegistry[id]
		if entry then
			entry.body:Destroy()
			enemyRegistry[id] = nil
		end
	end
end

-- RE_Batch handler
reEnemyBatch.OnClientEvent:Connect(function(batchData: { { any } })
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

reEnemySpawn.OnClientEvent:Connect(function(id: number, pos: Vector3, color: Color3, material: Enum.Material, size: number)
	spawnEnemy(id, pos, color, material, size)
end)

reEnemyDestroy.OnClientEvent:Connect(function(ids: { number })
	destroyEnemies(ids)
end)

-- RenderStepped lerp
RunService.RenderStepped:Connect(function(dt: number)
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

	local snapshot = snapshotOrErr :: { { [string]: any } }
	for _, enemyData in ipairs(snapshot) do
		local id = tonumber(enemyData.id)
		local pos = enemyData.pos
		local color = enemyData.color
		local material = enemyData.material
		local size = tonumber(enemyData.size)
		local lookDir = enemyData.lookDir
		local stateCode = tonumber(enemyData.stateCode) or 0

		if id and typeof(pos) == "Vector3" and typeof(color) == "Color3" and typeof(material) == "EnumItem" and size and typeof(lookDir) == "Vector3" then
			spawnEnemy(id, pos, color, material :: Enum.Material, size)
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

local titleLabel = Instance.new("TextLabel")
titleLabel.BackgroundTransparency = 1
titleLabel.Size = UDim2.fromScale(0.7, 0.2)
titleLabel.Position = UDim2.fromScale(0.15, 0.2)
titleLabel.TextScaled = true
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.Text = tr("ui.game_title")
titleLabel.Parent = playScreen

local playButton = Instance.new("TextButton")
playButton.Size = UDim2.new(0.3, 0, 0, 44)
playButton.Position = UDim2.fromScale(0.35, 0.72)
playButton.BackgroundColor3 = Color3.fromRGB(35, 95, 210)
playButton.TextColor3 = Color3.new(1, 1, 1)
playButton.TextScaled = true
playButton.Font = Enum.Font.GothamBold
playButton.Text = tr("ui.play_button")
playButton.Parent = playScreen

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

local function createLabel(text: string, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.fromScale(1, 0.09)
	label.BackgroundTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextScaled = true
	label.Font = Enum.Font.GothamSemibold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text
	label.Parent = panel
	return label
end

local function createInput(order: number, initialValue: string): TextBox
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

local function createSlider(order: number, minValue: number, maxValue: number, initialValue: number): (Frame, () -> number, (number) -> ())
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

	local function setFromPercent(percent: number)
		local clamped = math.clamp(percent, 0, 1)
		value = minValue + (maxValue - minValue) * clamped
		fill.Size = UDim2.fromScale(clamped, 1)
	end

	local function setValue(newValue: number)
		local clampedValue = math.clamp(newValue, minValue, maxValue)
		local percent = (clampedValue - minValue) / (maxValue - minValue)
		setFromPercent(percent)
	end

	local function updateFromX(x: number)
		local startX = track.AbsolutePosition.X
		local width = math.max(track.AbsoluteSize.X, 1)
		setFromPercent((x - startX) / width)
	end

	track.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			updateFromX(input.Position.X)
		end
	end)

	track.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromX(input.Position.X)
		end
	end)

	setValue(initialValue)

	return container, function(): number
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

local function onCharacter(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		deathScreen.Visible = true
	end)
end

if localPlayer.Character then
	onCharacter(localPlayer.Character)
end

localPlayer.CharacterAdded:Connect(onCharacter)

restartButton.Activated:Connect(function()
	reKillAll:FireServer()
	deathScreen.Visible = false
	localPlayer:LoadCharacter()
	gameContainer.Visible = true
	playScreen.Visible = false
end)
