-- MouseoverMacros: the macro manager behind the /mom window.
--
-- Game macros: the client's own (120 account, MAX_CHARACTER_MACROS character slots, 255 characters
-- each; the client enforces those, /mom can't raise them). Any of them can be edited here, because
-- that is what a macro window is for: the ownership record only limits what /mom changes on its own.
--
-- Extended macros: stored in our saved variables, as many as you like, up to 1023 characters each.
-- Each one is a hidden secure button (MoMX_<id>) that runs the text as a macro. They cost no slot;
-- you run one with a key binding (per character), or put it on an action bar through a one-line
-- "/click MoMX_<id>" macro, which takes one game slot.
--
-- Backups: every save keeps the text it replaced (the last 10 per macro); deleted macros go to a
-- bin (the last 20). Export / import moves a set of macros as one line of text.
local _, ns = ...

local MAX_BODY = 255
local MAX_EXT = 1023     -- macrotext on a secure button
local MAX_NAME = 16      -- the client's limit for a macro name
local HISTORY = 10
local BIN = 20
ns.MAX_EXT, ns.MAX_NAME = MAX_EXT, MAX_NAME

local function DB() return ns.db end
local function CDB() return ns.cdb end
local function Now() return time and time() or 0 end
local Trim = function(s) return ns.Trim(s) end

ns.MANAGER_DEFAULTS = {
    ext = {},          -- [id] = { name, icon, body, created }: extended macros (every character)
    extNext = 1,
    history = {},      -- ["a:" .. name] (account macros), ["x" .. id] (extended) = { { t, body, icon }, ... } newest first
    bin = {},          -- deleted macros: { { t, kind, scope, name, icon, body }, ... } newest first
}
ns.MANAGER_CHAR_DEFAULTS = {
    binds = {},        -- [extended id] = key: this character's key bindings for extended macros
    history = {},      -- [name] = { ... }: this character's character macros
}

------------------------------------------------------------------------
-- References: { kind = "game", scope, name, index, icon, body, ours, key } or { kind = "ext", id, name, icon, body }
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

function ns.ExtRef(id)
    local x = DB().ext[id]
    if not x then return nil end
    return { kind = "ext", id = id, name = x.name, icon = x.icon, body = x.body or "" }
end

-- The same macro looked up again (indexes move when macros are added, removed or renamed).
function ns.Fresh(ref)
    if not ref then return nil end
    if ref.kind == "ext" then return ns.ExtRef(ref.id) end
    if ref.index and GetMacroInfo(ref.index) == ref.name and ns.ScopeOf(ref.index) == ref.scope then return ns.GameRef(ref.index) end
    local i = ns.EachMacro(ref.scope, function(_, n) return n == ref.name end)
    return i and ns.GameRef(i) or nil
end

