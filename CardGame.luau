-- Enhanced Finder + Teleport Helper
-- Q = Diagnostic scan (no teleport)
-- T = Teleport to travelling merchant
-- E = Teleport to Travel Tokens (Token1, then 1s later Token2)
-- Auto-teleport: when TravelToken1/2 parkour timer hits 0, teleport to that token
-- R = Toggle coordinate HUD
-- F = Print coords once
-- G = Scan token parts near you and print (selects best part for teleport)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

local DIAGNOSTIC_KEY = Enum.KeyCode.Q
local MERCHANT_TELEPORT_KEY = Enum.KeyCode.T
local TOKEN_TELEPORT_KEY = Enum.KeyCode.V
local MERCHANT_DEEP_SCAN_KEY = Enum.KeyCode.U

local COORD_TOGGLE_KEY = Enum.KeyCode.R -- toggle HUD
local COORD_PRINT_KEY = Enum.KeyCode.F -- print coords once
local TOKEN_PART_SCAN_KEY = Enum.KeyCode.G -- scan token parts near you and print
local MERCHANT_SCAN_KEY = Enum.KeyCode.Y -- scan travelling merchant inventory

local TELEPORT_OFFSET = Vector3.new(8, 2, 8) -- used for merchant, not tokens
local TOKEN_EXTRA_Y = 0.5 -- small safety lift after placing on the top surface

local TOKEN_REFERENCE_POS = Vector3.new(-440, 44, -37)
local TOKEN_REFERENCE_RADIUS = 25 -- studs; increase if needed (ex: 50)
local TOKEN_REFERENCE_PRINT_LIMIT = 20

local SHOP_KEYWORDS = {
	"shop", "merchant", "vendor", "sell", "item", "ware",
	"market", "store", "travel", "travelling", "wandering"
}

local TRAVELLING_MERCHANT_KEYWORDS = {
	"travelling", "traveling", "wandering", "merchantstand", "merchant stand"
}

local TOKEN_KEYWORDS = {"token", "traveltoken", "travel_token"}
local EXACT_TOKEN_NAMES = {"travel token"} -- exact name match (case-insensitive)

local WATCHED_TOKENS = {
	{tokenName = "TravelToken1", timerName = "TravelToken1ParkourTimer"},
	{tokenName = "TravelToken2", timerName = "TravelToken2ParkourTimer"},
}

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

local coordHudGui = nil
local coordHudLabel = nil
local coordHudEnabled = true

local function round2(n)
	return math.floor((n * 100) + 0.5) / 100
end

local function vecToString(v)
	return "(" .. round2(v.X) .. ", " .. round2(v.Y) .. ", " .. round2(v.Z) .. ")"
end

local function ensureCoordHud()
	if coordHudGui and coordHudGui.Parent then
		return
	end

	coordHudGui = Instance.new("ScreenGui")
	coordHudGui.Name = "CoordHUD"
	coordHudGui.ResetOnSpawn = false

	local label = Instance.new("TextLabel")
	label.Name = "Coords"
	label.AnchorPoint = Vector2.new(0, 0)
	label.Position = UDim2.new(0, 10, 0, 10)
	label.Size = UDim2.new(0, 360, 0, 48)
	label.BackgroundTransparency = 0.3
	label.TextScaled = false
	label.TextSize = 18
	label.Font = Enum.Font.SourceSansBold
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = "Coords: (..)"
	label.Parent = coordHudGui

	coordHudLabel = label

	local playerGui = player:WaitForChild("PlayerGui")
	coordHudGui.Parent = playerGui
end

local function setHudEnabled(on)
	coordHudEnabled = on and true or false
	if coordHudGui then
		coordHudGui.Enabled = coordHudEnabled
	end
end

local function toggleHud()
	ensureCoordHud()
	setHudEnabled(not coordHudEnabled)
	print("[COORD HUD] " .. (coordHudEnabled and "ON" or "OFF"))
end

local function printMyCoords()
	ensureHumanoidRootPart()
	local pos = humanoidRootPart.Position
	print("[COORDS] HRP Position = " .. vecToString(pos))
