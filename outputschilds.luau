-- Card Market Stock Scanner + BuyAll
-- M = teleport to known market + scan stock UI
-- N = scan stock UI only
-- B = fire BuyAll remote
-- K = dump raw stock UI
-- J = toggle button checker on/off
-- H = toggle button checker scope (market-only / all buttons)

local ALLOWED_PLACE_ID = 76285745979410

if game.PlaceId ~= ALLOWED_PLACE_ID then
	warn("[CARD MARKET] Wrong game detected. Script will not load.")
	return
end

if _G.CARD_MARKET_STOCK_RUNNING then
	return
end
_G.CARD_MARKET_STOCK_RUNNING = true

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
if not player then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	player = Players.LocalPlayer
end

local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

player.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
	humanoidRootPart = character:WaitForChild("HumanoidRootPart")
end)

local TELEPORT_AND_SCAN_KEY = Enum.KeyCode.M
local SCAN_ONLY_KEY = Enum.KeyCode.N
local BUY_ALL_KEY = Enum.KeyCode.B
local RAW_DUMP_KEY = Enum.KeyCode.K
local TOGGLE_BUTTON_CHECKER_KEY = Enum.KeyCode.J
local TOGGLE_BUTTON_SCOPE_KEY = Enum.KeyCode.H

local REMOTES_FOLDER_NAME = "Remotes"
local BUY_ALL_REMOTE_NAME = "BuyAll"

local TOKEN_EXTRA_Y = 0.5
local TELEPORT_DISTANCE = 10

local BUTTON_TRACE_ENABLED = true
local BUTTON_TRACE_ALL = false
local TRACED_BUTTONS = setmetatable({}, { __mode = "k" })

local function ensureHumanoidRootPart()
	if not character or not character.Parent then
		character = player.Character or player.CharacterAdded:Wait()
	end
	if not humanoidRootPart or not humanoidRootPart.Parent then
		humanoidRootPart = character:WaitForChild("HumanoidRootPart")
	end
end

local LOG_FOLDER = "CardMarketLogs"
local LOG_FILE = LOG_FOLDER .. "/logs.txt"

local function canFileLog()
	return type(writefile) == "function"
		and type(appendfile) == "function"
		and type(isfile) == "function"
end

local function ensureLogFolder()
	if type(makefolder) == "function" and type(isfolder) == "function" then
		if not isfolder(LOG_FOLDER) then
			makefolder(LOG_FOLDER)
		end
	end
end

if canFileLog() then
	ensureLogFolder()
	writefile(LOG_FILE, "")
end

local function toLogString(...)
	local parts = {}

	for i = 1, select("#", ...) do
		local v = select(i, ...)
		table.insert(parts, tostring(v))
	end

	return table.concat(parts, " ")
end

local function appendLogLine(line)
	if not canFileLog() then
		return
	end

	ensureLogFolder()

	if not isfile(LOG_FILE) then
		writefile(LOG_FILE, "")
	end

	appendfile(LOG_FILE, os.date("[%H:%M:%S] ") .. tostring(line) .. "\n")
end

local _oldPrint = print
print = function(...)
	local line = toLogString(...)
	_oldPrint(...)
	appendLogLine(line)
end

local _oldWarn = warn
warn = function(...)
	local line = toLogString(...)
	_oldWarn(...)
	appendLogLine("[WARN] " .. line)
end

local function safeName(obj)
	if not obj then
		return "nil"
	end

	local ok, full = pcall(function()
		return obj:GetFullName()
	end)

	if ok and full then
		return full
	end

	return tostring(obj.Name or obj)
end

local function getGuiText(obj)
	if not obj then
		return ""
	end

	local ok, text = pcall(function()
		return obj.Text
	end)

	if ok and type(text) == "string" then
		text = text:gsub("%s+", " ")
		text = text:gsub("^%s+", "")
		text = text:gsub("%s+$", "")
		return text
	end

	return ""
end

local function normalizeText(text)
	text = tostring(text or "")
	text = string.lower(text)
	text = text:gsub("[%[%]%(%)%{%}%p]", " ")
	text = text:gsub("%s+", " ")
	text = text:gsub("^%s+", "")
	text = text:gsub("%s+$", "")
	return text
end

local function getParentChain(inst, maxDepth)
	local parts = {}
	local current = inst
	local depth = 0

	while current and depth < (maxDepth or 12) do
		table.insert(parts, 1, current.Name)
		current = current.Parent
		depth += 1
	end

	return table.concat(parts, " -> ")
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

