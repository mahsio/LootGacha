-- The rolling loot window: a look-alike of Blizzard's loot window in which every item stays
-- sealed until you click it. It then rolls up, one quality at a time, to what it really is,
-- and is looted once the roll lands. With auto loot every item rolls at once, quickly, while
-- the game loots it.
local _, ns = ...

local WIDTH = 220
local ROW_HEIGHT = 46
local ROW_SPACING = 2
local TOP_INSET = 28
local FOOTER_HEIGHT = 38
local ROLL_DELAY = 0.1
local STEP_SECONDS = 0.3
local STAGGER_SECONDS = 0.2
-- How long the revealed item stays in the window before it is looted.
local REVEAL_HOLD = 0.6
-- Auto loot: quicker steps, and each revealed item stays a moment after the game loots it.
local RAPID_STEP_SECONDS = 0.07
local RAPID_STAGGER_SECONDS = 0.05
local RAPID_HOLD = 0.4
local SOUND_GAP = 0.06
local ROLLED_MEMORY_SECONDS = 120
local MYSTERY_ICON = 134400
local COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

-- Secret values can be displayed but not compared, so comparisons use a fallback instead.
local function Plain(value, fallback)
	if issecretvalue(value) then
		return fallback
	end
	return value
end

local frame = CreateFrame("Frame", "LootGachaLootFrame", UIParent, "DefaultPanelFlatTemplate")
frame:SetWidth(WIDTH)
frame:SetFrameStrata("HIGH")
frame:SetToplevel(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:Hide()
frame.TitleContainer.TitleText:SetText(ITEMS)
-- Lets Escape close the window, like Blizzard's.
table.insert(UISpecialFrames, "LootGachaLootFrame")

CreateFrame("Button", nil, frame, "UIPanelCloseButtonDefaultAnchors")

local lootAllButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
lootAllButton:SetSize(110, 22)
lootAllButton:SetPoint("BOTTOM", 0, 8)
lootAllButton:SetText("Loot all")

-- rolls[slot] holds what a slot really contains and where its roll is:
-- "sealed" until clicked, "rolling" while it climbs, "done" once it shows the item.
-- Auto-looted rolls (roll.auto) outlive their loot slot until their reveal has been seen.
local rolls = {}
local rows = {}
local rowForSlot = {}
local lastStepSound = 0
-- True while the game's loot session is open; the window can outlast it for auto loot.
local sessionOpen = false

-- When each item last landed here, so the pop-up can skip a climb this window already played.
local rolledAt = {}

function ns.WasRolled(link)
	local itemID = C_Item.GetItemInfoInstant(link)
	local landed = itemID and rolledAt[itemID]
	return landed and GetTime() - landed < ROLLED_MEMORY_SECONDS
end

-- Callbacks waiting for an item's roll to land, by item ID (see ns.AfterRoll).
local waiting = {}

local function RunWaiting(itemID)
	local callbacks = itemID and waiting[itemID]
	if callbacks then
		waiting[itemID] = nil
		for _, callback in ipairs(callbacks) do
			callback()
		end
	end
end

-- Forgets every roll, first running anything still waiting for one to land.
local function ClearRolls()
	for itemID in pairs(waiting) do
		RunWaiting(itemID)
	end
	wipe(rolls)
end

-- Runs callback once the window has revealed the item, or right away if it isn't rolling.
-- This keeps the pop-up and the name at the mouse from spoiling an item mid-roll.
function ns.AfterRoll(link, callback)
	local itemID = C_Item.GetItemInfoInstant(link)
	for _, roll in pairs(rolls) do
		if itemID and roll.itemID == itemID and roll.state == "rolling" then
			waiting[itemID] = waiting[itemID] or {}
			table.insert(waiting[itemID], callback)
			return
		end
	end
	callback()
end

local function SortedSlots()
	local slots = {}
	for slot in pairs(rolls) do
		table.insert(slots, slot)
	end
	table.sort(slots)
	return slots
end

local function StartRoll(roll, delay, rapid)
	if roll.state == "sealed" then
		roll.state = "rolling"
		roll.nextAt = GetTime() + delay
		roll.stepSeconds = rapid and RAPID_STEP_SECONDS or STEP_SECONDS
	end
end

-- Coins skip the roll. Solo, the shower starts on the click instead of waiting for the money to
-- arrive; in a group it waits, because only the money change shows your actual share.
local function LootCoins(slot, roll)
	if not roll.showered and not IsInGroup() and roll.amount and roll.amount > 0 then
		roll.showered = true
		ns.StartCoinShowerAhead(roll.amount)
	end
	LootSlot(slot)
end

local function OpenSlot(slot, delay)
	local roll = rolls[slot]
	-- Rows that linger after the game looted them are only there to finish their reveal.
	if not roll or roll.locked or roll.looted or not sessionOpen then
		return
	end
	if roll.coin then
		LootCoins(slot, roll)
	elseif roll.state == "done" and not roll.lootAt then
		-- Revealed but still here (full bags, a declined bind prompt, auto loot that failed).
		LootSlot(slot)
	else
		StartRoll(roll, delay)
	end
end

lootAllButton:SetScript("OnClick", function()
	for i, slot in ipairs(SortedSlots()) do
		OpenSlot(slot, ROLL_DELAY + (i - 1) * STAGGER_SECONDS)
	end
end)

local function OnRowClick(row)
	local roll = rolls[row.slot]
	if IsModifiedClick() then
		-- Linking only works once the item is revealed, so it can't spoil a sealed one.
		if roll and roll.state == "done" and roll.link and not issecretvalue(roll.link) then
			HandleModifiedItemClick(roll.link)
		end
		return
	end
	OpenSlot(row.slot, ROLL_DELAY)
end

local function OnRowEnter(row)
	local roll = rolls[row.slot]
	if not roll or roll.coin then
		if GameTooltip:IsOwned(row) then
			GameTooltip:Hide()
		end
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if roll.state == "done" and roll.link and not issecretvalue(roll.link) then
		GameTooltip:SetHyperlink(roll.link)
	else
		GameTooltip:SetText("???")
		if roll.state == "rolling" then
			GameTooltip:AddLine("Rolling...", 1, 1, 1)
		elseif roll.locked then
			GameTooltip:AddLine("Not yours to open yet.", 1, 1, 1)
		else
			GameTooltip:AddLine("Click to open.", 1, 1, 1)
		end
	end
	GameTooltip:Show()
end

local function CreateRow(index)
	local row = CreateFrame("Button", nil, frame)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -TOP_INSET - (index - 1) * (ROW_HEIGHT + ROW_SPACING))
	row:SetPoint("RIGHT", frame, "RIGHT", -10, 0)

	-- Same atlases as Blizzard's loot rows; the card is tinted by quality.
	row.card = row:CreateTexture(nil, "BACKGROUND")
	row.card:SetAtlas("looting_itemcard_bg")
	row.card:SetAllPoints()
	row.qualityTag = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.qualityTag:SetAtlas("looting_raritytag_frame")
	row.qualityTag:SetSize(100, 13)
	row.qualityTag:SetPoint("TOPRIGHT")
	row.stroke = row:CreateTexture(nil, "BORDER")
	row.stroke:SetAtlas("looting_itemcard_stroke_normal")
	row.stroke:SetAllPoints()
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAtlas("looting_itemcard_stroke_clickstate")
	highlight:SetBlendMode("ADD")
	highlight:SetAlpha(0.7)
	highlight:SetAllPoints()

	row.qualityText = row:CreateFontString(nil, "ARTWORK", "GameFontWhiteTiny2")
	row.qualityText:SetPoint("TOPRIGHT", -4, -2)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(37, 37)
	row.icon:SetPoint("TOPLEFT", 5, -4)
	row.iconBorder = row:CreateTexture(nil, "OVERLAY")
	row.iconBorder:SetTexture("Interface\\Common\\WhiteIconFrame")
	row.iconBorder:SetAllPoints(row.icon)
	row.count = row:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", -2, 2)
	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -10)
	row.name:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	row.name:SetHeight(28)
	row.name:SetJustifyH("LEFT")
	row.name:SetJustifyV("TOP")
	row.pop = ns.AddPop(row.icon:CreateAnimationGroup(), 1.3, 0.2)

	-- Both buttons loot, like Blizzard's rows.
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", OnRowClick)
	row:SetScript("OnEnter", OnRowEnter)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

