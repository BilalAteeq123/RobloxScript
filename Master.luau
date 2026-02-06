-- Travel Tokens + Merchant Teleport (Minimal)
-- E = Teleport to TravelToken1, then 1s later TravelToken2 (if they exist)
-- Q = Teleport to travelling merchant (if not found, prints "no merchant")
-- Auto-teleport: when TravelToken1/2 timer hits 0, teleport to that token
-- J = Manually send webhook (includes weather + merchant selling list / selling nothing)
-- H = Server hop (manual)
--
-- NEW:
-- P = Toggle FULL AUTO CYCLE on/off (token -> merchant scan -> weather scan -> hop)
-- K = Merchant scan + webhook (only if selling special pack list)
-- L = Weather scan + webhook @everyone (only if Blood Moon / Sandstorm)
-- [ / ] = Toggle token step on/off (inside full auto cycle)
-- ; / ' = Toggle merchant step on/off (inside full auto cycle)
-- , / . = Toggle weather step on/off (inside full auto cycle)
-- - / = = Toggle hop step on/off (inside full auto cycle)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

local MERCHANT_TELEPORT_KEY = Enum.KeyCode.Q
local TOKEN_TELEPORT_KEY = Enum.KeyCode.E
local WEBHOOK_KEY = Enum.KeyCode.J
local SERVER_HOP_KEY = Enum.KeyCode.H

local AUTO_TOGGLE_KEY = Enum.KeyCode.P
local MERCHANT_SCAN_KEY = Enum.KeyCode.K
local WEATHER_SCAN_KEY = Enum.KeyCode.L

local TOGGLE_TOKENS_ON_KEY = Enum.KeyCode.LeftBracket
local TOGGLE_TOKENS_OFF_KEY = Enum.KeyCode.RightBracket
local TOGGLE_MERCHANT_ON_KEY = Enum.KeyCode.Semicolon
local TOGGLE_MERCHANT_OFF_KEY = Enum.KeyCode.Quote
local TOGGLE_WEATHER_ON_KEY = Enum.KeyCode.Comma
local TOGGLE_WEATHER_OFF_KEY = Enum.KeyCode.Period
local TOGGLE_HOP_ON_KEY = Enum.KeyCode.Minus
local TOGGLE_HOP_OFF_KEY = Enum.KeyCode.Equals

local TOKEN_EXTRA_Y = 0.5

local WATCHED_TOKENS = {
	{tokenName = "TravelToken1", timerName = "TravelToken1ParkourTimer"},
	{tokenName = "TravelToken2", timerName = "TravelToken2ParkourTimer"},
}

local TRAVELLING_MERCHANT_KEYWORDS = {
	"travelling", "traveling", "wandering", "merchantstand", "merchant stand"
}

-- =========================
-- AUTO CYCLE SETTINGS
-- =========================

local AUTO_ENABLED = false

local AUTO_DO_TOKENS = true
local AUTO_DO_MERCHANT = true
local AUTO_DO_WEATHER = true
local AUTO_DO_HOP = true

local AUTO_LOOP_DELAY = 1.0
local AUTO_CYCLE_COOLDOWN = 6.0
local lastAutoCycleAt = 0

-- =========================
-- SPECIAL WATCH LISTS
-- =========================

local SPECIAL_MERCHANT_ITEM_KEYWORDS = {
	"rainbow ego pack",
	"rainbow ego packs",
	"rainbow flight pack",
	"rainbow flight packs",
}

local SPECIAL_WEATHER_KEYWORDS = {
	"blood moon",
	"bloodmoon",
	"sandstorm",
}

-- =========================
-- DISCORD WEBHOOK LOGIC
-- =========================

local WEBHOOK_URL = "https://discord.com/api/webhooks/1468533154687225929/dzN_OZqHJlohalYYE5_ZEIEkRa12o_gnC18lT4vfTMZstrq0M4fFShCgqQLWofB_tqyD"

local function getCurrentServerLinks()
	return {
		profileJoin = "https://www.roblox.com/users/" .. player.UserId .. "/profile"
	}
end

