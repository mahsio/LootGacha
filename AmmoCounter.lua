-- The ammo counter: when a shot or spell uses up your ammo or a class reagent (Soul Shards,
-- Flash Powder, Rune of Teleportation...), the number you have left pops up in the middle of
-- the screen with a red "-1". It stays up while you keep shooting, turns yellow and then red
-- as you run low, and fades out a few seconds after the last one is used.
local _, ns = ...

-- Class reagents, checked against the live game's spell reagent data (build 1.60.1.70790).
-- Thrown weapons aren't counted: in Forever they don't stack and are never used up.
local REAGENTS = {
	DRUID = {
		17021, -- Wild Berries (Gift of the Wild)
		17026, -- Wild Thornroot (Gift of the Wild)
		17034, 17035, 17036, 17037, 17038, -- Maple, Stranglethorn, Ashwood, Hornbeam and Ironwood Seed (Rebirth)
	},
	MAGE = {
		17020, -- Arcane Powder (Arcane Brilliance)
		17031, -- Rune of Teleportation
		17032, -- Rune of Portals
		17056, -- Light Feather (Slow Fall)
	},
	PALADIN = {
		17033, -- Symbol of Divinity (Divine Intervention)
		21177, -- Symbol of Kings (greater blessings)
	},
	PRIEST = {
		17028, -- Holy Candle (Prayer of Fortitude)
		17029, -- Sacred Candle (the group prayers)
		17056, -- Light Feather (Levitate)
	},
	ROGUE = {
		5140, -- Flash Powder (Vanish)
		5530, -- Blinding Powder (Blind)
	},
	SHAMAN = {
		17030, -- Ankh (Reincarnation)
		17057, -- Shiny Fish Scales (Water Breathing)
		17058, -- Fish Oil (Water Walking)
	},
	WARLOCK = {
		6265, -- Soul Shard
		5565, -- Infernal Stone (Inferno)
		16583, -- Demonic Figurine (Ritual of Doom)
	},
}
-- Shown by /gacha ammo when you have no ammo and your class uses no reagents.
local PREVIEW_ITEM, PREVIEW_COUNT = 2512, 200 -- Rough Arrow

-- Ammo comes in stacks of 200, so it counts as running low much sooner than reagents do.
local THRESHOLDS = {
	ammo = { low = 200, veryLow = 50 },
	reagent = { low = 5, veryLow = 2 },
}
-- Only uses within this many seconds of one of your own casts or shots count, so selling,
-- banking, mailing or deleting a stack never brings up the counter.
local CAST_WINDOW = 2
local LINGER = 2.5
-- How long the "-1" stays before it fades.
local SPENT_HOLD = 0.8
local DEFAULT_POS = { "CENTER", "CENTER", 0, -120 }

local counter = CreateFrame("Frame", "LootGachaAmmoCounter", UIParent)
counter:SetSize(220, 50)
counter:SetFrameStrata("HIGH")
counter:SetClampedToScreen(true)
counter:SetMovable(true)
counter:RegisterForDrag("LeftButton")
counter:SetScript("OnDragStart", counter.StartMoving)
counter:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	self:SetUserPlaced(false)
	local point, _, relativePoint, x, y = self:GetPoint()
	LootGachaDB.ammoPos = { point, relativePoint, x, y }
end)
counter:Hide()

-- A small icon left of the counter's center and the number right of it. Like the coins in the
-- money counter, the icon pulses each time one is used.
local icon = counter:CreateTexture(nil, "ARTWORK")
icon:SetSize(22, 22)
icon:SetPoint("RIGHT", counter, "CENTER", -4, 0)
icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
local pulse = ns.AddPop(icon:CreateAnimationGroup(), 1.4, 0.15)
-- The number uses a 12px font and the "-1" a 10px one, so the "-1" stays the smaller line.
local countText = counter:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
countText:SetPoint("LEFT", icon, "RIGHT", 5, 0)

-- A red "-1" over the number's last digit each time one is used, like the money counter's "+"
-- line. Uses close together add up, so a quick double shot shows "-2". It has its own frame so
-- its fade leaves the number alone.
local spentHolder = CreateFrame("Frame", nil, counter)
spentHolder:SetSize(1, 1)
spentHolder:SetPoint("BOTTOMRIGHT", countText, "TOPRIGHT", 0, -1)
local spentText = spentHolder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmallOutline")
spentText:SetPoint("BOTTOMRIGHT")
spentText:SetTextColor(1, 0.3, 0.3)
local spent = 0

local function ClearSpent()
	spent = 0
	spentText:SetText("")
end

local spentFade = ns.AddFade(spentHolder:CreateAnimationGroup(), 1, 0, 0.4, SPENT_HOLD)
spentFade:SetScript("OnFinished", ClearSpent)

local fade = ns.AddFade(counter:CreateAnimationGroup(), 1, 0, 0.5)
fade:SetScript("OnFinished", function()
	counter:Hide()
end)

local watched = {} -- itemID -> "ammo" or "reagent"
local counts = {} -- itemID -> the count last seen
local classReagents = {}
local ammoItem, shownItem
local lastCast, shooting, channeling = 0, false, false
local moving = false
local lingerTimer

local function StartLinger()
	lingerTimer = ns.CancelTimer(lingerTimer)
	lingerTimer = C_Timer.NewTimer(LINGER, function()
		lingerTimer = nil
		fade:Play()
	end)
end

