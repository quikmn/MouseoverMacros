-- MouseoverMacros: mouseover macros for your class (mouseover, then target; never yourself).
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
    -- Either side (Dispel Magic: cleanse a friend or purge an enemy): mouseover, else target.
    any = { desc = "mouseover friend or enemy, else target",
        body = function(spell) return "#showtooltip " .. spell .. "\n/cast [@mouseover,exists,nodead][exists,nodead] " .. spell end },
    -- Like help, but with nobody to cast on it goes on you (Prayer of Healing: heals the target's party,
    -- and with no one else that's your own).
    helpOrSelf = { desc = "mouseover friend, else friendly target, else you",
        body = function(spell) return "#showtooltip " .. spell .. "\n/cast [@mouseover,help,nodead][help,nodead][@player] " .. spell end },
    -- Res: mouseover corpse, else dead target.
    res = { desc = "mouseover corpse, else dead target",
        body = function(spell) return "#showtooltip " .. spell .. "\n/cast [@mouseover,help,dead][help,dead] " .. spell end },
}

ns.MACROS = {
    PRIEST = {
        { "renew",   "Renew", "help" },
        { "lheal",   "Lesser Heal", "help" },
        { "heal",    "Heal", "help" },
        { "fheal",   "Flash Heal", "help" },
        { "dgrace",  "Divine Grace", "help" },
        { "shield",  "Power Word: Shield", "help" },
        { "fort",    "Power Word: Fortitude", "help" },
        { "dspirit", "Divine Spirit", "help" },
        { "fward",   "Fear Ward", "help" },
        { "sprot",   "Shadow Protection", "help" },
        -- group buffs: cast on a friend, they buff that friend's whole party (never you by default)
        { "pfort",   "Prayer of Fortitude", "help" },
        { "pspirit", "Prayer of Spirit", "help" },
        { "psprot",  "Prayer of Shadow Protection", "help" },
        { "poh",     "Prayer of Healing", "helpOrSelf" },
        { "curedis", "Cure Disease", "help" },
        { "dispel",  "Dispel Magic", "any" },
        { "penance", "Penance", "any" },  -- heals a friend, hurts an enemy: mouseover, else target; never you
        { "swp",     "Shadow Word: Pain", "harm" },
        { "smite",   "Smite", "harm" },
        { "mblast",  "Mind Blast", "harm" },
        { "swd",     "Shadow Word: Death", "harm" },
        { "dplague", "Devouring Plague", "harm" },
        { "shackle", "Shackle Undead", "harm" },
        { "rez",     "Resurrection", "res" },
    },
}

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
        rez = { L(R, "Resurrection") },
    },
}

ns.DEFAULTS = {
    version = 2,
    off = {},               -- [macro key] = true: left out of "/mom install"
    autoSelfCastOff = true, -- keep the game's Auto Self Cast setting off
    where = "character",    -- new macros: "character" (account when full) or "account"
    owned = {},             -- [macro key] = { name, scope = "account", created }: our account macros
}
ns.CHAR_DEFAULTS = {
    owned = {},             -- [macro key] = { name, scope = "char", created }: this character's macros of ours
}

local db, cdb
local function Off(key) return db and db.off[key] and true or false end

local function Marker(key) return "#mom " .. key end
-- Our text for a macro: the generated body plus the marker line when it fits in 255 characters.
function ns.Body(m)
    local body = ns.KINDS[m[3]].body(m[2])
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
    Record(e.key, name, scope)
    return name
end

------------------------------------------------------------------------
-- Entries
------------------------------------------------------------------------
-- This class's macros with what the game has:
-- { key, spell, kind, body, desc, on, macro (our name, or the one a new one gets), index, account, status, clash }
-- status: "ok" (ours, up to date), "differs" (ours, changed by hand), "missing" (we made it, it's gone),
-- "legacy" (an old /mom macro under the plain name; renamed on the next change), "new" (never made).
-- clash: the player has a macro of their own called like the key (never touched).
function ns.Entries()
    local out = {}
    for _, m in ipairs(ns.MACROS[Class()] or {}) do
        local e = { key = m[1], spell = m[2], kind = m[3], body = ns.Body(m), desc = ns.KINDS[m[3]].desc, on = not Off(m[1]) }
        local index, name, body, rec = ns.Resolve(e.key)
        if index then
            e.index, e.macro, e.account = index, name, rec.scope == "account"
            e.status = Trim(body) == Trim(e.body) and "ok" or "differs"
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
        Record(e.key, new, perChar and "char" or "account")
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
local queue = { keys = {}, all = false, migrate = false, jobs = {} }
ns.queue = queue

------------------------------------------------------------------------
-- Window and chat
------------------------------------------------------------------------
local app = UI:NewApp({
    name = "MouseoverMacros",
    addon = ADDON,
    slash = "/mom",
    tagline = "Your macros: mouseover sets, extended macros past the slot limits, backups.",
    accent = { 0.25, 0.75, 1.0 },
    width = 860, height = 640,
    position = function() return db end,
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

-- Create or update every switched-on macro.
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
    local created, updated, failed, skipped = {}, {}, {}, 0
    for _, e in ipairs(ns.Entries()) do
        if not e.on then
            skipped = skipped + 1
        else
            local r = ns.Install(e)
            if r == "created" then created[#created + 1] = e.key
            elseif r == "updated" or r == "adopted" then updated[#updated + 1] = e.key
            else failed[#failed + 1] = e.key end
        end
    end
    app:Print(("created %d, updated %d%s%s. Drag them from /macro or this window to your bars."):format(
        #created, #updated,
        skipped > 0 and (", " .. skipped .. " switched off") or "",
        #failed > 0 and (", |cffff4040no room (character and account macros full) for: " .. table.concat(failed, ", ") .. "|r") or ""))
    app:Refresh()
    return created, updated, failed
end

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
    differs = "|cffffb347ours, changed by hand - Update restores it|r",
}
local PLAIN = {
    new = "not created", missing = "missing (deleted), create makes a new one", legacy = "old /mom macro, renamed on the next change",
    ok = "ours, up to date", differs = "ours, changed by hand; /mom create %s restores it",
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
app:Command("on", "on <macro>", "include a macro in /mom install", function(rest)
    local e = NamedEntry(rest, "on")
    if e then db.off[e.key] = nil; app:Refresh(); app:Print(e.key .. ": on") end
end)
app:Command("off", "off <macro>", "leave a macro out of /mom install", function(rest)
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
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spell) or QUESTION_MARK end
    if GetSpellTexture then return GetSpellTexture(spell) or QUESTION_MARK end
    return QUESTION_MARK
end
ns.SpellIcon = SpellIcon

ns.InstallOne = InstallOne
ns.Where = Where

SLASH_MOUSEOVERMACROS1 = "/mom"
SlashCmdList.MOUSEOVERMACROS = function(msg) app:HandleSlash(msg) end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("UPDATE_MACROS")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
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
        if not migrated then migrated = true; RunMigration() end
        if ns.OnWorld then ns.OnWorld() end
    elseif event == "UPDATE_MACROS" then
        app:Refresh()
    elseif event == "PLAYER_REGEN_ENABLED" then
        RunQueue()
        if ns.OnCombatEnd then ns.OnCombatEnd() end
    end
end)
