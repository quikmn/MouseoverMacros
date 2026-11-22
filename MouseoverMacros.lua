-- EverlookDB Macros: mouseover macros for your class (mouseover, then target; never yourself).
-- /mom opens the window: every macro with an on/off switch, Create / Update and Pick up buttons.
-- /mom install creates or updates all the switched-on ones at once.
--
-- Ownership: /mom names its macros "_mom" + 4 random digits (unique among all macro names) and
-- records each one (macro key -> { name, scope, created }): account macros in MouseoverMacrosDB,
-- character macros in MouseoverMacrosCharDB (per character). A macro is ours only when its name
-- is in that record and it still exists; /mom never edits, renames or deletes anything else.
-- Our macros also end in a "#mom <key>" line (a # line the game ignores; #showtooltip has to stay
-- first, so the marker goes last), so a macro of ours the player renamed is found again.
local ADDON, ns = ...
local UI = LibStub("EverlookUI-1")

local QUESTION_MARK = 134400 -- with #showtooltip the button shows the spell icon anyway
local MAX_BODY = 255         -- the client's limit for a macro's text
ns.QUESTION_MARK, ns.MAX_BODY = QUESTION_MARK, MAX_BODY

-- How each kind of macro picks its target. Never yourself, except HelpOrSelf (asked for by the owner).
ns.KINDS = {
    -- Friendly: whoever the mouse is over, else your friendly target. If neither exists the macro does nothing.
    help = { desc = "mouseover friend, else friendly target",
        body = function(spell) return "#showtooltip " .. spell .. "\n/cast [@mouseover,help,nodead][help,nodead] " .. spell end },
    -- Hostile: whoever the mouse is over, else your target.
    harm = { desc = "mouseover enemy, else target",
        body = function(spell) return "#showtooltip " .. spell .. "\n/cast [@mouseover,harm,nodead][harm,nodead] " .. spell end },
    -- Hostile, and it cuts off whatever you are casting or channeling (Mind Flay) first: for an instant finisher you
    -- weave in mid-cast (Shadow Word: Death). /stopcasting stops a channel as well as a cast.
    harmStop = { desc = "stops your cast or channel, then mouseover enemy, else target",
        body = function(spell) return "#showtooltip " .. spell .. "\n/stopcasting\n/cast [@mouseover,harm,nodead][harm,nodead] " .. spell end },
    -- Either side (Dispel Magic: cleanse a friend or purge an enemy): mouseover, else target.
    any = { desc = "mouseover friend or enemy, else target",
        body = function(spell) return "#showtooltip " .. spell .. "\n/cast [@mouseover,exists,nodead][exists,nodead] " .. spell end },
    -- Like help, but with nobody to cast on it goes on you (Prayer of Healing: heals the target's party,
    -- and with no one else that's your own).
    helpOrSelf = { desc = "mouseover friend, else friendly target, else you",
        body = function(spell) return "#showtooltip " .. spell .. "\n/cast [@mouseover,help,nodead][help,nodead][@player] " .. spell end },
    -- Res: mouseover corpse, else dead target, else the spell's hand cursor to click a body on the ground (someone
    -- who released leaves only their corpse there). Never yourself.
    res = { desc = "mouseover corpse, else dead target, else click a body on the ground",
        body = function(spell) return "#showtooltip " .. spell .. "\n/cast [@mouseover,help,dead][help,dead][] " .. spell end },
}

