# Changelog

## Unreleased

- /mom no longer overwrites a macro just because it has the same name. Its macros are now called `_mom` plus four random digits (`_mom4821`, never one that already exists), and it remembers which ones it made (account macros for the account, character macros per character). Only those are ever updated; every other macro is left alone. If one of yours is called `heal`, /mom says so and makes its own under a `_mom` name.
- Your old /mom macros (`heal`, `fort`, ...) are renamed to `_mom` names at login, in place, so they stay on your action bars. Only macros whose text is exactly what an older /mom wrote are renamed; a macro you changed keeps its name and is yours.
- The window shows each macro's name and state: ours and up to date, ours but changed by hand (Update puts ours back), missing (you deleted it; Create makes a new one), or not created. A macro of ours you renamed is still recognised.
- In combat, Create / Update waits and runs when combat ends (it says so) instead of failing.
- Bar addons show the macro name under the button, so those now read `_mom4821`. Bartender4: "Hide Macro Text" hides them.
- `/mom` opens a window with your class's macros: switch each one on or off, Create or Update it on its own, Pick it up to drop it on a bar, or "Create / update all" for the switched-on ones. It shows which macros exist and which were changed by hand. `/mom install` does what a bare `/mom` used to. New options: where new macros go (character macros first, as before, or account macros) and keeping the game's Auto Self Cast off (on, as before). Also under Settings > AddOns. Chat: `/mom create <macro>`, `/mom on|off <macro>`, `/mom list`, `/mom where account`, `/mom help`.
- Each macro's row shows its state first (not created, on your macros, changed), so it is never cut off; the full description is in the row's tooltip.
- Settings window: Escape closes an open dropdown list first, then the window; Escape in a text box puts the old text back; a number typed next to a slider snaps to the slider's steps; a Delete or Reset that asks for a second click no longer forgets it early.