local function getKnownCardMarket()
	local map = workspace:FindFirstChild("Map")
	if not map then
		return nil
	end

	local marketArea = map:FindFirstChild("Market Area")
	if not marketArea then
		return nil
	end

	local cardMarket = marketArea:FindFirstChild("Card Market")
	if not cardMarket then
		return nil
	end

	return cardMarket
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

	local targetPos = basePart.Position
	local referencePos = Vector3.new(-534, 9, -419)

	local dir = referencePos - targetPos
	dir = Vector3.new(dir.X, 0, dir.Z)

	if dir.Magnitude < 0.05 then
		dir = Vector3.new(1, 0, 0)
	else
		dir = dir.Unit
	end

	local desiredXZ = targetPos + (dir * horizontalDistance)

	local rayOrigin = desiredXZ + Vector3.new(0, 80, 0)
	local rayDir = Vector3.new(0, -250, 0)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {character, model}
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

local function getStockGui()
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil
	end

	return playerGui:FindFirstChild("Stock")
end

local function getStockFrame()
	local stockGui = getStockGui()
	if not stockGui then
		return nil
	end

	return stockGui:FindFirstChild("Frame")
end

local function getStockScrollingFrame()
	local frame = getStockFrame()
	if not frame then
		return nil
	end

	return frame:FindFirstChild("ScrollingFrame")
end

local function getTextFromChild(parent, childName)
	if not parent then
		return ""
	end

	local child = parent:FindFirstChild(childName)
	if not child then
		return ""
	end

	return getGuiText(child)
end

local function dumpButtonState(button, label)
	if not button then
		print("[BUTTON STATE]", tostring(label), "button=nil")
		return
	end

	print("------ [BUTTON STATE] " .. tostring(label) .. " ------")
	print("PATH:", safeName(button))
	print("CLASS:", button.ClassName)
	print("VISIBLE:", tostring(button.Visible))
	print("ACTIVE:", tostring(button.Active))
	print("SELECTABLE:", tostring(button.Selectable))
	print("AUTO_BUTTON_COLOR:", tostring(button.AutoButtonColor))
	print("MODAL:", tostring(button.Modal))
	print("ZINDEX:", tostring(button.ZIndex))
	print("ABS_POS:", tostring(button.AbsolutePosition))
	print("ABS_SIZE:", tostring(button.AbsoluteSize))

	local okInteractable, interactable = pcall(function()
		return button.Interactable
	end)
	if okInteractable then
		print("INTERACTABLE:", tostring(interactable))
	end

	local amountLabel = button:FindFirstChild("Amount")
	if amountLabel then
		print("AMOUNT TEXT:", getGuiText(amountLabel))
	end

	local parent = button.Parent
	if parent then
		print("PARENT:", safeName(parent))
		for _, child in ipairs(parent:GetChildren()) do
			local text = getGuiText(child)
			if text ~= "" then
				print("[PARENT CHILD]", "[" .. child.ClassName .. "]", safeName(child), "=>", text)
			else
				print("[PARENT CHILD]", "[" .. child.ClassName .. "]", safeName(child))
			end
		end
	end

	print("-----------------------------------")
end

local function buildParsedItemLine(itemFrame)
	local packName = getTextFromChild(itemFrame, "PackName")
	local mutation = getTextFromChild(itemFrame, "Mutation")
	local stockText = getTextFromChild(itemFrame, "Stock")
	local priceText = getTextFromChild(itemFrame, "Price")
	local discountText = getTextFromChild(itemFrame, "Discount")

	if packName == "" and mutation == "" and stockText == "" and priceText == "" and discountText == "" then
		return nil
	end

	local left = ""

	if mutation ~= "" and packName ~= "" then
		left = mutation .. " " .. packName
	elseif packName ~= "" then
		left = packName
	elseif mutation ~= "" then
		left = mutation
	else
		left = itemFrame.Name
	end

	local parts = {left}

	if stockText ~= "" then
		table.insert(parts, stockText)
	end

	if priceText ~= "" then
		table.insert(parts, "Price: " .. priceText)
	end

	if discountText ~= "" then
		table.insert(parts, "Discount: " .. discountText)
	end

	return table.concat(parts, " | ")
end

local function getRawChildOutput(itemFrame)
	local raw = {}

	for _, child in ipairs(itemFrame:GetDescendants()) do
		local entry = "[" .. child.ClassName .. "] " .. safeName(child)

		local text = getGuiText(child)
		if text ~= "" then
			entry = entry .. " => " .. text
		end

		table.insert(raw, entry)
	end

	table.sort(raw, function(a, b)
		return tostring(a) < tostring(b)
	end)

	return raw