end

ensureCoordHud()
setHudEnabled(true)

RunService.RenderStepped:Connect(function()
	if not coordHudEnabled then
		return
	end
	if not coordHudLabel then
		return
	end
	if not character or not character.Parent then
		return
	end
	if not humanoidRootPart or not humanoidRootPart.Parent then
		return
	end

	local pos = humanoidRootPart.Position
	coordHudLabel.Text = "HRP: " .. vecToString(pos)
end)

local function getModelTeleportPart(model)
	if not model then
		return nil
	end

	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function isCharacterModel(model)
	return model and model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function teleportToInstanceWithOffset(targetInstance, offset)
	ensureHumanoidRootPart()

	local targetPart = nil

	if targetInstance:IsA("BasePart") then
		targetPart = targetInstance
	elseif targetInstance:IsA("Model") then
		targetPart = getModelTeleportPart(targetInstance)
	else
		local asModel = targetInstance:FindFirstAncestorOfClass("Model")
		if asModel then
			targetPart = getModelTeleportPart(asModel)
		end
	end

	if targetPart then
		local targetPosition = targetPart.Position + offset
		humanoidRootPart.CFrame = CFrame.new(targetPosition)
		print("Teleported to: " .. targetInstance.Name)
		return true
	end

	print("Could not find a BasePart to teleport to for: " .. targetInstance:GetFullName())
	return false
end

local function getLikelyTimerValueObject(timerContainer)
	local best = nil
	local bestScore = -1

	for _, d in ipairs(timerContainer:GetDescendants()) do
		if d:IsA("IntValue") or d:IsA("NumberValue") or d:IsA("StringValue") then
			local n = string.lower(d.Name)
			local score = 0
			if string.find(n, "time", 1, true) then score = score + 3 end
			if string.find(n, "timer", 1, true) then score = score + 3 end
			if string.find(n, "count", 1, true) then score = score + 2 end
			if string.find(n, "sec", 1, true) then score = score + 2 end

			if score > bestScore then
				bestScore = score
				best = d
			end
		end
	end

	return best
end

local function readTimerValue(valueObj)
	if not valueObj then
		return nil
	end

	if valueObj:IsA("IntValue") or valueObj:IsA("NumberValue") then
		return valueObj.Value
	end

	if valueObj:IsA("StringValue") then
		return tonumber(valueObj.Value)
	end

	return nil
end

local function parseTimerFromText(text)
	if not text then
		return nil
	end

	local t = tostring(text)

	local mm, ss = t:match("(%d+)%s*:%s*(%d+)")
	if mm and ss then
		return (tonumber(mm) * 60) + tonumber(ss)
	end

	local hh, mm2, ss2 = t:match("(%d+)%s*:%s*(%d+)%s*:%s*(%d+)")
	if hh and mm2 and ss2 then
		return (tonumber(hh) * 3600) + (tonumber(mm2) * 60) + tonumber(ss2)
	end

	local lastNumber = nil
	for num in t:gmatch("(%d+%.?%d*)") do
		lastNumber = num
	end

	if lastNumber then
		return tonumber(lastNumber)
	end

	return nil
end

local function getTimerValueFromTextLabel(timerContainer)
	if not timerContainer then
		return nil, nil
	end

	local bestLabel = nil
	local bestScore = -1

	for _, d in ipairs(timerContainer:GetDescendants()) do
		if d:IsA("TextLabel") then
			local txt = d.Text or ""
			local score = 0

			if txt ~= "" then
				score += 10
			end

			if txt:find("%d") then
				score += 25
			end

			if txt:find(":") then
				score += 25
			end

			local nameLower = string.lower(d.Name)
			if nameLower:find("timer", 1, true) then score += 10 end
			if nameLower:find("time", 1, true) then score += 10 end

			if score > bestScore then
				bestScore = score
				bestLabel = d
			end
		end
	end

	if not bestLabel then
		return nil, nil
	end

	local parsed = parseTimerFromText(bestLabel.Text)
	return parsed, bestLabel
