-- The pop-up for green or better loot: the item climbs to its real quality (unless it already
-- rolled in the loot window), then floats its stats.
local _, ns = ...

local STEP_SECONDS = 0.35
local HOLD_SECONDS = 1.8
-- Shorter hold when another pop-up is waiting, so the next item shows up quickly.
local QUEUED_HOLD_SECONDS = 0.6
local STAT_SECONDS = 0.25
local MAX_QUEUE = 10

local STAT_SOUND = SOUNDKIT.IG_QUEST_LIST_SELECT

-- Stats from the item API, falling back to "+N Stat" tooltip lines (random suffix items).
local function CollectStats(link)
	local stats = {}
	local statTable = C_Item.GetItemStats(link)
	if statTable then
		for key, value in pairs(statTable) do
			local label = _G[key]
			if type(value) == "number" and value ~= 0 and type(label) == "string" then
				table.insert(stats, { label = label, value = value })
			end
		end
	end
	if #stats == 0 then
		local data = C_TooltipInfo.GetHyperlink(link)
		for _, line in ipairs(data and data.lines or {}) do
			local text = line.leftText
			if type(text) == "string" and not issecretvalue(text) then
				local value, label = text:match("^%+(%d+) (.+)$")
				if value then
					table.insert(stats, { label = label, value = tonumber(value) })
				end
			end
		end
	end
	table.sort(stats, function(a, b)
		return a.label < b.label
	end)
	return stats
end

local function StatText(stat)
	local value = stat.value
	local number = value % 1 == 0 and format("%d", value) or format("%.1f", value)
	return format("%s%s %s!", value > 0 and "+" or "", number, stat.label)
end

local popup = CreateFrame("Frame", "LootGachaRevealFrame", UIParent)
popup:SetSize(280, 84)
popup:SetPoint("TOP", 0, -140)
popup:SetFrameStrata("DIALOG")
popup:EnableMouse(true)
popup:Hide()

local background = popup:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints()
background:SetColorTexture(0, 0, 0, 0.7)

-- The icon has its own frame so the pop animation scales only the icon.
local iconFrame = CreateFrame("Frame", nil, popup)
iconFrame:SetSize(52, 52)
iconFrame:SetPoint("LEFT", 16, 0)

local icon = iconFrame:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints()

local border = iconFrame:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Common\\WhiteIconFrame")
border:SetAllPoints()

local nameText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
nameText:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 12, -8)
nameText:SetPoint("RIGHT", popup, "RIGHT", -12, 0)
nameText:SetJustifyH("LEFT")

local qualityText = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
qualityText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -6)

local pop = ns.AddPop(iconFrame:CreateAnimationGroup(), 1.35, 0.25)
local fadeOut = ns.AddFade(popup:CreateAnimationGroup(), 1, 0, 0.4)

-- current is the entry being shown; nil means the pop-up is idle.
local queue = {}
local current, ticker, holdTimer

local function Hold(seconds)
	ns.CancelTimer(holdTimer)
	holdTimer = C_Timer.NewTimer(seconds, function()
		holdTimer = nil
		fadeOut:Play()
	end)
end

local function ShowStep(quality, isFinal)
	local r, g, b = C_Item.GetItemQualityColor(quality)
	border:SetVertexColor(r, g, b)
	icon:SetDesaturated(quality == Enum.ItemQuality.Poor and not isFinal)
	nameText:SetText(isFinal and current.name or "???")
	nameText:SetTextColor(r, g, b)
	qualityText:SetText(_G["ITEM_QUALITY" .. quality .. "_DESC"] or "")
	qualityText:SetTextColor(r, g, b)
	pop:Restart()
	if isFinal then
		ns.PlayFinalSound(quality)
	else
		ns.PlaySfx(ns.STEP_SOUND)
	end
end

-- Floats one "+N Stat!" line per stat. Returns how long they take to all appear.
local function ShowStats(link)
	local stats = CollectStats(link)
	local entry = current
	for i, stat in ipairs(stats) do
		C_Timer.After((i - 1) * STAT_SECONDS, function()
			-- A skipped pop-up's remaining stats don't float over the next item.
			if current ~= entry then
				return
			end
			local r, g, b = 0.2, 1, 0.2
			if stat.value < 0 then
				r, g, b = 1, 0.25, 0.25
			end
			ns.FloatText(popup, StatText(stat), r, g, b, 56)
			ns.PlaySfx(STAT_SOUND)
		end)
	end
	return #stats * STAT_SECONDS
end

local function Finale()
	ns.ReleaseChatLine(current.lineID)
	local statSeconds = ShowStats(current.link)
	current.statsUntil = GetTime() + statSeconds
	Hold((#queue > 0 and QUEUED_HOLD_SECONDS or HOLD_SECONDS) + statSeconds)
end

-- Shows the next queued item: it climbs one quality per tick from gray, or starts at its real
-- quality when it already rolled in the loot window.
local function PlayNext()
	current = table.remove(queue, 1)
	if not current then
		return
	end
	local step = current.skipLadder and current.quality or Enum.ItemQuality.Poor
	icon:SetTexture(current.icon)
	popup:Show()
	ShowStep(step, step >= current.quality)
	if step >= current.quality then
		Finale()
		return
	end
	-- One tick per remaining step; the ticker stops by itself after the last one.
	ticker = C_Timer.NewTicker(STEP_SECONDS, function()
		step = step + 1
		local isFinal = step >= current.quality
		ShowStep(step, isFinal)
		if isFinal then
			ticker = nil
			Finale()
		end
	end, current.quality - step)
end

fadeOut:SetScript("OnFinished", function()
	popup:Hide()
	PlayNext()
end)

-- Clicking the pop-up skips to the next queued item.
popup:SetScript("OnMouseDown", function()
	ns.ReleaseChatLine(current and current.lineID)
	ticker = ns.CancelTimer(ticker)
	holdTimer = ns.CancelTimer(holdTimer)
	fadeOut:Stop()
	popup:Hide()
	PlayNext()
end)

-- force shows the pop-up for any quality, even when it is turned off (used by /gacha test).
-- lineID is the held-back chat line for this item, printed once the pop-up finishes.
function ns.QueueReveal(link, forcedQuality, force, lineID)
	local item = Item:CreateFromItemLink(link)
	if not (LootGachaDB.reveal or force) or item:IsItemEmpty() then
		ns.ReleaseChatLine(lineID)
		return
	end
	item:ContinueOnItemLoad(function()
		local name, _, quality, _, _, _, _, _, _, iconFileID = C_Item.GetItemInfo(link)
		quality = forcedQuality or quality or Enum.ItemQuality.Common
		if not name or #queue >= MAX_QUEUE or (quality < Enum.ItemQuality.Uncommon and not force) then
			ns.ReleaseChatLine(lineID)
			return
		end
		table.insert(queue, {
			link = link,
			name = name,
			icon = iconFileID,
			quality = quality,
			lineID = lineID,
			skipLadder = not forcedQuality and ns.WasRolled(link),
		})
		if not current then
			PlayNext()
		elseif holdTimer then
			-- The current pop-up is only lingering, so cut it short for the new one, but let its
			-- stats finish floating first.
			Hold(math.max((current.statsUntil or 0) - GetTime(), 0) + QUEUED_HOLD_SECONDS)
		end
	end)
end
