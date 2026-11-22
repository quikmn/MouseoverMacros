# Changelog

## Unreleased
- Priest: the Cure Disease macro casts Abolish Disease once you know it. One slot for both, and it's already on your bars.
- In combat, Pick up and dragging a macro open the game's own macro window to drag it from, with one short line in chat instead of a line per try.

## v0.3.8 (2026-11-22)
- Power Infusion whispers a funny line to whoever gets it (the friend under the mouse, else your friendly target). Once a minute per person at most, only when it's ready, never to yourself. In the Power Infusion macro, the Devouring Plague / Power Infusion template (now also on a friendly target) and a new "Power Infusion + a funny whisper" template. /mom pi does it from any macro.

## v0.3.7 (2026-11-22)
- Priest templates, one button for two jobs (the friend under the mouse, else the enemy): Mind Blast / Heal rank 1, Smite / Flash Heal rank 1, Devouring Plague / Power Infusion, Shadow Word: Pain / Renew.

## v0.3.6 (2026-11-22)
- Priest: lower ranks of Lesser Heal, Heal, Flash Heal and Greater Heal as their own mouseover macros ("Heal(Rank 2)"), for cheaper top-ups. Off by default; switch on the ones you use under Templates.

## v0.3.5 (2026-11-22)
- The Mine list shows what each macro casts, by spell name, next to its _mom name.

## v0.3.4 (2026-11-22)
- Resurrection macros (Resurrection, Redemption, Ancestral Spirit, Rebirth, Revive): with no corpse under the mouse or targeted, the spell's hand comes up so you can click a body on the ground.

## v0.3.3 (2026-11-21)
- Drag macros straight onto your action bars: drag any macro's row in the lists, or the big icon on the Edit page (a click on that icon picks it up too). Pick up still works.

## v0.3.2 (2026-11-21)
- Mages now get mouseover macros for Fireball, Frostbolt, Fire Blast, Arcane Missiles and the wand (Shoot) by default, next to Polymorph and Arcane Intellect. Each casts on the enemy under your mouse, else on your target. Characters set up before get them at the next login; switch any off in /mom.

## v0.3.1 (2026-11-21)
- The addon is now called EverlookDB Macros (was MouseoverMacros): it does more than mouseover macros. Settings, macros, /mom and the folder stay the same.
- /emacros opens the window too, like /ebar and /epets in the other EverlookDB addons.

## v0.3.0 (2026-11-21)
- Every class now has a mouseover set, not only priests: Warrior, Paladin, Hunter, Rogue, Shaman, Mage, Warlock and Druid, with the spells that make sense as a mouseover macro (heals, buffs, dispels and resurrections on a friend; DoTs, curses, interrupts, crowd control and taunts on an enemy; Holy Shock and Dispel Magic on either). Self-only spells, stances, forms, auras, totems and ground spells are left out. None of them ever falls back to casting on you.
- The first time you log in on a character, /mom makes the mouseover macros for the spells it knows and says so in one chat line. It uses character macro slots only, always leaves 3 free for your own, and names what didn't fit. Characters you had already set up are left as they were. Switch it off under Options ("Set up every character automatically").
- When you learn a new spell (at a trainer or from a talent), its mouseover macro is made too, with one chat line per batch. If you delete one of these macros, it is never made again. In combat it waits until the fight ends.
- Each macro uses the spell's name in your game's language and always casts your highest rank.
- New priest macros: Greater Heal, Power Infusion, Prayer of Mending, Contingency Plan, Silence, Vampiric Embrace, Starshards, Chastise and Shadowfiend. Also Holy Fire, Mind Flay, Mana Burn, Mind Control, Mind Vision and Hex of Weakness, which are off by default.
- Prayer of Fortitude, Prayer of Spirit and Prayer of Shadow Protection are now off by default, because WoW Forever made them raid-wide and the target is ignored. Macros you already have stay.
- The mouseover set shows which spells you haven't learned yet ("made when you learn it"). Create / update all skips those, and keeps any macro of ours that you changed by hand.