end

local function printTimerContainerContents(timerName)
	local timerContainer = workspace:FindFirstChild(timerName, true)
	if not timerContainer then
		print("[TIMER CONTENTS] " .. timerName .. ": not found")
		return nil, nil
	end

	print("[TIMER CONTENTS] " .. timerName .. " -> " .. timerContainer:GetFullName())
	local directChildren = timerContainer:GetChildren()
	if #directChildren == 0 then
		print("  (no direct children)")
	else
		for _, child in ipairs(directChildren) do
			print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
		end
	end

	local foundValueObjects = {}
	for _, d in ipairs(timerContainer:GetDescendants()) do
		if d:IsA("IntValue") or d:IsA("NumberValue") or d:IsA("StringValue") or d:IsA("BoolValue") then
			table.insert(foundValueObjects, d)
		end
	end

	if #foundValueObjects > 0 then
		print("  Value-like objects under timer:")
		for _, v in ipairs(foundValueObjects) do
			local valText = ""
			if v:IsA("BoolValue") then
				valText = tostring(v.Value)
			elseif v:IsA("IntValue") or v:IsA("NumberValue") then
				valText = tostring(v.Value)
			elseif v:IsA("StringValue") then
				valText = v.Value
			end
			print("    * " .. v.Name .. " (" .. v.ClassName .. ") = " .. valText .. "  [" .. v:GetFullName() .. "]")
		end
	else
		print("  (no Value-like objects found under timer)")
	end

	local likely = getLikelyTimerValueObject(timerContainer)
	local likelyValue = readTimerValue(likely)

	if likely then
		print("  Likely timer value object: " .. likely.Name .. " (" .. likely.ClassName .. ") = " .. tostring(likelyValue))
	else
		print("  Likely timer value object: none")
	end

	local textTimerValue, textLabel = getTimerValueFromTextLabel(timerContainer)
	if textLabel then
		print("  TextLabel timer: " .. textLabel.Name .. " = " .. tostring(textLabel.Text) .. "  (parsed=" .. tostring(textTimerValue) .. ")")
	else
		print("  TextLabel timer: none")
	end

	if likelyValue ~= nil then
		return likely, likelyValue
	end

	if textTimerValue ~= nil then
		return textLabel, textTimerValue
	end

	return nil, nil
end

local function getTokenSpawnStatusAndTimer(tokenName, timerName)
	local tokenTarget = workspace:FindFirstChild(tokenName, true)
	if tokenTarget then
		return true, nil, tokenTarget
	end

	local timerContainer = workspace:FindFirstChild(timerName, true)
	if not timerContainer then
		return false, nil, nil
	end

	local valueObj = getLikelyTimerValueObject(timerContainer)
	local v = readTimerValue(valueObj)
	if v ~= nil then
		return false, v, nil
	end

	local textV = nil
	local parsed, _ = getTimerValueFromTextLabel(timerContainer)
	textV = parsed

	return false, textV, nil
end


local function findTravellingMerchant()
	local best = nil

	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("Model") and obj ~= character and not isCharacterModel(obj) then
			local objName = string.lower(obj.Name)

			if objName == "merchantstand" then
				return obj
			end

			for _, k in ipairs(TRAVELLING_MERCHANT_KEYWORDS) do
				if string.find(objName, k, 1, true) then
					best = obj
					break
				end
			end
		end

		if best then
			break
		end
	end

	return best
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

	local dir = (humanoidRootPart.Position - merchantPos)
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
		local finalPos = Vector3.new(desiredXZ.X, result.Position.Y + standY + TOKEN_EXTRA_Y, desiredXZ.Z)
		humanoidRootPart.CFrame = CFrame.new(finalPos)
		return true
	end

	local fallbackPos = desiredXZ + Vector3.new(0, 6, 0)
	humanoidRootPart.CFrame = CFrame.new(fallbackPos)
	return true
end

local function teleportToTravellingMerchant()
	local merchant = findTravellingMerchant()
	if merchant then
		local ok = teleportNearModelOnGround(merchant, 10)
		if not ok then
			print("no merchant")
		end
	else
		print("no merchant")
	end