end

local function getCardMarketItems()
	local items = {}
	local scrollingFrame = getStockScrollingFrame()

	if not scrollingFrame then
		return items
	end

	for _, itemFrame in ipairs(scrollingFrame:GetChildren()) do
		if itemFrame:IsA("Frame") and tonumber(itemFrame.Name) then
			local packName = getTextFromChild(itemFrame, "PackName")
			local mutation = getTextFromChild(itemFrame, "Mutation")
			local stockText = getTextFromChild(itemFrame, "Stock")
			local priceText = getTextFromChild(itemFrame, "Price")
			local discountText = getTextFromChild(itemFrame, "Discount")

			local rawLines = {}
			for _, child in ipairs(itemFrame:GetChildren()) do
				local entry = "[" .. child.ClassName .. "] " .. safeName(child)
				local text = getGuiText(child)
				if text ~= "" then
					entry = entry .. " => " .. text
				end
				table.insert(rawLines, entry)
			end

			table.sort(rawLines, function(a, b)
				return tostring(a) < tostring(b)
			end)

			local left = ""
			if mutation ~= "" and packName ~= "" then
				left = mutation .. " " .. packName
			elseif packName ~= "" then
				left = packName
			elseif mutation ~= "" then
				left = mutation
			else
				left = itemFrame.Name
			end

			local parts = {left}
			if stockText ~= "" then
				table.insert(parts, stockText)
			end
			if priceText ~= "" then
				table.insert(parts, "Price: " .. priceText)
			end
			if discountText ~= "" then
				table.insert(parts, "Discount: " .. discountText)
			end

			table.insert(items, {
				frame = itemFrame,
				frameName = itemFrame.Name,
				packName = packName,
				mutation = mutation,
				stockText = stockText,
				priceText = priceText,
				discountText = discountText,
				parsed = table.concat(parts, " | "),
				raw = rawLines
			})
		end
	end

	table.sort(items, function(a, b)
		return tonumber(a.frameName) < tonumber(b.frameName)
	end)

	return items
end

local function printCardMarketItems()
	local items = getCardMarketItems()

	print("========== [CARD MARKET] ==========")
	if #items > 0 then
		for i, item in ipairs(items) do
			print(i .. ") " .. tostring(item.parsed))
			print("    FOLDER:", safeName(item.frame))
			print("    RAW KEY FIELDS:",
				"PackName=" .. tostring(item.packName ~= "" and item.packName or "(blank)"),
				"Mutation=" .. tostring(item.mutation ~= "" and item.mutation or "(blank)"),
				"Stock=" .. tostring(item.stockText ~= "" and item.stockText or "(blank)"),
				"Price=" .. tostring(item.priceText ~= "" and item.priceText or "(blank)"),
				"Discount=" .. tostring(item.discountText ~= "" and item.discountText or "(blank)")
			)

			if #item.raw > 0 then
				for _, rawLine in ipairs(item.raw) do
					print("    RAW:", rawLine)
				end
			else
				print("    RAW: (no descendants)")
			end
		end
	else
		print("no market items found")
	end
	print("===================================")
end

local function debugDumpStockUi()
	local stockGui = getStockGui()
	local frame = getStockFrame()
	local scrollingFrame = getStockScrollingFrame()
	local items = getCardMarketItems()

	print("========== [CARD MARKET UI DEBUG] ==========")
	print("StockGui:", stockGui and safeName(stockGui) or "nil")
	print("Frame:", frame and safeName(frame) or "nil")
	print("ScrollingFrame:", scrollingFrame and safeName(scrollingFrame) or "nil")

	if frame then
		for _, child in ipairs(frame:GetDescendants()) do
			local text = getGuiText(child)
			if text ~= "" then
				print("[FRAME RAW]", "[" .. child.ClassName .. "]", safeName(child), "=>", text)
			else
				print("[FRAME RAW]", "[" .. child.ClassName .. "]", safeName(child))
			end
		end
	end

	print("------ [ITEM FRAMES] ------")
	for i, item in ipairs(items) do
		print(i .. ") FRAME:", safeName(item.frame))
		print("    PARSED:", item.parsed)
		print("    RAW KEY FIELDS:",
			"PackName=" .. tostring(item.packName ~= "" and item.packName or "(blank)"),
			"Mutation=" .. tostring(item.mutation ~= "" and item.mutation or "(blank)"),
			"Stock=" .. tostring(item.stockText ~= "" and item.stockText or "(blank)"),
			"Price=" .. tostring(item.priceText ~= "" and item.priceText or "(blank)"),
			"Discount=" .. tostring(item.discountText ~= "" and item.discountText or "(blank)")
		)

		if #item.raw > 0 then
			for _, rawLine in ipairs(item.raw) do
				print("    RAW:", rawLine)
			end
		else
			print("    RAW: (no descendants)")
		end
	end

	print("===========================================")
