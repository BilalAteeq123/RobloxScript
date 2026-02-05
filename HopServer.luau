local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local lastTeleportAttempt = 0
local TELEPORT_COOLDOWN = 5

local player = Players.LocalPlayer
local placeId = game.PlaceId
local currentJobId = game.JobId

-- cooldown in seconds (example: 10 minutes)
local SERVER_COOLDOWN = 10 * 60

-- table to track visited servers
-- [serverId] = lastVisitUnixTime
local visitedServers = visitedServers or {}

-- mark current server as visited
visitedServers[currentJobId] = os.time()

TeleportService.TeleportInitFailed:Connect(function(player, result, err)
	if player ~= Players.LocalPlayer then
		return
	end

	warn("[SERVER HOP] Teleport failed:", result, err)

	-- unfreeze character if Roblox left them stuck
	local char = player.Character
	if char then
		for _, v in ipairs(char:GetDescendants()) do
			if v:IsA("BasePart") then
				v.Anchored = false
			end
		end
	end
end)

local function isOnCooldown(serverId)
	local lastVisit = visitedServers[serverId]
	if not lastVisit then
		return false
	end
	return (os.time() - lastVisit) < SERVER_COOLDOWN
end

local function getServers(cursor)
	local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?limit=100"
	if cursor then
		url = url .. "&cursor=" .. cursor
	end

	return HttpService:JSONDecode(game:HttpGet(url))
end

local hopping = false

local function hopServer()
	if hopping then
		return
	end
	hopping = true
    
    if os.clock() - lastTeleportAttempt < TELEPORT_COOLDOWN then
        warn("[SERVER HOP] Teleport cooldown active")
        return
    end

    lastTeleportAttempt = os.clock()

	local cursor = nil

	while true do
		local success, data = pcall(function()
			return getServers(cursor)
		end)

		if not success or not data or type(data.data) ~= "table" then
			warn("[SERVER HOP] Server list unavailable (rate limited?). Retrying...")
			task.wait(2)
			hopping = false
			return
		end

		for _, server in ipairs(data.data) do
			if server.id ~= currentJobId
				and server.playing < server.maxPlayers
				and not isOnCooldown(server.id)
			then
				visitedServers[server.id] = os.time()
				TeleportService:TeleportToPlaceInstance(placeId, server.id, player)
				return
			end
		end

		if not data.nextPageCursor then
			break
		end

		cursor = data.nextPageCursor
		task.wait(0.2) -- small yield to avoid rate limits
	end

	hopping = false
	warn("[SERVER HOP] No available servers found outside cooldown")
end


local UserInputService = game:GetService("UserInputService")
local SERVER_HOP_KEY = Enum.KeyCode.H

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == SERVER_HOP_KEY then
		print("[SERVER HOP] Attempting to hop servers...")
		hopServer()
	end
end)