local function RenderRow(row, slot)
	local roll = rolls[slot]
	row.slot = slot
	rowForSlot[slot] = row
	if roll.coin then
		-- The amount stays hidden; the coin shower reveals it.
		local r, g, b = C_Item.GetItemQualityColor(Enum.ItemQuality.Common)
		row.icon:SetTexture(COIN_ICON)
		row.name:SetText("Coins")
		row.name:SetTextColor(1, 0.82, 0)
		row.card:SetVertexColor(r, g, b)
		row.iconBorder:SetVertexColor(1, 0.82, 0)
		row.qualityTag:Hide()
		row.qualityText:SetText("")
		row.count:SetText("")
	else
		-- Sealed and rolling items keep the "?" icon and "???" name until the roll lands.
		local done = roll.state == "done"
		local quality = roll.shown or Enum.ItemQuality.Poor
		local r, g, b = C_Item.GetItemQualityColor(quality)
		row.icon:SetTexture(done and roll.texture or MYSTERY_ICON)
		row.name:SetText(done and roll.name or "???")
		row.name:SetTextColor(r, g, b)
		row.card:SetVertexColor(r, g, b)
		row.iconBorder:SetVertexColor(r, g, b)
		row.qualityTag:Show()
		row.qualityText:SetText(roll.shown and _G["ITEM_QUALITY" .. quality .. "_DESC"] or "")
		row.count:SetText(done and roll.quantity > 1 and tostring(roll.quantity) or "")
	end
	-- Blizzard tints locked items red.
	if roll.locked then
		row.icon:SetVertexColor(0.9, 0, 0)
	else
		row.icon:SetVertexColor(1, 1, 1)
	end
	row:Show()
	-- Keeps the tooltip in step with the row under the mouse as it rolls.
	if GameTooltip:IsOwned(row) then
		OnRowEnter(row)
	end