end

local function clickGuiButton(button)
	if not button or not button:IsA("GuiButton") then
		return false
	end

	if not button.Visible then
		return false
	end

	if button.AbsoluteSize.X <= 0 or button.AbsoluteSize.Y <= 0 then
		return false
	end

	local absPos = button.AbsolutePosition
	local absSize = button.AbsoluteSize
	local centerX = absPos.X + (absSize.X / 2)
	local centerY = absPos.Y + (absSize.Y / 2)

	local vim = game:GetService("VirtualInputManager")

	local ok = pcall(function()
		vim:SendMouseMoveEvent(centerX, centerY, game)
		task.wait(0.03)
		vim:SendMouseButtonEvent(centerX, centerY, 0, true, game, 0)
		task.wait(0.08)
		vim:SendMouseButtonEvent(centerX, centerY, 0, false, game, 0)
	end)

	if ok then
		print("[SCRIPT CLICK] Virtual click sent to:", centerX, centerY)
		return true
	end

	return false
end

local function clickBuyAll()
	print("[CARD MARKET] B pressed - attempting remote fire")

	local okFolder, remotesFolder = pcall(function()
		return ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 3)
	end)

	if not okFolder or not remotesFolder then
		warn("[CARD MARKET] Remotes folder not found:", REMOTES_FOLDER_NAME)
		return false
	end

	print("[CARD MARKET] Found remotes folder:", safeName(remotesFolder))

	local buyAllRemote = remotesFolder:FindFirstChild(BUY_ALL_REMOTE_NAME)
	if not buyAllRemote then
		warn("[CARD MARKET] BuyAll remote not found:", BUY_ALL_REMOTE_NAME)
		print("[CARD MARKET] Children inside remotes folder:")
		for _, child in ipairs(remotesFolder:GetChildren()) do
			print(" -", child.Name, "[" .. child.ClassName .. "]")
		end
		return false
	end

	print("[CARD MARKET] Found remote:", safeName(buyAllRemote), "[" .. buyAllRemote.ClassName .. "]")

	if buyAllRemote:IsA("RemoteEvent") then
		local okFire, err = pcall(function()
			buyAllRemote:FireServer()
		end)

		if okFire then
			print("[CARD MARKET] Fired RemoteEvent successfully")
			return true
		else
			warn("[CARD MARKET] FireServer failed:", err)
			return false
		end
	end

	if buyAllRemote:IsA("RemoteFunction") then
		local okInvoke, result = pcall(function()
			return buyAllRemote:InvokeServer()
		end)

		if okInvoke then
			print("[CARD MARKET] Invoked RemoteFunction successfully:", result)
			return true
		else
			warn("[CARD MARKET] InvokeServer failed:", result)
			return false
		end
	end

	warn("[CARD MARKET] Object is not a RemoteEvent or RemoteFunction:", buyAllRemote.ClassName)
	return false
end

local function isMarketRelatedButton(button)
	local current = button
	local depth = 0

	while current and depth < 16 do
		local n = normalizeText(current.Name)

		if n:find("stock", 1, true)
			or n:find("buy", 1, true)
			or n:find("pack", 1, true)
			or n:find("market", 1, true)
			or n:find("restock", 1, true)
		then
			return true
		end

		if current:IsA("TextLabel") or current:IsA("TextButton") or current:IsA("TextBox") then
			local txt = normalizeText(getGuiText(current))
			if txt:find("buy", 1, true)
				or txt:find("pack", 1, true)
				or txt:find("stock", 1, true)
				or txt:find("restock", 1, true)
				or txt:find("gold", 1, true)
				or txt:find("emerald", 1, true)
				or txt:find("diamond", 1, true)
				or txt:find("rainbow", 1, true)
			then
				return true
			end
		end

		current = current.Parent
		depth += 1
	end

	return false
end

local function dumpNearbyButtonTexts(button)
	local root = button.Parent
	if not root then
		return
	end

	print("------ [NEARBY BUTTON TEXTS] ------")
	for _, inst in ipairs(root:GetDescendants()) do
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			local text = getGuiText(inst)
			if text ~= "" then
				print(inst.ClassName, inst.Name, "=>", text)
			end
		end
	end
	print("-----------------------------------")