end

local function getBestPickupPart(inst)
	if not inst then
		return nil
	end

	if inst:IsA("BasePart") then
		return inst
	end

	local model = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end

	local bestPart = nil
	local bestScore = -1

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local score = 0

			if d:FindFirstChildOfClass("TouchTransmitter") then
				score += 100
			end

			score += d.Size.Magnitude

			if d.Transparency < 1 then
				score += 10
			end

			if score > bestScore then
				bestScore = score
				bestPart = d
			end
		end
	end

	return bestPart
end

local function getTopCenterForInstance(inst)
	if not inst then
		return nil, nil, nil
	end

	if inst:IsA("BasePart") then
		local topCenter = Vector3.new(inst.Position.X, inst.Position.Y + (inst.Size.Y * 0.5), inst.Position.Z)
		return topCenter, inst.Size, inst
	end

	local model = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model")
	if not model then
		return nil, nil, nil
	end

	local boxCFrame, boxSize = model:GetBoundingBox()
	local topCenter = Vector3.new(boxCFrame.Position.X, boxCFrame.Position.Y + (boxSize.Y * 0.5), boxCFrame.Position.Z)
	return topCenter, boxSize, model
end

local function getPartsForInstance(inst)
	local parts = {}

	if not inst then
		return parts
	end

	if inst:IsA("BasePart") then
		table.insert(parts, inst)
		return parts
	end

	local model = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model")
	if not model then
		return parts
	end

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end

	return parts
end

