-- The coin shower: money you gain (loot, quest rewards, mail, vendor sales...) flies from the
-- cursor into a money counter that pops up just above it. The counter shows your total and
-- the amount still on its way, and plays a stinger whenever copper rolls over into silver or
-- silver into gold.
local _, ns = ...

local PER_SILVER, PER_GOLD = COPPER_PER_SILVER, COPPER_PER_GOLD
local MAX_SPRITES_PER_COIN = 40
local SPAWN_INTERVAL = 0.03
local COIN_SIZE = 18
local CLINK_GAP = 0.07
local HUD_LINGER = 3
-- Puts the counter above the loot window, which also opens at the cursor.
local HUD_CURSOR_OFFSET = 70
local SYNC_DELAY = 0.6

local COINS = {
	{ key = "copper", atlas = "coin-copper", copper = 1, label = COPPER_AMOUNT, color = { 0.93, 0.6, 0.35 } },
	{ key = "silver", atlas = "coin-silver", copper = PER_SILVER, label = SILVER_AMOUNT, color = { 0.85, 0.85, 0.9 } },
	{ key = "gold", atlas = "coin-gold", copper = PER_GOLD, label = GOLD_AMOUNT, color = { 1, 0.82, 0 } },
}
for _, coin in ipairs(COINS) do
	coin.pattern = ns.FormatToPattern(coin.label)
end

-- Copper in coin text such as the loot window's "1 Silver\n23 Copper".
function ns.ParseCoinText(text)
	local copper = 0
	for _, coin in ipairs(COINS) do
		copper = copper + (tonumber(text:match(coin.pattern)) or 0) * coin.copper
	end
	return copper
end

local hud = CreateFrame("Frame", "LootGachaMoneyHUD", UIParent)
hud:SetSize(200, 50)
hud:SetFrameStrata("DIALOG")
hud:SetClampedToScreen(true)
hud:SetMovable(true)
hud:RegisterForDrag("LeftButton")
hud:SetScript("OnDragStart", hud.StartMoving)
hud:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	self:SetUserPlaced(false)
	local point, _, relativePoint, x, y = self:GetPoint()
	LootGachaDB.hudPos = { point, relativePoint, x, y }
end)
hud:Hide()

local hudFade = ns.AddFade(hud:CreateAnimationGroup(), 1, 0, 0.4)
hudFade:SetScript("OnFinished", function()
	hud:Hide()
end)

-- The top line: coins still on their way, e.g. "+1g 23s 45c". It counts down as each coin
-- lands while the total below counts up.
local gainText = hud:CreateFontString(nil, "OVERLAY", "GameFontNormal")
gainText:SetPoint("TOPRIGHT", -10, -7)
gainText:SetTextColor(0.2, 1, 0.2)
local pendingGain = 0

local function UpdateGainText()
	gainText:SetText(pendingGain > 0 and "+" .. GetMoneyString(pendingGain, true) or "")
end

-- Laid out right to left like Blizzard's money frames: gold, silver, copper.
local slots = {}
local previous
for _, coin in ipairs(COINS) do
	local slotIcon = hud:CreateTexture(nil, "ARTWORK")
	slotIcon:SetAtlas(coin.atlas)
	slotIcon:SetSize(16, 16)
	if previous then
		slotIcon:SetPoint("RIGHT", previous, "LEFT", -8, 0)
	else
		slotIcon:SetPoint("BOTTOMRIGHT", hud, "BOTTOMRIGHT", -10, 8)
	end
	local slotText = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	slotText:SetPoint("RIGHT", slotIcon, "LEFT", -2, 0)
	previous = slotText
	slots[coin.key] = {
		icon = slotIcon,
		text = slotText,
		pulse = ns.AddPop(slotIcon:CreateAnimationGroup(), 1.4, 0.15),
		bigPulse = ns.AddPop(slotIcon:CreateAnimationGroup(), 2.6, 0.45),
	}
end

-- A backpack icon marks the total as the coins already in your bags.
local bagIcon = hud:CreateTexture(nil, "ARTWORK")
bagIcon:SetTexture("Interface\\Icons\\ui-hud-actionbar-bag")
bagIcon:SetSize(18, 18)
bagIcon:SetPoint("RIGHT", previous, "LEFT", -6, 0)

-- shown is the balance the counter displays; it lags GetMoney() while coins are in flight.
local shown = 0

local function UpdateText()
	slots.gold.text:SetText(tostring(math.floor(shown / PER_GOLD)))
	slots.silver.text:SetText(tostring(math.floor(shown / PER_SILVER) % SILVER_PER_GOLD))
	slots.copper.text:SetText(tostring(shown % PER_SILVER))
