-- Settings panel (Esc > Options > AddOns > LootGacha) and the minimap addon menu entry.
local _, ns = ...

-- An option with a parent is indented under it and grayed out while the parent is off.
local OPTIONS = {
	{ key = "rollingLoot", name = "Rolling loot window", tooltip = "Replace the loot window with one where each item stays hidden until you click it, then rolls up from gray to its real quality. Click it again to loot it. Master loot always uses the normal window. If you use another loot window addon, turn this off and then type /reload." },
	{ key = "reveal", name = "Pop-up for green or better", tooltip = "Show a pop-up with floating stats when you loot an Uncommon (green) or better item." },
	{ key = "holdChat", parent = "reveal", name = "Hold loot chat lines", tooltip = "Hide your \"You receive loot\" chat line until that item's pop-up finishes." },
	{ key = "lootNames", name = "Item names at the mouse", tooltip = "Show each item's name just above your mouse after you loot it, or \"No loot\" for an empty corpse." },
	{ key = "coins", name = "Coin shower", tooltip = "Fly the coins from every money gain (loot, quests, mail, vendor sales) into a money counter at your mouse." },
	{ key = "hudAlways", name = "Always show money counter", tooltip = "Keep the money counter in one spot on screen instead of popping up at your mouse. Drag it to move it." },
	{ key = "sound", name = "Sound effects", tooltip = "Play LootGacha's sound effects." },
	{ key = "debug", name = "Debug log", tooltip = "Print loot and money events to chat. Useful for bug reports." },
}

local category
local settings = {}

local function Apply()
	ns.UpdateHUD()
	ns.ApplyLootTakeover()
end

table.insert(ns.onLoad, function()
	category = Settings.RegisterVerticalLayoutCategory("LootGacha")
	local initializers = {}
	for _, option in ipairs(OPTIONS) do
		local setting = Settings.RegisterAddOnSetting(category, "LootGacha_" .. option.key, option.key, LootGachaDB,
			Settings.VarType.Boolean, option.name, ns.defaults[option.key])
		setting:SetValueChangedCallback(Apply)
		local initializer = Settings.CreateCheckbox(category, setting, option.tooltip)
		if option.parent then
			initializer:SetParentInitializer(initializers[option.parent], function()
				return LootGachaDB[option.parent]
			end)
		end
		initializers[option.key] = initializer
		settings[option.key] = setting
	end
	Settings.RegisterAddOnCategory(category)
end)

-- Flips a setting through the settings system so the panel's checkbox stays in sync; its
-- callback applies the change.
function ns.ToggleOption(key)
	local setting = settings[key]
	setting:SetValue(not setting:GetValue())
	ns.Print(format("%s: %s", setting:GetName(), setting:GetValue() and "on" or "off"))
end

function ns.OpenOptions()
	Settings.OpenToCategory(category:GetID())
end

LootGacha_OnAddonCompartmentClick = ns.OpenOptions