-- used is how many were just used up. The /gacha ammo preview passes none.
local function Display(itemID, count, kind, used)
	if itemID ~= shownItem or not used then
		spentFade:Stop()
		ClearSpent()
	end
	shownItem = itemID
	local limits = THRESHOLDS[kind]
	icon:SetTexture(C_Item.GetItemIconByID(itemID))
	countText:SetText(tostring(count))
	if count <= limits.veryLow then
		countText:SetTextColor(1, 0.25, 0.25)
	elseif count <= limits.low then
		countText:SetTextColor(1, 0.82, 0)
	else
		countText:SetTextColor(1, 1, 1)
	end
	if used then
		spent = spent + used
		spentText:SetText("-" .. spent)
		spentFade:Restart()
		pulse:Restart()
	end
	fade:Stop()
	counter:Show()
	if not moving then
		StartLinger()
	end
end

local function Watch(itemID, kind)
	watched[itemID] = kind
	counts[itemID] = C_Item.GetItemCount(itemID)
end

local function WatchClassReagents()
	local class = UnitClassBase("player")
	classReagents = not issecretvalue(class) and REAGENTS[class] or {}
	for _, itemID in ipairs(classReagents) do
		Watch(itemID, "reagent")
	end
end

-- The last ammo stays watched after its slot empties, so the final shot can still show 0.
local function UpdateAmmo()
	local itemID = GetInventoryItemID("player", INVSLOT_AMMO)
	if not itemID or itemID == ammoItem then
		return
	end
	if ammoItem then
		watched[ammoItem], counts[ammoItem] = nil, nil
	end
	ammoItem = itemID
	Watch(itemID, "ammo")
end

-- Bag changes only bring up the counter when they come right after one of your own casts or
-- shots. Gains (looting, buying, Drain Soul) just update the count.
local function Refresh()
	local sinceCast = GetTime() - lastCast
	local consuming = shooting or channeling or sinceCast <= CAST_WINDOW
	for itemID, kind in pairs(watched) do
		local count = C_Item.GetItemCount(itemID)
		local before = counts[itemID]
		counts[itemID] = count
		if before and count < before then
			ns.Debug(format("ammo counter: %s %d -> %d, %s", C_Item.GetItemNameByID(itemID) or itemID, before, count,
				consuming and "used" or format("not shown, last cast %.1fs ago", sinceCast)))
			if consuming and LootGachaDB.ammoCounter then
				Display(itemID, count, kind, before - count)
			end
		end
	end
end

local handlers = {}

function handlers.PLAYER_LOGIN()
	WatchClassReagents()
	UpdateAmmo()
end

function handlers.PLAYER_ENTERING_WORLD()
	shooting, channeling = false, false
	UpdateAmmo()
end

handlers.PLAYER_EQUIPMENT_CHANGED = UpdateAmmo
handlers.BAG_UPDATE_DELAYED = Refresh
handlers.UNIT_INVENTORY_CHANGED = Refresh

function handlers.START_AUTOREPEAT_SPELL()
	shooting = true
end

-- The last shot's ammo can come in just after auto shot stops.
function handlers.STOP_AUTOREPEAT_SPELL()
	shooting = false
	lastCast = GetTime()
end

function handlers.UNIT_SPELLCAST_CHANNEL_START()
	channeling = true
	lastCast = GetTime()
end

function handlers.UNIT_SPELLCAST_CHANNEL_STOP()
	channeling = false
	lastCast = GetTime()
end

-- SENT comes before the server takes the reagent and SUCCEEDED after, so the window covers
-- either order.
function handlers.UNIT_SPELLCAST_SENT()
	lastCast = GetTime()
end

handlers.UNIT_SPELLCAST_SUCCEEDED = handlers.UNIT_SPELLCAST_SENT

-- Only your own casts are listened to, so the payloads (secret for other units) are never read.
local UNIT_EVENTS = {
	UNIT_INVENTORY_CHANGED = true,
	UNIT_SPELLCAST_CHANNEL_START = true,
	UNIT_SPELLCAST_CHANNEL_STOP = true,
	UNIT_SPELLCAST_SENT = true,
	UNIT_SPELLCAST_SUCCEEDED = true,
}

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event)
	handlers[event]()
end)
for event in pairs(handlers) do
	if UNIT_EVENTS[event] then
		eventFrame:RegisterUnitEvent(event, "player")
	else
		eventFrame:RegisterEvent(event)
	end
end

-- Your ammo, else the first reagent you carry, else your class's first reagent.
local function PreviewItem()
	if ammoItem then
		return ammoItem, C_Item.GetItemCount(ammoItem), "ammo"
	end
	for _, itemID in ipairs(classReagents) do
		local count = C_Item.GetItemCount(itemID)
		if count > 0 then
			return itemID, count, "reagent"
		end
	end
	if classReagents[1] then
		return classReagents[1], 0, "reagent"
	end
	return PREVIEW_ITEM, PREVIEW_COUNT, "ammo"
end

-- /gacha ammo: shows the counter so it can be dragged. Running it again locks it in place.
function ns.ToggleAmmoMover()
	moving = not moving
	counter:EnableMouse(moving)
	if moving then
		lingerTimer = ns.CancelTimer(lingerTimer)
		Display(PreviewItem())
		ns.Print("Drag the ammo counter where you want it, then type /gacha ammo again to lock it.")
	else
		StartLinger()
		ns.Print("Ammo counter locked.")
	end
end

-- Hides the counter right away when it is turned off in the settings.
function ns.UpdateAmmoCounter()
	if not LootGachaDB.ammoCounter and not moving then
		lingerTimer = ns.CancelTimer(lingerTimer)
		fade:Stop()
		spentFade:Stop()
		ClearSpent()
		counter:Hide()
	end
end

table.insert(ns.onLoad, function()
	local pos = LootGachaDB.ammoPos or DEFAULT_POS
	counter:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
end)