end

function ns.SyncMoney()
	shown = GetMoney()
	UpdateText()
end

-- Just enough copper to roll the counter over into the next silver (used by /gacha coins).
function ns.CopperToNextSilver()
	return PER_SILVER - shown % PER_SILVER
end

-- Coins live on a full-screen layer above everything else.
local layer = CreateFrame("Frame", nil, UIParent)
layer:SetAllPoints(UIParent)
layer:SetFrameStrata("FULLSCREEN_DIALOG")

local freeCoins = {}
local flying = {}
local spawnQueue = {}
local spawnTimer = 0
local lastClink = 0
local syncTimer, lingerTimer

local function CenterInLayer(region)
	local x, y = region:GetCenter()
	local scale = region:GetEffectiveScale() / layer:GetEffectiveScale()
	return x * scale, y * scale
end

local function CursorInLayer()
	local x, y = GetCursorPosition()
	local scale = layer:GetEffectiveScale()
	return x / scale, y / scale
end

-- Spreads count coins over at most budget sprites without losing any value.
-- Each sprite remembers where its shower started (x, y).
local function Enqueue(coin, count, budget, x, y)
	local sprites = math.min(count, budget)
	for i = 1, sprites do
		local units = math.floor(count / sprites) + ((i <= count % sprites) and 1 or 0)
		table.insert(spawnQueue, { coin = coin, value = units * coin.copper, x = x, y = y })
	end
end

local function SpawnCoin(item)
	local texture = table.remove(freeCoins) or layer:CreateTexture(nil, "OVERLAY")
	texture:SetAtlas(item.coin.atlas)
	texture:SetSize(COIN_SIZE, COIN_SIZE)
	texture:Show()
	local sx, sy = item.x + math.random(-12, 12), item.y + math.random(-12, 12)
	local ex, ey = CenterInLayer(slots[item.coin.key].icon)
	table.insert(flying, {
		texture = texture,
		coin = item.coin,
		value = item.value,
		elapsed = 0,
		duration = 0.55 + math.random() * 0.4,
		spin = 8 + math.random() * 8,
		sx = sx, sy = sy,
		-- The control point flings the coin up and out before it curves into the counter.
		cx = sx + math.random(-160, 160), cy = math.max(sy, ey) + math.random(80, 220),
		ex = ex, ey = ey,
	})
end

-- Moves a coin along its quadratic Bezier curve. Returns true once it has arrived.
local function MoveCoin(c, elapsed)
	c.elapsed = c.elapsed + elapsed
	local p = math.min(c.elapsed / c.duration, 1)
	local u = p * p * (3 - 2 * p)
	local a, b, d = (1 - u) ^ 2, 2 * (1 - u) * u, u ^ 2
	c.texture:SetPoint("CENTER", layer, "BOTTOMLEFT", a * c.sx + b * c.cx + d * c.ex, a * c.sy + b * c.cy + d * c.ey)
	-- Squashing the width fakes a spinning coin.
	c.texture:SetWidth(COIN_SIZE * (0.3 + 0.7 * math.abs(math.cos(c.elapsed * c.spin))))
	return p >= 1
end

local function Clink()
	local now = GetTime()
	if now - lastClink >= CLINK_GAP then
		lastClink = now
		ns.PlaySfx(SOUNDKIT.IG_BACKPACK_COIN_SELECT)
	end
end

local function Rollover(coin)
	local slot = slots[coin.key]
	slot.bigPulse:Restart()
	ns.PlaySfx(coin.key == "gold" and SOUNDKIT.UI_ITEM_UPGRADE_UI_ITEM_UPGRADED_EPIC or SOUNDKIT.UI_ITEM_UPGRADE_UI_ITEM_UPGRADED_RARE)
	-- Starts above the "+" line so the two don't overlap.
	ns.FloatText(slot.icon, "+" .. format(coin.label, 1) .. "!", coin.color[1], coin.color[2], coin.color[3], 44)
end

local function Arrive(c)
	c.texture:Hide()
	c.texture:ClearAllPoints()
	table.insert(freeCoins, c.texture)
	local before = shown
	shown = shown + c.value
	pendingGain = math.max(pendingGain - c.value, 0)
	UpdateText()
	UpdateGainText()
	slots[c.coin.key].pulse:Restart()
	if c.coin.key ~= "gold" and math.floor(shown / PER_GOLD) > math.floor(before / PER_GOLD) then
		Rollover(COINS[3])
	elseif c.coin.key == "copper" and math.floor(shown / PER_SILVER) > math.floor(before / PER_SILVER) then
		Rollover(COINS[2])
	else
		Clink()
	end
end