end

-- Lays out one row per roll, in slot order, and hides the window once nothing is left.
-- Returns how many rows are shown.
local function Layout()
	wipe(rowForSlot)
	local slots = SortedSlots()
	for i, slot in ipairs(slots) do
		rows[i] = rows[i] or CreateRow(i)
		RenderRow(rows[i], slot)
	end
	for i = #slots + 1, #rows do
		rows[i]:Hide()
	end
	frame:SetHeight(TOP_INSET + #slots * (ROW_HEIGHT + ROW_SPACING) + FOOTER_HEIGHT)
	if #slots == 0 then
		frame:Hide()
	end
	return #slots
end

-- Copper in a coin slot: the loot sources report it per corpse; the slot text is the fallback.
local function CoinAmount(slot, text)
	local sources = { GetLootSourceInfo(slot) }
	local total = 0
	for i = 2, #sources, 2 do
		if issecretvalue(sources[i]) then
			return nil
		end
		total = total + (sources[i] or 0)
	end
	if total > 0 then
		return total
	end
	if text and not issecretvalue(text) then
		return ns.ParseCoinText(text)
	end
	return nil
end

local function ReadSlot(slot)
	local slotType = Plain(GetLootSlotType(slot), Enum.LootSlotType.Item)
	if slotType == Enum.LootSlotType.None then
		return nil
	end
	local texture, name, quantity, _, quality, locked = GetLootSlotInfo(slot)
	local link = GetLootSlotLink(slot)
	local roll = {
		state = "sealed",
		texture = texture,
		name = name,
		quantity = Plain(quantity, 1) or 1,
		quality = Plain(quality, Enum.ItemQuality.Common) or Enum.ItemQuality.Common,
		locked = Plain(locked, false),
		link = link,
		itemID = link and not issecretvalue(link) and C_Item.GetItemInfoInstant(link) or nil,
	}
	if slotType == Enum.LootSlotType.Money then
		roll.coin = true
		roll.amount = CoinAmount(slot, name)
	end
	return roll
end

-- With auto loot, every item starts rolling right away and quickly.
local function ReadAllSlots(autoLoot)
	ClearRolls()
	local order = 0
	for slot = 1, GetNumLootItems() do
		local roll = ReadSlot(slot)
		if roll and autoLoot and not roll.coin then
			roll.auto = true
			StartRoll(roll, order * RAPID_STAGGER_SECONDS, true)
			order = order + 1
		end
		rolls[slot] = roll
	end
end

local function Land(roll, now)
	roll.state = "done"
	ns.PlayFinalSound(roll.quality)
	if roll.itemID then
		rolledAt[roll.itemID] = now
	end
	RunWaiting(roll.itemID)
	if roll.auto then
		roll.holdUntil = now + RAPID_HOLD
	else
		roll.lootAt = now + REVEAL_HOLD
	end
end

-- Steps rolling items, loots clicked items once their reveal has shown, and removes auto-looted
-- items once theirs has. Runs only while the window is shown.
frame:SetScript("OnUpdate", function()
	local now = GetTime()
	local removed = false
	for slot, roll in pairs(rolls) do
		if roll.state == "rolling" and now >= roll.nextAt then
			roll.shown = roll.shown and roll.shown + 1 or Enum.ItemQuality.Poor
			roll.nextAt = now + roll.stepSeconds
			if roll.shown >= roll.quality then
				roll.shown = roll.quality
				Land(roll, now)
			elseif now - lastStepSound >= SOUND_GAP then
				lastStepSound = now
				ns.PlaySfx(ns.STEP_SOUND)
			end
			local row = rowForSlot[slot]
			if row then
				RenderRow(row, slot)
				row.pop:Restart()
			end
		elseif roll.lootAt and now >= roll.lootAt then
			roll.lootAt = nil
			LootSlot(slot)
		elseif roll.holdUntil and now >= roll.holdUntil then
			roll.holdUntil = nil
			roll.held = true
			if roll.looted then
				rolls[slot] = nil
				removed = true
			end
		end
	end
	if removed then
		Layout()
	end
end)

-- Opens under the mouse like Blizzard's window when "Open loot window at mouse" is on.
local function Position()
	frame:ClearAllPoints()
	if GetCVarBool("lootUnderMouse") then
		local x, y = GetCursorPosition()
		local scale = frame:GetEffectiveScale()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 30, math.max(y / scale + 50, 350))
	else
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -120)
	end
