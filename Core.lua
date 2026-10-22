-- LootGacha: cosmetic gacha-style loot reveals. It never changes what drops, only how it is shown.
local addonName, ns = ...

ns.defaults = {
	debug = false,
	sound = true,
	reveal = true,
	rollingLoot = true,
	lootNames = true,
	holdChat = true,
	coins = true,
	hudAlways = false,
}

-- Modules add functions here; they run once the saved variables are loaded.
ns.onLoad = {}

function ns.Print(...)
	print("|cffffd200LootGacha:|r", ...)
end

-- Debug lines carry a timestamp so the real event order can be read in-game.
function ns.Debug(...)
	if LootGachaDB and LootGachaDB.debug then
		print(format("|cff888888LootGacha %.2f|r", GetTime()), ...)
	end
end

-- Printable text for any value, without ever comparing or indexing a secret value.
local function Safe(value)
	if issecretvalue(value) then
		return "<secret>"
	end
	return tostring(value)
end

-- Cancels a C_Timer timer or ticker if there is one. Returns nil, so "timer = ns.CancelTimer(timer)"
-- also clears the variable.
function ns.CancelTimer(timer)
	if timer then
		timer:Cancel()
	end
	return nil
end

-- Adds an alpha fade, optionally after a delay, to an animation group. Returns the group.
function ns.AddFade(group, fromAlpha, toAlpha, duration, delay)
	local fade = group:CreateAnimation("Alpha")
	fade:SetFromAlpha(fromAlpha)
	fade:SetToAlpha(toAlpha)
	fade:SetDuration(duration)
	fade:SetStartDelay(delay or 0)
	return group
end

-- Adds a pop (scales down from scale to normal size) to an animation group. Returns the group.
function ns.AddPop(group, scale, duration)
	local pop = group:CreateAnimation("Scale")
	pop:SetScaleFrom(scale, scale)
	pop:SetScaleTo(1, 1)
	pop:SetDuration(duration)
	pop:SetSmoothing("OUT")
	pop:SetOrigin("CENTER", 0, 0)
	return group
end

-- Turns a GlobalStrings format such as "You receive loot: %sx%d" into a Lua pattern.
function ns.FormatToPattern(fmt, anchored)
	if type(fmt) ~= "string" then
		return nil
	end
	local pattern = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
	pattern = pattern:gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)")
	if anchored then
		return "^" .. pattern .. "$"
	end
	return pattern
end

local function SoundOn()
	return LootGachaDB and LootGachaDB.sound
end

-- Plays a sound kit unless sounds are off.
function ns.PlaySfx(soundKitID)
	if soundKitID and SoundOn() and not PlaySound(soundKitID) then
		ns.Debug("sound kit " .. soundKitID .. " did not play")
	end
end

-- Plays one of the game's sound files by file ID unless sounds are off.
function ns.PlayFileSfx(fileID)
	if SoundOn() and not PlaySoundFile(fileID, "SFX") then
		ns.Debug("sound file " .. fileID .. " did not play")
	end
end

-- Played on each quality step of a roll before it lands.
ns.STEP_SOUND = SOUNDKIT.UI_ITEM_UPGRADE_UI_ITEM_UPGRADED

local function FinalSound(quality)
	if quality >= Enum.ItemQuality.Legendary then
		return SOUNDKIT.UI_LEGENDARY_LOOT_TOAST
	elseif quality >= Enum.ItemQuality.Rare then
		return SOUNDKIT.UI_EPICLOOT_TOAST
	elseif quality >= Enum.ItemQuality.Uncommon then
		return SOUNDKIT.UI_RAID_LOOT_TOAST_LESSER_ITEM_WON
	end
	return SOUNDKIT.IG_QUEST_LIST_SELECT
end

-- Gray (Poor) items get a lame reveal: a meat splat or a gravelly stone scrape, and now and
-- then one of the game's fart sounds instead. All are the game's own sounds.
local POOR_SOUNDS = {
	{ file = 567547 }, -- sound/interface/pickup/putdownmeat.ogg
	{ kit = 1194 }, -- the rocks/ore pickup sound, heard when looting Coarse Stone
}
local FART_FILES = { 598718, 598466 } -- sound/spells/fart_01.ogg, sound/spells/fart_02.ogg
local FART_CHANCE = 0.1
-- Keeps several grays landing together from turning into one long rumble.
local POOR_SOUND_GAP = 0.25
local lastPoorSound = 0