-- ns.MACROS (every class's set) and ns.EXCLUDED live in Classes.lua.

-- Every body a version of /mom before the _mom names wrote under the plain name (the key), taken from the
-- git history (two commits that never loaded, ffc7ee8 and 3ca1ad6, wrote nothing). A plain-named
-- macro is adopted only when its text is one of these; anything else under that name is the player's.
local function L(cond, spell) return "#showtooltip " .. spell .. "\n/cast " .. cond .. " " .. spell end
local H, X, A, S, R = "[@mouseover,help,nodead][help,nodead]", "[@mouseover,harm,nodead][harm,nodead]",
    "[@mouseover,exists,nodead][exists,nodead]", "[@mouseover,help,nodead][help,nodead][@player]", "[@mouseover,help,dead][help,dead]"
ns.LEGACY = {
    PRIEST = {
        renew = { L(H, "Renew") }, lheal = { L(H, "Lesser Heal") }, heal = { L(H, "Heal") },
        fheal = { L(H, "Flash Heal") }, dgrace = { L(H, "Divine Grace") }, shield = { L(H, "Power Word: Shield") },
        fort = { L(H, "Power Word: Fortitude") }, dspirit = { L(H, "Divine Spirit") }, fward = { L(H, "Fear Ward") },
        sprot = { L(H, "Shadow Protection") }, poh = { L(S, "Prayer of Healing") }, curedis = { L(H, "Cure Disease") },
        dispel = { L(H, "Dispel Magic"), L(A, "Dispel Magic") }, -- the first version had it friendly-only
        penance = { L(A, "Penance") }, swp = { L(X, "Shadow Word: Pain") }, smite = { L(X, "Smite") },
        mblast = { L(X, "Mind Blast") }, dplague = { L(X, "Devouring Plague") }, shackle = { L(X, "Shackle Undead") },
        rez = { L(R, "Resurrection"), L(R .. "[]", "Resurrection") },
    },
}

ns.DEFAULTS = {
    version = 2,
    off = {},               -- [macro key] = true (off) / false (on): the player's switch; nil: the set's default
    autoSetup = true,       -- make the class's set on a character's first login, and macros for spells learned later
    autoSelfCastOff = true, -- keep the game's Auto Self Cast setting off
    where = "character",    -- new macros: "character" (account when full) or "account"
    owned = {},             -- [macro key] = { name, scope = "account", created }: our account macros
    takeover = true,        -- /macro (and the game menu's Macros) open this window instead of Blizzard's
}
ns.CHAR_DEFAULTS = {
    owned = {},             -- [macro key] = { name, scope = "char", created, body }: this character's macros of ours
    made = {},              -- [macro key] = true: /mom made this macro on this character once (never made again on its own)
    -- auto: nil = first login not handled yet; true = set up by /mom automatically (new spells get macros);
    -- false = the player had set /mom up here already (left alone)
}

local db, cdb

-- The class's entry for a key (nil for keys of other classes and templates).
local function Def(key)
    local _, class = UnitClass("player")
    for _, m in ipairs(ns.MACROS[class] or {}) do if m[1] == key then return m end end
end
ns.Def = Def
-- Switched off: the player's choice, else the set's default (on unless the entry says on = false).
local function Off(key)
    if db and db.off[key] ~= nil then return db.off[key] and true or false end
    local m = Def(key)
    return m ~= nil and m.on == false
end
ns.Off = Off
function ns.SetOn(key, on) if db then db.off[key] = not on end end

-- The spell's name in the client's language (from its ID), else the English name in Classes.lua.
function ns.SpellName(m)
    local n
    if m.id then
        if C_Spell and C_Spell.GetSpellName then n = C_Spell.GetSpellName(m.id)
        elseif GetSpellInfo then n = GetSpellInfo(m.id) end
    end
    if type(n) ~= "string" or n == "" then n = m[2] end
    if m.rank then   -- a set rank: "Heal(Rank 2)", in the client's language when it says how it writes "Rank 2"
        local sub
        if C_Spell and C_Spell.GetSpellSubtext then sub = C_Spell.GetSpellSubtext(m.id)
        elseif GetSpellSubtext then sub = GetSpellSubtext(m.id) end
        if type(sub) ~= "string" or not sub:find("%d") then sub = "Rank " .. m.rank end
        n = n .. "(" .. sub .. ")"
    end
    return n
end

-- Does this character know the spell (any rank; a pet's spell in the pet's spellbook)?
local function Ask(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, r = pcall(fn, ...)
    return ok and r and true or false
end
function ns.Known(m)
    if not m.id then return true end
    local SB = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank[m.pet and "Pet" or "Player"]
    if SB and bank ~= nil and Ask(SB.IsSpellKnown, m.id, bank) then return true end
    if m.pet then
        if Ask(IsSpellKnown, m.id, true) then return true end
    elseif Ask(IsPlayerSpell, m.id) or Ask(IsSpellKnown, m.id) then
        return true
    end
    if m.rank then return false end   -- a set rank: that exact rank, never "any rank of the name"
    -- a higher rank under the same name (rank 1 dropped from the spellbook)
    if SB and SB.FindSpellBookSlotForSpell then
        local ok, slot = pcall(SB.FindSpellBookSlotForSpell, ns.SpellName(m), false, true, false, false)
        if ok and slot then return true end
    end
    return false
end

local function Marker(key) return "#mom " .. key end
-- Our text for a macro: the generated body plus the marker line when it fits in 255 characters.
function ns.Body(m)
    local body = ns.KINDS[m[3]].body(ns.SpellName(m))
    if m.pre then body = body:gsub("\n", "\n" .. m.pre .. "\n", 1) end   -- an extra line before the /cast
    local withMarker = body .. "\n" .. Marker(m[1])
    return #withMarker <= MAX_BODY and withMarker or body
end

local function Class()
    local _, class = UnitClass("player")
    return class
end
ns.Class = Class

local function Trim(s) return (tostring(s or ""):gsub("%s+$", "")) end
ns.Trim = Trim
local function HasMarker(body, key)
    for line in tostring(body or ""):gmatch("[^\n]+") do
        if Trim(line) == Marker(key) then return true end
    end
    return false
end

------------------------------------------------------------------------
-- The game's macros
------------------------------------------------------------------------
-- The client's limits: Constants.MacroConsts on this client (120 account, 30 per character); the old
-- globals only on clients that still have them.
local function MacroConst(key)
    local c = Constants and Constants.MacroConsts
    return c and tonumber(c[key]) or nil
end
local function MaxAccount() return MacroConst("MAX_ACCOUNT_MACROS") or MAX_ACCOUNT_MACROS or 120 end
local function MaxChar() return MacroConst("MAX_CHARACTER_MACROS") or MAX_CHARACTER_MACROS or 18 end
local function ScopeOf(index) return index <= MaxAccount() and "account" or "char" end
ns.MaxAccount, ns.MaxChar, ns.ScopeOf = MaxAccount, MaxChar, ScopeOf

-- Every macro in one scope (nil: both): calls fn(index, name, body); stops when fn returns true.
local function EachMacro(scope, fn)
    local numAccount, numChar = GetNumMacros()
    if scope ~= "char" then
        for i = 1, numAccount or 0 do
            local name, _, body = GetMacroInfo(i)
            if name and fn(i, name, body) then return i, name, body end
        end
    end
    if scope ~= "account" then
        for i = MaxAccount() + 1, MaxAccount() + (numChar or 0) do
            local name, _, body = GetMacroInfo(i)
            if name and fn(i, name, body) then return i, name, body end
        end
    end
end
ns.EachMacro = EachMacro

local function FindNamed(name, scope)
    return EachMacro(scope, function(_, n) return n == name end)
end

local function Records()
    local list = {}  -- { key, rec } for every record of ours this character can see
    if cdb then for key, rec in pairs(cdb.owned) do list[#list + 1] = { key = key, rec = rec } end end
    if db then for key, rec in pairs(db.owned) do list[#list + 1] = { key = key, rec = rec } end end
    return list
end

ns.Records = Records

-- True when `name` is a macro of ours (in that scope, if given).
function ns.IsOurs(name, scope)
    for _, r in ipairs(Records()) do
        if r.rec.name == name and (not scope or r.rec.scope == scope) then return true end
    end
    return false
end

-- A name no macro has (either scope, any case) and no record of ours uses. The name picked for a
-- key is kept for the session, so the window can say which name a new macro will get.
local planned = {}
function ns.NewName(key)
    local taken = {}
    EachMacro(nil, function(_, n) taken[n:lower()] = true end)
    for _, r in ipairs(Records()) do taken[r.rec.name:lower()] = true end
    for k, n in pairs(planned) do if k ~= key then taken[n:lower()] = true end end
    if ns.ExtraNames then for n in pairs(ns.ExtraNames()) do taken[n:lower()] = true end end
    if key and planned[key] and not taken[planned[key]:lower()] then return planned[key] end
    for _ = 1, 500 do
        local n = ("_mom%04d"):format(math.random(0, 9999))
        if not taken[n] then
            if key then planned[key] = n end
            return n
        end
    end
    for i = 0, 9999 do -- practically unreachable: 500 random tries all taken
        local n = ("_mom%04d"):format(i)
        if not taken[n] then if key then planned[key] = n end return n end
    end
end

local function Record(key, name, scope)
    local store = scope == "char" and cdb.owned or db.owned
    store[key] = { name = name, scope = scope, created = time and time() or 0 }
    -- one record per key for this character: a new one replaces a dead one in the other store
    local other = scope == "char" and db.owned or cdb.owned
    if other[key] and not FindNamed(other[key].name, other[key].scope) then other[key] = nil end
    planned[key] = nil
    return store[key]
end
ns.Record = Record

-- Our live macro for a key: index, name, body, record. Falls back to the marker line when the
-- player renamed it. Returns nil, record when we made one and it is gone.
function ns.Resolve(key)
    local dead
    for _, store in ipairs({ cdb and cdb.owned or {}, db and db.owned or {} }) do
        local rec = store[key]
        if rec then
            local i, name, body = FindNamed(rec.name, rec.scope)
            if i then return i, name, body, rec end
            -- renamed by the player? the marker line finds it (unless that name is another record's)
            i, name, body = EachMacro(rec.scope, function(_, n, b) return HasMarker(b, key) and not ns.IsOurs(n) end)
            if i then rec.name = name; return i, name, body, rec end
            dead = dead or rec
        end
    end
    if not dead and db and cdb then
        -- no record at all (saved variables lost, macros kept by the server): a _momNNNN name AND
        -- our marker for this key, both, before we call it ours again
        local i, name, body = EachMacro(nil, function(_, n, b) return n:match("^_mom%d%d%d%d$") and HasMarker(b, key) and not ns.IsOurs(n) end)
        if i then return i, name, body, Record(key, name, ScopeOf(i)) end
    end
    return nil, dead
end

-- An old /mom macro still under its plain name, with its text exactly as an older /mom wrote it.
local function Legacy(key)
    local bodies = (ns.LEGACY[Class()] or {})[key]
    if not bodies then return end
    return EachMacro(nil, function(_, n, b)
        if n ~= key then return false end
        for _, want in ipairs(bodies) do
            if Trim(b) == want then return true end -- only trailing whitespace is ignored
        end
        return false
    end)
end
ns.Legacy = Legacy

-- Rename an old /mom macro in place (it stays on the action bars) and record it.
local function Adopt(e, index)
    local name = ns.NewName(e.key)
    local scope = ScopeOf(index)
    EditMacro(index, name, nil, e.body)
    Record(e.key, name, scope).body = e.body
    if cdb then cdb.made[e.key] = true end
    return name
end

------------------------------------------------------------------------
-- Entries
------------------------------------------------------------------------
-- This class's macros with what the game has:
-- { key, spell, kind, body, desc, on, macro (our name, or the one a new one gets), index, account, status, clash }
-- known: the character has the spell; why: the set's reason; default: on by default.
-- status: "ok" (ours, up to date), "stale" (ours, as an older /mom wrote it: never changed by hand, Update
-- brings it up to date), "differs" (ours, changed by hand), "missing" (we made it, it's gone),
-- "legacy" (an old /mom macro under the plain name; renamed on the next change), "new" (never made).
-- clash: the player has a macro of their own called like the key (never touched).
function ns.Entries()
    local out = {}
    for _, m in ipairs(ns.MACROS[Class()] or {}) do
        local e = { key = m[1], spell = ns.SpellName(m), kind = m[3], body = ns.Body(m), desc = ns.KINDS[m[3]].desc,
            on = not Off(m[1]), known = ns.Known(m), why = m.why, default = m.on ~= false, pet = m.pet }
        local index, name, body, rec = ns.Resolve(e.key)
        if index then
            e.index, e.macro, e.account = index, name, rec.scope == "account"
            if Trim(body) == Trim(e.body) then e.status = "ok"
            elseif (rec.body and Trim(body) == Trim(rec.body)) or ns.OurOldText(m, body) then e.status = "stale"
            else e.status = "differs" end
        else
            local li = Legacy(e.key)
            if li then
                e.status, e.index, e.account = "legacy", li, ScopeOf(li) == "account"
            else
                e.status = name and "missing" or "new"
                e.clash = FindNamed(e.key) ~= nil
            end
            e.macro = ns.NewName(e.key)
        end
        out[#out + 1] = e
    end
    return out
end

-- True when `body` is text some /mom version generated for this spell (any kind, with or without the marker):
-- ours and never changed by hand, so updating it loses nothing of the player's.
function ns.OurOldText(m, body)
    body = Trim(body)
    local names = { ns.SpellName(m), m[2] }
    for _, spell in ipairs(names) do
        for _, kind in pairs(ns.KINDS) do
            local b = kind.body(spell)
            if body == b or body == b .. "\n" .. Marker(m[1]) then return true end
        end
    end
    for _, b in ipairs((ns.LEGACY[Class()] or {})[m[1]] or {}) do if body == b then return true end end
    return false
end

function ns.Find(key)
    key = tostring(key or ""):lower()
    for _, e in ipairs(ns.Entries()) do
        if e.key == key or (e.macro and e.macro:lower() == key) then return e end
    end
end

-- Create or update one macro. Returns "created"|"updated"|"adopted" and the macro's name, or "full"|"combat".
function ns.Install(e)
    if InCombatLockdown() then return "combat" end
    local index, name = ns.Resolve(e.key)
    if index then
        local _, _, old = GetMacroInfo(index)
        if Trim(old) ~= Trim(e.body) and ns.PushHistory then ns.PushHistory(ns.GameRef(index), old) end
        EditMacro(index, name, nil, e.body)
        local _, _, _, rec = ns.Resolve(e.key)
        if rec then rec.body = e.body end
        return "updated", name
    end
    local li = Legacy(e.key)
    if li then return "adopted", Adopt(e, li) end
    local new = ns.NewName(e.key)
    local numAccount, numChar = GetNumMacros()
    local charRoom = numChar < MaxChar()
    local accountRoom = numAccount < MaxAccount()
    local function make(perChar)
        if not CreateMacro(new, QUESTION_MARK, e.body, perChar) then return false end
        Record(e.key, new, perChar and "char" or "account").body = e.body
        cdb.made[e.key] = true
        return true
    end
    if db.where ~= "account" and charRoom and make(true) then return "created", new end
    -- account macros: chosen, or the character ones are full (far more room)
    if accountRoom and make(false) then return "created", new end
    if db.where == "account" and charRoom and make(true) then return "created", new end
    return "full"
end

-- Adopt every old /mom macro still under its plain name. Returns the names, "old -> new".
function ns.Migrate()
    local done = {}
    if InCombatLockdown() or not db or not cdb then return done end
    for _, m in ipairs(ns.MACROS[Class()] or {}) do
        if not ns.Resolve(m[1]) then
            local li = Legacy(m[1])
            if li then done[#done + 1] = m[1] .. " -> " .. Adopt({ key = m[1], body = ns.Body(m) }, li) end
        end
    end
    return done
end

------------------------------------------------------------------------
-- Combat queue: macros can't be changed in combat; the request runs when combat ends.
------------------------------------------------------------------------
local queue = { keys = {}, all = false, migrate = false, jobs = {}, auto = nil }
ns.queue = queue

------------------------------------------------------------------------
-- Window and chat
------------------------------------------------------------------------
local app = UI:NewApp({
    name = "EverlookDB Macros", -- two words: the sidebar wraps it instead of cutting it off
    frameName = "MouseoverMacros",
    addon = ADDON,
    slash = "/mom",
    aliases = { "/emacros" }, -- the EverlookDB family's /e<name> (like /ebar, /epets)
    tagline = "Your macros: mouseover sets, extended macros past the slot limits, backups.",
    accent = { 0.25, 0.75, 1.0 },
    width = 860, height = 640,
    position = function() return db end,
    buttons = {
        { label = "Blizzard's macro window", onClick = function() ns.OpenBlizzard() end,
            desc = "Opens the game's own macro window, also while /macro opens this one." },
    },
})
ns.app = app

local function Queued(what)
    app:Print("|cffffb347in combat:|r macros can't be changed now. " .. what .. " will happen when combat ends.")
end

-- Run fn now, or (in combat) after combat. Returns true when it had to wait.
function ns.Defer(what, fn)
    if InCombatLockdown() then
        queue.jobs[#queue.jobs + 1] = fn
        Queued(what)
        return true
    end
    fn()
end

local function InstallOne(e)
    if InCombatLockdown() then
        queue.keys[e.key] = true
        Queued(e.key)
        return "combat"
    end
    local r, name = ns.Install(e)
    if r == "full" then
        app:Print("|cffff6060no room for " .. e.key .. ":|r your character (" .. MaxChar() .. ") and account (" .. MaxAccount() .. ") macros are all used.")
    elseif r == "adopted" then
        app:Print("renamed your old /mom macro " .. e.key .. " to " .. name .. " (same macro, still on your bars).")
    else
        app:Print(r .. " " .. e.key .. " as " .. name .. ". Drag it from the window (Pick up) or /macro to your bars.")
    end
    app:Refresh()
    return r
end

-- Create or update every switched-on macro of a spell you know. Macros of ours you changed by hand are kept
-- (Update on the macro's own row puts ours back); spells you haven't learned get theirs when you learn them.
function ns.InstallAll()
    if InCombatLockdown() then
        queue.all = true
        Queued("Create / update all")
        return
    end
    local class = Class()
    if not ns.MACROS[class] then
        app:Print("no macros defined for " .. tostring(class) .. " yet.")
        return
    end
    local created, updated, failed, kept, skipped, later = {}, {}, {}, {}, 0, 0
    for _, e in ipairs(ns.Entries()) do
        if not e.on then
            skipped = skipped + 1
        elseif e.status == "differs" then
            kept[#kept + 1] = e.key
        elseif not e.known and not e.index then
            later = later + 1
        else
            local r = ns.Install(e)
            if r == "created" then created[#created + 1] = e.key
            elseif r == "updated" or r == "adopted" then updated[#updated + 1] = e.key
            else failed[#failed + 1] = e.key end
        end
    end
    app:Print(("created %d, updated %d%s%s%s%s. Drag them from /macro or this window to your bars."):format(
        #created, #updated,
        skipped > 0 and (", " .. skipped .. " switched off") or "",
        later > 0 and (", " .. later .. " for spells you haven't learned yet (made when you learn them)") or "",
        #kept > 0 and (", kept " .. #kept .. " you changed by hand (" .. table.concat(kept, ", ") .. "; Update on its row puts ours back)") or "",
        #failed > 0 and (", |cffff4040no room (character and account macros full) for: " .. table.concat(failed, ", ") .. "|r") or ""))
    app:Refresh()
    return created, updated, failed, kept
end

------------------------------------------------------------------------
-- Automatic set-up: the class's set on a character's first login, and a macro for each spell learned later.
-- Only character macros (account macros show on every character, and a Paladin's set doesn't belong on your
-- Mage), always leaving AUTO_RESERVE character slots free for your own. Only macros never made on this
-- character before: one you deleted is never made again on its own. Nothing of yours is changed.
------------------------------------------------------------------------
local AUTO_RESERVE = 3
ns.AUTO_RESERVE = AUTO_RESERVE

local function FreeCharSlots()
    local _, numChar = GetNumMacros()
    return MaxChar() - (numChar or 0)
end
ns.FreeCharSlots = FreeCharSlots

-- Was /mom set up on this character before (by hand, or by a version before automatic set-up)?
local function SetUpBefore()
    if next(cdb.owned) then return true end
    for _, m in ipairs(ns.MACROS[Class()] or {}) do
        if ns.Resolve(m[1]) or Legacy(m[1]) then return true end
    end
    return false
end

-- The macros automatic set-up would make now.
function ns.AutoCandidates()
    local out = {}
    for _, e in ipairs(ns.Entries()) do
        if e.on and e.known and e.status == "new" and not cdb.made[e.key] then out[#out + 1] = e end
    end
    return out
end

local function Names(list, max)
    local t = {}
    for i, e in ipairs(list) do
        if i > max then t[#t + 1] = "and " .. (#list - max) .. " more" break end
        t[#t + 1] = e.spell
    end
    return table.concat(t, ", ")
end

-- first: the first-login run (makes the whole set); else a batch of newly learned spells.
-- Says what it did in one chat line. Returns the entries made and the ones that didn't fit.
function ns.AutoSetup(first)
    if not db or not cdb or db.autoSetup == false or not ns.MACROS[Class()] then return end
    if first then
        if cdb.auto ~= nil then return end
    elseif cdb.auto ~= true then
        return
    end
    if InCombatLockdown() then
        queue.auto = queue.auto or (first and "first" or "learned")
        return
    end
    if first then
        if SetUpBefore() then cdb.auto = false return end
        cdb.auto = true
    end
    local made, left = {}, {}
    for _, e in ipairs(ns.AutoCandidates()) do
        local name = FreeCharSlots() > AUTO_RESERVE and ns.NewName(e.key)
        if name and CreateMacro(name, QUESTION_MARK, e.body, true) then
            Record(e.key, name, "char").body = e.body
            cdb.made[e.key] = true
            e.macro = name
            made[#made + 1] = e
        else
            left[#left + 1] = e
        end
    end
    local _, numChar = GetNumMacros()
    local full = #left > 0 and (" |cffffb347%d didn't fit|r (%d of %d character macros used; /mom keeps %d free for yours): %s. "
        .. "Make them as account macros in /mom."):format(#left, numChar or 0, MaxChar(), AUTO_RESERVE, Names(left, 6)) or ""
    if first and (#made > 0 or #left > 0) then
        local className = UnitClass("player")
        app:Print(("made %d mouseover macro%s for your %s; /mom to change.%s"):format(#made, #made == 1 and "" or "s", tostring(className), full))
    elseif not first and #made == 1 then
        app:Print(("made a mouseover macro for %s (%s); /mom to change.%s"):format(made[1].spell, made[1].macro, full))
    elseif not first and #made > 1 then
        app:Print(("made %d mouseover macros for new spells: %s; /mom to change.%s"):format(#made, Names(made, 6), full))
    elseif #left > 0 and not ns.toldFull then
        ns.toldFull = true -- once per session: a full character list stays full
        app:Print(("no room for a mouseover macro for %s."):format(Names(left, 6)) .. full)
    end
    if #made > 0 then app:Refresh() end
    return made, left
end

-- New spells come in bursts (a trainer visit, a level-up): one run, one chat line, a moment after the last.
local learnPending = false
function ns.SpellsChanged()
    if not cdb or cdb.auto ~= true or learnPending then return end
    learnPending = true
    local function run() learnPending = false; ns.AutoSetup(false) end
    if C_Timer and C_Timer.After then C_Timer.After(2, run) else run() end
end

app:Setting({
    key = "autosetup", type = "bool", label = "Set up every character automatically",
    desc = "On a character's first login, make the mouseover macros for the spells it knows (character macros, keeping "
        .. AUTO_RESERVE .. " free), and one for each spell it learns later. Never touches a macro of yours and never makes one again that you deleted. For all characters.",
    keywords = { "auto", "first login", "new spells", "learned" },
    get = function() return db.autoSetup ~= false end, set = function(v) db.autoSetup = v end,
})

local function RunMigration()
    if InCombatLockdown() then queue.migrate = true return end
    local done = ns.Migrate()
    if #done > 0 then
        app:Print(("renamed %d old /mom macro%s to _mom names (same macros, still on your bars): %s"):format(
            #done, #done == 1 and "" or "s", table.concat(done, ", ")))
        app:Refresh()
    end
end
ns.RunMigration = RunMigration

local function RunQueue()
    local jobs = queue.jobs
    queue.jobs = {}
    for _, fn in ipairs(jobs) do fn() end
    if queue.migrate then queue.migrate = false; RunMigration() end
    if queue.auto then
        local first = queue.auto == "first"
        queue.auto = nil
        ns.AutoSetup(first)
    end
    if queue.all then
        queue.all = false
        wipe(queue.keys)
        ns.InstallAll()
    end
    for key in pairs(queue.keys) do
        queue.keys[key] = nil
        local e = ns.Find(key)
        if e then InstallOne(e) end
    end
end

local function ApplySelfCast()
    if not db or not db.autoSelfCastOff then return end
    if C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("autoSelfCast") then
        C_CVar.SetCVar("autoSelfCast", "0")
    elseif GetCVar and GetCVar("autoSelfCast") then
        SetCVar("autoSelfCast", "0")
    end
end
ns.ApplySelfCast = ApplySelfCast

app:Setting({
    key = "autoselfcast", type = "bool", label = "Keep the game's Auto Self Cast off",
    desc = "With Auto Self Cast on, plain spell buttons fall back to you when you have no friendly target. This turns it off on every login. Switching this off leaves the game's setting as it is.",
    get = function() return db.autoSelfCastOff end, set = function(v) db.autoSelfCastOff = v end, after = ApplySelfCast,
})
app:Setting({
    key = "takeover", type = "bool", label = "Open /mom for /macro", chatLabel = "Open /mom for /macro",
    desc = "/macro, and Macros in the game menu and the chat menu, open this window instead of Blizzard's. "
        .. "Blizzard's own window stays one click away: the button at the bottom left, or /mom blizzard.",
    get = function() return db.takeover end, set = function(v) db.takeover = v end,
})
app:Setting({
    key = "where", type = "choice", label = "Where new macros go", width = 300,
    choices = {
        { value = "character", text = "Character macros (account when full)" },
        { value = "account", text = "Account macros (all your characters)" },
    },
    desc = "Only for macros that don't exist yet; existing ones are updated where they are.",
    get = function() return db.where end, set = function(v) db.where = v end,
})

local function NamedEntry(rest, verb)
    local name = rest:match("^%s*(%S+)")
    if not name then
        app:Print("|cffff6060which macro?|r Example: /mom " .. verb .. " renew")
        return
    end
    local e = ns.Find(name)
    if not e then
        local names = {}
        for _, x in ipairs(ns.Entries()) do names[#names + 1] = x.key end
        app:Print("|cffff6060no macro called '" .. UI.Util.Escape(name) .. "'.|r " ..
            (#names > 0 and ("Yours: " .. table.concat(names, ", ")) or "None for your class yet."))
        return
    end
    return e
end

local STATUS = {
    new = "|cff8d94a3not created yet|r",
    missing = "|cffff8a8amissing - you deleted it; Create makes a new one|r",
    legacy = "|cffffd27fold /mom macro - renamed to a _mom name on the next change|r",
    ok = "|cff62cf88ours, up to date|r",
    stale = "|cffffd27fours, older text - Update brings it up to date|r",
    differs = "|cffffb347ours, changed by hand - Update restores it|r",
}
local PLAIN = {
    new = "not created", missing = "missing (deleted), create makes a new one", legacy = "old /mom macro, renamed on the next change",
    ok = "ours, up to date", stale = "ours, older text; /mom install updates it", differs = "ours, changed by hand; /mom create %s restores it",
}
ns.STATUS = STATUS

local function Where(e)
    if not e.index then return "" end
    return e.account and " (account)" or " (character)"
end
local function ClashNote(e)
    if not e.clash then return nil end
    return "a macro of yours is called " .. e.key .. "; ours will be made as " .. e.macro .. " (yours is never touched)"
end
ns.ClashNote = ClashNote

app:Command("install", "install", "create or update every switched-on macro", function() ns.InstallAll() end, { "all" })
app:Command("create", "create <macro>", "create or update one macro", function(rest)
    local e = NamedEntry(rest, "create")
    if e then InstallOne(e) end
end, { "update" })
-- "/mom on <macro>" and "/mom off <macro>"; with a setting's name instead ("/mom off ring", "/mom on takeover") they
-- switch that setting, as in every EverlookDB addon.
local function SettingInstead(rest, verb)
    local word = rest:match("^%s*(%S+)")
    if word and not ns.Find(word) and app:GetSetting(word) then UI.Verbs[verb](app, UI.Util.Trim(rest), verb) return true end
end
app:Command("on", "on <macro>", "include a macro in /mom install", function(rest)
    if SettingInstead(rest, "on") then return end
    local e = NamedEntry(rest, "on")
    if e then db.off[e.key] = false; app:Refresh(); app:Print(e.key .. ": on") end
end)
app:Command("off", "off <macro>", "leave a macro out of /mom install", function(rest)
    if SettingInstead(rest, "off") then return end
    local e = NamedEntry(rest, "off")
    if e then db.off[e.key] = true; app:Refresh(); app:Print(e.key .. ": off") end
end)
app:Command("list", "list", "your class's macros in chat", function()
    local list = ns.Entries()
    if #list == 0 then app:Print("no macros for " .. tostring(Class()) .. " yet.") return end
    for _, e in ipairs(list) do
        local state = PLAIN[e.status]:format(e.key)
        if e.clash then state = state .. "; " .. ClashNote(e) end
        DEFAULT_CHAT_FRAME:AddMessage(("  %s%s|r %s  %s - %s, %s"):format(e.on and "|cff40c0ff" or "|cff808080", e.key,
            e.macro, e.spell, e.desc, state))
    end
end)

local function SpellIcon(spell)
    spell = type(spell) == "string" and spell:gsub("%(.-%)$", "") or spell   -- "Heal(Rank 2)": the spell's icon
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spell) or QUESTION_MARK end
    if GetSpellTexture then return GetSpellTexture(spell) or QUESTION_MARK end
    return QUESTION_MARK
end
ns.SpellIcon = SpellIcon

ns.InstallOne = InstallOne
ns.Where = Where

app:RegisterSlash("MOUSEOVERMACROS") -- /mom, /emacros

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("UPDATE_MACROS")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("SPELLS_CHANGED")
-- a newly learned spell: this client's event, and the older name on clients that still have it
for _, ev in ipairs({ "LEARNED_SPELL_IN_SKILL_LINE", "LEARNED_SPELL_IN_TAB" }) do pcall(f.RegisterEvent, f, ev) end
local migrated
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        MouseoverMacrosDB = UI.Util.FillDefaults(type(MouseoverMacrosDB) == "table" and MouseoverMacrosDB or {}, ns.DEFAULTS)
        MouseoverMacrosCharDB = UI.Util.FillDefaults(type(MouseoverMacrosCharDB) == "table" and MouseoverMacrosCharDB or {}, ns.CHAR_DEFAULTS)
        db, cdb = MouseoverMacrosDB, MouseoverMacrosCharDB
        ns.db, ns.cdb = db, cdb
        if ns.OnLoad then ns.OnLoad(db, cdb) end
    elseif event == "PLAYER_LOGIN" then
        -- The game's "Auto Self Cast" makes plain spell buttons fall back to you when you have
        -- no friendly target. Keep it off on every login (unless switched off in /mom).
        ApplySelfCast()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- macros are loaded by now: adopt old plain-named /mom macros once per session
        if not migrated then
            migrated = true
            RunMigration()
            -- the first login on this character: its set, a moment later (the spellbook is complete by then)
            if C_Timer and C_Timer.After then C_Timer.After(1, function() ns.AutoSetup(true) end) else ns.AutoSetup(true) end
        end
        if ns.OnWorld then ns.OnWorld() end
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "LEARNED_SPELL_IN_TAB" then
        ns.SpellsChanged()
    elseif event == "UPDATE_MACROS" then
        app:Refresh()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if ns.OnCombatStart then ns.OnCombatStart() end
        app:Refresh() -- Pick up buttons grey out
    elseif event == "PLAYER_REGEN_ENABLED" then
        RunQueue()
        if ns.OnCombatEnd then ns.OnCombatEnd() end
        app:Refresh()
    end
end)
