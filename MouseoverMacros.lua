-- MouseoverMacros: mouseover macros for your class (mouseover, then target; never yourself).
-- /mom opens the window: every macro with an on/off switch, Create / Update and Pick up buttons.
-- /mom install creates or updates all the switched-on ones at once (what a bare /mom used to do).
-- An existing macro with the same name (account or character) is edited in place, so anything
-- already on your action bars keeps working.
local ADDON, ns = ...
local UI = LibStub("EverlookUI-1")

local QUESTION_MARK = 134400 -- with #showtooltip the button shows the spell icon anyway

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
        { "poh",     "Prayer of Healing", "helpOrSelf" },
        { "curedis", "Cure Disease", "help" },
        { "dispel",  "Dispel Magic", "any" },
        { "penance", "Penance", "any" },  -- heals a friend, hurts an enemy: mouseover, else target; never you
        { "swp",     "Shadow Word: Pain", "harm" },
        { "smite",   "Smite", "harm" },
        { "mblast",  "Mind Blast", "harm" },
        { "dplague", "Devouring Plague", "harm" },
        { "shackle", "Shackle Undead", "harm" },
        { "rez",     "Resurrection", "res" },
    },
}

ns.DEFAULTS = {
    version = 1,
    off = {},               -- [macro name] = true: left out of "/mom install"
    autoSelfCastOff = true, -- keep the game's Auto Self Cast setting off
    where = "character",    -- new macros: "character" (account when full) or "account"
}

local db
local function Off(name) return db and db.off[name] and true or false end

function ns.Body(m) return ns.KINDS[m[3]].body(m[2]) end

local function Class()
    local _, class = UnitClass("player")
    return class
end

local function Trim(s) return (tostring(s or ""):gsub("%s+$", "")) end