local function scanTokenPartsNearPosition(targetPos, radius)
	local candidates = {}

	for _, info in ipairs(WATCHED_TOKENS) do
		local tokenTarget = workspace:FindFirstChild(info.tokenName, true)
		if tokenTarget then
			for _, d in ipairs(tokenTarget:GetDescendants()) do
				if d:IsA("BasePart") then
					local dist = (d.Position - targetPos).Magnitude
					if dist <= radius then
						table.insert(candidates, {
							part = d,
							dist = dist,
							token = info.tokenName
						})
					end
				end
			end
		end
	end

	if #candidates == 0 then
		print("[REF SCAN] No token parts found within " .. tostring(radius) .. " studs of " .. tostring(targetPos))
		return
	end

	table.sort(candidates, function(a, b)
		return a.dist < b.dist
	end)

	print("========== [REF SCAN] Token parts near reference position ==========")
	print("[REF] pos=" .. tostring(targetPos) .. " radius=" .. tostring(radius))
	local top = math.min(TOKEN_REFERENCE_PRINT_LIMIT, #candidates)
	for i = 1, top do
		local c = candidates[i]
		local p = c.part
		print(
			i .. ") token=" .. c.token ..
			" dist=" .. tostring(math.floor(c.dist * 100 + 0.5) / 100) ..
			" part=" .. p.Name ..
			" pos=" .. tostring(p.Position) ..
			" full=" .. p:GetFullName()
		)
	end
	print("====================================================================")
end

local lastBestTokenPart = nil
local lastBestTokenPartDist = nil
local lastBestTokenModelName = nil

local function scanTokenPartsNearMe()
	ensureHumanoidRootPart()

	local myPos = humanoidRootPart.Position
	local candidates = {}

	for _, info in ipairs(WATCHED_TOKENS) do
		local tokenTarget = workspace:FindFirstChild(info.tokenName, true)
		if tokenTarget then
			local parts = getPartsForInstance(tokenTarget)
			for _, p in ipairs(parts) do
				if p and p:IsA("BasePart") then
					local d = (p.Position - myPos).Magnitude
					table.insert(candidates, {
						part = p,
						dist = d,
						token = info.tokenName
					})
				end
			end
		end
	end

	if #candidates == 0 then
		print("[TOKEN SCAN] No TravelToken1/2 spawned to scan.")
		return
	end

	table.sort(candidates, function(a, b)
		return a.dist < b.dist
	end)

	local top = math.min(15, #candidates)
	print("========== [TOKEN SCAN] Closest parts to YOU ==========")
	print("[YOU] " .. vecToString(myPos))
	for i = 1, top do
		local c = candidates[i]
		local p = c.part
		print(
			i .. ") token=" .. c.token ..
			" dist=" .. round2(c.dist) ..
			" part=" .. p.Name ..
			" pos=" .. vecToString(p.Position) ..
			" full=" .. p:GetFullName()
		)
	end
	print("=======================================================")

	local best = candidates[1]
	lastBestTokenPart = best.part
	lastBestTokenPartDist = best.dist
	lastBestTokenModelName = best.token

	print("[TOKEN SCAN] Selected best part for teleport:")
	print("  token=" .. tostring(lastBestTokenModelName))
	print("  part=" .. lastBestTokenPart:GetFullName())
	print("  partPos=" .. vecToString(lastBestTokenPart.Position))
	print("  dist=" .. round2(lastBestTokenPartDist))
end

local function teleportOnTopOfToken(tokenInstance)
	ensureHumanoidRootPart()

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		print("[TOKENS] Humanoid not found.")
		return false
	end

	local targetPart = nil

	if lastBestTokenPart and lastBestTokenPart.Parent then
		targetPart = lastBestTokenPart
		print("[TOKENS] Using scanned part:", targetPart:GetFullName())
	else
		targetPart = getBestPickupPart(tokenInstance)
		if targetPart then
			print("[TOKENS] Using best pickup part guess:", targetPart:GetFullName())
		end
	end

	if not targetPart then
		print("[TOKENS] No valid part found to teleport to for:", tokenInstance:GetFullName())
		return false
	end

	local topY = targetPart.Position.Y + (targetPart.Size.Y * 0.5)
	local finalY = topY + humanoid.HipHeight + (humanoidRootPart.Size.Y * 0.5) + TOKEN_EXTRA_Y

	local targetPos = Vector3.new(targetPart.Position.X, finalY, targetPart.Position.Z)
	humanoidRootPart.CFrame = CFrame.new(targetPos)

	print("[TOKENS] Teleported ON TOP of part:", targetPart:GetFullName())
	return true
end

local function teleportToSpawnedTravelToken()
	ensureHumanoidRootPart()

	local spawnedTokens = {}

	for _, info in ipairs(WATCHED_TOKENS) do
		local tokenTarget = workspace:FindFirstChild(info.tokenName, true)
		if tokenTarget then
			table.insert(spawnedTokens, tokenTarget)
		end
	end

	if #spawnedTokens == 0 then
		print("[TOKENS] No TravelToken1/2 currently spawned. Timers (if found):")
		for _, info in ipairs(WATCHED_TOKENS) do
			local spawned, timerValue = getTokenSpawnStatusAndTimer(info.tokenName, info.timerName)
			if spawned then
				print("  - " .. info.tokenName .. ": SPAWNED")
			else
				if timerValue ~= nil then
					print("  - " .. info.tokenName .. ": NOT SPAWNED, timer = " .. tostring(timerValue))
				else
					print("  - " .. info.tokenName .. ": NOT SPAWNED, timer = unknown")
				end
			end
		end
		return
	end

	local nearest = nil
	local nearestDist = nil

	for _, tok in ipairs(spawnedTokens) do
		local center = nil
		local c, _ = getTopCenterForInstance(tok)
		center = c

		if center then
			local d = (humanoidRootPart.Position - center).Magnitude
			if not nearestDist or d < nearestDist then
				nearestDist = d
				nearest = tok
			end
		end
	end

	if nearest then
		print("[TOKENS] Teleporting ON TOP (centered) of nearest spawned token: " .. nearest:GetFullName())
		teleportOnTopOfToken(nearest)
	else
		print("[TOKENS] Tokens were found but no valid center to teleport to.")
	end
end

local function findWorldTokenByName(tokenName)
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj.Name == tokenName and (obj:IsA("BasePart") or obj:IsA("Model")) then
			return obj
		end
	end
	return workspace:FindFirstChild(tokenName, true)
end

local function teleportToBothSpawnedTravelTokens()
	local token1 = findWorldTokenByName("TravelToken1")
	local token2 = findWorldTokenByName("TravelToken2")

	if not token1 and not token2 then
		print("[TOKENS] TravelToken1 and TravelToken2 not found.")
		return
	end

	if token1 then
		print("[TOKENS] E sequence: teleporting to TravelToken1 first -> " .. token1:GetFullName())
		teleportOnTopOfToken(token1)
	else
		print("[TOKENS] E sequence: TravelToken1 not found, skipping.")
	end

	task.wait(1)

	if token2 then
		print("[TOKENS] E sequence: teleporting to TravelToken2 second -> " .. token2:GetFullName())
		teleportOnTopOfToken(token2)
	else
		print("[TOKENS] E sequence: TravelToken2 not found, skipping.")
	end
end

local WEATHER_KEYWORDS = {
	"weather", "rain", "storm", "snow", "fog", "wind",
	"thunder", "lightning", "blizzard", "sandstorm",
	"hail", "cloud", "overcast"
}

local function scanForWeather()
	local found = {}

	for _, obj in ipairs(workspace:GetDescendants()) do
		local nameLower = string.lower(obj.Name)

		for _, k in ipairs(WEATHER_KEYWORDS) do
			if string.find(nameLower, k, 1, true) then
				table.insert(found, obj)
				break
			end
		end
	end

	print("---------- WEATHER SCAN ----------")

	if #found == 0 then
		print("[WEATHER] No weather detected in this server.")
	else
		print("[WEATHER] Found " .. #found .. " weather-related object(s):")
		for i, obj in ipairs(found) do
			print(
				"  " .. i .. ") " ..
				obj.ClassName .. " -> " ..
				obj.Name .. " @ " ..
				obj:GetFullName()
			)
		end
	end

	print("---------------------------------")
end

local WEBHOOK_URL = "https://discord.com/api/webhooks/1468533154687225929/dzN_OZqHJlohalYYE5_ZEIEkRa12o_gnC18lT4vfTMZstrq0M4fFShCgqQLWofB_tqyD"

local function sendWeatherWebhook()
	local weatherFolder =
		workspace:FindFirstChild("VFX")
		and workspace.VFX:FindFirstChild("Weather")

	local weatherNames = {}

	if weatherFolder then
		for _, child in ipairs(weatherFolder:GetChildren()) do
			table.insert(weatherNames, child.Name)
		end
	end

	local contentText
	local embedTitle

	local rawJoinLink =
		"roblox://placeId=" .. tostring(game.PlaceId) ..
		"&gameInstanceId=" .. tostring(game.JobId)

	local serverJoinLink =
		"https://www.roblox.com/games/start?placeId=" ..
		tostring(game.PlaceId) ..
		"&gameInstanceId=" ..
		tostring(game.JobId)

	if #weatherNames > 0 then
		embedTitle = "Weather detected"
		contentText = table.concat(weatherNames, ", ")
	else
		embedTitle = "No weather"
		contentText = "No active weather in this server"
	end

	request({
		Url = WEBHOOK_URL,
		Method = "POST",
		Headers = {
			["Content-Type"] = "application/json"
		},
		Body = game:GetService("HttpService"):JSONEncode({
			content = "🔗 Join Server:\n" .. serverJoinLink,
			embeds = {
				{
					title = embedTitle,
					url = serverJoinLink,
					description = contentText,
					color = 0xffffff
				}
			}
		})
	})
end


local function diagnoseScan()
	ensureHumanoidRootPart()

	print("========== ENHANCED DIAGNOSTIC SCAN ==========")

	print("---------- TIMER CONTAINER DUMP ----------")
	for _, info in ipairs(WATCHED_TOKENS) do
		printTimerContainerContents(info.timerName)
	end
	print("------------------------------------------")

	print("---------- TOKEN STATUS ----------")
	for _, info in ipairs(WATCHED_TOKENS) do
		local spawned, timerValue, tokenInstance = getTokenSpawnStatusAndTimer(info.tokenName, info.timerName)
		if spawned then
			print("[TOKEN STATUS] " .. info.tokenName .. ": SPAWNED -> " .. tokenInstance:GetFullName())
		else
			if timerValue ~= nil then
				print("[TOKEN STATUS] " .. info.tokenName .. ": NOT SPAWNED -> timer = " .. tostring(timerValue))
			else
				print("[TOKEN STATUS] " .. info.tokenName .. ": NOT SPAWNED -> timer = unknown (timer object not found)")
			end
		end
	end
	print("---------------------------------")

	local potentialShops = {}
	local travelTokens = {}
	local exactTravelTokens = {}

	for _, obj in ipairs(workspace:GetDescendants()) do
		local objName = string.lower(obj.Name)

		for _, exactName in ipairs(EXACT_TOKEN_NAMES) do
			if objName == exactName then
				table.insert(exactTravelTokens, obj)
				print("[EXACT TRAVEL TOKEN FOUND] " .. obj:GetFullName())
				break
			end
		end

		for _, tokenKeyword in ipairs(TOKEN_KEYWORDS) do
			if string.find(objName, tokenKeyword, 1, true) then
				table.insert(travelTokens, obj)
				print("[TRAVEL TOKEN FOUND] " .. obj:GetFullName())
				break
			end
		end

		if obj:IsA("Model") then
			if obj ~= character and not isCharacterModel(obj) then
				for _, keyword in ipairs(SHOP_KEYWORDS) do
					if string.find(objName, keyword, 1, true) then
						table.insert(potentialShops, obj)
						print("[SHOP FOUND] " .. obj:GetFullName())
						break
					end
				end
			end
		end
	end

	print("Found " .. #potentialShops .. " shop(s), " .. #travelTokens .. " token match(es), and " .. #exactTravelTokens .. " exact 'travel token' name match(es)")
	print("==============================================")

	print("---------- WEATHER STATUS ----------")
	sendWeatherWebhook()

	print("---------- REFERENCE POSITION SCAN ----------")
	scanTokenPartsNearPosition(TOKEN_REFERENCE_POS, TOKEN_REFERENCE_RADIUS)
end

local timerConnections = {}
local lastTeleportAt = {}

local function watchParkourTimer(tokenName, timerName)
	if timerConnections[timerName] then
		return
	end

	local timerContainer = workspace:FindFirstChild(timerName, true)
	if not timerContainer then
		return
	end

	local valueObj = getLikelyTimerValueObject(timerContainer)
	if not valueObj then
		print("[TIMER WATCH] Found " .. timerName .. " but no timer value object inside it.")
		timerConnections[timerName] = "no_value"
		return
	end

	print("[TIMER WATCH] Watching " .. timerName .. " -> " .. valueObj:GetFullName())

	local function onChanged()
		local v = readTimerValue(valueObj)
		if v == nil then
			return
		end

		if v <= 0 then
			local now = os.clock()
			local last = lastTeleportAt[timerName]
			if last and (now - last) < 1.0 then
				return
			end
			lastTeleportAt[timerName] = now

			local tokenTarget = findWorldTokenByName(tokenName)
			if tokenTarget then
				print("[TIMER ZERO] " .. timerName .. " reached 0 -> teleporting ON TOP (centered) of " .. tokenName)
				teleportOnTopOfToken(tokenTarget)
			else
				print("[TIMER ZERO] " .. timerName .. " reached 0 but couldn't find " .. tokenName .. " in workspace.")
			end
		end
	end

	local conn = valueObj:GetPropertyChangedSignal("Value"):Connect(onChanged)
	timerConnections[timerName] = conn

	onChanged()
end

task.spawn(function()
	while true do
		for _, info in ipairs(WATCHED_TOKENS) do
			if timerConnections[info.timerName] ~= "no_value" then
				watchParkourTimer(info.tokenName, info.timerName)
			end
		end
		task.wait(1)
	end
end)

local function scanTravellingMerchantInventory()
	local merchant = findTravellingMerchant()
	if not merchant then
		print("[MERCHANT SCAN] No travelling merchant found.")
		return
	end

	print("========== [TRAVELLING MERCHANT INVENTORY SCAN] ==========")
	print("Merchant model:", merchant:GetFullName())

	local foundItems = {}
	local seen = {}

	local function registerItem(name, obj)
		if not seen[name] then
			seen[name] = true
			table.insert(foundItems, {
				name = name,
				path = obj:GetFullName(),
				class = obj.ClassName
			})
		end
	end

	for _, d in ipairs(merchant:GetDescendants()) do
		-- Tools sold directly
		if d:IsA("Tool") then
			registerItem(d.Name, d)

		-- GUI buttons (shops often use these)
		elseif d:IsA("TextButton") or d:IsA("ImageButton") then
			local label = d.Text or d.Name
			if label ~= "" then
				registerItem(label, d)
			end

		-- Proximity / click based purchase systems
		elseif d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
			local parent = d.Parent
			if parent then
				registerItem(parent.Name, parent)
			end

		-- Models or parts with price/cost indicators
		elseif d:IsA("Model") or d:IsA("BasePart") then
			for _, v in ipairs(d:GetDescendants()) do
				if v:IsA("IntValue") or v:IsA("NumberValue") then
					local n = string.lower(v.Name)
					if
						n:find("price", 1, true)
						or n:find("cost", 1, true)
						or n:find("buy", 1, true)
						or n:find("sell", 1, true)
					then
						registerItem(d.Name, d)
						break
					end
				end
			end
		end
	end

	if #foundItems == 0 then
		print("[MERCHANT SCAN] No sellable items detected.")
	else
		print("[MERCHANT SCAN] Found " .. #foundItems .. " item(s):")
		for i, item in ipairs(foundItems) do
			print(
				i .. ") " ..
				item.name ..
				" [" .. item.class .. "] -> " ..
				item.path
			)
		end
	end

	print("=========================================================")
end

local function deepScanTravellingMerchant()
	local merchant = findTravellingMerchant()
	if not merchant then
		print("[MERCHANT DEEP SCAN] No travelling merchant found.")
		return
	end

	print("========== [MERCHANT DEEP SCAN BEGIN] ==========")
	print("Merchant model:", merchant:GetFullName())

	local total = 0

	for _, d in ipairs(merchant:GetDescendants()) do
		total += 1

		local line =
			"- " ..
			d.ClassName ..
			" | " ..
			d.Name ..
			" | " ..
			d:GetFullName()

		-- Dump value contents
		if d:IsA("IntValue")
			or d:IsA("NumberValue")
			or d:IsA("StringValue")
			or d:IsA("BoolValue")
			or d:IsA("ObjectValue")
		then
			local val
			pcall(function()
				val = d.Value
			end)
			line = line .. " => VALUE: " .. tostring(val)
		end

		print(line)

		-- Dump attributes if any
		local attrs = d:GetAttributes()
		for k, v in pairs(attrs) do
			print("    [ATTR] " .. k .. " = " .. tostring(v))
		end
	end

	print("[MERCHANT DEEP SCAN] Total descendants:", total)
	print("=========== [MERCHANT DEEP SCAN END] ===========")
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == DIAGNOSTIC_KEY then
		diagnoseScan()
	elseif input.KeyCode == MERCHANT_TELEPORT_KEY then
		teleportToTravellingMerchant()
	elseif input.KeyCode == TOKEN_TELEPORT_KEY then
		task.spawn(teleportToBothSpawnedTravelTokens)
	elseif input.KeyCode == COORD_TOGGLE_KEY then
		toggleHud()
	elseif input.KeyCode == COORD_PRINT_KEY then
		printMyCoords()
	elseif input.KeyCode == TOKEN_PART_SCAN_KEY then
		scanTokenPartsNearMe()
	elseif input.KeyCode == MERCHANT_SCAN_KEY then
		scanTravellingMerchantInventory()
	elseif input.KeyCode == MERCHANT_DEEP_SCAN_KEY then
		deepScanTravellingMerchant()
	end
end)