local function getActiveWeatherNames()
	local weatherFolder =
		workspace:FindFirstChild("VFX")
		and workspace.VFX:FindFirstChild("Weather")

	local names = {}

	if weatherFolder then
		for _, child in ipairs(weatherFolder:GetChildren()) do
			table.insert(names, child.Name)
		end
	end

	return names
end

local function clampDiscordFieldValue(text)
	text = tostring(text or "")
	if #text <= 1024 then
		return text
	end
	return string.sub(text, 1, 1021) .. "..."
end

local function safeRequest(payloadTable)
	local ok, res = pcall(function()
		return request({
			Url = WEBHOOK_URL,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json"
			},
			Body = HttpService:JSONEncode(payloadTable)
		})
	end)

	if not ok then
		warn("[WEBHOOK] request failed:", res)
		return false
	end

	if res then
		print("[WEBHOOK] status:", res.StatusCode or res.Status or "unknown")
		if res.Body then
			print("[WEBHOOK] body:", tostring(res.Body))
		end
	else
		print("[WEBHOOK] sent (no response object)")
	end

	return true
end

local function sendDiscordWebhook(embedTitle, embedDescription, merchantName, merchantLines, mentionEveryone)
	local links = getCurrentServerLinks()

	local merchantText
	if merchantLines and #merchantLines > 0 then
		local maxItems = 25
		if #merchantLines > maxItems then
			local sliced = {}
			for i = 1, maxItems do
				table.insert(sliced, merchantLines[i])
			end
			merchantText = table.concat(sliced, "\n") .. "\n... (+" .. tostring(#merchantLines - maxItems) .. " more)"
		else
			merchantText = table.concat(merchantLines, "\n")
		end
	else
		merchantText = "selling nothing"
	end

	merchantText = clampDiscordFieldValue(merchantText)
	merchantName = clampDiscordFieldValue(merchantName or "No merchant found")

	local contentText =
		(mentionEveryone and "@everyone\n\n" or "") ..
		"👤 **Join via profile:**\n" ..
		links.profileJoin

	local payload = {
		content = contentText,
		allowed_mentions = mentionEveryone and { parse = {"everyone"} } or { parse = {} },
		embeds = {
			{
				title = tostring(embedTitle or "Notification"),
				description = tostring(embedDescription or ""),
				color = 0xffffff,
				fields = {
					{
						name = "Travelling Merchant",
						value = merchantName,
						inline = false
					},
					{
						name = "Merchant is selling",
						value = merchantText,
						inline = false
					}
				}
			}
		}
	}

	return safeRequest(payload)
end

-- =========================
-- CHARACTER / COMMON HELPERS
-- =========================

local function bindCharacter(newCharacter)
	character = newCharacter
	humanoidRootPart = character:WaitForChild("HumanoidRootPart")
end

player.CharacterAdded:Connect(bindCharacter)

local function ensureHumanoidRootPart()
	if not character or not character.Parent then
		character = player.Character or player.CharacterAdded:Wait()
	end
	if not humanoidRootPart or not humanoidRootPart.Parent then
		humanoidRootPart = character:WaitForChild("HumanoidRootPart")
	end
end

local function isCharacterModel(model)
	return model and model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function getModelTeleportPart(model)
	if not model then
		return nil
	end

	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function strContainsAny(haystack, needles)
	haystack = string.lower(tostring(haystack or ""))
	for _, n in ipairs(needles or {}) do
		if string.find(haystack, string.lower(tostring(n)), 1, true) then
			return true
		end
	end
	return false
end

-- =========================
-- MERCHANT FIND + TELEPORT (REFERENCE POINT + RAYCAST)
-- =========================

local function findTravellingMerchant()
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("Model") and obj ~= character and not isCharacterModel(obj) then
			local objName = string.lower(obj.Name)

			if objName == "merchantstand" then
				return obj
			end

			for _, k in ipairs(TRAVELLING_MERCHANT_KEYWORDS) do
				if string.find(objName, k, 1, true) then
					return obj
				end
			end
		end
	end

	return nil
end

local function teleportNearModelOnGround(model, horizontalDistance)
	ensureHumanoidRootPart()

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	local basePart = getModelTeleportPart(model)
	if not basePart then
		return false
	end

	local merchantPos = basePart.Position

	local referencePos = Vector3.new(-534, 9, -419)

	local dir = (referencePos - merchantPos)
	dir = Vector3.new(dir.X, 0, dir.Z)

	if dir.Magnitude < 0.05 then
		dir = Vector3.new(1, 0, 0)
	else
		dir = dir.Unit
	end

	local desiredXZ = merchantPos + (dir * horizontalDistance)

	local rayOrigin = desiredXZ + Vector3.new(0, 80, 0)
	local rayDir = Vector3.new(0, -250, 0)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local ignore = {}
	table.insert(ignore, character)
	table.insert(ignore, model)
	rayParams.FilterDescendantsInstances = ignore
	rayParams.IgnoreWater = true

	local result = workspace:Raycast(rayOrigin, rayDir, rayParams)

	if result then
		local standY = humanoid.HipHeight + (humanoidRootPart.Size.Y * 0.5) + 0.15
		local finalPos = Vector3.new(
			desiredXZ.X,
			result.Position.Y + standY + TOKEN_EXTRA_Y,
			desiredXZ.Z
		)
		humanoidRootPart.CFrame = CFrame.new(finalPos)
		return true
	end

	local fallbackPos = desiredXZ + Vector3.new(0, 6, 0)
	humanoidRootPart.CFrame = CFrame.new(fallbackPos)
	return true
end

-- =========================
-- MERCHANT SELLING (GUI-BASED: TravelMerchant)
-- =========================

local function getTravellingMerchantSelling()
	local sellingLines = {}

	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return sellingLines
	end

	local gui = playerGui:FindFirstChild("TravelMerchant")
	if not gui then
		return sellingLines
	end

	local frame = gui:FindFirstChild("Frame")
	local scrollingFrame = frame and frame:FindFirstChild("ScrollingFrame")
	if not scrollingFrame then
		return sellingLines
	end

	for _, itemFrame in ipairs(scrollingFrame:GetChildren()) do
		if not itemFrame:IsA("Frame") then
			continue
		end

		local itemName = itemFrame.Name
		local baseName = itemName
		local mutation = nil

		if itemName:find("-", 1, true) then
			baseName, mutation = itemName:match("(.+)%-(.+)")
		end

		local lowerBase = string.lower(baseName)
		local itemType = "Card"
		if lowerBase:find("mutation", 1, true) then
			itemType = "Mutation / Potion"
		elseif lowerBase:find("totem", 1, true) then
			itemType = "Totem"
		end

		local price = nil
		local requirements = itemFrame:FindFirstChild("Requirements", true)
		if requirements then
			local cash = requirements:FindFirstChild("Cash", true)
			if cash then
				local display = cash:FindFirstChild("Display", true)
				if display and display:IsA("TextLabel") then
					price = display.Text
				end
			end
		end

		local nameText = baseName
		if mutation and mutation ~= "" then
			nameText = nameText .. " (" .. mutation .. ")"
		end

		local priceText = price or "Unknown"
		local line = nameText .. " | " .. itemType .. " | " .. priceText
		table.insert(sellingLines, line)
	end

	table.sort(sellingLines, function(a, b)
		return tostring(a) < tostring(b)
	end)

	return sellingLines
end

local function waitForMerchantItems(maxWaitSeconds)
	local t0 = os.clock()
	while os.clock() - t0 < (maxWaitSeconds or 2) do
		local selling = getTravellingMerchantSelling()
		if #selling > 0 then
			return selling
		end
		task.wait(0.1)
	end
	return getTravellingMerchantSelling()
end

local function printTravellingMerchantShop()
	local selling = getTravellingMerchantSelling()

	print("========== [TRAVELLING MERCHANT SHOP] ==========")
	if #selling > 0 then
		for i, line in ipairs(selling) do
			print(i .. ") " .. tostring(line))
		end
	else
		print("selling nothing")
	end
	print("===============================================")
end

local function teleportToTravellingMerchant()
	local merchant = findTravellingMerchant()
	if merchant then
		local ok = teleportNearModelOnGround(merchant, 10)
		if not ok then
			print("no merchant")
			return
		end
		printTravellingMerchantShop()
	else
		print("no merchant")
	end
end

local function getMatchedMerchantSpecials(sellingLines)
	local matched = {}
	for _, line in ipairs(sellingLines or {}) do
		if strContainsAny(line, SPECIAL_MERCHANT_ITEM_KEYWORDS) then
			table.insert(matched, line)
		end
	end
	return matched
end

local function merchantScanAndWebhookIfSpecial()
	local merchant = findTravellingMerchant()
	if not merchant then
		return false
	end

	teleportNearModelOnGround(merchant, 10)

	-- let the shop UI populate if it opens when near merchant
	local selling = waitForMerchantItems(2.5)
	if #selling <= 0 then
		return false
	end

	local matched = getMatchedMerchantSpecials(selling)
	if #matched <= 0 then
		return false
	end

	local weatherNames = getActiveWeatherNames()
	local weatherText = (#weatherNames > 0) and table.concat(weatherNames, ", ") or "No active weather"

	local merchantName = merchant and merchant.Name or "No merchant found"
	local desc =
		"Special merchant item(s) detected (treat as weather signal):\n" ..
		"**Matches:**\n" .. clampDiscordFieldValue(table.concat(matched, "\n")) ..
		"\n\n**Current Weather:** " .. weatherText

	sendDiscordWebhook("Merchant special detected", desc, merchantName, selling, false)
	return true
end

local function weatherScanAndWebhookIfSpecial()
	local weatherNames = getActiveWeatherNames()
	if #weatherNames <= 0 then
		return false
	end

	local foundSpecial = false
	local specialNames = {}
	for _, w in ipairs(weatherNames) do
		if strContainsAny(w, SPECIAL_WEATHER_KEYWORDS) then
			foundSpecial = true
			table.insert(specialNames, w)
		end
	end

	if not foundSpecial then
		return false
	end

	local merchant = findTravellingMerchant()
	local merchantName = merchant and merchant.Name or "No merchant found"

	local selling = {}
	if merchant then
		teleportNearModelOnGround(merchant, 10)
		selling = waitForMerchantItems(2.0)
	end

	local desc =
		"**Special weather detected:** " .. table.concat(specialNames, ", ") ..
		"\n**All weather:** " .. table.concat(weatherNames, ", ")

	sendDiscordWebhook("SPECIAL WEATHER", desc, merchantName, selling, true)
	return true
end

-- =========================
-- WEBHOOK SENDER (MANUAL KEY ONLY)
-- (keeps your original J behavior: always sends)
-- =========================

local function sendWeatherWebhook()
	local weatherNames = getActiveWeatherNames()

	-- wait a moment for the shop UI to populate (if it's open)
	local selling = waitForMerchantItems(2)

	local merchant = findTravellingMerchant()

	local embedTitle
	local embedDescription

	if #weatherNames > 0 then
		embedTitle = "Weather detected"
		embedDescription = table.concat(weatherNames, ", ")
	else
		embedTitle = "No weather"
		embedDescription = "No active weather in this server"
	end

	local merchantName = merchant and merchant.Name or "No merchant found"

	sendDiscordWebhook(embedTitle, embedDescription, merchantName, selling, true)
end

-- Legacy duplicate function preserved but disabled (prevents overwrite)
if false then
	local function sendWeatherWebhook()
		local weatherNames = getActiveWeatherNames()
		local links = getCurrentServerLinks()

		local selling = getTravellingMerchantSelling()
		local merchant = findTravellingMerchant()

		local embedTitle
		local embedDescription

		if #weatherNames > 0 then
			embedTitle = "Weather detected"
			embedDescription = table.concat(weatherNames, ", ")
		else
			embedTitle = "No weather"
			embedDescription = "No active weather in this server"
		end

		local merchantText
		if #selling > 0 then
			local maxItems = 25
			if #selling > maxItems then
				local sliced = {}
				for i = 1, maxItems do
					table.insert(sliced, selling[i])
				end
				merchantText = table.concat(sliced, "\n") .. "\n... (+" .. tostring(#selling - maxItems) .. " more)"
			else
				merchantText = table.concat(selling, "\n")
			end
		else
			merchantText = "selling nothing"
		end

		local merchantName = merchant and merchant.Name or "No merchant found"

		request({
			Url = WEBHOOK_URL,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json"
			},
			Body = HttpService:JSONEncode({
				content =
					"@everyone\n\n👤 **Join via profile:**\n" ..
					links.profileJoin,
				allowed_mentions = {
					parse = {"everyone"}
				},
				embeds = {
					{
						title = embedTitle,
						description = embedDescription,
						color = 0xffffff,
						fields = {
							{
								name = "Travelling Merchant",
								value = merchantName,
								inline = false
							},
							{
								name = "Merchant is selling",
								value = merchantText,
								inline = false
							}
						}
					}
				}
			})
		})
	end
end

-- =========================
-- TOKEN TELEPORT LOGIC
-- =========================

local function getBestPickupPart(inst)
	if inst:IsA("BasePart") then
		return inst
	end

	local model = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end

	local bestPart
	local bestScore = -1

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local score = d.Size.Magnitude
			if d:FindFirstChildOfClass("TouchTransmitter") then
				score += 100
			end
			if score > bestScore then
				bestScore = score
				bestPart = d
			end
		end
	end

	return bestPart
end

local function teleportOnTopOfToken(tokenInstance)
	ensureHumanoidRootPart()

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local part = getBestPickupPart(tokenInstance)
	if not part then
		return
	end

	local y =
		part.Position.Y
		+ (part.Size.Y * 0.5)
		+ humanoid.HipHeight
		+ (humanoidRootPart.Size.Y * 0.5)
		+ TOKEN_EXTRA_Y

	humanoidRootPart.CFrame = CFrame.new(part.Position.X, y, part.Position.Z)
end

local function findWorldTokenByName(tokenName)
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj.Name == tokenName and (obj:IsA("BasePart") or obj:IsA("Model")) then
			if not obj:IsDescendantOf(character) then
				return obj
			end
		end
	end
end

local function teleportToBothSpawnedTravelTokens()
	local token1 = findWorldTokenByName("TravelToken1")
	local token2 = findWorldTokenByName("TravelToken2")

	if token1 then
		teleportOnTopOfToken(token1)
	end

	task.wait(1)

	if token2 then
		teleportOnTopOfToken(token2)
	end
end

-- =========================
-- TIMER WATCH (AUTO TELEPORT ONLY)
-- =========================

local timerConnections = {}
local lastTeleportAt = {}

local function parseTimerFromText(text)
	local mm, ss = tostring(text):match("(%d+)%s*:%s*(%d+)")
	if mm and ss then
		return (tonumber(mm) * 60) + tonumber(ss)
	end
	return tonumber(text)
end

local function getTimerSeconds(timerName)
	local timerContainer = workspace:FindFirstChild(timerName, true)
	if not timerContainer then
		return nil
	end

	for _, d in ipairs(timerContainer:GetDescendants()) do
		if d:IsA("TextLabel") and d.Text:find("%d") then
			return parseTimerFromText(d.Text)
		end
	end

	return nil
end

local function watchParkourTimer(tokenName, timerName)
	if timerConnections[timerName] then
		return
	end

	local timerContainer = workspace:FindFirstChild(timerName, true)
	if not timerContainer then
		return
	end

	local label
	for _, d in ipairs(timerContainer:GetDescendants()) do
		if d:IsA("TextLabel") and d.Text:find("%d") then
			label = d
			break
		end
	end

	if not label then
		timerConnections[timerName] = "no_label"
		return
	end

	local function onChanged()
		local v = parseTimerFromText(label.Text)
		if v and v <= 0 then
			local now = os.clock()
			if lastTeleportAt[timerName] and (now - lastTeleportAt[timerName]) < 1 then
				return
			end
			lastTeleportAt[timerName] = now

			local token = findWorldTokenByName(tokenName)
			if token then
				teleportOnTopOfToken(token)
			end
		end
	end

	timerConnections[timerName] = label:GetPropertyChangedSignal("Text"):Connect(onChanged)
	onChanged()
end

task.spawn(function()
	while true do
		for _, info in ipairs(WATCHED_TOKENS) do
			if timerConnections[info.timerName] ~= "no_label" then
				watchParkourTimer(info.tokenName, info.timerName)
			end
		end
		task.wait(1)
	end
end)

-- =========================
-- FULL AUTO CYCLE (ORDER YOU REQUESTED)
-- 1) check token ready -> pick up
-- 2) check merchant list -> if special packs, webhook (non-@everyone)
-- 3) check weather -> if Blood Moon / Sandstorm, webhook @everyone
-- 4) server hop
-- =========================