end

-- The money counter and item names pop up above the cursor. While this window is open under
-- them, they stack above its top edge instead so they never cover its rows, or beside it when
-- there is no room above (for example its fixed top-left spot). Returns the x, y to use.
function ns.AboveLootWindow(x, y)
	local scale = frame:GetScale()
	if frame:IsShown() and x > frame:GetLeft() * scale - 100 and x < frame:GetRight() * scale + 100 then
		local top = frame:GetTop() * scale
		-- The counter and up to six name lines need about 210 units above top - 50.
		if top + 210 < UIParent:GetHeight() then
			return x, math.max(y, top - 50)
		end
		return frame:GetRight() * scale + 170, y
	end
	return x, y
end

local function IsMasterLoot()
	return Plain(C_PartyInfo.GetLootMethod(), nil) == Enum.LootMethod.Masterlooter
end

local takenOver = false
local retryPending = false

-- Blizzard's loot window only listens to LOOT_OPENED and LOOT_CLOSED, so switching those off
-- hands the loot session to this window without changing Blizzard's code. Master loot stays
-- with Blizzard's window because its assign menu depends on it. Blizzard's events are only
-- touched when the decision changes, so another loot addon that switched them off keeps them off.
function ns.ApplyLootTakeover()
	local takeOver = LootGachaDB.rollingLoot and not IsMasterLoot()
	-- Blizzard's window must still get its LOOT_CLOSED, so wait until it has closed.
	if takeOver and not takenOver and LootFrame:IsShown() then
		if not retryPending then
			retryPending = true
			C_Timer.After(1, function()
				retryPending = false
				ns.ApplyLootTakeover()
			end)
		end
		return
	end
	if takeOver ~= takenOver then
		takenOver = takeOver
		local method = takeOver and LootFrame.UnregisterEvent or LootFrame.RegisterEvent
		method(LootFrame, "LOOT_OPENED")
		method(LootFrame, "LOOT_CLOSED")
	end
