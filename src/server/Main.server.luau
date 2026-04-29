--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Remote Setup
local enemyRemotesFolder = ReplicatedStorage:FindFirstChild("EnemyRemotes")
if enemyRemotesFolder and not enemyRemotesFolder:IsA("Folder") then
	enemyRemotesFolder:Destroy()
	enemyRemotesFolder = nil
end
if not enemyRemotesFolder then
	enemyRemotesFolder = Instance.new("Folder")
	enemyRemotesFolder.Name = "EnemyRemotes"
	enemyRemotesFolder.Parent = ReplicatedStorage
end

local function getOrCreateRemoteEvent(name: string): RemoteEvent
	local existing = enemyRemotesFolder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = enemyRemotesFolder
	return remote
end

local function getOrCreateRemoteFunction(name: string): RemoteFunction
	local existing = enemyRemotesFolder:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = enemyRemotesFolder
	return remote
end

local enemySpawn = getOrCreateRemoteEvent("EnemySpawn")
local enemyDestroy = getOrCreateRemoteEvent("EnemyDestroy")
local enemyBatch = getOrCreateRemoteEvent("EnemyBatch")
local enemyClicked = getOrCreateRemoteEvent("EnemyClicked")
local killAllRemote = getOrCreateRemoteEvent("KillAll")
local updateSettings = getOrCreateRemoteEvent("UpdateSettings")
local getAllEnemies = getOrCreateRemoteFunction("GetAllEnemies")

-- Config
local config = {
	SPAWN_RATE = 1,
	MAX_ENEMIES = 20,
	CHASE_SPEED = 12,
	WANDER_SPEED = 4,
	ATTACK_RANGE = 4,
	ATTACK_DAMAGE = 10,
	ATTACK_CD = 1,
	WANDER_INTERVAL = 3.5,
	UPDATE_RATE = 0.05,
}

-- Enemy State
type EnemyStateName = "wander" | "chase" | "attack"
type EnemyData = {
	id: number,
	pos: Vector3,
	lookDir: Vector3,
	wanderPos: Vector3?,
	lastWander: number,
	lastAttack: number,
	state: EnemyStateName,
}

local enemies: { [number]: EnemyData } = {}
local nextEnemyId = 1

local stateCodeByName: { [EnemyStateName]: number } = {
	wander = 0,
	chase = 1,
	attack = 2,
}

local workspaceRef = game:GetService("Workspace")

local function getPlatformPart(): BasePart?
	local platform = workspaceRef:FindFirstChild("Platform")
	if platform and platform:IsA("BasePart") then
		return platform
	end
	return nil
end

local function getPlatformTopY(platform: BasePart): number
	return platform.Position.Y + (platform.Size.Y * 0.5)
end

local function randomPointOnPlatform(platform: BasePart): Vector3
	local halfX = platform.Size.X * 0.5
	local halfZ = platform.Size.Z * 0.5
	local x = platform.Position.X + (math.random() * 2 - 1) * halfX
	local z = platform.Position.Z + (math.random() * 2 - 1) * halfZ
	local y = getPlatformTopY(platform) + 1.5
	return Vector3.new(x, y, z)
end

local function isCharacterOnPlatform(rootPart: BasePart, platform: BasePart): boolean
	local relative = rootPart.Position - platform.Position
	local withinX = math.abs(relative.X) <= (platform.Size.X * 0.5)
	local withinZ = math.abs(relative.Z) <= (platform.Size.Z * 0.5)
	return withinX and withinZ
end

-- Deterministic Attributes
local colorPool = {
	Color3.fromRGB(239, 68, 68),
	Color3.fromRGB(249, 115, 22),
	Color3.fromRGB(250, 204, 21),
	Color3.fromRGB(74, 222, 128),
	Color3.fromRGB(59, 130, 246),
	Color3.fromRGB(168, 85, 247),
	Color3.fromRGB(244, 114, 182),
}

local materialPool = {
	Enum.Material.Concrete,
	Enum.Material.Metal,
	Enum.Material.Slate,
	Enum.Material.SmoothPlastic,
	Enum.Material.Neon,
}

