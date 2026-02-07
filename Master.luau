-- Travel Tokens + Merchant Teleport (Minimal)
-- v = Teleport to TravelToken1, then 1s later TravelToken2 (if they exist)
-- Q = Teleport to travelling merchant (if not found, prints "no merchant")
-- Auto-teleport: when TravelToken1/2 timer hits 0, teleport to that token
-- J = Manually send webhook (includes weather + merchant selling list / selling nothing)
-- H = Server hop (manual)
--
-- NEW:
-- P = Toggle FULL AUTO CYCLE on/off (token -> merchant scan -> weather scan -> hop)
-- K = Merchant scan + webhook (only if selling special pack list)
-- L = Weather scan + webhook @everyone (only if Blood Moon / Sandstorm)
-- [ = Toggle token step on/off (inside full auto cycle)
-- ; = Toggle merchant step on/off (inside full auto cycle)
-- , = Toggle weather step on/off (inside full auto cycle)
-- - = Toggle hop step on/off (inside full auto cycle)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

local MERCHANT_TELEPORT_KEY = Enum.KeyCode.Q
local TOKEN_TELEPORT_KEY = Enum.KeyCode.V
local WEBHOOK_KEY = Enum.KeyCode.J
local SERVER_HOP_KEY = Enum.KeyCode.H

local AUTO_TOGGLE_KEY = Enum.KeyCode.P
local MERCHANT_SCAN_KEY = Enum.KeyCode.K
local WEATHER_SCAN_KEY = Enum.KeyCode.L

local TOGGLE_TOKENS_KEY = Enum.KeyCode.LeftBracket
local TOGGLE_MERCHANT_KEY = Enum.KeyCode.Semicolon
local TOGGLE_WEATHER_KEY = Enum.KeyCode.Comma
local TOGGLE_HOP_KEY = Enum.KeyCode.Minus

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
-- JSON CONFIG (TOGGLES PERSISTENCE)
-- =========================

local CONFIG_FOLDER = "TravelScript"
local CONFIG_FILE = CONFIG_FOLDER .. "/config.json"

local function canFileIO()
	return type(readfile) == "function"
		and type(writefile) == "function"
		and type(isfile) == "function"
end

local function ensureConfigFolder()
	if type(makefolder) == "function" and type(isfolder) == "function" then
		if not isfolder(CONFIG_FOLDER) then
			makefolder(CONFIG_FOLDER)
		end
	end
end

local DEFAULT_CONFIG = {
	AUTO_ENABLED = false,
	AUTO_DO_TOKENS = true,
	AUTO_DO_MERCHANT = true,
	AUTO_DO_WEATHER = true,
	AUTO_DO_HOP = true,
}

local function loadConfig()
	if not canFileIO() then
		warn("[CONFIG] File IO not available (readfile/writefile/isfile). Using in-memory defaults.")
		return DEFAULT_CONFIG
	end

	ensureConfigFolder()

	if not isfile(CONFIG_FILE) then
		writefile(CONFIG_FILE, HttpService:JSONEncode(DEFAULT_CONFIG))
		return DEFAULT_CONFIG
	end

	local okRead, raw = pcall(function()
		return readfile(CONFIG_FILE)
	end)

	if not okRead or type(raw) ~= "string" or raw == "" then
		warn("[CONFIG] Failed to read config; rewriting defaults.")
		writefile(CONFIG_FILE, HttpService:JSONEncode(DEFAULT_CONFIG))
		return DEFAULT_CONFIG
	end

	local okDecode, decoded = pcall(function()
		return HttpService:JSONDecode(raw)
	end)

	if not okDecode or type(decoded) ~= "table" then
		warn("[CONFIG] Config JSON invalid; rewriting defaults.")
		writefile(CONFIG_FILE, HttpService:JSONEncode(DEFAULT_CONFIG))
		return DEFAULT_CONFIG
	end

	for k, v in pairs(DEFAULT_CONFIG) do
		if decoded[k] == nil then
			decoded[k] = v
		end
	end

	return decoded
end

local function saveConfig(cfg)
	if not canFileIO() then
		return false
	end

	ensureConfigFolder()

	local okEncode, encoded = pcall(function()
		return HttpService:JSONEncode(cfg)
	end)
	if not okEncode then
		warn("[CONFIG] Failed to encode config.")
		return false
	end

	local okWrite, err = pcall(function()
		writefile(CONFIG_FILE, encoded)
	end)
	if not okWrite then
		warn("[CONFIG] Failed to write config:", err)
		return false
	end

	return true
end

local CONFIG = loadConfig()

local function syncTogglesFromConfig()
	AUTO_ENABLED = (CONFIG.AUTO_ENABLED == true)

	AUTO_DO_TOKENS = (CONFIG.AUTO_DO_TOKENS ~= false)
	AUTO_DO_MERCHANT = (CONFIG.AUTO_DO_MERCHANT ~= false)
	AUTO_DO_WEATHER = (CONFIG.AUTO_DO_WEATHER ~= false)
	AUTO_DO_HOP = (CONFIG.AUTO_DO_HOP ~= false)
end

local function syncConfigFromToggles()
	CONFIG.AUTO_ENABLED = (AUTO_ENABLED == true)

	CONFIG.AUTO_DO_TOKENS = (AUTO_DO_TOKENS == true)
	CONFIG.AUTO_DO_MERCHANT = (AUTO_DO_MERCHANT == true)
	CONFIG.AUTO_DO_WEATHER = (AUTO_DO_WEATHER == true)
	CONFIG.AUTO_DO_HOP = (AUTO_DO_HOP == true)
end

syncTogglesFromConfig()
syncConfigFromToggles()
saveConfig(CONFIG)

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
-- ONE-SHOT EVENT STATE (PREVENT SPAM + SEND END)
-- =========================

local WEATHER_EVENT_ACTIVE = false
local WEATHER_EVENT_SIGNATURE = ""
local WEATHER_EVENT_LAST_ALL = ""

local MERCHANT_EVENT_ACTIVE = false
local MERCHANT_EVENT_SIGNATURE = ""
local MERCHANT_EVENT_LAST_NAME = "No merchant found"

local function buildSignatureFromList(list, sep)
	local tmp = {}
	for _, v in ipairs(list or {}) do
		table.insert(tmp, tostring(v))
	end
	table.sort(tmp, function(a, b)
		return a < b
	end)
	return table.concat(tmp, sep or ", ")
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

-- =========================
-- MERCHANT EVENT (ONE-SHOT START/END)
-- =========================

local function merchantScanAndWebhookIfSpecial(forceSend)
	local merchant = findTravellingMerchant()

	if not merchant then
		if MERCHANT_EVENT_ACTIVE then
			local desc =
				"Merchant special ended (merchant not found).\n" ..
				"**Previous matches:**\n" .. (MERCHANT_EVENT_SIGNATURE ~= "" and MERCHANT_EVENT_SIGNATURE or "Unknown")
			sendDiscordWebhook("Merchant special ended", desc, MERCHANT_EVENT_LAST_NAME, {}, false)
			MERCHANT_EVENT_ACTIVE = false
			MERCHANT_EVENT_SIGNATURE = ""
			MERCHANT_EVENT_LAST_NAME = "No merchant found"
			return true
		end
		return false
	end

	local merchantName = merchant.Name or "Travelling Merchant"
	MERCHANT_EVENT_LAST_NAME = merchantName

	teleportNearModelOnGround(merchant, 10)

	local selling = waitForMerchantItems(2.5)
	if #selling <= 0 then
		if MERCHANT_EVENT_ACTIVE then
			local desc =
				"Merchant special ended (shop empty / not loaded).\n" ..
				"**Previous matches:**\n" .. (MERCHANT_EVENT_SIGNATURE ~= "" and MERCHANT_EVENT_SIGNATURE or "Unknown")
			sendDiscordWebhook("Merchant special ended", desc, merchantName, selling, false)
			MERCHANT_EVENT_ACTIVE = false
			MERCHANT_EVENT_SIGNATURE = ""
			return true
		end
		return false
	end

	local matched = getMatchedMerchantSpecials(selling)
	local signature = buildSignatureFromList(matched, "\n")

	if #matched <= 0 then
		if MERCHANT_EVENT_ACTIVE then
			local desc =
				"Merchant special ended.\n" ..
				"**Previous matches:**\n" .. (MERCHANT_EVENT_SIGNATURE ~= "" and MERCHANT_EVENT_SIGNATURE or "Unknown")
			sendDiscordWebhook("Merchant special ended", desc, merchantName, selling, false)
			MERCHANT_EVENT_ACTIVE = false
			MERCHANT_EVENT_SIGNATURE = ""
			return true
		end
		return false
	end

	if forceSend then
		local weatherNames = getActiveWeatherNames()
		local weatherText = (#weatherNames > 0) and table.concat(weatherNames, ", ") or "No active weather"
		local desc =
			"Special merchant item(s) detected:\n" ..
			"**Matches:**\n" .. clampDiscordFieldValue(signature) ..
			"\n\n**Current Weather:** " .. weatherText

		sendDiscordWebhook("Merchant special detected", desc, merchantName, selling, false)
		MERCHANT_EVENT_ACTIVE = true
		MERCHANT_EVENT_SIGNATURE = signature
		return true
	end

	if (not MERCHANT_EVENT_ACTIVE) then
		local weatherNames = getActiveWeatherNames()
		local weatherText = (#weatherNames > 0) and table.concat(weatherNames, ", ") or "No active weather"
		local desc =
			"Special merchant item(s) detected:\n" ..
			"**Matches:**\n" .. clampDiscordFieldValue(signature) ..
			"\n\n**Current Weather:** " .. weatherText

		sendDiscordWebhook("Merchant special detected", desc, merchantName, selling, false)
		MERCHANT_EVENT_ACTIVE = true
		MERCHANT_EVENT_SIGNATURE = signature
		return true
	end

	if MERCHANT_EVENT_SIGNATURE ~= signature then
		-- Only send again if the special list actually changed (prevents spam every cycle)
		local weatherNames = getActiveWeatherNames()
		local weatherText = (#weatherNames > 0) and table.concat(weatherNames, ", ") or "No active weather"
		local desc =
			"Merchant special changed:\n" ..
			"**New matches:**\n" .. clampDiscordFieldValue(signature) ..
			"\n\n**Current Weather:** " .. weatherText

		sendDiscordWebhook("Merchant special changed", desc, merchantName, selling, false)
		MERCHANT_EVENT_SIGNATURE = signature
		return true
	end

	return false
end

-- =========================
-- WEATHER EVENT (ONE-SHOT START/END)
-- =========================

local function weatherScanAndWebhookIfSpecial(forceSend)
	local weatherNames = getActiveWeatherNames()
	local allSignature = buildSignatureFromList(weatherNames, ", ")
	WEATHER_EVENT_LAST_ALL = allSignature

	local specialNames = {}
	for _, w in ipairs(weatherNames) do
		if strContainsAny(w, SPECIAL_WEATHER_KEYWORDS) then
			table.insert(specialNames, w)
		end
	end

	local specialSignature = buildSignatureFromList(specialNames, ", ")
	local isSpecialActive = (#specialNames > 0)

	if not isSpecialActive then
		if WEATHER_EVENT_ACTIVE then
			local merchant = findTravellingMerchant()
			local merchantName = (merchant and merchant.Name) or MERCHANT_EVENT_LAST_NAME or "No merchant found"

			local selling = {}
			if merchant then
				teleportNearModelOnGround(merchant, 10)
				selling = waitForMerchantItems(2.0)
			end

			local desc =
				"Special weather ended.\n" ..
				"**Previous special:** " .. (WEATHER_EVENT_SIGNATURE ~= "" and WEATHER_EVENT_SIGNATURE or "Unknown") ..
				"\n**Weather now:** " .. ((allSignature ~= "" and allSignature) or "No active weather")

			sendDiscordWebhook("SPECIAL WEATHER ENDED", desc, merchantName, selling, false)

			WEATHER_EVENT_ACTIVE = false
			WEATHER_EVENT_SIGNATURE = ""
			return true
		end
		return false
	end

	local merchant = findTravellingMerchant()
	local merchantName = merchant and merchant.Name or "No merchant found"

	local selling = {}
	if merchant then
		teleportNearModelOnGround(merchant, 10)
		selling = waitForMerchantItems(2.0)
	end

	if forceSend then
		local desc =
			"**Special weather detected:** " .. specialSignature ..
			"\n**All weather:** " .. ((allSignature ~= "" and allSignature) or "No active weather")

		sendDiscordWebhook("SPECIAL WEATHER", desc, merchantName, selling, true)

		WEATHER_EVENT_ACTIVE = true
		WEATHER_EVENT_SIGNATURE = specialSignature
		return true
	end

	if not WEATHER_EVENT_ACTIVE then
		local desc =
			"**Special weather started:** " .. specialSignature ..
			"\n**All weather:** " .. ((allSignature ~= "" and allSignature) or "No active weather")

		sendDiscordWebhook("SPECIAL WEATHER STARTED", desc, merchantName, selling, true)

		WEATHER_EVENT_ACTIVE = true
		WEATHER_EVENT_SIGNATURE = specialSignature
		return true
	end

	if WEATHER_EVENT_SIGNATURE ~= specialSignature then
		local desc =
			"**Special weather changed:** " .. specialSignature ..
			"\n**All weather:** " .. ((allSignature ~= "" and allSignature) or "No active weather")

		sendDiscordWebhook("SPECIAL WEATHER CHANGED", desc, merchantName, selling, true)

		WEATHER_EVENT_SIGNATURE = specialSignature
		return true
	end

	return false
end

-- =========================
-- WEBHOOK SENDER (MANUAL KEY ONLY)
-- =========================

local function sendWeatherWebhook()
	local weatherNames = getActiveWeatherNames()

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

local function flushActiveEventEndNotifications(reason)
	reason = tostring(reason or "Unknown")
	local sentAny = false

	if MERCHANT_EVENT_ACTIVE then
		local desc =
			"Merchant special ended (" .. reason .. ").\n" ..
			"**Previous matches:**\n" .. (MERCHANT_EVENT_SIGNATURE ~= "" and MERCHANT_EVENT_SIGNATURE or "Unknown")
		sendDiscordWebhook("Merchant special ended", desc, MERCHANT_EVENT_LAST_NAME, {}, false)
		MERCHANT_EVENT_ACTIVE = false
		MERCHANT_EVENT_SIGNATURE = ""
		sentAny = true
	end

	if WEATHER_EVENT_ACTIVE then
		local merchant = findTravellingMerchant()
		local merchantName = (merchant and merchant.Name) or MERCHANT_EVENT_LAST_NAME or "No merchant found"

		local selling = {}
		if merchant then
			teleportNearModelOnGround(merchant, 10)
			selling = waitForMerchantItems(2.0)
		end

		local desc =
			"Special weather ended (" .. reason .. ").\n" ..
			"**Previous special:** " .. (WEATHER_EVENT_SIGNATURE ~= "" and WEATHER_EVENT_SIGNATURE or "Unknown") ..
			"\n**Last seen weather:** " .. ((WEATHER_EVENT_LAST_ALL ~= "" and WEATHER_EVENT_LAST_ALL) or "Unknown")

		sendDiscordWebhook("SPECIAL WEATHER ENDED", desc, merchantName, selling, false)

		WEATHER_EVENT_ACTIVE = false
		WEATHER_EVENT_SIGNATURE = ""
		sentAny = true
	end

	return sentAny
end

local function runFullAutoCycleOnce()
	if AUTO_DO_TOKENS then
		tryPickupReadyTokensInOrder()
	end

	if AUTO_DO_MERCHANT then
		merchantScanAndWebhookIfSpecial(false)
	end

	if AUTO_DO_WEATHER then
		weatherScanAndWebhookIfSpecial(false)
	end

	if AUTO_DO_HOP then
		-- Prevent missing "ended" notifications when you leave the server
		flushActiveEventEndNotifications("server hop")

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
-- (EXACT LOGIC FROM YOUR WORKING SCRIPT)
-- =========================

local lastTeleportAttempt = 0
local TELEPORT_COOLDOWN = 5

local placeId = game.PlaceId
local currentJobId = game.JobId

-- cooldown in seconds (example: 10 minutes)
local SERVER_COOLDOWN = 10 * 60

-- extra short cooldown for servers that were full (race condition)
local FULL_SERVER_COOLDOWN = 30
local SERVER_LIST_RETRY_MAX = 5
local SERVER_LIST_RETRY_DELAY_START = 0.25
local SERVER_LIST_RETRY_DELAY_MAX = 1.0
local SERVER_LIST_RETRY_JITTER_MAX = 0.15

-- table to track visited servers
-- [serverId] flushActiveEventEndNotifications= lastVisitUnixTime
local visitedServers = visitedServers or {}

-- mark current server as visited
visitedServers[currentJobId] = os.time()

local hopping = false

-- tracking current teleport attempt so we can react to "GameFull" and try a different server
local currentAttemptServerId = nil
local teleportOutcome = nil
local teleportOutcomeData = nil

local function unfreezeCharacter()
	local char = player.Character
	if char then
		for _, v in ipairs(char:GetDescendants()) do
			if v:IsA("BasePart") then
				v.Anchored = false
			end
		end
	end
end

TeleportService.TeleportInitFailed:Connect(function(p, result, err)
	if p ~= Players.LocalPlayer then
		return
	end

	warn("[SERVER HOP] Teleport failed:", result, err)

	unfreezeCharacter()

	teleportOutcome = "failed"
	teleportOutcomeData = {
		result = result,
		err = err,
		serverId = currentAttemptServerId
	}
end)

player.OnTeleport:Connect(function(state)
	-- If we reach "Started", Roblox is taking over and this hop "succeeded" (we'll leave the server)
	if state == Enum.TeleportState.Started then
		teleportOutcome = "started"
		teleportOutcomeData = {
			serverId = currentAttemptServerId
		}
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

local function waitForTeleportOutcome(timeoutSeconds)
	local start = os.clock()
	while os.clock() - start < timeoutSeconds do
		if teleportOutcome ~= nil then
			return teleportOutcome, teleportOutcomeData
		end
		task.wait(0.05)
	end
	return nil, nil
end

local function isGameFullResult(result)
	-- Robust check across environments: compare to enum when possible, otherwise fall back to string match.
	if typeof(result) == "EnumItem" then
		return result == Enum.TeleportResult.GameFull
	end
	local s = tostring(result)
	return s:find("GameFull") ~= nil or s:find("Full") ~= nil
end

local function attemptTeleport(serverId)
	currentAttemptServerId = serverId
	teleportOutcome = nil
	teleportOutcomeData = nil

	local ok, callErr = pcall(function()
		TeleportService:TeleportToPlaceInstance(placeId, serverId, player)
	end)

	if not ok then
		warn("[SERVER HOP] TeleportToPlaceInstance threw:", callErr)
		unfreezeCharacter()
		return false, "call_error"
	end

	-- Wait a bit to catch GameFull / other failures before we give up and try another server
	local outcome, data = waitForTeleportOutcome(4)

	-- If teleport started, we're done (Roblox will move us)
	if outcome == "started" then
		return true, "started"
	end

	-- If we got a failure, decide what to do
	if outcome == "failed" then
		if data and isGameFullResult(data.result) then
			-- Mark as visited for a short time so we don't immediately try it again
			visitedServers[serverId] = os.time() - (SERVER_COOLDOWN - FULL_SERVER_COOLDOWN)
			return false, "full"
		end
		-- Other failures: still skip this server for normal cooldown to avoid loops
		visitedServers[serverId] = os.time()
		return false, "failed"
	end

	-- No signal: treat as inconclusive; skip briefly to avoid hammering the same server
	visitedServers[serverId] = os.time() - (SERVER_COOLDOWN - FULL_SERVER_COOLDOWN)
	return false, "timeout"
end

function hopServer()
	if hopping then
		return
	end
	hopping = true

	-- make sure we always release the lock even if we return early
	local function finish()
		hopping = false
		currentAttemptServerId = nil
	end

	if os.clock() - lastTeleportAttempt < TELEPORT_COOLDOWN then
		warn("[SERVER HOP] Teleport cooldown active")
		finish()
		return
	end

	lastTeleportAttempt = os.clock()

	local cursor = nil

	while true do
		local success = false
		local data = nil

		local delay = SERVER_LIST_RETRY_DELAY_START

		for attempt = 1, SERVER_LIST_RETRY_MAX do
			success, data = pcall(function()
				return getServers(cursor)
			end)

			if success and data and type(data.data) == "table" then
				break
			end

			if attempt < SERVER_LIST_RETRY_MAX then
				local jitter = (math.random() * SERVER_LIST_RETRY_JITTER_MAX)
				warn(string.format(
					"[SERVER HOP] Server list unavailable (rate limited?). Retry %d/%d in %.2fs...",
					attempt,
					SERVER_LIST_RETRY_MAX,
					delay + jitter
				))
				task.wait(delay + jitter)
				delay = math.min(delay * 2, SERVER_LIST_RETRY_DELAY_MAX)
			end
		end

		if not success or not data or type(data.data) ~= "table" then
			warn("[SERVER HOP] Server list unavailable after retries. Aborting hop.")
			finish()
			return
		end

		-- Build a list of candidates from this page
		local candidates = {}
		for _, server in ipairs(data.data) do
			if server.id ~= currentJobId
				and server.playing < server.maxPlayers
				and not isOnCooldown(server.id)
			then
				table.insert(candidates, server.id)
			end
		end

		-- Try candidates in order; if one is full (race), move on to the next
		for _, serverId in ipairs(candidates) do
			-- mark now to reduce double-attempt spam; full servers get downgraded to short cooldown inside attemptTeleport
			visitedServers[serverId] = os.time()

			local ok, reason = attemptTeleport(serverId)
			if ok then
				-- Teleport started; Roblox will move us
				return
			end

			-- Small yield to avoid rapid-fire teleport attempts
			task.wait(0.15)
		end

		if not data.nextPageCursor then
			break
		end

		cursor = data.nextPageCursor
		task.wait(0.2) -- small yield to avoid rate limits
	end

	finish()
	warn("[SERVER HOP] No available servers found outside cooldown")
end


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
		-- If you manually hop, also flush end notifications so you don't miss them.
		flushActiveEventEndNotifications("manual hop")

		print("[SERVER HOP] Attempting to hop servers...")
		hopRetryCount = 0
		hopServer()

	elseif input.KeyCode == AUTO_TOGGLE_KEY then
		AUTO_ENABLED = not AUTO_ENABLED
		print("[AUTO] FULL AUTO CYCLE:", AUTO_ENABLED and "ON" or "OFF")
		syncConfigFromToggles()
		saveConfig(CONFIG)

	elseif input.KeyCode == MERCHANT_SCAN_KEY then
		local ok = merchantScanAndWebhookIfSpecial(true)
		print("[MERCHANT SCAN] special found:", ok and "YES" or "NO")

	elseif input.KeyCode == WEATHER_SCAN_KEY then
		local ok = weatherScanAndWebhookIfSpecial(true)
		print("[WEATHER SCAN] special weather found:", ok and "YES" or "NO")

	elseif input.KeyCode == TOGGLE_TOKENS_KEY then
		AUTO_DO_TOKENS = not AUTO_DO_TOKENS
		print("[AUTO] tokens step:", AUTO_DO_TOKENS and "ON" or "OFF")
		syncConfigFromToggles()
		saveConfig(CONFIG)

	elseif input.KeyCode == TOGGLE_MERCHANT_KEY then
		AUTO_DO_MERCHANT = not AUTO_DO_MERCHANT
		print("[AUTO] merchant step:", AUTO_DO_MERCHANT and "ON" or "OFF")
		syncConfigFromToggles()
		saveConfig(CONFIG)

	elseif input.KeyCode == TOGGLE_WEATHER_KEY then
		AUTO_DO_WEATHER = not AUTO_DO_WEATHER
		print("[AUTO] weather step:", AUTO_DO_WEATHER and "ON" or "OFF")
		syncConfigFromToggles()
		saveConfig(CONFIG)

	elseif input.KeyCode == TOGGLE_HOP_KEY then
		AUTO_DO_HOP = not AUTO_DO_HOP
		print("[AUTO] hop step:", AUTO_DO_HOP and "ON" or "OFF")
		syncConfigFromToggles()
		saveConfig(CONFIG)
	end
end)
