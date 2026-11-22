# EverlookDB Macros

WoW Forever (interface 16001). `/mom` opens a macro window: every macro you have with an editor next to it, a mouseover builder for your spells, your class's mouseover set, backups and export / import. `/mom help` lists the chat commands.

`/macro` opens this window too (on the Macros page), and Macros in the game menu and the chat menu opens it next to Blizzard's window (/mom never closes Blizzard's window). Blizzard's own macro window: "Blizzard's macro window" at the bottom of the sidebar or `/mom blizzard`; it has an "Open /mom" button to come back. To give `/macro` back to Blizzard, switch off "Open /mom for /macro" under Options (`/mom takeover off`).

## The window

- **Macros**: on the left every macro you have, account and character together, by what it casts ("Devouring Plague", a ready-made one by its title), with its name and kind after it, a search box and the slot counters ("Character 30/30, Account 14/120"). Drag a row onto an action bar, or Put on bar. Tick several and "Delete selected" deletes them at once. On the right, the editor for the one you clicked:
  - name; icon (from the spell it casts, or Change icon: a picker with search); drag the icon onto a bar;
  - "Stored as" character or account macro (a new one goes to a character slot, else an account slot, and the editor says which; both full: it says so and makes nothing);
  - the text with a live count against 255 and a check that every spell and item name exists;
  - Insert spell: type a few letters, pick from your spellbook, Rank... for a lower rank; condition buttons (mouseover friend / enemy / any / dead, focus, shift / ctrl / alt, /cast, /use, /stopcasting, #showtooltip);
  - Save, Undo (back to what was saved), Save as copy, Delete (one click: it goes to the bin, Undo on the list or `/mom undo` puts it back);
  - Earlier versions (the last 10, folded away): Restore puts one back in the editor.

  Leaving a macro with unsaved changes asks Save / Discard / Cancel. Save in combat waits and saves your latest text when combat ends.
- **Mouseover builder**: a spell "On a friend" and one "On an enemy" (either may stay empty), each with its rank (highest by default). Fall back to my target (on), Stop casting first, the Power Infusion whisper. You see the macro and a suggested name ("DP / FH r1"); Create saves it in a free slot (character, else account) and puts it on your cursor to drop on a bar. **Quick picks** below: your class's mouseover set (on/off switches, Create / Update, "Make my whole mouseover set") and the ready-made macros (both trinkets, focus or skull on mouseover, target and attack, assist focus, ready check; Priest: wand, Inner Focus + Greater Heal, Devouring Plague / Flash Heal rank 1, Devouring Plague / Power Infusion and more), with a search.
- **Ring**: the ring (below).
- **Backups**: the last 100 deleted macros (Restore), export of a set as text, import (as exported, as character or as account macros; nothing is replaced).
- **Options**: Open /mom for /macro, where new macros go, keeping the game's Auto Self Cast off.

In combat the game doesn't let an addon put a macro on your cursor: Put on bar then opens the game's macro window to drag it from. Deleting, moving and restoring in combat say at once that they happen when combat ends, show as waiting, and can be cancelled.

The game allows 120 account macros and a fixed number per character, 255 characters each. No addon can change that; when your character macros are full, new ones go to the account macros, which every character shares.

Extended macros (up to 0.3.9) are gone: at the next login each becomes a normal macro (bar buttons for it are turned into it, so they keep working); one over 255 characters or without a free slot goes to Backups, named in chat. Their key bindings go too, named in chat once.

## The ring

Hold the ring key (the middle mouse button by default), move the mouse toward a slice and let go: that slice is used. A quick flick works the same way. Letting go in the middle does nothing.

- **Right: Consumables**, a sub-ring with the best food, drink, healing potion (or healthstone), mana potion and bandage in your bags, plus your class's buff spells you know.
- **Left: Professions**, your profession windows, Disenchant / Prospecting / Milling, the cooking fire and Smelting when you know them.
- **Down: Fishing**, the Fishing spell, your "Fishing" equipment set (it switches back to your first other set when you hold a fishing pole) or else the best fishing pole in your bags, and each lure you carry (put on the pole).
- **Up: Hearthstone**. The other four directions are empty.

A sub-ring (blue corner) opens its own ring around the same point. Click a slice, or press and let go of the key toward it. Escape, a right click, a click far away or letting go in the middle closes it.

**Best consumable:** the usable item of that kind with the highest required level, then item level, then the bigger stack.

**Combat:** the ring works in combat. Its slices refresh when your bags, spells, macros or equipment sets change; changes made during a fight apply when combat ends, and used-up items show greyed. The ring never adds a self cast.

**Editing:** the **Ring** page in `/mom`. Set the key (any key or mouse button, with Shift / Ctrl / Alt), switch the ring off (the key does what it did before), click a direction to edit it, drag spells, items, macros, mounts or equipment sets onto a direction (onto a sub-ring they are added to it), drag one direction onto another to swap them, make a direction a sub-ring, add dynamic slices ("Best food", "Your buffs", "Fishing lures" ...), reorder and remove. In chat: `/mom ring help`, for example `/mom ring key BUTTON4`, `/mom ring set upright Fishing`, `/mom ring add down hpot`, `/mom ring swap left right`, `/mom ring reset`.

## Chat commands

`/mom` follows the same pattern as every EverlookDB addon:

- `/mom` (or `/emacros`): the window. `/mom help` (or `?`) lists every command; a mistyped one suggests the nearest.
- `/mom install`: create or update every switched-on macro; `/mom create <macro>` one of them; `/mom list` your class's macros.
- `/mom off <macro>`, `/mom on <macro>`: leave a macro out of `/mom install`, or put it back.
- `/mom new [account|char]`, `/mom build`, `/mom undo`, `/mom blizzard`: a new macro in the editor, the mouseover builder, put the last deleted macro(s) back, Blizzard's own macro window.
- `/mom ring help`: the ring's own commands.
- `/mom takeover off` or `/mom set takeover off`: change a setting (`/mom get` lists them; `/mom off takeover` works too).
- `/mom reset ring` (or `/mom ring reset`): the ring's default slices back, your key stays; type it twice within 10 seconds.
- `/mom search <words>`: the window with its search box filled; `/mom status`, `/mom version`.

## Which macros /mom changes

Its macros are named `_mom` plus four random digits (for example `_mom4821`), never a name already in use, and /mom remembers which ones it made (account macros for the account, character macros per character). On its own it only ever updates those, in place, so your bars keep working; it never touches a macro of yours, even one with the same name. Old plain-named /mom macros (`heal`, `fort`, ...) are renamed to `_mom` names at login if their text is exactly what an older /mom wrote. Bar addons show the macro name under the button; Bartender4's "Hide Macro Text" hides it.

Macros can't be changed in combat: anything you ask for then waits and happens when combat ends.

## The mouseover set

Every class has one: the spells worth a mouseover macro, from levels 1 to 60 and every spec. Warrior 11, Paladin 26, Hunter 11, Rogue 5, Priest 41, Shaman 15, Mage 12, Warlock 27, Druid 24; most are on by default, situational ones (and plain nukes) are listed but off.

- Friendly spells (heals, shields, dispels, buffs, blessings, Innervate, Power Infusion): mouseover, then friendly target. Never yourself.
- Hostile spells (DoTs, curses, interrupts, crowd control, taunts, Hunter's Mark, Purge): mouseover, then target.
- Either side (Dispel Magic, Penance, Holy Shock, Mind Vision, Devour Magic): mouseover, then target, friend or enemy.
- Resurrections: mouseover corpse, then dead target.
- Left out: self-only spells, stances, forms, auras, totems, ground spells, pet-only spells and buffs that are raid-wide in Forever.
- A macro is only made for a spell you know; talent spells appear when you learn them. Spells are cast by name without a rank (always your best rank), in your client's language.
- Turns off the game's Auto Self Cast setting on every login.

**Every character set up automatically:** on a character's first login (one where /mom was never set up), /mom makes the switched-on macros for the spells it knows, as character macros, and says so in one chat line ("made 14 mouseover macros for your Paladin; /mom to change"). It always leaves 3 character slots free for your own and never uses account macros for this (they would show up on all your characters); what didn't fit is named in that line. Spells you learn later get their macro too, one chat line per batch. A macro you deleted is never made again on its own, and your own macros are never touched. Characters you had already set up are left as they are ("Make my whole mouseover set" adds the new ones there). Switch it off for all characters under Options ("Set up every character automatically", `/mom off autosetup`).

**Make my whole mouseover set** (in the Mouseover builder) makes or updates the switched-on macros for spells you know. A macro of ours you changed by hand is kept (its row's Update puts ours back); one still exactly as an older /mom wrote it is brought up to date.

## License

GPL-3.0 (see `LICENSE`). Bundles LibStub (public domain).
