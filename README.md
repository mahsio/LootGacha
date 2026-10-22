# LootGacha

Gacha-style loot for World of Warcraft: Forever. **Cosmetic only: it never changes what drops, only how it is shown.**

## Features
- **Rolling loot window.** Every item stays hidden ("???") until you click it, then rolls up one quality at a time, from gray to what it really is. It stays in the window until you click it again to loot it, and stays uncovered if you close the window and loot the same body again. "Loot all" rolls and loots everything. With auto loot, every item rolls at once, quickly.
- **Pop-up for green or better items**, with floating "+N Stat!" text.
- **Coin shower.** Every money gain (loot, quest rewards, mail, vendor sales) flies from your mouse into a money counter, with stingers when copper rolls over into silver and silver into gold.
- **Item names at the mouse** after you loot, or a red "No loot" for an empty corpse.
- **Your "You receive loot" chat line** waits until that item's pop-up has finished.
- Uses only the game's own sounds and art.

## Commands
- `/gacha options`: open the settings (also under Esc > Options > AddOns, or the minimap addon menu)
- `/gacha test [0-5]`: preview the pop-up with one of your equipped items (0 = gray ... 5 = orange)
- `/gacha coins [copper]`: preview a coin shower
- `/gacha hud`: pin the money counter on screen so you can drag it
- `/gacha debug`: toggle the loot and money event log

## Compatibility
- If you use another loot window addon, turn off **Rolling loot window** and then type `/reload`.
- Master loot always uses Blizzard's own loot window.
- The addon's own text is English. Item names, stats and coin names follow your client's language.

## Reporting bugs
Turn on the event log with `/gacha debug`, reproduce the problem, and include the chat lines it prints.

## AI Transparency
- This addon was 100% "vibe-coded" for fun via Claude.
- The LLM was prompted to adhere to WoW's ToS regarding addons