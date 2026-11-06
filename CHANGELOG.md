# Changelog

## 1.0.2
- Fixed "LootGacha has been blocked from an action only available to the Blizzard UI" with the Gamepad UI on, which could also collapse the gamepad action bars mid-combat. The live client's gamepad action bar clears a dead target whenever a loot window closes, and LootGacha closing its own window set that off.
- With the Gamepad UI on, looting uses Blizzard's own loot window, which works with a gamepad. The pop-up, coin shower and item names still play.

## 1.0.1
- A revealed item now stays in the loot window until you click it again to loot it. "Loot all" still reveals and loots everything.
- Revealed items stay uncovered if you close the loot window and loot the same body again.

## 1.0.0
- First public release for World of Warcraft: Forever.
- Rolling loot window: every item stays hidden until you click it, then rolls up from gray to its real quality. With auto loot, everything rolls at once, quickly.
- Pop-up with floating "+N Stat!" text for green or better items.
- Coin shower: every money gain flies into a money counter at your mouse, with copper-to-silver and silver-to-gold rollovers.
- Item names (or a red "No loot") pop up at the mouse after looting.
- Your "You receive loot" chat line waits until the item's pop-up finishes.