## v0.2.1 (2026-11-21)
- Shadow Word: Death first stops whatever you are casting or channeling (Mind Flay, a heal), then fires at the mouseover enemy, else your target. Run /mom install (or press Install) to update a Shadow Word: Death macro /mom already made.

## v0.2.0 (2026-11-20)
- Settings window: switches, buttons and sliders use a softer shade of the accent colour, an on switch has a dark knob so it stands out, and boxes have cleaner rounded edges.
- Rings also find items in your reagent bag (WoW Forever's extra bag slot).

- The ring no longer takes the middle mouse button silently: if that key (or the ring key you picked) already did something, /mom says once what it replaced, for example "Move and Steer", and how to pick another key (Ring page, `/mom ring key <key>`) or give it back (`/mom ring off`). The Ring page shows it too.
- "Set key" lets go of your keyboard the moment combat starts (it used to keep waiting for a key and swallow your keys in the fight); set the key again after combat. Pressing Escape in combat with unsaved changes no longer opens the Game Menu and the "unsaved changes" question at the same time: in combat Escape only opens the Game Menu.
- /mom no longer closes Blizzard's macro window. Macros in the game menu (with "Open MoM for /macro" on) and the "Open /mom" button in Blizzard's window now open /mom next to it; close each one when you like.
- "Pick up" is greyed out in combat (the game doesn't allow putting a macro on your cursor then, and it used to cause an "action blocked" error). Its tooltip says "after combat"; it works again as soon as combat ends.

## v0.1.0 (2026-11-19)

- Settings: an AI help button copies a description of every setting for an AI assistant, and `/mom apply` runs the commands it gives back.
- New priest macro: Abolish Disease (mouseover friend, else your friendly target).
- New priest macro: Mind Soothe (mouseover enemy, else your enemy target).

- Chat commands now follow one pattern across all EverlookDB addons: `/mom help` (or `?`) lists them; `get` and `set <setting> <value>`; `/mom off ring` or `/mom on takeover` switch a setting (`/mom on <macro>` and `/mom off <macro>` work as before); `search <words>`; `status` and `version`; `/mom reset ring` (and `/mom ring reset`) asks first; a mistyped command suggests the nearest one.
- The settings window has a search box at the top: type to find any setting.
- The ring: hold the middle mouse button (or any key you pick), flick the mouse toward a slice and let go. Right: Consumables (the best food, drink, healing and mana potion and bandage in your bags, picked by required level and item level, plus your buffs). Left: Professions. Down: Fishing (Fishing, your "Fishing" equipment set or best pole, lures on the pole). Up: Hearthstone. A sub-ring opens its own ring: click a slice or press the key again toward it; Escape, a right click or letting go in the middle closes it. Works in combat (secure buttons; its contents update after combat, used-up items show greyed). Edit it on the new Ring page (drag spells, items, macros, mounts or equipment sets onto a direction, sub-rings, dynamic slices like "Best food") or with /mom ring. "Ring on" off gives the key back.
- /macro opens /mom instead of Blizzard's macro window, on your account macros (character macros when you have no account ones). So does Macros in the game menu and in the chat menu (outside combat; in combat those open Blizzard's window as before). Blizzard's window is still one click away: "Blizzard's macro window" at the bottom of the sidebar, or /mom blizzard; inside it, "Open /mom" comes back. Switch it off with "Open MoM for /macro" under Options (/mom takeover off).
- Mine, when empty, says your own macros are under Account and Character.
- Editor: changes you haven't saved are never dropped silently. Picking another macro, New, another page, or closing the window (x, Escape, /mom) asks: Save, Discard or Cancel.
- Saving in combat: Save and Save as copy grey out and the editor says "Will save when combat ends". You can keep typing: the latest text is what gets saved, once (pressing Save again no longer makes a second macro). Afterwards the editor shows the saved macro and says "Saved after combat"; if it fails, it says why in red and your text stays.
- Set key: clicking it again while it waits cancels (it no longer asks again in chat), and the button reads "Press a key..." while it waits. Shift, Ctrl, Alt and the Windows key on their own are no longer taken as the key.
- The window's title reads "Mouseover Macros" (it was cut off as "MouseoverM..."). The icon button "? (follows the spell)" is now "Icon from the spell".
- Extended macros fire when you press their key, not when you let go. The one-line bar macro now clicks on the press too; bar macros made by earlier versions are updated at login (out of combat).
- Macro lists: an empty list says how to make the first one. A game macro that is too long says an extended macro takes up to 1023 characters.
- Character macros: /mom now counts the client's real limit (30 per character on this client; it read 18 before, so it said "full" too early and put macros in account slots).
- Editor: the quick-insert buttons are three rows of four, so none runs past the window's edge ("dead" is now "mouseover dead").
- Set key: closing the window or leaving the page cancels it, so a key pressed later (W to walk) is no longer bound by surprise. The window says while it waits for a key, and the reply says what the key did before ("instead of Move Forward").
- Delete in the editor: the editor starts a new macro of the same kind instead of keeping the deleted text under "New ...". A deleted macro's earlier versions go with it (the bin keeps its last text).
- Restore from the bin in combat: waits for combat to end, then restores and takes it out of the bin (it stayed in the bin before).
- Updating a template macro keeps the text it replaced under Earlier versions, like every other save.
- Backups: Import is the page's one highlighted button; Export is plain.
- New macro: the editor says when that kind's slots are all used, before you type it.
- Chat replies show macro names with a "|" as typed; a change made after combat says "after combat:" and shows failures in red.
- New macros: Shadow Word: Death, and the group buffs Prayer of Fortitude, Prayer of Spirit and Prayer of Shadow Protection (they show as not learned until you have them).

- A macro window: Mine, Account, Character, Extended, Templates, Edit, Backups and Options in the sidebar. Search, slot counters, and an editor for any macro (yours too: /mom only limits what it changes on its own) with an icon picker, a live character count, a check that spell and item names exist, quick inserts for conditionals, Save as copy, Move to account / character (when there is room), Delete (click twice) and Pick up.
- Extended macros: as many as you like, up to 1023 characters, no macro slot. Run one with a key binding (per character), or put it on a bar through a one-line _mom macro (one slot).
- Backups: every save keeps the last 10 versions of a macro; deleted macros go to a bin (last 20) and can be restored. Export a set of macros as text and import it again (on any character, as extended, character or account macros; nothing is replaced).
- Templates: besides the mouseover set, both trinkets, focus / skull on mouseover, target and attack, assist focus, ready check, and for priests a wand and Inner Focus + Greater Heal macro.
- /mom no longer overwrites a macro just because it has the same name. Its macros are now called `_mom` plus four random digits (`_mom4821`, never one that already exists), and it remembers which ones it made (account macros for the account, character macros per character). Only those are ever updated; every other macro is left alone. If one of yours is called `heal`, /mom says so and makes its own under a `_mom` name.
- Your old /mom macros (`heal`, `fort`, ...) are renamed to `_mom` names at login, in place, so they stay on your action bars. Only macros whose text is exactly what an older /mom wrote are renamed; a macro you changed keeps its name and is yours.
- The window shows each macro's name and state: ours and up to date, ours but changed by hand (Update puts ours back), missing (you deleted it; Create makes a new one), or not created. A macro of ours you renamed is still recognised.
- In combat, Create / Update waits and runs when combat ends (it says so) instead of failing.
- Bar addons show the macro name under the button, so those now read `_mom4821`. Bartender4: "Hide Macro Text" hides them.
- `/mom` opens a window with your class's macros: switch each one on or off, Create or Update it on its own, Pick it up to drop it on a bar, or "Create / update all" for the switched-on ones. It shows which macros exist and which were changed by hand. `/mom install` does what a bare `/mom` used to. New options: where new macros go (character macros first, as before, or account macros) and keeping the game's Auto Self Cast off (on, as before). Also under Settings > AddOns. Chat: `/mom create <macro>`, `/mom on|off <macro>`, `/mom list`, `/mom where account`, `/mom help`.
- Each macro's row shows its state first (not created, on your macros, changed), so it is never cut off; the full description is in the row's tooltip.
- Settings window: Escape closes an open dropdown list first, then the window; Escape in a text box puts the old text back; a number typed next to a slider snaps to the slider's steps; a Delete or Reset that asks for a second click no longer forgets it early.