-- This class's macros with what the game has: { name, spell, kind, body, desc, on, index, status, account }.
-- status: "missing", "ok" (the game's macro is ours), "differs" (edited by hand or an older version).
function ns.Entries()
    local out = {}
    for _, m in ipairs(ns.MACROS[Class()] or {}) do
        local e = { name = m[1], spell = m[2], kind = m[3], body = ns.Body(m), desc = ns.KINDS[m[3]].desc, on = not Off(m[1]) }
        local index = GetMacroIndexByName(e.name)
        if index and index > 0 then
            e.index = index
            e.account = index <= (MAX_ACCOUNT_MACROS or 120)
            local _, _, body = GetMacroInfo(index)
            e.status = Trim(body) == Trim(e.body) and "ok" or "differs"
        else
            e.status = "missing"
        end
        out[#out + 1] = e
    end
    return out
end

function ns.Find(name)
    name = tostring(name or ""):lower()
    for _, e in ipairs(ns.Entries()) do
        if e.name == name then return e end
    end
end

-- Create or update one macro. Returns "created", "updated", "full" or "combat".
function ns.Install(e)
    if InCombatLockdown() then return "combat" end
    local index = GetMacroIndexByName(e.name)
    if index and index > 0 then
        EditMacro(index, e.name, nil, e.body)
        return "updated"
    end
    local numAccount, numChar = GetNumMacros()
    local charRoom = numChar < (MAX_CHARACTER_MACROS or 18)
    local accountRoom = numAccount < (MAX_ACCOUNT_MACROS or 120)
    if db.where ~= "account" and charRoom and CreateMacro(e.name, QUESTION_MARK, e.body, true) then return "created" end
    -- account macros: chosen, or the character ones are full (far more room)
    if accountRoom and CreateMacro(e.name, QUESTION_MARK, e.body, false) then return "created" end
    if db.where == "account" and charRoom and CreateMacro(e.name, QUESTION_MARK, e.body, true) then return "created" end
    return "full"
end

------------------------------------------------------------------------
-- Window and chat
------------------------------------------------------------------------
local app = UI:NewApp({
    name = "MouseoverMacros",
    addon = ADDON,
    slash = "/mom",
    tagline = "Mouseover macros for your class: mouseover first, then your target, never yourself.",
    accent = { 0.25, 0.75, 1.0 },
    width = 640, height = 600,
    position = function() return db end,
})
ns.app = app

local function InstallOne(e)
    local r = ns.Install(e)
    if r == "combat" then
        app:Print("|cffff6060can't edit macros in combat.|r")
    elseif r == "full" then
        app:Print("|cffff6060no room for " .. e.name .. ":|r your character and account macros are full.")
    else
        app:Print(r .. " " .. e.name .. ". Drag it from the window (Pick up) or /macro to your bars.")
    end
    app:Refresh()
    return r
end

-- Create or update every switched-on macro (the old bare /mom).
function ns.InstallAll()
    if InCombatLockdown() then
        app:Print("|cffff6060can't edit macros in combat.|r")
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
            if r == "created" then created[#created + 1] = e.name
            elseif r == "updated" then updated[#updated + 1] = e.name
            else failed[#failed + 1] = e.name end
        end
    end
    app:Print(("created %d, updated %d%s%s. Drag them from /macro or this window to your bars."):format(
        #created, #updated,
        skipped > 0 and (", " .. skipped .. " switched off") or "",
        #failed > 0 and (", |cffff4040no room for: " .. table.concat(failed, ", ") .. "|r") or ""))
    app:Refresh()
    return created, updated, failed
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
        for _, x in ipairs(ns.Entries()) do names[#names + 1] = x.name end
        app:Print("|cffff6060no macro called '" .. UI.Util.Escape(name) .. "'.|r " ..
            (#names > 0 and ("Yours: " .. table.concat(names, ", ")) or "None for your class yet."))
        return
    end
    return e
end

app:Command("install", "install", "create or update every switched-on macro", function() ns.InstallAll() end, { "all" })
app:Command("create", "create <macro>", "create or update one macro", function(rest)
    local e = NamedEntry(rest, "create")
    if e then InstallOne(e) end
end, { "update" })
app:Command("on", "on <macro>", "include a macro in /mom install", function(rest)
    local e = NamedEntry(rest, "on")
    if e then db.off[e.name] = nil; app:Refresh(); app:Print(e.name .. ": on") end
end)
app:Command("off", "off <macro>", "leave a macro out of /mom install", function(rest)
    local e = NamedEntry(rest, "off")
    if e then db.off[e.name] = true; app:Refresh(); app:Print(e.name .. ": off") end
end)
app:Command("list", "list", "your class's macros in chat", function()
    local list = ns.Entries()
    if #list == 0 then app:Print("no macros for " .. tostring(Class()) .. " yet.") return end
    for _, e in ipairs(list) do
        DEFAULT_CHAT_FRAME:AddMessage(("  %s%s|r  %s - %s, %s"):format(e.on and "|cff40c0ff" or "|cff808080", e.name, e.spell, e.desc,
            e.status == "missing" and "not created" or e.status == "ok" and "up to date" or "changed, /mom create " .. e.name .. " puts ours back"))
    end
end)

local STATUS = {
    missing = "|cff8d94a3not created yet|r",
    ok = "|cff62cf88on your macros|r",
    differs = "|cffffb347changed - Update puts ours back|r",
}

local function SpellIcon(spell)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spell) or QUESTION_MARK end
    if GetSpellTexture then return GetSpellTexture(spell) or QUESTION_MARK end
    return QUESTION_MARK
end

app:Section("macros", "Macros", function(stack)
    UI.Header(stack, "Your macros", "Switched-on macros are made by \"Create / update all\". Each one can also be made on its own.")
    UI.ButtonRow(stack, {
        { label = "Create / update all", width = 180, style = "accent", onClick = function() ns.InstallAll() end,
            desc = "Every switched-on macro. Existing ones are edited in place, so your action bars keep working." },
        { label = "All on", width = 90, onClick = function() db.off = {}; app:Refresh() end },
        { label = "All off", width = 90, onClick = function()
            for _, e in ipairs(ns.Entries()) do db.off[e.name] = true end
            app:Refresh()
        end },
    })
    UI.List(stack, {
        items = ns.Entries,
        rowHeight = 40,
        empty = "No macros for your class yet (Priest so far).",
        toggle = { get = function(e) return e.on end, set = function(e, on) db.off[e.name] = (not on) or nil end },
        icon = function(e) return SpellIcon(e.spell) end,
        title = function(e) return e.name .. "  |cff8d94a3" .. e.spell .. "|r" end,
        -- the status first: the row is too narrow for both in full, and the tooltip has the rest
        detail = function(e) return STATUS[e.status] .. (e.index and (e.account and " (account)" or " (character)") or "") .. "  |cff8d94a3-  " .. e.desc .. "|r" end,
        tooltip = function(e)
            return { e.name .. " - " .. e.spell, e.desc, STATUS[e.status] .. (e.index and (e.account and " (account macro)" or " (character macro)") or ""), " ", (e.body:gsub("|", "||")) }
        end,
        buttons = {
            { label = function(e) return e.status == "missing" and "Create" or e.status == "differs" and "Update" or "Up to date" end,
                width = 90, onClick = function(e) InstallOne(e) end, usable = function(e) return e.status ~= "ok" end },
            { label = "Pick up", width = 74, onClick = function(e) if e.index and PickupMacro then PickupMacro(e.index) end end,
                shown = function(e) return e.index ~= nil end },
        },
    })
    UI.Header(stack, "Options")
    app:Widget(stack, "where")
    app:Widget(stack, "autoselfcast")
    UI.Note(stack, "Pick up puts the macro on your cursor: drop it on an action bar slot.")
end)

SLASH_MOUSEOVERMACROS1 = "/mom"
SlashCmdList.MOUSEOVERMACROS = function(msg) app:HandleSlash(msg) end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UPDATE_MACROS")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        MouseoverMacrosDB = UI.Util.FillDefaults(type(MouseoverMacrosDB) == "table" and MouseoverMacrosDB or {}, ns.DEFAULTS)
        db = MouseoverMacrosDB
        ns.db = db
    elseif event == "PLAYER_LOGIN" then
        -- The game's "Auto Self Cast" makes plain spell buttons fall back to you when you have
        -- no friendly target. Keep it off on every login (unless switched off in /mom).
        ApplySelfCast()
    elseif event == "UPDATE_MACROS" then
        app:Refresh()
    end
end)