-- Game macros of a scope ("account", "char", nil = both), extended ones, or "mine" (what /mom made).
function ns.List(which)
    local out = {}
    if which == "ext" then
        local ids = {}
        for id in pairs(DB().ext) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do out[#out + 1] = ns.ExtRef(id) end
        return out
    end
    local scope = (which == "account" or which == "char") and which or nil
    ns.EachMacro(scope, function(i) out[#out + 1] = ns.GameRef(i) end)
    if which == "mine" then
        local mine = {}
        for _, r in ipairs(out) do if r.ours then mine[#mine + 1] = r end end
        for _, r in ipairs(ns.List("ext")) do mine[#mine + 1] = r end
        return mine
    end
    return out
end

function ns.Counts()
    local a, c = GetNumMacros()
    local n = 0
    for _ in pairs(DB().ext) do n = n + 1 end
    return a or 0, ns.MaxAccount(), c or 0, ns.MaxChar(), n
end

function ns.Limit(ref) return ref and ref.kind == "ext" and MAX_EXT or MAX_BODY end

-- What a macro costs, in words.
function ns.Cost(ref)
    if ref.kind == "ext" then
        local bar = ns.ExtBarMacro(ref.id)
        return "extended - no slot" .. (bar and ("; on bars via " .. bar.name .. " (1 " .. (bar.scope == "account" and "account" or "character") .. " slot)") or "")
    end
    return ref.scope == "account" and "account macro - 1 of " .. ns.MaxAccount() .. " account slots" or "character macro - 1 of " .. ns.MaxChar() .. " character slots"
end

------------------------------------------------------------------------
-- Backups
------------------------------------------------------------------------
local function HistStore(ref)
    if ref.kind == "ext" then return DB().history, "x" .. ref.id end
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

local function ToBin(ref)
    table.insert(DB().bin, 1, { t = Now(), kind = ref.kind, scope = ref.scope, name = ref.name, icon = ref.icon, body = ref.body })
    while #DB().bin > BIN do table.remove(DB().bin) end
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
    if #body > limit then return ("too long: %d of %d characters"):format(#body, limit) end
end

-- Macros can't be changed in combat: then it is queued (ns.Defer says so), returns true, "queued",
-- and says how it went when it runs after combat.
local function ExactlyNow(what, fn)
    local result, deferred
    deferred = ns.Defer(what, function()
        result = { fn() }
        if deferred then
            ns.app:Print(tostring(result[2]))
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
                or ("character macros are full (" .. ns.MaxChar() .. "); account macros or an extended macro need no character slot")
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
-- Extended macros
------------------------------------------------------------------------
local bindOwner
local function Button(id)
    local name = "MoMX_" .. id
    local b = _G[name]
    if not b then
        b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
        b:Hide()
        -- down and up both reach the button; with useOnKeyDown false it acts once, on release,
        -- for a key binding and for "/click MoMX_n" alike
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("useOnKeyDown", false)
        b:SetAttribute("type", "macro")
    end
    return b
end
ns.ExtButton = Button

local function ApplyBindings()
    bindOwner = bindOwner or CreateFrame("Frame")
    ClearOverrideBindings(bindOwner)
    for id, key in pairs(CDB().binds) do
        if DB().ext[id] then SetOverrideBindingClick(bindOwner, false, key, "MoMX_" .. id, "LeftButton")
        else CDB().binds[id] = nil end
    end
end

-- Every extended macro's button and this character's key bindings (out of combat).
function ns.SyncExt()
    if InCombatLockdown() then
        ns.Defer("setting up extended macros", ns.SyncExt)
        return
    end
    for id, x in pairs(DB().ext) do Button(id):SetAttribute("macrotext", x.body) end
    ApplyBindings()
end

function ns.ExtBarMacro(id)
    local i, name = ns.Resolve("x" .. id)
    if i then return { index = i, name = name, scope = ns.ScopeOf(i) } end
end

local function BarBody(id, body)
    local tip = tostring(body or ""):match("^(#showtooltip[^\n]*)")
    return (tip and tip .. "\n" or "") .. "/click MoMX_" .. id .. "\n#mom x" .. id
end

function ns.CreateExt(name, icon, body)
    local err = CheckText(name, body, MAX_EXT)
    if err then return false, err end
    return ExactlyNow("creating " .. name, function()
        local id = DB().extNext
        DB().extNext = id + 1
        DB().ext[id] = { name = name, icon = icon or ns.QUESTION_MARK, body = body, created = Now() }
        Button(id):SetAttribute("macrotext", body)
        return true, "created extended macro " .. name, id
    end)
end

function ns.SaveExt(ref, name, icon, body)
    local err = CheckText(name, body, MAX_EXT)
    if err then return false, err end
    return ExactlyNow("saving " .. name, function()
        local x = DB().ext[ref.id]
        if not x then return false, "that extended macro no longer exists" end
        if x.body ~= body or (icon and x.icon ~= icon) then ns.PushHistory(ns.ExtRef(ref.id), x.body, x.icon) end
        x.name, x.icon, x.body = name, icon or x.icon, body
        Button(ref.id):SetAttribute("macrotext", body)
        local bar = ns.ExtBarMacro(ref.id)
        if bar then EditMacro(bar.index, bar.name, x.icon, BarBody(ref.id, body)) end
        return true, "saved " .. name
    end)
end

function ns.DeleteExt(ref)
    return ExactlyNow("deleting " .. ref.name, function()
        local x = DB().ext[ref.id]
        if not x then return false, "that extended macro no longer exists" end
        ToBin(ns.ExtRef(ref.id))
        local bar = ns.ExtBarMacro(ref.id)
        if bar then DeleteMacro(bar.index) end
        DB().owned["x" .. ref.id], CDB().owned["x" .. ref.id] = nil, nil
        DB().ext[ref.id] = nil
        CDB().binds[ref.id] = nil
        Button(ref.id):SetAttribute("macrotext", nil)
        ApplyBindings()
        return true, "deleted " .. x.name .. " (in the bin under Backups)"
    end)
end

-- A key for an extended macro on this character (nil clears it). Overrides the key's normal
-- binding while set; the game's own key binding set is not changed.
function ns.BindExt(ref, key)
    return ExactlyNow("binding " .. ref.name, function()
        if not DB().ext[ref.id] then return false, "that extended macro no longer exists" end
        if key then
            for id, k in pairs(CDB().binds) do if k == key then CDB().binds[id] = nil end end
        end
        CDB().binds[ref.id] = key
        ApplyBindings()
        return true, key and (ref.name .. " runs on " .. key) or (ref.name .. ": key cleared")
    end)
end

-- A one-line game macro that clicks the extended macro's button, to drag to a bar. Uses one slot.
function ns.ExtToBar(ref)
    return ExactlyNow("making a bar macro for " .. ref.name, function()
        local x = DB().ext[ref.id]
        if not x then return false, "that extended macro no longer exists" end
        local bar = ns.ExtBarMacro(ref.id)
        if bar then return true, "already on " .. bar.name, bar.index end
        local name = ns.NewName("x" .. ref.id)
        local body = BarBody(ref.id, x.body)
        local first = ns.db.where == "account" and "account" or "char"
        local second = first == "account" and "char" or "account"
        for _, scope in ipairs({ first, second }) do
            if Room(scope) and CreateMacro(name, x.icon or ns.QUESTION_MARK, body, scope == "char") then
                ns.Record("x" .. ref.id, name, scope)
                local i = ns.Resolve("x" .. ref.id)
                return true, ("made %s (one %s slot): drag it to a bar"):format(name, scope == "account" and "account" or "character"), i
            end
        end
        return false, "no room: character and account macros are full. A key binding needs no slot."
    end)
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
        local kind = r.kind == "ext" and "x" or (r.scope == "account" and "a" or "c")
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

-- Import entries: as they were (`as` nil), or all as "x" (extended), "a" or "c". Never replaces a macro:
-- a name already taken in that scope gets " 2", " 3" ... (shortened to fit 16 characters).
function ns.Import(list, as)
    if InCombatLockdown() then
        ns.Defer("importing macros", function() ns.app:Print(select(2, ns.Import(list, as))) end)
        return false, "queued"
    end
    local made, failed = 0, {}
    for _, e in ipairs(list) do
        local kind = as or e.kind
        local body = e.body
        if kind ~= "x" and #body > MAX_BODY then kind = "x" end -- too long for a game macro
        if kind == "x" then
            if ns.CreateExt(e.name, e.icon, body) then made = made + 1 else failed[#failed + 1] = e.name end
        else
            local scope = kind == "a" and "account" or "char"
            local name, n = e.name:sub(1, MAX_NAME), 1
            while ns.EachMacro(scope, function(_, x) return x == name end) do
                n = n + 1
                local suffix = " " .. n
                name = e.name:sub(1, MAX_NAME - #suffix) .. suffix
            end
            if ns.CreateGame(scope, name, e.icon, body) then made = made + 1 else failed[#failed + 1] = e.name end
        end
    end
    return made > 0, ("imported %d macro%s%s"):format(made, made == 1 and "" or "s",
        #failed > 0 and (", no room for: " .. table.concat(failed, ", ")) or "")
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
}

function ns.Templates()
    local out = {}
    for _, t in ipairs(ns.TEMPLATES) do
        if not t.class or t.class == ns.Class() then out[#out + 1] = t end
    end
    return out
end

-- Make a template as a _mom game macro (ours, key "t:<id>") or an extended macro.
function ns.MakeTemplate(t, asExt)
    if asExt then return ns.CreateExt(t.title, ns.QUESTION_MARK, t.body) end
    return ExactlyNow("making " .. t.title, function()
        local key = "t:" .. t.id
        local i, name = ns.Resolve(key)
        local body = t.body .. "\n#mom " .. key
        if i then
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
        return false, "no room: character and account macros are full. Make it as an extended macro instead."
    end)
end
