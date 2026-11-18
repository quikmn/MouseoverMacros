# MouseoverMacros

WoW Forever (interface 16001). `/mom` opens a macro window: your class's mouseover set, every macro you have, extended macros past the slot limits, backups and export / import. `/mom help` lists the chat commands.

`/macro` opens this window too (on your account macros), and so does Macros in the game menu and the chat menu (outside combat). Blizzard's own macro window: "Blizzard's macro window" at the bottom of the sidebar or `/mom blizzard`; it has an "Open /mom" button to come back. To give `/macro` back to Blizzard, switch off "Open MoM for /macro" under Options (`/mom takeover off`).

## The window

- **Mine**: what /mom made for you (`_mom` macros) and your extended macros.
- **Account** / **Character**: all your game macros, with search and slot counters ("Account 34/120, Character 30/30"). Click one to edit it. Your own macros can be edited here too; /mom never changes them by itself.
- **Extended**: macros stored by /mom instead of the game: as many as you like, up to 1023 characters each, on every character. Each one runs from a hidden button. Give it a key on a character (no slot), or "Put on a bar" makes a one-line `_mom` macro that clicks it (one slot). Both fire when you press the key, not when you let go (the bar macro follows the game's "Cast action keybinds on key down" setting, like every action button).
- **Templates**: the mouseover set for your class (on/off switches, Create / update all) and a few common macros (both trinkets, focus or skull on mouseover, target and attack, assist focus, ready check; Priest: wand and Inner Focus + Greater Heal), made as a `_mom` macro or as an extended one.
- **Edit**: name, icon (picker with search; "Icon from the spell" shows the icon of the spell the macro casts), the text with a live count against its limit (255 or 1023), a check that every spell and item name exists, quick inserts for conditionals, Save, Save as copy, Pick up, Move to account / character, Delete (click twice). Leaving a macro with unsaved changes asks Save / Discard / Cancel. Save in combat waits and saves your latest text when combat ends. The last 10 versions of each macro are kept; Restore puts one back in the editor.
- **Backups**: the last 20 deleted macros (Restore), export of a set as text, import (as exported, or as extended, character or account macros; nothing is replaced).
- **Ring**: the ring (below).
- **Options**: Open MoM for /macro, where new macros go, keeping the game's Auto Self Cast off.

The game allows 120 account macros and a fixed number per character, 255 characters each. No addon can change that; extended macros are the way past it.

## The ring

Hold the ring key (the middle mouse button by default), move the mouse toward a slice and let go: that slice is used. A quick flick works the same way. Letting go in the middle does nothing.

- **Right: Consumables**, a sub-ring with the best food, drink, healing potion (or healthstone), mana potion and bandage in your bags, plus your class's buff spells you know.
- **Left: Professions**, your profession windows, Disenchant / Prospecting / Milling, the cooking fire and Smelting when you know them.
- **Down: Fishing**, the Fishing spell, your "Fishing" equipment set (it switches back to your first other set when you hold a fishing pole) or else the best fishing pole in your bags, and each lure you carry (put on the pole).
- **Up: Hearthstone**. The other four directions are empty.

A sub-ring (blue corner) opens its own ring around the same point. Click a slice, or press and let go of the key toward it. Escape, a right click, a click far away or letting go in the middle closes it.

**Best consumable:** among the items in your bags of that kind (from the item's use spell: Food, Drink, Healing Potion, Restore Mana, First Aid; else its item class), the usable ones first (your level is high enough and the game says it is usable), then the highest required level, then the highest item level, then the bigger stack.

**Combat:** the ring works in combat. Every slice is a secure button and the direction is worked out by the game's secure code, so nothing insecure casts anything. What the slices hold is set outside combat. It is rebuilt when your bags, spells, macros or equipment sets change, and kept as it is during combat; a change made then (in the bags or on the Ring page) happens when combat ends. Items you use up in combat show greyed. Spells and items are used as they are: the ring never adds a self cast.

**Editing:** the **Ring** page in `/mom`. Set the key (any key or mouse button, with Shift / Ctrl / Alt), switch the ring off (the key does what it did before), click a direction to edit it, drag spells, items, macros, mounts or equipment sets onto a direction (onto a sub-ring they are added to it), drag one direction onto another to swap them, make a direction a sub-ring, add dynamic slices ("Best food", "Your buffs", "Fishing lures" ...) or extended macros, reorder and remove. In chat: `/mom ring help`, for example `/mom ring key BUTTON4`, `/mom ring set upright Fishing`, `/mom ring add down hpot`, `/mom ring swap left right`, `/mom ring reset`.

## Chat commands

`/mom` follows the same pattern as every EverlookDB addon:

- `/mom`: the window. `/mom help` (or `?`) lists every command; a mistyped one suggests the nearest.
- `/mom install`: create or update every switched-on macro; `/mom create <macro>` one of them; `/mom list` your class's macros.
- `/mom off <macro>`, `/mom on <macro>`: leave a macro out of `/mom install`, or put it back.
- `/mom new`, `/mom blizzard`: a new macro in the editor, Blizzard's own macro window.
- `/mom ring help`: the ring's own commands.
- `/mom takeover off` or `/mom set takeover off`: change a setting (`/mom get` lists them; `/mom off takeover` works too).
- `/mom reset ring` (or `/mom ring reset`): the ring's default slices back, your key stays; type it twice within 10 seconds.
- `/mom search <words>`: the window with its search box filled; `/mom status`, `/mom version`.

## Which macros /mom changes

Its macros are named `_mom` plus four random digits (for example `_mom4821`), never a name already in use, and /mom remembers which ones it made (account macros for the account, character macros per character). On its own it only ever updates those, in place, so your bars keep working; it never touches a macro of yours, even one with the same name. Old plain-named /mom macros (`heal`, `fort`, ...) are renamed to `_mom` names at login if their text is exactly what an older /mom wrote. Bar addons show the macro name under the button; Bartender4's "Hide Macro Text" hides it.

Macros can't be changed in combat: anything you ask for then waits and happens when combat ends.

## The mouseover set

- Friendly spells: mouseover, then friendly target. Never yourself.
- Hostile spells: mouseover, then target.
- Dispel Magic, Penance: mouseover, then target, friend or enemy.
- Turns off the game's Auto Self Cast setting on every login.

Classes covered so far: Priest.

## License

GPL-3.0 (see `LICENSE`). Written from scratch; it embeds LibStub (public domain) to load EverlookUI, the settings-window library shared by the EverlookDB addons.
