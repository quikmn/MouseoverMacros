-- EverlookDB Macros: the macro manager behind the /mom window.
--
-- Game macros: the client's own (120 account, MAX_CHARACTER_MACROS character slots, 255 characters
-- each; the client enforces those, /mom can't raise them). Any of them can be edited here, because
-- that is what a macro window is for: the ownership record only limits what /mom changes on its own.
--
-- Extended macros (up to 0.3.9: macros in our saved variables, run by a hidden button) are gone: at login each one
-- becomes a normal macro (ns.MigrateExt), its bar macro is turned into it in place, and what can't be one goes to the bin.
--
-- Backups: every save keeps the text it replaced (the last 10 per macro); deleted macros go to a
-- bin (the last 100). Export / import moves a set of macros as one line of text.
local _, ns = ...

local MAX_BODY = 255
local MAX_NAME = 16      -- the client's limit for a macro name
local HISTORY = 10
local BIN = 100   -- deleting goes on one click (Undo, Backups): room for a whole clean-up
ns.MAX_NAME = MAX_NAME

local function DB() return ns.db end
local function CDB() return ns.cdb end
local function Now() return time and time() or 0 end
local Trim = function(s) return ns.Trim(s) end

ns.MANAGER_DEFAULTS = {
    -- ext = { [id] = { name, icon, body } }: extended macros of 0.3.9 and earlier, until ns.MigrateExt turns them into macros
    extMoved = {},     -- [old extended id] = the macro it became: other characters' bar macros for it are turned into it too
    history = {},      -- ["a:" .. name] (account macros) = { { t, body, icon }, ... } newest first
    bin = {},          -- deleted macros: { { t, kind, scope, name, icon, body }, ... } newest first
}
ns.MANAGER_CHAR_DEFAULTS = {
    history = {},      -- [name] = { ... }: this character's character macros
}

------------------------------------------------------------------------
-- References: { kind = "game", scope, name, index, icon, body, ours, key }
------------------------------------------------------------------------
local function OwnerKey(name, scope)
    for _, r in ipairs(ns.Records()) do
        if r.rec.name == name and r.rec.scope == scope then return r.key end
    end
end

function ns.GameRef(index)
    local name, icon, body = GetMacroInfo(index)
    if not name then return nil end
    local scope = ns.ScopeOf(index)
    local key = OwnerKey(name, scope)
    return { kind = "game", scope = scope, name = name, index = index, icon = icon, body = body or "", ours = key ~= nil, key = key }
end

-- The same macro looked up again (indexes move when macros are added, removed or renamed).
function ns.Fresh(ref)
    if not ref then return nil end
    if ref.index and GetMacroInfo(ref.index) == ref.name and ns.ScopeOf(ref.index) == ref.scope then return ns.GameRef(ref.index) end
    local i = ns.EachMacro(ref.scope, function(_, n) return n == ref.name end)
    return i and ns.GameRef(i) or nil
end

