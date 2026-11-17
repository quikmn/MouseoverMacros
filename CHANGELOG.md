# Changelog

## Unreleased

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
