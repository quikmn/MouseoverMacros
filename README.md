# MouseoverMacros

WoW Forever (interface 16001). `/mom` opens a macro window: your class's mouseover set, every macro you have, extended macros past the slot limits, backups and export / import. `/mom help` lists the chat commands.

## The window

- **Mine**: what /mom made for you (`_mom` macros) and your extended macros.
- **Account** / **Character**: all your game macros, with search and slot counters ("Account 34/120, Character 30/30"). Click one to edit it. Your own macros can be edited here too; /mom never changes them by itself.
- **Extended**: macros stored by /mom instead of the game: as many as you like, up to 1023 characters each, on every character. Each one runs from a hidden button. Give it a key on a character (no slot), or "Put on a bar" makes a one-line `_mom` macro that clicks it (one slot).
- **Templates**: the mouseover set for your class (on/off switches, Create / update all) and a few common macros (both trinkets, focus or skull on mouseover, target and attack, assist focus, ready check; Priest: wand and Inner Focus + Greater Heal), made as a `_mom` macro or as an extended one.
- **Edit**: name, icon (picker with search; the "?" icon follows the spell), the text with a live count against its limit (255 or 1023), a check that every spell and item name exists, quick inserts for conditionals, Save, Save as copy, Pick up, Move to account / character, Delete (click twice). The last 10 versions of each macro are kept; Restore puts one back in the editor.
- **Backups**: the last 20 deleted macros (Restore), export of a set as text, import (as exported, or as extended, character or account macros; nothing is replaced).
- **Options**: where new macros go, keeping the game's Auto Self Cast off.

The game allows 120 account macros and a fixed number per character, 255 characters each. No addon can change that; extended macros are the way past it.

## Which macros /mom changes

Its macros are named `_mom` plus four random digits (for example `_mom4821`), never a name already in use, and /mom remembers which ones it made (account macros for the account, character macros per character). On its own it only ever updates those, in place, so your bars keep working; it never touches a macro of yours, even one with the same name. Old plain-named /mom macros (`heal`, `fort`, ...) are renamed to `_mom` names at login if their text is exactly what an older /mom wrote. Bar addons show the macro name under the button; Bartender4's "Hide Macro Text" hides it.

Macros can't be changed in combat: anything you ask for then waits and happens when combat ends.

## The mouseover set

- Friendly spells: mouseover, then friendly target. Never yourself.
- Hostile spells: mouseover, then target.
- Dispel Magic, Penance: mouseover, then target, friend or enemy.
- Turns off the game's Auto Self Cast setting on every login.

Classes covered so far: Priest.