end

local function announceButtonClick(button, eventName)
	local text = getGuiText(button)
	local fullName = safeName(button)

	print("========== [BUTTON CLICK] ==========")
	print("EVENT:", tostring(eventName))
	print("CLASS:", button.ClassName)
	print("NAME:", tostring(button.Name))
	print("TEXT:", text ~= "" and text or "(no text)")
	print("PATH:", fullName)
	print("CHAIN:", getParentChain(button, 12))

	local parent = button.Parent
	if parent then
		print("PARENT:", parent.ClassName, parent.Name)

		for _, child in ipairs(parent:GetChildren()) do
			if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("ImageButton") or child:IsA("TextBox") then
				local childText = getGuiText(child)
				print("SIBLING:", child.ClassName, child.Name, childText ~= "" and ("=> " .. childText) or "")
			end
		end
	end

	dumpNearbyButtonTexts(button)
	dumpButtonState(button, "MANUAL CLICK EVENT " .. tostring(eventName))
	print("====================================")
end

local function shouldAnnounceButton(button)
	if not BUTTON_TRACE_ENABLED then
		return false
	end

	if BUTTON_TRACE_ALL then
		return true
	end

	return isMarketRelatedButton(button)
end

local function traceButton(button)
	if not button or TRACED_BUTTONS[button] then
		return
	end
	TRACED_BUTTONS[button] = true

	if button:IsA("TextButton") or button:IsA("ImageButton") then
		button.Activated:Connect(function()
			if shouldAnnounceButton(button) then
				announceButtonClick(button, "Activated")
			end
		end)

		button.MouseButton1Click:Connect(function()
			if shouldAnnounceButton(button) then
				announceButtonClick(button, "MouseButton1Click")
			end
		end)
	end
end

local function startButtonChecker()
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		playerGui = player:WaitForChild("PlayerGui")
	end

	for _, inst in ipairs(playerGui:GetDescendants()) do
		traceButton(inst)
	end

	playerGui.DescendantAdded:Connect(function(inst)
		traceButton(inst)
	end)

	for _, inst in ipairs(workspace:GetDescendants()) do
		traceButton(inst)
	end

	workspace.DescendantAdded:Connect(function(inst)
		traceButton(inst)
	end)
end

startButtonChecker()

local function teleportAndScan()
	local market = getKnownCardMarket()
	if not market then
		print("[CARD MARKET] Could not find Workspace.Map.Market Area.Card Market")
		return
	end

	print("[CARD MARKET] Found market:", safeName(market))
	teleportNearModelOnGround(market, TELEPORT_DISTANCE)
	task.wait(1.25)
	printCardMarketItems()
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == TELEPORT_AND_SCAN_KEY then
		task.spawn(teleportAndScan)
	elseif input.KeyCode == SCAN_ONLY_KEY then
		task.spawn(printCardMarketItems)
	elseif input.KeyCode == BUY_ALL_KEY then
		task.spawn(clickBuyAll)
	elseif input.KeyCode == RAW_DUMP_KEY then
		task.spawn(debugDumpStockUi)
	elseif input.KeyCode == TOGGLE_BUTTON_CHECKER_KEY then
		BUTTON_TRACE_ENABLED = not BUTTON_TRACE_ENABLED
		print("[BUTTON CHECKER]", BUTTON_TRACE_ENABLED and "ON" or "OFF")
	elseif input.KeyCode == TOGGLE_BUTTON_SCOPE_KEY then
		BUTTON_TRACE_ALL = not BUTTON_TRACE_ALL
		print("[BUTTON CHECKER SCOPE]", BUTTON_TRACE_ALL and "ALL BUTTONS" or "MARKET ONLY")
	end
end)

print("[CARD MARKET] Loaded")
print("[CARD MARKET] Press M to teleport to known market + scan")
print("[CARD MARKET] Press N to scan stock UI")
print("[CARD MARKET] Press B to fire BuyAll remote")
print("[CARD MARKET] Press K to dump raw stock UI")
print("[CARD MARKET] Press J to toggle button checker")
print("[CARD MARKET] Press H to toggle checker scope")
print("[CARD MARKET] Logging to file:", LOG_FILE)

print("hookmetamethod:", type(hookmetamethod))
print("getnamecallmethod:", type(getnamecallmethod))
print("checkcaller:", type(checkcaller))
print("newcclosure:", type(newcclosure))