local function ScheduleSync()
	ns.CancelTimer(syncTimer)
	syncTimer = C_Timer.NewTimer(SYNC_DELAY, function()
		syncTimer = nil
		ns.SyncMoney()
	end)
end

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self, elapsed)
	spawnTimer = spawnTimer + elapsed
	while spawnTimer >= SPAWN_INTERVAL and #spawnQueue > 0 do
		spawnTimer = spawnTimer - SPAWN_INTERVAL
		SpawnCoin(table.remove(spawnQueue, 1))
	end
	for i = #flying, 1, -1 do
		local c = flying[i]
		if MoveCoin(c, elapsed) then
			table.remove(flying, i)
			Arrive(c)
		end
	end
	if #spawnQueue == 0 and #flying == 0 then
		self:Hide()
		-- Snap to the real balance in case the showered amount and the actual change differ.
		ScheduleSync()
		-- A counter pinned during the shower moves to its pinned spot now that no coins aim at it.
		if LootGachaDB.hudAlways then
			ns.UpdateHUD()
		end
		-- The counter lingers, then clears the "+" line and fades out unless it is pinned.
		lingerTimer = C_Timer.NewTimer(HUD_LINGER, function()
			lingerTimer = nil
			pendingGain = 0
			UpdateGainText()
			if not LootGachaDB.hudAlways then
				hudFade:Play()
			end
		end)
	end
end)

-- force plays the shower even when it is turned off in the settings (used by /gacha coins).
-- Returns true when a shower started.
function ns.StartCoinShower(copper, force)
	if not (LootGachaDB.coins or force) or copper <= 0 then
		return false
	end
	syncTimer = ns.CancelTimer(syncTimer)
	lingerTimer = ns.CancelTimer(lingerTimer)
	local x, y = CursorInLayer()
	-- A fresh stream starts with one coin right away instead of a burst of banked spawn time.
	if #spawnQueue == 0 then
		spawnTimer = SPAWN_INTERVAL
	end
	-- Pop up just above the cursor, unless the counter is pinned in place. It doesn't move
	-- while coins are still flying, so they always land where they were aimed.
	if not driver:IsShown() and not LootGachaDB.hudAlways then
		local hudX, hudY = ns.AboveLootWindow(x, y)
		hud:ClearAllPoints()
		hud:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", hudX, hudY + HUD_CURSOR_OFFSET)
	end
	hudFade:Stop()
	hud:Show()
	pendingGain = pendingGain + copper
	UpdateGainText()
	-- A backlog (vendor sales, mail) gets fewer, heavier coins so showers don't trail on.
	local budget = math.max(1, MAX_SPRITES_PER_COIN - #spawnQueue)
	-- No start sound: the game already plays its own coin sound when you gain money.
	-- Copper first, so the copper-to-silver rollover can happen before the silver arrives.
	Enqueue(COINS[1], copper % PER_SILVER, budget, x, y)
	Enqueue(COINS[2], math.floor(copper / PER_SILVER) % SILVER_PER_GOLD, budget, x, y)
	Enqueue(COINS[3], math.floor(copper / PER_GOLD), budget, x, y)
	driver:Show()
	return true
end

-- The loot window showers coins on the click, before the money arrives. That amount is kept
-- as credit so the money change that follows doesn't shower the same coins again.
local CREDIT_SECONDS = 3
local credit, creditUntil = 0, 0

function ns.StartCoinShowerAhead(copper)
	credit = credit + copper
	creditUntil = GetTime() + CREDIT_SECONDS
	ns.StartCoinShower(copper)
end

-- Spending only updates the counter; gains shower from the cursor (usually the button you just
-- clicked).
function ns.OnMoneyChanged(delta)
	if GetTime() > creditUntil then
		credit = 0
	end
	local gain = delta
	if delta > 0 then
		local covered = math.min(delta, credit)
		credit = credit - covered
		gain = delta - covered
	end
	if gain > 0 and ns.StartCoinShower(gain) then
		return
	end
	if not driver:IsShown() then
		ScheduleSync()
	end
end

-- Pinned ("Always show money counter"): stays where you dragged it. Otherwise it only pops up
-- at the cursor while you gain money.
function ns.UpdateHUD()
	hud:EnableMouse(LootGachaDB.hudAlways)
	if LootGachaDB.hudAlways then
		if not driver:IsShown() then
			local pos = LootGachaDB.hudPos
			hud:ClearAllPoints()
			if pos then
				hud:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
			else
				hud:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -40, 120)
			end
		end
		hudFade:Stop()
		hud:Show()
	elseif not driver:IsShown() and not lingerTimer then
		hud:Hide()
	end
end

table.insert(ns.onLoad, ns.UpdateHUD)