local function getAttributes(id: number): (Color3, Enum.Material, number)
	local rng = Random.new(id * 99991 + 31337)
	local color = colorPool[rng:NextInteger(1, #colorPool)]
	local material = materialPool[rng:NextInteger(1, #materialPool)]
	local size = rng:NextNumber(2.0, 4.0)
	return color, material, size
end

-- Spawn/Destroy
local function getEnemyCount(): number
	local count = 0
	for _ in pairs(enemies) do
		count += 1
	end
	return count
end

local function spawnEnemy()
	if getEnemyCount() >= config.MAX_ENEMIES then
		return
	end

	local platform = getPlatformPart()
	if not platform then
		return
	end

	local id = nextEnemyId
	nextEnemyId += 1

	local spawnPos = randomPointOnPlatform(platform)
	local enemy: EnemyData = {
		id = id,
		pos = spawnPos,
		lookDir = Vector3.new(0, 0, -1),
		wanderPos = nil,
		lastWander = os.clock(),
		lastAttack = 0,
		state = "wander",
	}
	enemies[id] = enemy

	local color, material, size = getAttributes(id)
	enemySpawn:FireAllClients(id, enemy.pos, color, material, size)
end

local function destroyEnemy(id: number)
	if enemies[id] == nil then
		return
	end

	enemies[id] = nil
	enemyDestroy:FireAllClients({ id })
end

local function killAll()
	local ids = {}
	for id in pairs(enemies) do
		table.insert(ids, id)
		enemies[id] = nil
	end

	if #ids > 0 then
		enemyDestroy:FireAllClients(ids)
	end
end

local function moveTowards(current: Vector3, target: Vector3, speed: number, dt: number): Vector3
	local delta = target - current
	local distance = delta.Magnitude
	if distance <= 0 then
		return current
	end
	local step = math.min(distance, speed * dt)
	return current + delta.Unit * step
end

local function getClosestPlayerOnPlatform(enemyPos: Vector3, platform: BasePart): (Player?, BasePart?, Humanoid?, number)
	local closestPlayer: Player? = nil
	local closestRoot: BasePart? = nil
	local closestHumanoid: Humanoid? = nil
	local closestDistance = math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if rootPart and rootPart:IsA("BasePart") and humanoid and humanoid.Health > 0 then
				if isCharacterOnPlatform(rootPart, platform) then
					local delta = rootPart.Position - enemyPos
					local xzDistance = Vector2.new(delta.X, delta.Z).Magnitude
					if xzDistance < closestDistance then
						closestDistance = xzDistance
						closestPlayer = player
						closestRoot = rootPart
						closestHumanoid = humanoid
					end
				end
			end
		end
	end

	return closestPlayer, closestRoot, closestHumanoid, closestDistance
end

-- AI
local function updateAI(dt: number)
	local platform = getPlatformPart()
	if not platform then
		return
	end

	local now = os.clock()

	for _, enemy in pairs(enemies) do
		local _, targetRoot, targetHumanoid, xzDistance = getClosestPlayerOnPlatform(enemy.pos, platform)

		if targetRoot and targetHumanoid then
			local targetPosition = Vector3.new(targetRoot.Position.X, enemy.pos.Y, targetRoot.Position.Z)
			local toTarget = targetPosition - enemy.pos
			if toTarget.Magnitude > 0 then
				enemy.lookDir = toTarget.Unit
			end

			if xzDistance <= config.ATTACK_RANGE then
				enemy.state = "attack"
				if now - enemy.lastAttack >= config.ATTACK_CD then
					enemy.lastAttack = now
					print(("Enemy %d attacked %s"):format(enemy.id, targetHumanoid.Parent and targetHumanoid.Parent.Name or "unknown"))
					targetHumanoid:TakeDamage(config.ATTACK_DAMAGE)
				end
			else
				enemy.state = "chase"
				enemy.pos = moveTowards(enemy.pos, targetPosition, config.CHASE_SPEED, dt)
			end
		else
			enemy.state = "wander"
			local shouldPickNewWander = false

			if enemy.wanderPos == nil then
				shouldPickNewWander = true
			elseif now - enemy.lastWander >= config.WANDER_INTERVAL then
				shouldPickNewWander = true
			elseif (enemy.wanderPos - enemy.pos).Magnitude <= 0.5 then
				shouldPickNewWander = true
			end

			if shouldPickNewWander then
				enemy.wanderPos = randomPointOnPlatform(platform)
				enemy.lastWander = now
			end

			if enemy.wanderPos then
				local toWander = enemy.wanderPos - enemy.pos
				if toWander.Magnitude > 0 then
					enemy.lookDir = toWander.Unit
				end
				enemy.pos = moveTowards(enemy.pos, enemy.wanderPos, config.WANDER_SPEED, dt)
			end
		end
	end
end

-- Heartbeat loop
local spawnAccumulator = 0
local batchAccumulator = 0

RunService.Heartbeat:Connect(function(dt)
	spawnAccumulator += dt
	batchAccumulator += dt

	local spawnInterval = 1 / math.max(config.SPAWN_RATE, 0.001)
	while spawnAccumulator >= spawnInterval do
		spawnAccumulator -= spawnInterval
		spawnEnemy()
	end

	updateAI(dt)

	if batchAccumulator >= config.UPDATE_RATE then
		batchAccumulator = 0

		local payload = {}
		for _, enemy in pairs(enemies) do
			local code = stateCodeByName[enemy.state]
			table.insert(payload, {
				enemy.id,
				enemy.pos.X,
				enemy.pos.Y,
				enemy.pos.Z,
				enemy.lookDir.X,
				enemy.lookDir.Z,
				code,
			})
		end
		enemyBatch:FireAllClients(payload)
	end
end)

-- Remote Handlers
enemyClicked.OnServerEvent:Connect(function(player: Player, id: any)
	print(("EnemyClicked from %s on enemy %s"):format(player.Name, tostring(id)))
end)

killAllRemote.OnServerEvent:Connect(function()
	killAll()
end)

updateSettings.OnServerEvent:Connect(function(_player: Player, spawnRate: any, maxEnemies: any)
	local parsedSpawnRate = tonumber(spawnRate) or config.SPAWN_RATE
	local parsedMaxEnemies = tonumber(maxEnemies) or config.MAX_ENEMIES

	config.SPAWN_RATE = math.clamp(parsedSpawnRate, 0.1, 10)
	config.MAX_ENEMIES = math.floor(math.clamp(parsedMaxEnemies, 1, 100))
end)

getAllEnemies.OnServerInvoke = function(_player: Player)
	local snapshot = {}
	for _, enemy in pairs(enemies) do
		local color, material, size = getAttributes(enemy.id)
		table.insert(snapshot, {
			id = enemy.id,
			pos = enemy.pos,
			lookDir = enemy.lookDir,
			stateCode = stateCodeByName[enemy.state],
			color = color,
			material = material,
			size = size,
		})
	end
	return snapshot
end