end

frame:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "PARTY_LOOT_METHOD_CHANGED" or event == "GROUP_ROSTER_UPDATE" then
		ns.ApplyLootTakeover()
	elseif event == "LOOT_CLOSED" then
		-- The bind prompt's slot number belongs to the session that just closed. Blizzard's
		-- window clears it for the sessions it owns.
		if sessionOpen then
			StaticPopup_Hide("LOOT_BIND")
		end
		sessionOpen = false
		-- Auto-looted items finish their reveal first; everything else goes away now.
		for slot, roll in pairs(rolls) do
			if not (roll.auto and roll.looted) then
				rolls[slot] = nil
			end
		end
		Layout()
	elseif event == "LOOT_OPENED" then
		if not takenOver then
			return
		end
		sessionOpen = true
		ReadAllSlots(Plain(arg1, false))
		if Layout() == 0 then
			-- Replaces Blizzard's empty-loot sound.
			ns.ShowNoLoot()
			CloseLoot()
			return
		end
		-- Shrinks a very long window once, on open, so the last rows and "Loot all" stay on screen.
		frame:SetScale(math.min(1, (UIParent:GetHeight() - 60) / frame:GetHeight()))
		Position()
		frame:Show()
		frame:Raise()
		-- Blizzard's window plays these on open; the takeover would otherwise silence them.
		if Plain(arg2, false) then
			PlaySound(SOUNDKIT.UI_CONTAINER_ITEM_OPEN)
		elseif IsFishingLoot() then
			PlaySound(SOUNDKIT.FISHING_REEL_IN)
		end
	-- Slot events follow the session this window opened, even if the takeover was switched off since.
	elseif sessionOpen and not issecretvalue(arg1) then
		local roll = rolls[arg1]
		if event == "LOOT_SLOT_CLEARED" then
			if roll and roll.auto and not roll.held then
				-- Keep showing it until its reveal has been seen.
				roll.looted = true
			else
				rolls[arg1] = nil
			end
		elseif roll then
			-- Contents changed (for example a roll finished and the item unlocked).
			roll.locked = Plain(select(6, GetLootSlotInfo(arg1)), false)
		end
		Layout()
	end
end)
FrameUtil.RegisterFrameForEvents(frame, {
	"LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED", "LOOT_CLOSED", "PARTY_LOOT_METHOD_CHANGED", "GROUP_ROSTER_UPDATE",
})

-- Hiding the window (close button, Escape, or empty) ends its loot session, as Blizzard's does.
-- After the session already ended (auto-looted rows finishing), there is nothing to close.
frame:HookScript("OnHide", function()
	local owner = GameTooltip:GetOwner()
	if owner and owner:GetParent() == frame then
		GameTooltip:Hide()
	end
	ClearRolls()
	if sessionOpen then
		CloseLoot()
	end
end)

table.insert(ns.onLoad, ns.ApplyLootTakeover)