-- Game macros of a scope ("account", "char", nil = both), or "mine" (what /mom made).
function ns.List(which)
    local out = {}
    local scope = (which == "account" or which == "char") and which or nil
    ns.EachMacro(scope, function(i) out[#out + 1] = ns.GameRef(i) end)
    if which == "mine" then
        local mine = {}
        for _, r in ipairs(out) do if r.ours then mine[#mine + 1] = r end end
        return mine
    end
    return out
end

-- What a macro casts, in words: the spell names of its /cast and /use lines ("Abolish Disease"). Shown next to the
-- _mom names, which say nothing by themselves.
function ns.WhatItDoes(body)
    local names, seen = {}, {}
    local function add(n)
        n = n and n:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^!", "")
        if n and n ~= "" and not n:match("^%d+$") and not seen[n] then seen[n] = true; names[#names + 1] = n end
    end
    for line in tostring(body or ""):gmatch("[^\n]+") do
        local cmd, rest = line:match("^%s*/(%a+)%s+(.*)$")
        cmd = cmd and cmd:lower()
        if cmd == "cast" or cmd == "use" or cmd == "castsequence" then
            for part in (rest .. ";"):gmatch("([^;]*);") do
                part = part:gsub("%b[]", ""):gsub("reset=%S+", "")
                for n in (part .. ","):gmatch("([^,]*),") do add(n) end
            end
        end
    end
    return table.concat(names, ", ")
end

function ns.Counts()
    local a, c = GetNumMacros()
    return a or 0, ns.MaxAccount(), c or 0, ns.MaxChar()
end

function ns.Limit() return MAX_BODY end

-- What a macro costs, in words.
function ns.Cost(ref)
    return ref.scope == "account" and "account macro - 1 of " .. ns.MaxAccount() .. " account slots" or "character macro - 1 of " .. ns.MaxChar() .. " character slots"
end

------------------------------------------------------------------------
-- Backups
------------------------------------------------------------------------
local function HistStore(ref)
    if ref.scope == "account" then return DB().history, "a:" .. ref.name end
    return CDB().history, ref.name
end

function ns.History(ref)
    if not ref then return {} end
    local store, key = HistStore(ref)
    return store[key] or {}
end

-- Keep `old` (the text being replaced) in the macro's history, newest first, at most 10.
function ns.PushHistory(ref, old, oldIcon)
    if not ref or old == nil then return end
    local store, key = HistStore(ref)
    local list = store[key] or {}
    if list[1] and list[1].body == old then return end
    table.insert(list, 1, { t = Now(), body = old, icon = oldIcon or ref.icon })
    while #list > HISTORY do table.remove(list) end
    store[key] = list
end

local function MoveHistory(fromRef, toRef)
    local fs, fk = HistStore(fromRef)
    local ts, tk = HistStore(toRef)
    if fs == ts and fk == tk then return end
    if fs[fk] then ts[tk] = fs[fk]; fs[fk] = nil end
end

-- A deleted macro goes to the bin; its earlier versions go with it (the bin keeps the last text), so
-- the history of deleted macros doesn't pile up in the saved variables.
local function ToBin(ref)
    table.insert(DB().bin, 1, { t = Now(), kind = ref.kind, scope = ref.scope, name = ref.name, icon = ref.icon, body = ref.body, key = ref.key })
    while #DB().bin > BIN do table.remove(DB().bin) end
    local store, key = HistStore(ref)
    store[key] = nil
end

------------------------------------------------------------------------
-- Game macros
------------------------------------------------------------------------
local function Room(scope)
    local a, maxA, c, maxC = ns.Counts()
    if scope == "account" then return a < maxA end
    return c < maxC
end
ns.Room = Room

local function CheckText(name, body, limit)
    if Trim(name) == "" then return "a macro needs a name" end
    if limit == MAX_BODY and #name > MAX_NAME then return "names are at most " .. MAX_NAME .. " characters" end
    if #body > limit then
        return ("too long: %d of %d characters"):format(#body, limit)
    end
end

ns.CheckText = CheckText

-- Macros can't be changed in combat: then it is queued (ns.Defer says so), returns true, "queued",
-- and says how it went when it runs after combat.
local function ExactlyNow(what, fn)
    local result, deferred
    deferred = ns.Defer(what, function()
        result = { fn() }
        if deferred then
            local ok, msg = result[1], tostring(result[2])
            ns.app:Print((ok and "" or "|cffff6060") .. "after combat: " .. msg:gsub("|", "||") .. (ok and "" or "|r"))
            ns.app:Refresh()
        end
    end)
    if deferred then return true, "queued" end
    return unpack(result)
end
ns.ExactlyNow = ExactlyNow

-- Save a game macro (anyone's: this is the player editing). Returns ok, message.
function ns.SaveGame(ref, name, icon, body)
    local err = CheckText(name, body, MAX_BODY)
    if err then return false, err end
    return ExactlyNow("saving " .. name, function()
        local cur = ns.Fresh(ref)
        if not cur then return false, ref.name .. " no longer exists" end
        if cur.body ~= body or (icon and cur.icon ~= icon) then ns.PushHistory(cur, cur.body, cur.icon) end
        EditMacro(cur.index, name, icon or cur.icon, body)
        if name ~= cur.name then
            MoveHistory(cur, { kind = "game", scope = cur.scope, name = name })
            if cur.key then
                local store = cur.scope == "char" and CDB().owned or DB().owned
                if store[cur.key] then store[cur.key].name = name end
            end
        end
        return true, "saved " .. name
    end)
end

-- Create a game macro in a scope. Returns ok, message.
function ns.CreateGame(scope, name, icon, body)
    local err = CheckText(name, body, MAX_BODY)
    if err then return false, err end
    return ExactlyNow("creating " .. name, function()
        if not Room(scope) then
            return false, scope == "account" and ("account macros are full (" .. ns.MaxAccount() .. ")")
                or ("character macros are full (" .. ns.MaxChar() .. "); account macros need no character slot")
        end
        if not CreateMacro(name, icon or ns.QUESTION_MARK, body, scope == "char") then return false, "the game refused to create " .. name end
        return true, "created " .. name
    end)
end

-- Delete a game macro (it goes to the bin). Ours: the record goes too.
function ns.DeleteGame(ref)
    return ExactlyNow("deleting " .. ref.name, function()
        local cur = ns.Fresh(ref)
        if not cur then return false, ref.name .. " no longer exists" end
        ToBin(cur)
        if cur.key then
            local store = cur.scope == "char" and CDB().owned or DB().owned
            store[cur.key] = nil
            -- deleted on purpose: Create / update all leaves it out from now on (Create on its row makes it again)
            if CDB().deleted then CDB().deleted[cur.key] = true end
        end
        DeleteMacro(cur.index)
        return true, "deleted " .. cur.name .. " (in the bin under Backups)"
    end)
end

-- Move a game macro to the other scope. It becomes a new macro there, so it must be put on the bars again.
function ns.MoveGame(ref, toScope)
    return ExactlyNow("moving " .. ref.name, function()
        local cur = ns.Fresh(ref)
        if not cur then return false, ref.name .. " no longer exists" end
        if cur.scope == toScope then return false, cur.name .. " is already there" end
        if not Room(toScope) then
            return false, "no room: " .. (toScope == "account" and "account" or "character") .. " macros are full"
        end
        if not CreateMacro(cur.name, cur.icon, cur.body, toScope == "char") then return false, "the game refused to create " .. cur.name end
        local to = { kind = "game", scope = toScope, name = cur.name }
        MoveHistory(cur, to)
        if cur.key then
            local from = cur.scope == "char" and CDB().owned or DB().owned
            from[cur.key] = nil
            ns.Record(cur.key, cur.name, toScope)
        end
        DeleteMacro(cur.index)
        return true, ("moved %s to %s macros (put it on your bars again)"):format(cur.name, toScope == "account" and "account" or "character")
    end)
end

------------------------------------------------------------------------
-- Key bindings: only the ring's key now (extended macros had keys of their own up to 0.3.9)
------------------------------------------------------------------------
local bindOwner
-- What a key does without /mom (the game's binding, or another addon's override), as the key binding list
-- names it ("Move and Steer"), or nil. Read while /mom's own overrides are cleared.
local function BoundTo(key)
    if not GetBindingAction or not key then return nil end
    local ok, action = pcall(GetBindingAction, key, true)
    if not ok or type(action) ~= "string" or action == "" then return nil end
    local text = _G["BINDING_NAME_" .. action]
    if type(text) ~= "string" or text == "" then
        local button = action:match("^CLICK ([^:]+)")
        text = button and ("a click on " .. button) or action
    end
    return text, action
end
ns.BoundTo = BoundTo

-- The ring's key takes over a key that already did something: say so once (per key and action, per character),
-- with how to change it. The Ring page shows it too (ns.ringReplaces).
local function TellRingClash(key)
    ns.ringReplaces = nil
    if not key then return end
    local text, action = BoundTo(key)
    if not text then return end
    ns.ringReplaces = text
    local cdb = CDB()
    cdb.ringTold = type(cdb.ringTold) == "table" and cdb.ringTold or {}
    local told = key .. "=" .. action
    if cdb.ringTold[told] then return end
    cdb.ringTold[told] = true
    local keyText = ns.Ring and ns.Ring.KeyText and ns.Ring.KeyText(key) or key
    if ns.app then
        ns.app:Print(("the ring now opens on %s, which did %s before. Pick another ring key on the Ring page "
            .. "(/mom ring key <key>), or /mom ring off gives the key back."):format(keyText, text))
    end
end

local function ApplyBindings()
    bindOwner = bindOwner or CreateFrame("Frame")
    ClearOverrideBindings(bindOwner)
    -- the ring's key: what it did before ours (read now, with /mom's overrides cleared)
    local ringKey, ringButton
    if ns.RingBinding then ringKey, ringButton = ns.RingBinding() end
    TellRingClash(ringKey)
    -- the ring's key (Ring.lua)
    if ringKey then SetOverrideBindingClick(bindOwner, false, ringKey, ringButton, "LeftButton") end
end
ns.ApplyBindings = ApplyBindings

------------------------------------------------------------------------
-- Extended macros of 0.3.9 and earlier become normal macros (at login, out of combat)
------------------------------------------------------------------------
-- A name for a macro in a scope: at most 16 characters, not taken there (a number added when it is).
local function FreeName(name, scope)
    name = Trim(tostring(name or "")):sub(1, MAX_NAME)
    if name == "" then name = "Macro" end
    local try, n = name, 1
    while ns.EachMacro(scope, function(_, x) return x == try end) do
        n = n + 1
        local suffix = " " .. n
        try = name:sub(1, MAX_NAME - #suffix) .. suffix
    end
    return try
end
ns.FreeName = FreeName

-- The ring's slices that held an extended macro hold the macro it became (or nothing, when it went to the bin).
local function RingSlices(moved)
    local ring = DB().ring
    if type(ring) ~= "table" or type(ring.top) ~= "table" then return end
    local function fix(slot)
        if type(slot) ~= "table" or slot.kind ~= "ext" then return slot end
        local m = moved[slot.id]
        return m and { kind = "macro", name = m.name } or false
    end
    for i, slot in pairs(ring.top) do
        ring.top[i] = fix(slot)
        if type(slot) == "table" and slot.kind == "ring" and type(slot.items) == "table" then
            local items = {}
            for _, it in ipairs(slot.items) do
                local f = fix(it)
                if f then items[#items + 1] = f end
            end
            slot.items = items
        end
    end
end

local function DropRecord(key) DB().owned[key], CDB().owned[key] = nil, nil end

-- Every extended macro becomes a normal macro: its bar macro ("/click MoMX_<id>") turned into it in place (the bar
-- buttons keep working), else a new one (an account slot first: extended macros were on every character, else a
-- character slot). Over 255 characters or no slot: it goes to the bin under Backups, named in chat. Their key
-- bindings go (one line says which); bar macros for them on other characters are turned into the macro at those
-- characters' logins.
function ns.MigrateExt()
    if InCombatLockdown() then
        ns.Defer("turning extended macros into normal macros", ns.MigrateExt)
        return
    end
    local db, cdb = DB(), CDB()
    if type(cdb.binds) == "table" and next(cdb.binds) then
        local keys = {}
        for _, k in pairs(cdb.binds) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        ns.app:Print("extended macros are now normal macros, so their key bindings on this character are gone: "
            .. table.concat(keys, ", ") .. ". Put the macros on your action bars and bind those.")
    end
    cdb.binds = nil
    db.extMoved = type(db.extMoved) == "table" and db.extMoved or {}
    local moved = db.extMoved
    -- the bar macros this character can see, by extended id
    local bars = {}
    ns.EachMacro(nil, function(i, _, body)
        local id = tostring(body or ""):match("/click MoMX_(%d+)")
        if id then bars[tonumber(id)] = bars[tonumber(id)] or {} ; table.insert(bars[tonumber(id)], i) end
    end)
    local made, binned = {}, {}
    local ext = type(db.ext) == "table" and db.ext or {}
    local ids = {}
    for id in pairs(ext) do ids[#ids + 1] = id end
    table.sort(ids)
    -- turn macros into others from the highest index down: deleting one moves the indexes after it
    local deletes = {}
    for _, id in ipairs(ids) do
        local x = ext[id]
        local body, icon = tostring(x.body or ""), x.icon or ns.QUESTION_MARK
        local bar = bars[id] and bars[id][1]
        local scope, name
        if #body <= MAX_BODY then
            if bar then
                scope = ns.ScopeOf(bar)
                local cur = GetMacroInfo(bar)
                name = cur == Trim(tostring(x.name or "")):sub(1, MAX_NAME) and cur or FreeName(x.name, scope)
                EditMacro(bar, name, icon, body)
                for k = 2, #bars[id] do deletes[#deletes + 1] = bars[id][k] end
            else
                for _, sc in ipairs({ "account", "char" }) do
                    if not scope and Room(sc) then
                        local n = FreeName(x.name, sc)
                        if CreateMacro(n, icon, body, sc == "char") then scope, name = sc, n end
                    end
                end
            end
        end
        DropRecord("x" .. id)
        if scope then
            moved[id] = { name = name, scope = scope, body = body, icon = icon }
            local h = db.history["x" .. id]
            if h then
                local store, key = HistStore({ kind = "game", scope = scope, name = name })
                store[key] = h
            end
            made[#made + 1] = name
        else
            table.insert(db.bin, 1, { t = Now(), kind = "game", scope = "account", name = tostring(x.name), icon = icon, body = body })
            while #db.bin > BIN do table.remove(db.bin) end
            for _, i in ipairs(bars[id] or {}) do deletes[#deletes + 1] = i end
            binned[#binned + 1] = tostring(x.name) .. (#body > MAX_BODY and (" (" .. #body .. " characters, a macro takes 255)") or " (no free macro slot)")
        end
        db.history["x" .. id] = nil
        bars[id] = nil
    end
    -- bar macros on this character for extended macros moved on another one: they become that macro too
    for id, list in pairs(bars) do
        local m = moved[id]
        for k, i in ipairs(list) do
            if m and k == 1 then
                local scope = ns.ScopeOf(i)
                local cur = GetMacroInfo(i)
                EditMacro(i, cur == m.name and cur or FreeName(m.name, scope), m.icon, m.body)
            else
                deletes[#deletes + 1] = i -- it clicked a button that no longer exists
            end
        end
        DropRecord("x" .. id)
    end
    table.sort(deletes, function(p, q) return p > q end)
    for _, i in ipairs(deletes) do DeleteMacro(i) end
    for k in pairs(db.history) do if type(k) == "string" and k:match("^x%d+$") then db.history[k] = nil end end
    db.ext, db.extNext = nil, nil
    RingSlices(moved)
    if #made > 0 then
        ns.app:Print(("extended macros are gone: %d became normal macros (%s). Your bar buttons for them keep working."):format(#made, table.concat(made, ", ")))
    end
    if #binned > 0 then
        ns.app:Print("|cffffb347not made into a macro, kept in the bin under Backups:|r " .. table.concat(binned, ", ") .. ".")
    end
    if (#made > 0 or #binned > 0) and ns.app.Refresh then ns.app:Refresh() end
    return made, binned
end

------------------------------------------------------------------------
-- Checking a macro's lines
------------------------------------------------------------------------
local CAST = { ["/cast"] = "spell", ["/use"] = "any", ["/castsequence"] = "seq", ["/castrandom"] = "seq", ["/userandom"] = "seq" }

local function SpellKnown(name)
    if C_Spell and C_Spell.GetSpellInfo then return C_Spell.GetSpellInfo(name) ~= nil end
    if GetSpellInfo then return GetSpellInfo(name) ~= nil end
    return true
end
local function ItemKnown(name)
    if C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(name) then return true end
    if C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(name) then return true end
    if GetItemInfo and GetItemInfo(name) then return true end
    return false
end

-- Problems per line: { { line = n, text = "..." }, ... }.
function ns.CheckLines(body, limit)
    local out = {}
    local n = 0
    for line in (tostring(body or "") .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        local cmd, rest = line:match("^%s*(/%a+)%s*(.*)$")
        local kind = cmd and CAST[cmd:lower()]
        if kind then
            for clause in (rest .. ";"):gmatch("([^;]*);") do
                local args = clause:gsub("%b[]", "")
                local names = {}
                if kind == "seq" then
                    args = args:gsub("reset=%S+", "")
                    for a in args:gmatch("[^,]+") do names[#names + 1] = a end
                else
                    names[1] = args
                end
                for _, a in ipairs(names) do
                    a = Trim((a:gsub("^%s*!", "")):gsub("^%s+", ""))
                    if a ~= "" and not a:match("^%d") and not a:match("^item:") then
                        if not SpellKnown(a) and not ItemKnown(a) then
                            out[#out + 1] = { line = n, text = ('"%s" is not a spell you know or an item the game has seen'):format(a) }
                        end
                    end
                end
            end
        elseif line:match("^%s*#show") and n > 1 then
            out[#out + 1] = { line = n, text = "#showtooltip only works on the first line" }
        end
    end
    if #tostring(body or "") > (limit or MAX_BODY) then
        out[#out + 1] = { line = 0, text = ("%d characters, the limit is %d"):format(#body, limit or MAX_BODY) }
    end
    return out
end

------------------------------------------------------------------------
-- Icons
------------------------------------------------------------------------
local iconCache
function ns.AllIcons()
    if iconCache then return iconCache end
    local list = {}
    if GetMacroIcons then GetMacroIcons(list) end
    if GetMacroItemIcons then GetMacroItemIcons(list) end
    iconCache = list
    return list
end

-- Icons matching a search: spells in your spellbook by name, icon file names or file IDs. "" = all.
function ns.SearchIcons(text)
    text = Trim(text or ""):lower()
    local out, seen = { ns.QUESTION_MARK }, { [ns.QUESTION_MARK] = true }
    local function add(icon) if icon and not seen[icon] then seen[icon] = true; out[#out + 1] = icon end end
    local SB = C_SpellBook
    if text ~= "" and SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemName and SB.GetSpellBookItemTexture and Enum and Enum.SpellBookSpellBank then
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            for i = 1, info and info.numSpellBookItems or 0 do
                local slot = info.itemIndexOffset + i
                local name = C_SpellBook.GetSpellBookItemName(slot, Enum.SpellBookSpellBank.Player)
                if name and name:lower():find(text, 1, true) then add(C_SpellBook.GetSpellBookItemTexture(slot, Enum.SpellBookSpellBank.Player)) end
            end
        end
    end
    for _, icon in ipairs(ns.AllIcons()) do
        if text == "" or tostring(icon):lower():find(text, 1, true) then add(icon) end
    end
    return out
end

------------------------------------------------------------------------
-- Export / import: "MOM1" then one entry per line: kind (a = account, c = character, x = extended),
-- icon, name and text, separated by spaces, percent-encoded.
------------------------------------------------------------------------
local function Enc(s) return (tostring(s):gsub("[%%%s|;,%c]", function(c) return ("%%%02X"):format(c:byte()) end)) end
local function Dec(s) return (tostring(s):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

function ns.Export(refs)
    local lines = { "MOM1" }
    for _, r in ipairs(refs) do
        local kind = r.scope == "account" and "a" or "c"
        lines[#lines + 1] = kind .. " " .. Enc(r.icon or ns.QUESTION_MARK) .. " " .. Enc(r.name) .. " " .. Enc(r.body)
    end
    return table.concat(lines, "\n")
end

-- Parse an export. Returns the entries { kind, icon, name, body } or nil, error.
function ns.ParseExport(text)
    text = tostring(text or ""):gsub("||", "|"):gsub("\r", "")
    local list, header = {}, false
    for line in text:gmatch("[^\n]+") do
        line = Trim(line:gsub("^%s+", ""))
        if line == "MOM1" then header = true
        elseif line ~= "" then
            local kind, icon, name, body = line:match("^([acx]) (%S+) (%S+) ?(%S*)$")
            if not kind then return nil, "this isn't a /mom export (a line doesn't read right)" end
            icon = Dec(icon)
            list[#list + 1] = { kind = kind, icon = tonumber(icon) or icon, name = Dec(name), body = Dec(body) }
        end
    end
    if not header then return nil, "this isn't a /mom export (it starts with MOM1)" end
    return list
end

-- Import entries: as they were (`as` nil), or all as "a" or "c". Never replaces a macro: a name already taken in that
-- scope gets " 2", " 3" ... (shortened to fit 16 characters). An older export's extended ones ("x") go where new macros
-- go (Options); one that is full goes to the other kind; text over 255 characters can't be a macro.
function ns.Import(list, as)
    if InCombatLockdown() then
        ns.Defer("importing macros", function() ns.app:Print(select(2, ns.Import(list, as))) end)
        return false, "queued"
    end
    local made, failed = 0, {}
    for _, e in ipairs(list) do
        local kind = as or e.kind
        local body = tostring(e.body or "")
        if #body > MAX_BODY then
            failed[#failed + 1] = e.name .. " (" .. #body .. " characters, a macro takes 255)"
        else
            local first = kind == "a" and "account" or kind == "c" and "char" or (ns.db.where == "account" and "account" or "char")
            local scope
            for _, sc in ipairs({ first, first == "account" and "char" or "account" }) do
                if not scope and Room(sc) then scope = sc end
            end
            local name, n = e.name:sub(1, MAX_NAME), 1
            while scope and ns.EachMacro(scope, function(_, x) return x == name end) do
                n = n + 1
                local suffix = " " .. n
                name = e.name:sub(1, MAX_NAME - #suffix) .. suffix
            end
            if scope and ns.CreateGame(scope, name, e.icon, body) then made = made + 1 else failed[#failed + 1] = e.name .. " (no free macro slot)" end
        end
    end
    return made > 0, ("imported %d macro%s%s"):format(made, made == 1 and "" or "s",
        #failed > 0 and (", not made: " .. table.concat(failed, ", ")) or "")
end

------------------------------------------------------------------------
-- The spellbook (the spell pickers) and the mouseover builder
------------------------------------------------------------------------
-- The spells this character can cast, by name: { name, icon, rank = highest "Rank N" or nil, id }, sorted.
function ns.SpellBook()
    local out, byName = {}, {}
    local SB = C_SpellBook
    if not (SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo) then return out end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local future = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
    for line = 1, SB.GetNumSpellBookSkillLines() or 0 do
        local li = SB.GetSpellBookSkillLineInfo(line)
        local off = li and li.itemIndexOffset or 0
        for i = 1, li and li.numSpellBookItems or 0 do
            local slot = off + i
            local info = SB.GetSpellBookItemInfo and SB.GetSpellBookItemInfo(slot, bank)
            local name = info and info.name or (SB.GetSpellBookItemName and SB.GetSpellBookItemName(slot, bank))
            if type(name) == "string" and name ~= "" and not (info and (info.isPassive or (future and info.itemType == future))) then
                local sub = info and info.subName
                if (type(sub) ~= "string" or sub == "") and info and info.spellID and C_Spell and C_Spell.GetSpellSubtext then
                    sub = C_Spell.GetSpellSubtext(info.spellID)
                end
                local rank = type(sub) == "string" and tonumber(sub:match("(%d+)")) or nil
                local icon = info and info.iconID or (SB.GetSpellBookItemTexture and SB.GetSpellBookItemTexture(slot, bank))
                local s = byName[name]
                if not s then
                    s = { name = name, icon = icon or ns.QUESTION_MARK, rank = rank, id = info and info.spellID }
                    byName[name] = s
                    out[#out + 1] = s
                elseif rank and (not s.rank or rank > s.rank) then
                    s.rank = rank
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- A spell for a macro line: "Flash Heal", or a set rank "Flash Heal(Rank 1)".
local function Ranked(spell, rank) return rank and (spell .. "(Rank " .. rank .. ")") or spell end
ns.Ranked = Ranked

-- A short name for a spell in a macro name: initials of a long one ("Devouring Plague" -> "DP"), a rank as "r1".
local function Short(spell, rank, whole)
    local words = {}
    for w in tostring(spell):gmatch("[%w']+") do words[#words + 1] = w end
    local s = spell
    if not whole and #words > 1 then
        s = ""
        for _, w in ipairs(words) do s = s .. w:sub(1, 1):upper() end
    end
    return s .. (rank and (" r" .. rank) or "")
end

-- The mouseover builder: o = { friend, friendRank, enemy, enemyRank, fallback (default on), stop, whisper }.
-- The friend under the mouse gets `friend`, the enemy under it `enemy`; with fallback, your target when the mouse
-- is over nobody. Never casts on you. Returns the text and a suggested name (at most 16 characters).
function ns.BuildMouseover(o)
    local f = o.friend and o.friend ~= "" and Ranked(o.friend, o.friendRank) or nil
    local e = o.enemy and o.enemy ~= "" and Ranked(o.enemy, o.enemyRank) or nil
    if not f and not e then return nil, nil end
    local fallback = o.fallback ~= false
    local cast
    if f and e then
        cast = "[@mouseover,help,nodead] " .. f .. "; [@mouseover,harm,nodead]" .. (fallback and "[harm,nodead]" or "") .. " " .. e
            .. (fallback and ("; [help,nodead] " .. f) or "")
    elseif f then
        cast = "[@mouseover,help,nodead]" .. (fallback and "[help,nodead]" or "") .. " " .. f
    else
        cast = "[@mouseover,harm,nodead]" .. (fallback and "[harm,nodead]" or "") .. " " .. e
    end
    local lines = { (f and e) and "#showtooltip" or ("#showtooltip " .. (f or e)) }
    if o.stop then lines[#lines + 1] = "/stopcasting" end
    local pi = o.friend == "Power Infusion" or o.enemy == "Power Infusion"
    if pi and o.whisper ~= false then lines[#lines + 1] = "/mom pi" end
    lines[#lines + 1] = "/cast " .. cast
    local name
    if f and e then
        name = Short(o.enemy, o.enemyRank) .. " / " .. Short(o.friend, o.friendRank, true)
        if #name > MAX_NAME then name = Short(o.enemy, o.enemyRank) .. " / " .. Short(o.friend, o.friendRank) end
    else
        name = Short(o.friend or o.enemy, f and o.friendRank or o.enemyRank, true)
        if #name > MAX_NAME then name = Short(o.friend or o.enemy, f and o.friendRank or o.enemyRank) end
    end
    return table.concat(lines, "\n"), name:sub(1, MAX_NAME)
end

-- Where a new macro goes: the chosen kind ("char" or "account"), else the other one; nil when both are full.
function ns.FreeScope(first)
    first = first == "account" and "account" or "char"
    for _, sc in ipairs({ first, first == "account" and "char" or "account" }) do
        if Room(sc) then return sc end
    end
end

------------------------------------------------------------------------
-- Templates (besides the class's mouseover set)
------------------------------------------------------------------------
ns.TEMPLATES = {
    { id = "trinkets", title = "Both trinkets", desc = "Uses both trinket slots.", body = "#showtooltip\n/use 13\n/use 14" },
    { id = "focusmo", title = "Focus mouseover", desc = "Focus whoever the mouse is over, else your target.", body = "/focus [@mouseover,exists][]" },
    { id = "skull", title = "Skull on mouseover", desc = "Puts a skull on the mouseover, else your target.", body = "/tm [@mouseover,exists][] 8" },
    { id = "attack", title = "Target and attack", desc = "Takes the nearest enemy if you have none (or it is dead) and starts attacking.", body = "/targetenemy [noharm][dead]\n/startattack" },
    { id = "assist", title = "Assist focus", desc = "Takes your focus's target.", body = "/assist focus" },
    { id = "ready", title = "Ready check", desc = "Starts a ready check.", body = "/readycheck" },
    { id = "wand", title = "Wand (mouseover)", desc = "Shoots your wand at the mouseover enemy, else your target; never stops a shot already going.", class = "PRIEST",
        body = "#showtooltip Shoot\n/cast [@mouseover,harm,nodead][harm,nodead] !Shoot" },
    { id = "ifheal", title = "Inner Focus + Greater Heal", desc = "Inner Focus, then Greater Heal on the mouseover friend, else your friendly target.", class = "PRIEST",
        body = "#showtooltip Greater Heal\n/cast Inner Focus\n/cast [@mouseover,help,nodead][help,nodead] Greater Heal" },
    -- one button, two jobs: the friend under the mouse gets the first spell, else the mouseover enemy or your target the second
    { id = "mbheal", title = "Mind Blast / Heal rank 1", desc = "Heal (rank 1) on the friend under the mouse; else Mind Blast on the mouseover enemy or your target.", class = "PRIEST",
        body = "#showtooltip\n/cast [@mouseover,help,nodead] Heal(Rank 1); [@mouseover,harm,nodead][harm,nodead] Mind Blast" },
    { id = "smfheal", title = "Smite / Flash Heal rank 1", desc = "Flash Heal (rank 1) on the friend under the mouse; else Smite on the mouseover enemy or your target.", class = "PRIEST",
        body = "#showtooltip\n/cast [@mouseover,help,nodead] Flash Heal(Rank 1); [@mouseover,harm,nodead][harm,nodead] Smite" },
    { id = "dppi", title = "Devouring Plague / Power Infusion", desc = "Power Infusion on the friend under the mouse; else Devouring Plague on the mouseover enemy or your target.", class = "PRIEST",
        body = "#showtooltip\n/mom pi\n/cast [@mouseover,help,nodead] Power Infusion; [@mouseover,harm,nodead][harm,nodead] Devouring Plague; [help,nodead] Power Infusion" },
    { id = "dpfheal", title = "Devouring Plague / Flash Heal rank 1", desc = "Flash Heal (rank 1) on the friend under the mouse, else your friendly target; else Devouring Plague on the mouseover enemy or your target.", class = "PRIEST",
        body = "#showtooltip\n/cast [@mouseover,help,nodead] Flash Heal(Rank 1); [@mouseover,harm,nodead][harm,nodead] Devouring Plague; [help,nodead] Flash Heal(Rank 1)" },
    { id = "pifun", title = "Power Infusion + a funny whisper", desc = "Power Infusion on the friend under the mouse, else your friendly target, and a funny whisper to them.", class = "PRIEST",
        body = "#showtooltip Power Infusion\n/mom pi\n/cast [@mouseover,help,nodead][help,nodead] Power Infusion" },
    { id = "swprenew", title = "Shadow Word: Pain / Renew", desc = "Renew on the friend under the mouse; else Shadow Word: Pain on the mouseover enemy or your target.", class = "PRIEST",
        body = "#showtooltip\n/cast [@mouseover,help,nodead] Renew; [@mouseover,harm,nodead][harm,nodead] Shadow Word: Pain" },
}

function ns.Templates()
    local out = {}
    for _, t in ipairs(ns.TEMPLATES) do
        if not t.class or t.class == ns.Class() then out[#out + 1] = t end
    end
    return out
end

-- Make a template as a _mom game macro (ours, key "t:<id>"), or update the one made before.
function ns.MakeTemplate(t)
    return ExactlyNow("making " .. t.title, function()
        local key = "t:" .. t.id
        local i, name = ns.Resolve(key)
        local body = t.body .. "\n#mom " .. key
        if i then
            local _, _, old = GetMacroInfo(i)
            if old and Trim(old) ~= Trim(body) then ns.PushHistory(ns.GameRef(i), old) end
            EditMacro(i, name, nil, body)
            return true, "updated " .. name
        end
        name = ns.NewName(key)
        local first = ns.db.where == "account" and "account" or "char"
        for _, scope in ipairs({ first, first == "account" and "char" or "account" }) do
            if Room(scope) and CreateMacro(name, ns.QUESTION_MARK, body, scope == "char") then
                ns.Record(key, name, scope)
                return true, ("made %s as %s"):format(t.title, name)
            end
        end
        return false, "no free macro slot: character and account macros are full. Delete one first."
    end)
end