local function tryPickupReadyTokensInOrder()
	local didAnything = false

	for _, info in ipairs(WATCHED_TOKENS) do
		local secs = getTimerSeconds(info.timerName)
		if secs and secs <= 0 then
			local token = findWorldTokenByName(info.tokenName)
			if token then
				teleportOnTopOfToken(token)
				didAnything = true
				task.wait(0.35)
			end
		end
	end

	return didAnything
end

local function runFullAutoCycleOnce()
	if AUTO_DO_TOKENS then
		tryPickupReadyTokensInOrder()
	end

	if AUTO_DO_MERCHANT then
		merchantScanAndWebhookIfSpecial()
	end

	if AUTO_DO_WEATHER then
		weatherScanAndWebhookIfSpecial()
	end

	if AUTO_DO_HOP then
		print("[SERVER HOP] Attempting to hop servers...")
		hopRetryCount = 0
		hopServer()
	end
end

task.spawn(function()
	while true do
		if AUTO_ENABLED then
			local now = os.clock()
			if (now - lastAutoCycleAt) >= AUTO_CYCLE_COOLDOWN then
				lastAutoCycleAt = now
				pcall(runFullAutoCycleOnce)
			end
		end
		task.wait(AUTO_LOOP_DELAY)
	end
end)

-- =========================
-- SERVER HOP LOGIC (MANUAL KEY)
-- Fixes error 267 by:
-- 1) Only targeting servers with >=2 open slots (reduces race-to-full)
-- 2) Tracking "full" servers temporarily and skipping them
-- 3) Auto-retrying on TeleportInitFailed when result is GameFull/Flooded (or similar)
-- =========================