-- Played when a roll lands on its real quality.
function ns.PlayFinalSound(quality)
	if quality ~= Enum.ItemQuality.Poor then
		ns.PlaySfx(FinalSound(quality))
		return
	end
	local now = GetTime()
	if now - lastPoorSound < POOR_SOUND_GAP then
		return
	end
	lastPoorSound = now
	local sound = POOR_SOUNDS[math.random(#POOR_SOUNDS)]
	if math.random() < FART_CHANCE then
		ns.PlayFileSfx(FART_FILES[math.random(#FART_FILES)])
	elseif sound.kit then
		ns.PlaySfx(sound.kit)
	else
		ns.PlayFileSfx(sound.file)
	end
end

local floatPool = {}

local function CreateFloatText()
	local holder = CreateFrame("Frame", nil, UIParent)
	holder:SetSize(1, 1)
	holder:SetFrameStrata("FULLSCREEN_DIALOG")
	holder.text = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge3Outline")
	holder.text:SetPoint("CENTER")
	-- All three run together: fade in, rise, and fade out near the end.
	holder.anim = ns.AddFade(holder:CreateAnimationGroup(), 0, 1, 0.15)
	local rise = holder.anim:CreateAnimation("Translation")
	rise:SetOffset(0, 50)
	rise:SetDuration(1.3)
	rise:SetSmoothing("OUT")
	ns.AddFade(holder.anim, 1, 0, 0.5, 0.8)
	holder.anim:SetScript("OnFinished", function()
		holder:Hide()
		table.insert(floatPool, holder)
	end)
	return holder
end

-- Rising, fading text such as "+2 Intellect!" centered on any frame or texture.
function ns.FloatText(anchor, text, r, g, b, yOffset)
	local holder = table.remove(floatPool) or CreateFloatText()
	holder:ClearAllPoints()
	holder:SetPoint("CENTER", anchor, "CENTER", 0, yOffset or 0)
	holder.text:SetText(text)
	holder.text:SetTextColor(r, g, b)
	holder:Show()
	holder.anim:Restart()
end

-- Your own "You receive loot" lines. Order matters: the more specific string is tried first.
local ITEM_PATTERNS = { ns.FormatToPattern(LOOT_ITEM_SELF_MULTIPLE, true), ns.FormatToPattern(LOOT_ITEM_SELF, true) }

-- Returns the item link and count when text is one of your own "You receive loot" lines.
local function MatchOwnLoot(text)
	for _, pattern in ipairs(ITEM_PATTERNS) do
		local link, count = text:match(pattern)
		if link then
			return link, count
		end
	end
	return nil
end

-- Your own loot lines are held back per chat lineID and printed once that item's pop-up
-- finishes. The timeout makes sure a line is never lost if its pop-up does not play.
local MAX_HOLD_SECONDS = 15
local heldLines = {}
-- Lines released recently, so a chat frame that sees one after its release doesn't hold it.
local released = {}

function ns.ReleaseChatLine(lineID)
	if not lineID or released[lineID] then
		return
	end
	released[lineID] = true
	C_Timer.After(MAX_HOLD_SECONDS, function()
		released[lineID] = nil
	end)
	local held = heldLines[lineID]
	heldLines[lineID] = nil
	if held then
		local info = ChatTypeInfo.LOOT
		for _, chatFrame in ipairs(held.frames) do
			chatFrame:AddMessage(held.text, info.r, info.g, info.b, info.id)
		end
	end
end

-- Runs once per chat frame that shows loot. Returning true hides the line in that frame.
local function HoldOwnLoot(chatFrame, _, text, ...)
	if not (LootGachaDB and LootGachaDB.holdChat and LootGachaDB.reveal) or issecretvalue(text) or not MatchOwnLoot(text) then
		return false
	end
	local lineID = select(10, ...)
	if not lineID or released[lineID] then
		return false
	end
	local held = heldLines[lineID]
	if not held then
		held = { text = text, frames = {} }
		heldLines[lineID] = held
		C_Timer.After(MAX_HOLD_SECONDS, function()
			ns.ReleaseChatLine(lineID)
		end)
	end
	table.insert(held.frames, chatFrame)
	return true
end

ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_LOOT", HoldOwnLoot)

-- Creature GUIDs look like Creature-0-server-instance-zone-npcID-spawn.
local function DescribeSource(guid)
	if issecretvalue(guid) then
		return "<secret source>"
	end
	if not guid then
		return "no source"
	end
	local unitType, _, _, _, _, id = strsplit("-", guid)
	return format("%s %s", unitType, id or "?")
end

local handlers = {}
local lootLogged = false
local lastMoney

function handlers.ADDON_LOADED(name)
	if name ~= addonName then
		return
	end
	LootGachaDB = LootGachaDB or {}
	for key, value in pairs(ns.defaults) do
		if LootGachaDB[key] == nil then
			LootGachaDB[key] = value
		end
	end
	for _, onLoad in ipairs(ns.onLoad) do
		onLoad()
	end
end

function handlers.PLAYER_LOGIN()
	lastMoney = GetMoney()
	ns.SyncMoney()
	-- One hello on the first login only; after that LootGacha stays quiet in chat.
	if not LootGachaDB.welcomed then
		LootGachaDB.welcomed = true
		ns.Print("Your loot now rolls up from gray to its real quality. Type /gacha for commands and settings.")
	end
	local version, build, _, interface = GetBuildInfo()
	ns.Debug(format("v%s, game %s.%s, interface %d", C_AddOns.GetAddOnMetadata(addonName, "Version"), version, build, interface))
end

function handlers.CHAT_MSG_LOOT(text, ...)
	if issecretvalue(text) then
		ns.Debug("CHAT_MSG_LOOT <secret>")
		return
	end
	local link, count = MatchOwnLoot(text)
	if link then
		ns.Debug(format("CHAT_MSG_LOOT you got %s x%s", link, count or "1"))
		local lineID = select(10, ...)
		-- Waits while the loot window is still rolling this item (auto loot), so it isn't spoiled.
		ns.AfterRoll(link, function()
			ns.ShowLootName(link, tonumber(count) or 1)
			ns.QueueReveal(link, nil, false, lineID)
		end)
		return
	end
	ns.Debug("CHAT_MSG_LOOT (not yours): " .. text)
end

function handlers.PLAYER_MONEY()
	local money = GetMoney()
	local delta = money - (lastMoney or money)
	ns.Debug(format("PLAYER_MONEY %+d copper", delta))
	lastMoney = money
	ns.OnMoneyChanged(delta)
end

-- The remaining handlers only feed the debug log.
function handlers.LOOT_READY(autoLoot)
	-- Forever fires LOOT_READY twice per loot window, so only the first one is logged.
	if lootLogged or not LootGachaDB.debug then
		return
	end
	lootLogged = true
	local numSlots = GetNumLootItems()
	ns.Debug(format("LOOT_READY autoLoot=%s slots=%s", Safe(autoLoot), Safe(numSlots)))
	if issecretvalue(numSlots) then
		return
	end
	-- Slot types: 1 item, 2 coin, 3 currency (Enum.LootSlotType).
	for slot = 1, numSlots do
		local _, name, quantity, _, quality = GetLootSlotInfo(slot)
		local guid, sourceAmount = GetLootSourceInfo(slot)
		ns.Debug(format("  slot %d: type %s, %s %s x%s, quality %s, source amount %s, from %s", slot, Safe(GetLootSlotType(slot)),
			Safe(GetLootSlotLink(slot)), (Safe(name):gsub("\n", " ")), Safe(quantity), Safe(quality), Safe(sourceAmount), DescribeSource(guid)))
	end
end

function handlers.LOOT_SLOT_CLEARED(slot)
	ns.Debug(format("LOOT_SLOT_CLEARED %s", Safe(slot)))
end

function handlers.LOOT_CLOSED()
	lootLogged = false
	ns.Debug("LOOT_CLOSED")
end

-- Coin showers follow the actual money change in PLAYER_MONEY; the chat line is only logged.
function handlers.CHAT_MSG_MONEY(text)
	ns.Debug("CHAT_MSG_MONEY " .. Safe(text))
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
for event in pairs(handlers) do
	eventFrame:RegisterEvent(event)
end

local function RandomEquippedLink()
	local links = {}
	for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
		local link = GetInventoryItemLink("player", slot)
		if link then
			table.insert(links, link)
		end
	end
	if #links == 0 then
		return nil
	end
	return links[math.random(#links)]
end

SLASH_LOOTGACHA1 = "/gacha"
SLASH_LOOTGACHA2 = "/lootgacha"
SlashCmdList.LOOTGACHA = function(msg)
	local command, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
	local number = tonumber(arg) and math.floor(tonumber(arg))
	if command == "test" then
		local quality = number and math.max(Enum.ItemQuality.Poor, math.min(Enum.ItemQuality.Legendary, number))
		-- Falls back to the Hearthstone when nothing is equipped.
		ns.QueueReveal(RandomEquippedLink() or "item:6948", quality, true)
	elseif command == "coins" then
		ns.StartCoinShower(number or ns.CopperToNextSilver(), true)
	elseif command == "hud" then
		ns.ToggleOption("hudAlways")
	elseif command == "debug" then
		ns.ToggleOption("debug")
	elseif command == "options" then
		ns.OpenOptions()
	else
		ns.Print(format("v%s commands:", C_AddOns.GetAddOnMetadata(addonName, "Version")))
		print("  /gacha options - open the settings")
		print("  /gacha test [0-5] - preview the pop-up with one of your equipped items (0 = gray ... 5 = orange)")
		print("  /gacha coins [copper] - preview a coin shower (default: just enough copper to roll over into 1 silver)")
		print("  /gacha hud - pin the money counter on screen so you can drag it")
		print("  /gacha debug - toggle the loot and money event log")
	end
end
