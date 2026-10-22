-- Looted item names pop up just above the mouse, over the coin counter, then fade away.
-- Several at once stack upward, newest at the bottom.
local _, ns = ...

-- Clears the coin counter, which pops up at the mouse too.
local OFFSET_Y = 125
local LINE_HEIGHT = 22
local SHOW_SECONDS = 2.5
local MAX_LINES = 6

local holder = CreateFrame("Frame", nil, UIParent)
holder:SetSize(1, 1)
holder:SetFrameStrata("DIALOG")

local active = {}
local free = {}

local function Layout()
	for i, line in ipairs(active) do
		line:ClearAllPoints()
		line:SetPoint("BOTTOM", holder, "BOTTOM", 0, (i - 1) * LINE_HEIGHT)
	end
end

local function Release(line)
	for i, other in ipairs(active) do
		if other == line then
			table.remove(active, i)
			break
		end
	end
	line.anim:Stop()
	line:Hide()
	table.insert(free, line)
	Layout()
end

local function CreateLine()
	local line = CreateFrame("Frame", nil, holder)
	line:SetSize(320, LINE_HEIGHT)
	line.text = line:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	line.text:SetPoint("CENTER")

	-- All three run together: fade in with a pop, then fade out after SHOW_SECONDS.
	line.anim = line:CreateAnimationGroup()
	ns.AddFade(line.anim, 0, 1, 0.15)
	ns.AddPop(line.anim, 1.25, 0.2)
	ns.AddFade(line.anim, 1, 0, 0.5, SHOW_SECONDS)
	line.anim:SetScript("OnFinished", function()
		Release(line)
	end)
	return line
end

local function AddLine(text, r, g, b)
	if not LootGachaDB.lootNames then
		return
	end
	-- A new batch starts at the current mouse position (above the loot window if it is open
	-- there); later lines stack onto it.
	if #active == 0 then
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		x, y = ns.AboveLootWindow(x / scale, y / scale)
		holder:ClearAllPoints()
		holder:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x, y + OFFSET_Y)
	end
	if #active >= MAX_LINES then
		Release(active[#active])
	end
	local line = table.remove(free) or CreateLine()
	line.text:SetText(text)
	line.text:SetTextColor(r, g, b)
	table.insert(active, 1, line)
	Layout()
	line:Show()
	line.anim:Restart()
end

function ns.ShowLootName(link, count)
	local _, _, _, _, icon = C_Item.GetItemInfoInstant(link)
	local text = link
	if icon then
		text = "|T" .. icon .. ":18|t " .. text
	end
	if count and count > 1 then
		text = text .. " x" .. count
	end
	-- The link carries its own quality color.
	AddLine(text, 1, 1, 1)
end

-- An empty corpse: a red "No loot" at the mouse and a frog croak.
local FROG_CROAK = 549323 -- sound/creature/frog/frogwounda.ogg

function ns.ShowNoLoot()
	AddLine("No loot", 1, 0.2, 0.2)
	ns.PlayFileSfx(FROG_CROAK)
end