local lastTeleportAttempt = 0
local TELEPORT_COOLDOWN = 5

local placeId = game.PlaceId
local currentJobId = game.JobId

local SERVER_COOLDOWN = 10 * 60
local FULL_SERVER_COOLDOWN = 90
local MIN_OPEN_SLOTS = 2

local MAX_HOP_RETRIES = 6
hopRetryCount = 0

local visitedServers = visitedServers or {}
visitedServers[currentJobId] = os.time()

local fullServers = fullServers or {}

local hopping = false
local lastTargetServerId = nil

local function isOnCooldown(serverId)
	local lastVisit = visitedServers[serverId]
	if not lastVisit then
		return false
	end
	return (os.time() - lastVisit) < SERVER_COOLDOWN
end

local function isMarkedFull(serverId)
	local t = fullServers[serverId]
	if not t then
		return false
	end
	return (os.time() - t) < FULL_SERVER_COOLDOWN
end

local function markFull(serverId)
	if serverId and serverId ~= "" then
		fullServers[serverId] = os.time()
	end
end

local function getServers(cursor)
	local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?limit=100"
	if cursor then
		url = url .. "&cursor=" .. cursor
	end

	return HttpService:JSONDecode(game:HttpGet(url))
end

function hopServer()
	if hopping then
		return
	end
	hopping = true

	if os.clock() - lastTeleportAttempt < TELEPORT_COOLDOWN then
		warn("[SERVER HOP] Teleport cooldown active")
		hopping = false
		return
	end

	lastTeleportAttempt = os.clock()

	local cursor = nil

	while true do
		local success, data = pcall(function()
			return getServers(cursor)
		end)

		if not success or not data or type(data.data) ~= "table" then
			warn("[SERVER HOP] Server list unavailable (rate limited?).")
			hopping = false
			return
		end

		for _, server in ipairs(data.data) do
			local openSlots = (server.maxPlayers or 0) - (server.playing or 0)

			if server.id ~= currentJobId
				and openSlots >= MIN_OPEN_SLOTS
				and not isOnCooldown(server.id)
				and not isMarkedFull(server.id)
			then
				lastTargetServerId = server.id
				visitedServers[server.id] = os.time()

				local ok, err = pcall(function()
					TeleportService:TeleportToPlaceInstance(placeId, server.id, player)
				end)

				if not ok then
					warn("[SERVER HOP] Teleport call error:", err)
					markFull(server.id)
					lastTargetServerId = nil
					task.wait(0.25)
					continue
				end

				return
			end
		end

		if not data.nextPageCursor then
			break
		end

		cursor = data.nextPageCursor
		task.wait(0.2)
	end

	hopping = false
	warn("[SERVER HOP] No available servers found (outside cooldown/full list)")
end

TeleportService.TeleportInitFailed:Connect(function(p, result, err)
	if p ~= Players.LocalPlayer then
		return
	end

	warn("[SERVER HOP] Teleport failed:", result, err)

	local char = p.Character
	if char then
		for _, v in ipairs(char:GetDescendants()) do
			if v:IsA("BasePart") then
				v.Anchored = false
			end
		end
	end

	local r = tostring(result)
	local shouldRetry =
		(result == Enum.TeleportResult.GameFull)
		or (result == Enum.TeleportResult.Flooded)
		or (result == Enum.TeleportResult.Failure)
		or (r:lower():find("full", 1, true) ~= nil)
		or (tostring(err):find("267", 1, true) ~= nil)

	if shouldRetry then
		if lastTargetServerId then
			markFull(lastTargetServerId)
			lastTargetServerId = nil
		end

		hopping = false

		if hopRetryCount < MAX_HOP_RETRIES then
			hopRetryCount += 1
			task.delay(0.4, function()
				hopServer()
			end)
		else
			warn("[SERVER HOP] Gave up after retries")
			hopRetryCount = 0
		end

		return
	end

	hopping = false
	hopRetryCount = 0
	lastTargetServerId = nil
end)

-- =========================
-- INPUT BINDS
-- =========================

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == TOKEN_TELEPORT_KEY then
		task.spawn(teleportToBothSpawnedTravelTokens)

	elseif input.KeyCode == MERCHANT_TELEPORT_KEY then
		teleportToTravellingMerchant()

	elseif input.KeyCode == WEBHOOK_KEY then
		sendWeatherWebhook()

	elseif input.KeyCode == SERVER_HOP_KEY then
		print("[SERVER HOP] Attempting to hop servers...")
		hopRetryCount = 0
		hopServer()

	elseif input.KeyCode == AUTO_TOGGLE_KEY then
		AUTO_ENABLED = not AUTO_ENABLED
		print("[AUTO] FULL AUTO CYCLE:", AUTO_ENABLED and "ON" or "OFF")

	elseif input.KeyCode == MERCHANT_SCAN_KEY then
		local ok = merchantScanAndWebhookIfSpecial()
		print("[MERCHANT SCAN] special found:", ok and "YES" or "NO")

	elseif input.KeyCode == WEATHER_SCAN_KEY then
		local ok = weatherScanAndWebhookIfSpecial()
		print("[WEATHER SCAN] special weather found:", ok and "YES" or "NO")

	elseif input.KeyCode == TOGGLE_TOKENS_ON_KEY then
		AUTO_DO_TOKENS = true
		print("[AUTO] tokens step: ON")
	elseif input.KeyCode == TOGGLE_TOKENS_OFF_KEY then
		AUTO_DO_TOKENS = false
		print("[AUTO] tokens step: OFF")

	elseif input.KeyCode == TOGGLE_MERCHANT_ON_KEY then
		AUTO_DO_MERCHANT = true
		print("[AUTO] merchant step: ON")
	elseif input.KeyCode == TOGGLE_MERCHANT_OFF_KEY then
		AUTO_DO_MERCHANT = false
		print("[AUTO] merchant step: OFF")

	elseif input.KeyCode == TOGGLE_WEATHER_ON_KEY then
		AUTO_DO_WEATHER = true
		print("[AUTO] weather step: ON")
	elseif input.KeyCode == TOGGLE_WEATHER_OFF_KEY then
		AUTO_DO_WEATHER = false
		print("[AUTO] weather step: OFF")

	elseif input.KeyCode == TOGGLE_HOP_ON_KEY then
		AUTO_DO_HOP = true
		print("[AUTO] hop step: ON")
	elseif input.KeyCode == TOGGLE_HOP_OFF_KEY then
		AUTO_DO_HOP = false
		print("[AUTO] hop step: OFF")
	end
end)
