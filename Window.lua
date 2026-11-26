-- EverlookDB Macros: the /mom window, built around three jobs:
--   Macros: every macro (account and character together) on the left, the editor for the one you picked on the
--     right; drag any of them (or "Put on bar") straight onto your action bars.
--   Mouseover builder: a spell for a friend under the mouse, one for an enemy, or both; Create saves it in a free slot
--     and puts it on your cursor. The class's mouseover set and the templates are its quick picks.
--   Ring, Backups, Options.
local _, ns = ...
local UI = LibStub("EverlookUI-1")
local app = ns.app
local QM = ns.QUESTION_MARK

local function Esc(s) return UI.Util.Escape(s or "") end

-- Messages carry macro names, which may hold a "|": escaped so chat shows them as typed.
local function Say(ok, msg)
    if msg and msg ~= "queued" then app:Print((ok and "" or "|cffff6060") .. Esc(msg) .. (ok and "" or "|r")) end
    app:Refresh()
end

local function Date(t)
    if date and t and t > 0 then return date("%Y-%m-%d %H:%M", t) end
    return "earlier"
end

local function FirstLine(body)
    for line in tostring(body or ""):gmatch("[^\n]+") do
        if not line:match("^%s*#") then return line end
    end
    return tostring(body or ""):match("[^\n]*") or ""
end

local function ScopeWord(scope) return scope == "account" and "account" or "character" end

------------------------------------------------------------------------
-- The editor's state
------------------------------------------------------------------------
-- ed.ref: the macro being edited (nil: a new one); ed.as: for a new one, "char" or "account" (where it goes first).
-- ed.base: what the editor held when it was opened or last saved (unsaved changes are measured against it).
-- ed.pending: a save waiting for combat to end; ed.status: how the last save went.
local ed = { name = "", icon = QM, body = "#showtooltip\n", as = "char" }
ns.ed = ed

local function Snapshot() ed.base = { name = ed.name, icon = ed.icon, body = ed.body, as = ed.as } end
Snapshot()

-- Unsaved changes: the name, icon or text. A save waiting for combat is a save already chosen (it saves the latest
-- text), so it doesn't count.
local function Dirty()
    if ed.pending then return false end
    local b = ed.base
    return ed.name ~= b.name or ed.icon ~= b.icon or ed.body ~= b.body
end
ns.EditorDirty = Dirty

local function Values() return { ref = ed.ref, as = ed.as, name = ns.Trim(ed.name), icon = ed.icon, body = ed.body } end

-- Leaving a macro whose save waits for combat: that save keeps the text as it is now.
local function Detach()
    local p = ed.pending
    if p then p.values, p.live, ed.pending = Values(), false, nil end
    ed.status = nil
end

local function DefaultScope() return ns.db and ns.db.where == "account" and "account" or "char" end

local function OpenRef(ref)
    Detach()
    ref = ns.Fresh(ref) or ref
    ed.ref, ed.as = ref, ref.scope
    ed.name, ed.icon, ed.body = ref.name, ref.icon or QM, ref.body or ""
    ed.picking, ed.showHistory = false, false
    Snapshot()
    if ns.editorBox then ns.editorBox:SetText(ed.body) end
    app:Open("macros")
    app:Refresh()
end

local function ResetEditor(as)
    Detach()
    ed.ref, ed.as = nil, as or DefaultScope()
    ed.name, ed.icon, ed.body = "", QM, "#showtooltip\n"
    ed.picking, ed.showHistory = false, false
    if ns.editorBox then ns.editorBox:SetText(ed.body) end
    Snapshot()
end

local function OpenNew(as)
    ResetEditor(as)
    app:Open("macros")
    app:Refresh()
end

-- Save v ({ ref, as, name, icon, body }) now (out of combat). Returns ok, message, the saved macro.
-- A new macro goes to a character slot (or the kind chosen), else to the other kind, and says so; both full: it says
-- so plainly and nothing is made.
local function SaveNow(v, asCopy)
    local name, icon, body = v.name, v.icon, v.body
    if v.ref and not asCopy then
        local ok, msg = ns.SaveGame(v.ref, name, icon, body)
        return ok, msg, ok and ns.Fresh({ kind = "game", scope = v.ref.scope, name = name }) or nil
    end
    local err = ns.CheckText(name, body, ns.MAX_BODY)
    if err then return false, err end
    local want = v.ref and v.ref.scope or v.as or DefaultScope()
    local scope = ns.FreeScope(want)
    if not scope then return false, "no free macro slot: your account and character macros are all used. Delete one first." end
    if asCopy and ns.EachMacro(scope, function(_, n) return n == name end) then name = ns.FreeName(name, scope) end
    local ok, msg = ns.CreateGame(scope, name, icon, body)
    if not ok then return false, msg end
    local why = scope ~= want and (" (" .. ScopeWord(want) .. " macros are full)") or ""
    return true, ("created %s as %s macro%s: drag it to a bar"):format(name, scope == "account" and "an account" or "a character", why),
        ns.Fresh({ kind = "game", scope = scope, name = name })
end

-- The editor now holds the saved macro: no longer "New ...", and nothing unsaved.
local function Saved(ref)
    if ref then ed.ref = ref; ed.name = ref.name; ed.as = ref.scope end
    Snapshot()
end

-- A save that waited for combat: it saves what the editor holds now (or held when the player left it).
local function FinishPending(p)
    local v = p.live and Values() or p.values
    if p.live then ed.pending = nil end
    local ok, msg, ref = SaveNow(v, p.asCopy)
    app:Print((ok and "" or "|cffff6060") .. "after combat: " .. Esc(msg) .. (ok and "" or "|r"))
    if p.live then
        if ok then
            Saved(ref)
            ed.status = { ok = true, text = "Saved after combat." }
        else
            ed.status = { ok = false, text = "Not saved after combat: " .. tostring(msg) .. ". Your text is still here." }
        end
    end
    app:Refresh()
end

-- Save what is in the editor. Returns ok, message ("queued": it saves when combat ends).
function ns.EditorSave(asCopy)
    if ed.pending then return true, "queued" end -- one save at a time: the waiting one takes the latest text
    local v = Values()
    ed.status = nil
    if InCombatLockdown() then
        local err = ns.CheckText(v.name, v.body, ns.MAX_BODY)
        if err then Say(false, err) return false, err end
        local p = { live = true, asCopy = asCopy }
        ed.pending = p
        ns.Defer("saving " .. Esc(v.name), function() FinishPending(p) end,
            "|cffffb347in combat:|r " .. Esc(v.name) .. " will be saved when combat ends.")
        app:Refresh()
        return true, "queued"
    end
    local ok, msg, ref = SaveNow(v, asCopy)
    if ok then Saved(ref) end
    ed.status = { ok = ok, text = (msg or ""):gsub("^%l", string.upper) .. "." }
    Say(ok, msg)
    return ok, msg
end

-- Back to what was saved.
local function Revert()
    local b = ed.base
    ed.name, ed.icon, ed.body, ed.as = b.name, b.icon, b.body, b.as
    ed.picking = false
    if ns.editorBox then ns.editorBox:ClearFocus(); ns.editorBox:SetText(ed.body) end
    app:Refresh()
end
ns.EditorRevert = Revert

------------------------------------------------------------------------
-- Unsaved changes: ask Save / Discard / Cancel before they would be lost. Our own small window, not
-- a StaticPopup (an addon's entry in StaticPopupDialogs taints Blizzard's dialogs).
------------------------------------------------------------------------
local dialog
local function Dialog()
    if dialog then return dialog end
    local T = app.T
    local d = CreateFrame("Frame", nil, UIParent)
    d.eluiTheme = T
    d:SetSize(420, 116)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:SetToplevel(true)
    d:SetClampedToScreen(true)
    d:EnableMouse(true)
    d:Hide()
    UI.Util.Solid(d, "BACKGROUND", unpack(T.bg)):SetAllPoints()
    UI.Util.Border(d, 1, unpack(T.border))
    d.text = UI.Text(d, T.font, T.text)
    d.text:SetPoint("TOPLEFT", 18, -18)
    d.text:SetPoint("TOPRIGHT", -18, -18)
    d.text:SetJustifyH("CENTER")
    local function choose(what)
        local go = d.proceed
        d.proceed = nil
        d:Hide()
        if what == "save" then
            if ns.EditorSave() and go then go() end -- a failed save stays in the editor (the reason is in chat)
        elseif what == "discard" then
            Revert()
            if go then go() end
        end
    end
    d.save = UI.Button(d, "Save", function() choose("save") end, 110, "accent")
    d.discard = UI.Button(d, "Discard", function() choose("discard") end, 110)
    d.cancel = UI.Button(d, "Cancel", function() choose() end, 110)
    d.discard:SetPoint("BOTTOM", 0, 16)
    d.save:SetPoint("RIGHT", d.discard, "LEFT", -8, 0)
    d.cancel:SetPoint("LEFT", d.discard, "RIGHT", 8, 0)
    UI.Tooltip(d.discard, "Discard", "Throws away the changes and goes on.")
    UI.Tooltip(d.cancel, "Cancel", "Stays in the editor with your changes.")
    -- while it asks, the window behind takes no clicks
    d:SetScript("OnShow", function()
        local w = app.window
        if not w then return end
        if not d.blocker then
            d.blocker = CreateFrame("Button", nil, w)
            d.blocker:SetAllPoints()
            d.blocker:EnableMouse(true)
            UI.Util.Solid(d.blocker, "OVERLAY", 0, 0, 0, 0.35):SetAllPoints()
        end
        d.blocker:SetFrameLevel(w:GetFrameLevel() + 100)
        d.blocker:Show()
    end)
    d:SetScript("OnHide", function()
        d.proceed = nil -- Escape: the same as Cancel
        if d.blocker then d.blocker:Hide() end
    end)
    UI.CloseOnEscape(d)
    dialog = d
    ns.unsavedDialog = d
    return d
end

-- Run proceed() now, or (with unsaved changes) after the player chose Save or Discard.
function ns.Guard(proceed)
    if not Dirty() then return proceed() end
    local d = Dialog()
    d.proceed = proceed
    d.text:SetText((ed.ref and ("You changed |cffffffff" .. Esc(ed.ref.name) .. "|r and didn't save it.")
        or "Your new macro isn't saved yet.") .. "\nSave it first?")
    d:ClearAllPoints()
    if app.window and app.window:IsShown() then d:SetPoint("CENTER", app.window, "CENTER") else d:SetPoint("CENTER", UIParent, "CENTER", 0, 120) end
    d:Show()
end

local function SameAsEditor(ref)
    local cur = ed.ref
    if not ref or not cur then return false end
    return ref.scope == cur.scope and ref.name == cur.name
end

function ns.Edit(ref)
    -- the macro already in the editor, with changes or a save waiting: just show it
    if SameAsEditor(ref) and (Dirty() or ed.pending) then app:Open("macros") return end
    ns.Guard(function() OpenRef(ref) end)
end

function ns.EditNew(as) ns.Guard(function() OpenNew(as) end) end

-- Pages before 0.4.0 (and their links, /mom commands): Mine, Account, Character, Extended and Edit are the Macros
-- page now, Templates is the mouseover builder's quick picks.
local OLD_PAGES = { mine = "macros", account = "macros", char = "macros", ext = "macros", edit = "macros", list = "macros",
    templates = "builder", ready = "builder" }
ns.OLD_PAGES = OLD_PAGES

-- Leaving the Macros page (the editor) and closing the window ask first too (sidebar, x, Escape, /mom).
local baseShowSection, baseClose, baseCreateWindow = app.ShowSection, app.Close, app.CreateWindow
function app:ShowSection(id)
    if OLD_PAGES[id] and not self.sections[id] then id = OLD_PAGES[id] end
    if self.current == "macros" and id ~= "macros" and self:IsShown() and Dirty() then
        return ns.Guard(function() baseShowSection(self, id) end)
    end
    return baseShowSection(self, id)
end
function app:Close()
    if self:IsShown() and Dirty() then return ns.Guard(function() baseClose(self) end) end
    return baseClose(self)
end
-- The sidebar: Macros, Mouseover builder, Ring, Backups, Options.
local NAV = { macros = 1, builder = 2, ring = 3, backups = 4, options = 5 }
function app:CreateWindow()
    local pos = {}
    for i, id in ipairs(self.order) do pos[id] = i end
    table.sort(self.order, function(a, b)
        local x, y = NAV[a] or 50, NAV[b] or 50
        if x ~= y then return x < y end
        return pos[a] < pos[b]
    end)
    local f = baseCreateWindow(self)
    f.close:SetScript("OnClick", function() app:Close() end)
    local onKey = f:GetScript("OnKeyDown")
    f:SetScript("OnKeyDown", function(frame, key)
        -- In combat the game gets Escape anyway (an addon can't keep it), so asking here would also open the Game
        -- Menu: leave Escape to the game then (EverlookUI lets go of the keyboard when combat starts).
        if key == "ESCAPE" and Dirty() and not UI.IsPopupShown() and not InCombatLockdown() then
            frame:SetPropagateKeyboardInput(false)
            app:Close()
            return
        end
        if onKey then onKey(frame, key) end
    end)
    return f
end

------------------------------------------------------------------------
-- Waiting for combat: one entry per macro and action, said once, shown on its row and in the editor, cancellable
------------------------------------------------------------------------
local function CountsLine()
    local a, maxA, c, maxC = ns.Counts()
    local function col(n, max) return n >= max and "|cffff8a8a" or "|cffffffff" end
    return ("Character %s%d/%d|r   Account %s%d/%d|r"):format(col(c, maxC), c, maxC, col(a, maxA), a, maxA)
end
ns.CountsLine = CountsLine

local function RefId(ref) return tostring(ref.scope) .. ":" .. tostring(ref.name) end
ns.RefId = RefId

-- pending[id] = { line = "Riding will be deleted", text = "Deleting after combat", ids }; id = "del:<ref>", "move:<ref>", ...
local pending = {}
ns.pending = pending

-- Run fn now; in combat once, when combat ends. Chat says so at once; a second try while it waits queues nothing.
-- ids: the pending entries it stands for (a bulk delete waits as one job for many macros). Returns true when it waits.
local function Later(ids, line, text, fn)
    if type(ids) ~= "table" then ids = { ids } end
    if not InCombatLockdown() then fn() return false end
    for _, id in ipairs(ids) do
        if pending[id] then
            app:Print("|cffffd27falready waiting for combat to end:|r " .. Esc(pending[id].line) .. ". Cancel it in /mom.")
            return true
        end
    end
    local p = { line = line, text = text, ids = ids }
    for _, id in ipairs(ids) do pending[id] = p end
    ns.Defer(line, function()
        if pending[ids[1]] ~= p then return end -- cancelled
        for _, id in ipairs(ids) do pending[id] = nil end
        fn()
        app:Refresh()
    end, "|cffffb347in combat:|r " .. Esc(line) .. " when combat ends. Cancel it in /mom.")
    app:Refresh()
    return true
end
ns.Later = Later

local function CancelLater(id)
    local p = pending[id]
    if not p then return end
    for _, x in ipairs(p.ids) do pending[x] = nil end
    app:Print("cancelled: " .. Esc(p.line) .. " (nothing changes).")
    app:Refresh()
end
ns.CancelLater = CancelLater

------------------------------------------------------------------------
-- Onto your action bars: drag a row or the editor's icon, or "Put on bar"
------------------------------------------------------------------------
-- The game doesn't let an addon put a macro on the cursor in combat (ADDON_ACTION_BLOCKED): then the game's own macro
-- window opens (it still can) and one line says so, at most every 30 s. Nothing waits for later.
local function CanPickUp() return not InCombatLockdown() end
ns.CanPickUp = CanPickUp
local PICKUP_LATER = "|cffffd27fIn combat: Put on bar works after combat (or drag it from the game's macro window).|r"
local function PickUpTip(t)
    if not CanPickUp() then t[#t + 1] = " "; t[#t + 1] = PICKUP_LATER end
    return t
end

local saidAt
local function InCombat()
    if ns.ShowBlizzardMacros then ns.ShowBlizzardMacros() end
    local now = GetTime and GetTime() or 0
    if not saidAt or now - saidAt > 30 then
        saidAt = now
        app:Print("in combat the game won't let an addon put a macro on your cursor: Put on bar works after combat, "
            .. "or drag it from the game's macro window (opened).")
    end
end
ns.PickUpInCombat = InCombat

local function PickUp(ref)
    if not ref then return end
    if not CanPickUp() then InCombat() return end
    local cur = ns.Fresh(ref)
    if cur and PickupMacro then PickupMacro(cur.index) end
end
ns.PickUp = PickUp

------------------------------------------------------------------------
-- Deleting: one click, into the bin; Undo (on the list, /mom undo) puts the last delete back
------------------------------------------------------------------------
local selected = {}   -- [RefId] = true: ticked on the list
ns.selected = selected
local lastDeleted     -- { bin entries } of the last delete (one macro or several)
local status          -- the list's status line: { text, undo = true }
ns.Status = function() return status end

local function Names(list, max)
    local t = {}
    for i, n in ipairs(list) do
        if i > max then t[#t + 1] = "and " .. (#list - max) .. " more" break end
        t[#t + 1] = n
    end
    return table.concat(t, ", ")
end

-- Out of combat: delete them all (each to the bin), one line for the lot.
local function DeleteNow(refs)
    local done, names, failed = {}, {}, {}
    for _, r in ipairs(refs) do
        local wasOpen = SameAsEditor(r)
        local ok, msg = ns.DeleteGame(r)
        selected[RefId(r)] = nil
        if ok then
            done[#done + 1] = ns.db.bin[1]
            names[#names + 1] = r.name
            if wasOpen then ResetEditor(r.scope) end
        else
            failed[#failed + 1] = tostring(msg)
        end
    end
    if #done > 0 then
        lastDeleted = done
        status = { undo = true, text = #done == 1 and ("Deleted " .. names[1] .. ". Undo or Backups restores it.")
            or ("Deleted " .. #done .. " macros. Undo puts them all back.") }
        app:Print((#done == 1 and ("deleted " .. Esc(names[1]) .. " - /mom undo or Backups restores it.")
            or ("deleted %d macros (%s) - /mom undo puts them all back, Backups has each one."):format(#done, Esc(Names(names, 8))))
            .. (#failed > 0 and (" |cffff6060Not deleted: " .. Esc(table.concat(failed, "; ")) .. "|r") or ""))
    elseif #failed > 0 then
        app:Print("|cffff6060not deleted: " .. Esc(table.concat(failed, "; ")) .. "|r")
    end
    app:Refresh()
    return #done, #failed
end

-- Delete macros (refs): now, or once when combat ends.
function ns.DeleteMacros(refs)
    if #refs == 0 then return end
    local ids = {}
    for i, r in ipairs(refs) do ids[i] = "del:" .. RefId(r) end
    local line = #refs == 1 and (refs[1].name .. " will be deleted") or (#refs .. " macros will be deleted")
    return Later(ids, line, "Deleting after combat", function() DeleteNow(refs) end)
end

-- A bin entry made again (in the other kind of slot when its own is full); it leaves the bin.
local function RestoreNow(b)
    local kind = b.scope == "account" and "a" or "c"
    local ok, msg = ns.Import({ { kind = kind, icon = b.icon, name = b.name, body = b.body } })
    if ok then
        for i, x in ipairs(ns.db.bin) do if x == b then table.remove(ns.db.bin, i) break end end
        if b.key and ns.cdb.deleted then ns.cdb.deleted[b.key] = nil end
    end
    return ok, msg
end
ns.RestoreNow = RestoreNow

local function InBin(b) for _, x in ipairs(ns.db.bin) do if x == b then return true end end end

-- Puts the last delete back (every macro of a bulk delete).
function ns.Undo()
    local list = lastDeleted
    if not list then app:Print("nothing to undo: no macro deleted in this session.") return end
    return Later("undo", "the last delete will be undone", "Undoing after combat", function()
        if lastDeleted == list then lastDeleted = nil end
        status = nil
        local names = {}
        for _, b in ipairs(list) do
            if InBin(b) and RestoreNow(b) then names[#names + 1] = b.name end
        end
        app:Print(#names > 0 and ("put back " .. Esc(Names(names, 8)) .. ".") or "nothing to put back (restored from Backups already).")
        app:Refresh()
    end)
end

------------------------------------------------------------------------
-- What a macro is, in words: a template's title, the spell of a set macro, else the spells it casts
------------------------------------------------------------------------
local function Known()
    local byIndex = {}
    for _, e in ipairs(ns.Entries()) do if e.index then byIndex[e.index] = { e = e } end end
    for _, t in ipairs(ns.Templates()) do
        local i = ns.Resolve("t:" .. t.id)
        if i then byIndex[i] = { t = t } end
    end
    return byIndex
end

local function Readable(ref, known)
    local k = known and known[ref.index]
    if k and k.t then return k.t.title end
    if k and k.e then return k.e.spell end
    local w = ns.WhatItDoes(ref.body)
    return w ~= "" and w or nil
end
ns.Readable = Readable

local function MacroIcon(ref)
    if ref.icon and ref.icon ~= QM then return ref.icon end
    local first = ns.WhatItDoes(ref.body):match("^[^,]+")
    return first and ns.SpellIcon(first) or QM
end

-- The macros for the list: all of them (account first, as in the game's window), filtered by the search.
local search = ""
local function MacroItems()
    local known, out = Known(), {}
    local terms = {}
    for w in search:lower():gmatch("%S+") do terms[#terms + 1] = w end
    for _, r in ipairs(ns.List(nil)) do
        local read = Readable(r, known)
        r.readable = read
        local ok = true
        if #terms > 0 then
            local hay = ((read or "") .. "\n" .. r.name .. "\n" .. (r.body or "")):lower()
            for _, w in ipairs(terms) do if not hay:find(w, 1, true) then ok = false break end end
        end
        if ok then out[#out + 1] = r end
    end
    return out
end
ns.MacroItems = MacroItems

local function Selected()
    local out = {}
    if not next(selected) then return out end
    for _, r in ipairs(ns.List(nil)) do if selected[RefId(r)] then out[#out + 1] = r end end
    return out
end
ns.Selected = Selected

------------------------------------------------------------------------
-- A spell picker: type a few letters, pick from your spellbook
------------------------------------------------------------------------
-- o = { label, placeholder, get = fn() -> spell name, set = fn(name or nil), buttons = row buttons (insert mode) }
local function SpellPicker(stack, o)
    local query, list = "", nil
    local input = UI.Input(stack, {
        label = o.label, placeholder = o.placeholder or "Type a spell name", width = o.width or 230, desc = o.desc,
        get = o.get or function() return "" end,
        set = function(text) if o.set and ns.Trim(text) == "" then o.set(nil) end end,
        onChange = function(text) query = text or ""; list:Refresh() end,
        search = false,
    })
    list = UI.List(stack, {
        items = function()
            local q = ns.Trim(query):lower()
            if q == "" or (o.get and q == tostring(o.get() or ""):lower()) then return {} end
            local out = {}
            for _, s in ipairs(ns.SpellBook()) do
                if s.name:lower():find(q, 1, true) then out[#out + 1] = s end
            end
            return out
        end,
        max = 6,
        rowHeight = 26,
        empty = "No spell in your spellbook matches.",
        icon = function(s) return s.icon or QM end,
        title = function(s) return Esc(s.name) .. (s.rank and ("  |cff8d94a3Rank " .. s.rank .. "|r") or "") end,
        onClick = function(s)
            if o.pick then o.pick(s) end
            if o.set then
                o.set(s.name)
                query = ""
                input.box:SetText(s.name)
                input.box:ClearFocus()
            end
            stack:RefreshAll()
        end,
        buttons = o.buttons,
    })
    local base = list.Refresh
    function list:Refresh()
        base(self)
        local open = ns.Trim(query) ~= "" and not (o.get and ns.Trim(query):lower() == tostring(o.get() or ""):lower())
        self:SetShown(open)
        if not open then stack:SetHeightOf(self, 0) end
    end
    list:Refresh()
    function input:Clear() query = ""; self.box:SetText(""); list:Refresh() end
    input.list = list
    return input
end

------------------------------------------------------------------------
-- The editor (the right side of the Macros page)
------------------------------------------------------------------------
local INSERTS = {
    { "mouseover friend", "[@mouseover,help,nodead][help,nodead] " }, { "mouseover enemy", "[@mouseover,harm,nodead][harm,nodead] " },
    { "mouseover any", "[@mouseover,exists,nodead][exists,nodead] " }, { "mouseover dead", "[@mouseover,help,dead][help,dead] " },
    { "#showtooltip", "#showtooltip\n" }, { "/cast", "/cast " }, { "/use", "/use " }, { "/stopcasting", "/stopcasting\n" },
    { "focus", "[@focus,exists,nodead] " }, { "shift", "[mod:shift] " }, { "ctrl", "[mod:ctrl] " }, { "alt", "[mod:alt] " },
}

local ICON_COLS, ICON_ROWS, ICON_SIZE = 12, 4, 30

local function BuildEditor(stack)
    local T = stack.T
    UI.Note(stack, function()
        if ed.ref then
            return ("|cffffffff%s|r  -  %s%s"):format(Esc(ed.ref.name), ns.Cost(ed.ref),
                not ed.ref.ours and "" or "  |cff8d94a3(made by /mom)|r")
        end
        local scope = ns.FreeScope(ed.as)
        return "|cffffffffNew macro|r  -  " .. (scope and ("it goes to " .. (scope == "account" and "an account" or "a character") .. " slot"
            .. (scope ~= ed.as and (" (" .. ScopeWord(ed.as) .. " macros are full)") or ""))
            or "|cffff8a8ano free macro slot: delete one first|r")
    end)

    -- the icon (drag it, or click it, onto an action bar) and Put on bar
    local iconRow = CreateFrame("Frame")
    iconRow:SetParent(stack.parent)
    local grab = CreateFrame("Button", nil, iconRow)
    grab:SetSize(26, 26)
    grab:SetPoint("LEFT")
    grab:RegisterForDrag("LeftButton")
    local function Grab()
        if not ed.ref then app:Print("save it first, then put it on a bar.") return end
        PickUp(ed.ref)
    end
    grab:SetScript("OnDragStart", Grab)
    grab:SetScript("OnClick", Grab)
    UI.Tooltip(grab, "Drag to your bars", "Drag this icon (or click it) to put the macro on your cursor, then drop it on an action bar.")
    local tex = grab:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(grab)
    local put = UI.Button(iconRow, "Put on bar", Grab, 100)
    put:SetPoint("LEFT", 36, 0)
    UI.Tooltip(put, "Put on bar", "Puts the macro on your cursor: click an action bar slot to drop it there.")
    local change = UI.Button(iconRow, "Change icon", function() ed.picking = not ed.picking; stack:RefreshAll() end, 110)
    change:SetPoint("LEFT", put, "RIGHT", 8, 0)
    local dyn = UI.Button(iconRow, "Icon from the spell", function() ed.icon = QM; stack:RefreshAll() end, 150)
    dyn:SetPoint("LEFT", change, "RIGHT", 8, 0)
    UI.Tooltip(dyn, "Icon from the spell", "The question mark icon: with #showtooltip on the first line, the button shows the icon of the spell it casts.")
    function iconRow:Refresh()
        tex:SetTexture(ed.icon ~= QM and ed.icon or (ed.ref and MacroIcon(ed.ref)) or QM)
        put:SetUsable(ed.ref ~= nil)
    end
    iconRow.put = put
    ns.putOnBar = put
    ns.editorIcon = grab
    stack:Add(iconRow, 28)
    iconRow:Refresh()

    -- icon picker (shown while picking)
    local picker = CreateFrame("Frame")
    picker:SetParent(stack.parent)
    local search = UI.EditBox(picker, 200, 24)
    search:SetPoint("TOPLEFT")
    local page, found = 1, nil
    local pageText = UI.Text(picker, T.font, T.muted)
    local prev = UI.Button(picker, "<", function() page = math.max(1, page - 1); picker:Refresh() end, 30)
    local nextB = UI.Button(picker, ">", function() page = page + 1; picker:Refresh() end, 30)
    prev:SetPoint("LEFT", search, "RIGHT", 8, 0)
    nextB:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    pageText:SetPoint("LEFT", nextB, "RIGHT", 8, 0)
    UI.Tooltip(search, "Search icons", "A spell name from your spellbook, part of an icon's file name, or a file ID.")
    search:SetScript("OnTextChanged", function(self, user) if user then found = nil; page = 1; picker:Refresh() end end)
    picker.cells = {}
    for i = 1, ICON_COLS * ICON_ROWS do
        local b = CreateFrame("Button", nil, picker)
        b:SetSize(ICON_SIZE, ICON_SIZE)
        b:SetPoint("TOPLEFT", ((i - 1) % ICON_COLS) * (ICON_SIZE + 4), -30 - math.floor((i - 1) / ICON_COLS) * (ICON_SIZE + 4))
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b:SetScript("OnClick", function(self) if self.icon then ed.icon = self.icon; ed.picking = false; stack:RefreshAll() end end)
        picker.cells[i] = b
    end
    local pickerH = 30 + ICON_ROWS * (ICON_SIZE + 4) + 4
    function picker:Refresh()
        self:SetShown(ed.picking and true or false)
        stack:SetHeightOf(self, ed.picking and pickerH or 0)
        if not ed.picking then return end
        found = found or ns.SearchIcons(search:GetText())
        local per = ICON_COLS * ICON_ROWS
        local pages = math.max(1, math.ceil(#found / per))
        page = math.min(page, pages)
        pageText:SetText(("%d / %d  (%d icons)"):format(page, pages, #found))
        for i, b in ipairs(self.cells) do
            local icon = found[(page - 1) * per + i]
            b.icon = icon
            b.tex:SetTexture(icon)
            b:SetShown(icon ~= nil)
        end
    end
    picker.search = search
    ns.picker = picker
    stack:Add(picker, 0)
    picker:Refresh()

    UI.Input(stack, {
        label = "Name", width = 220, search = false,
        get = function() return ed.name end, set = function(v) ed.name = v end,
        onChange = function(text) ed.name = text end,
    })
    -- where it is stored: picked for a new one (character, else account); for one that exists, choosing moves it
    UI.Dropdown(stack, {
        label = "Stored as", width = 220, search = false,
        desc = "Character macros are only this character's; account macros are on all your characters. A moved macro is a new macro: put it on your bars again.",
        items = { { value = "char", text = "Character macro" }, { value = "account", text = "Account macro" } },
        get = function() return ed.ref and ed.ref.scope or ed.as end,
        set = function(v)
            if not ed.ref then ed.as = v return end
            if v == ed.ref.scope then return end
            ns.EditorMove(v)
        end,
        after = function() app:Refresh() end,
    })

    -- the text
    local area = UI.TextArea(stack.parent, stack.width, 140)
    local box = area.box
    box:SetScript("OnTextChanged", function(self, user)
        if user then ed.body = self:GetText(); stack:RefreshAll() end
    end)
    function area:Refresh() if not box:HasFocus() then box:SetText(ed.body or "") end end
    stack:Add(area, 140)
    area:Refresh()
    ns.editorBox = box

    -- live count and line check
    UI.Note(stack, function()
        local n, limit = #(ed.body or ""), ns.MAX_BODY
        local col = n > limit and "|cffff6060" or (n > limit - 20 and "|cffffb347" or "|cff62cf88")
        local lines = { ("%s%d / %d characters|r"):format(col, n, limit) }
        for _, p in ipairs(ns.CheckLines(ed.body, limit)) do
            if p.line > 0 then lines[#lines + 1] = ("|cffffb347line %d:|r %s"):format(p.line, Esc(p.text)) end
        end
        if #lines == 1 then lines[1] = lines[1] .. "  |cff8d94a3- every spell and item name checks out|r" end
        return table.concat(lines, "\n")
    end)

    local function Insert(text)
        local before = box:GetText() or ""
        box:Insert(text)
        if (box:GetText() or "") == before then box:SetText(before .. text) end -- no cursor to insert at
        ed.body = box:GetText()
        stack:RefreshAll()
    end
    ns.EditorInsert = Insert

    -- Insert spell: from the spellbook, the highest rank or one you pick
    local spellPick
    spellPick = SpellPicker(stack, {
        label = "Insert spell", placeholder = "Type a spell name",
        desc = "Puts a spell from your spellbook into the text where the cursor is.",
        pick = function(s) Insert(s.name); spellPick:Clear() end,
        buttons = {
            { label = "Insert", width = 64, onClick = function(s) Insert(s.name); spellPick:Clear() end },
            { label = "Rank...", width = 64, shown = function(s) return (s.rank or 0) > 1 end, onClick = function(s, btn)
                local items = {}
                for r = s.rank, 1, -1 do items[#items + 1] = { value = r, text = "Rank " .. r } end
                UI.OpenPopup(btn, items, nil, function(r) Insert(ns.Ranked(s.name, r)); spellPick:Clear() end, { width = 120 })
            end },
        },
    })
    ns.insertSpell = spellPick

    -- the condition buttons: tidy rows, four across when the editor is wide enough, else three
    local perRow = stack.width >= 4 * 104 + 3 * 8 and 4 or 3
    local bw = math.min(130, math.floor((stack.width - (perRow - 1) * 8) / perRow))
    local rows = {}
    for i, d in ipairs(INSERTS) do
        local ri = math.floor((i - 1) / perRow) + 1
        rows[ri] = rows[ri] or {}
        local row = rows[ri]
        row[#row + 1] = { label = d[1], width = bw, onClick = function() Insert(d[2]) end, desc = "Inserts " .. (d[2]:gsub("\n", "")) }
    end
    for _, row in ipairs(rows) do row.search = false; UI.ButtonRow(stack, row) end

    local saveRow = UI.ButtonRow(stack, {
        { label = "Save", width = 90, style = "accent", onClick = function() if not ed.pending then ns.EditorSave() end end },
        { label = "Undo", width = 80, onClick = function() Revert() end, desc = "Puts back what was last saved." },
        { label = "Save as copy", width = 120, onClick = function() if not ed.pending and ed.ref then ns.EditorSave(true) end end },
        -- one click: it goes to the bin under Backups, and Undo on the list (or /mom undo) puts it back
        { label = "Delete", width = 90, style = "danger", onClick = function()
            if not ed.ref then return end
            local id = "del:" .. RefId(ed.ref)
            if pending[id] then CancelLater(id) return end
            ns.DeleteMacros({ ed.ref })
        end, desc = "Deletes it at once. It goes to the bin under Backups; Undo on the list (or /mom undo) puts it back." },
        search = false,
        refresh = function(row)
            local b = row.buttons
            local id = ed.ref and RefId(ed.ref)
            b[1]:SetUsable(true)
            b[2]:SetUsable(Dirty())
            b[3]:SetUsable(ed.ref ~= nil)
            b[4]:SetText(id and pending["del:" .. id] and "Cancel" or "Delete")
            b[4]:SetUsable(ed.ref ~= nil)
            -- a save waiting for combat: Save and Save as copy greyed out (their tooltip says why)
            if ed.pending then b[1]:SetAlpha(0.4); b[3]:SetAlpha(0.4) end
        end,
    })
    for _, i in ipairs({ 1, 3 }) do
        local b = saveRow.buttons[i]
        b:HookScript("OnEnter", function(self)
            if not ed.pending then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Waiting for combat to end", 1, 1, 1)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    ns.saveRow = saveRow
    UI.Note(stack, function()
        local id = ed.ref and RefId(ed.ref)
        local p = id and (pending["del:" .. id] or pending["move:" .. id])
        if p then return "|cffffd27fIn combat: " .. Esc(p.line) .. " when combat ends. Cancel stops it.|r" end
        if ed.pending then return "|cffffd27fIn combat: it will be saved when combat ends.|r" end
        local s = ed.status
        if not s then return "" end
        return (s.ok and "|cff62cf88" or "|cffff6060") .. Esc(s.text) .. "|r"
    end)

    -- earlier versions, tucked away
    local histRow = UI.ButtonRow(stack, {
        { label = "Earlier versions", width = 170, onClick = function() ed.showHistory = not ed.showHistory; stack:RefreshAll() end },
        search = false,
        refresh = function(row)
            local n = #ns.History(ed.ref)
            row.buttons[1]:SetText(("%s Earlier versions (%d)"):format(ed.showHistory and "-" or "+", n))
            row.buttons[1]:SetUsable(n > 0)
        end,
    })
    ns.historyToggle = histRow.buttons[1]
    local hist = UI.List(stack, {
        items = function() return ns.History(ed.ref) end,
        empty = "No earlier versions yet.",
        title = function(h) return Date(h.t) end,
        detail = function(h) return "|cff8d94a3" .. Esc(FirstLine(h.body)) .. "|r" end,
        tooltip = function(h)
            local t = { Date(h.t), " " }
            for line in (h.body or ""):gmatch("[^\n]+") do t[#t + 1] = Esc(line) end
            return t
        end,
        buttons = { { label = "Restore", width = 80, onClick = function(h)
            ed.body, ed.icon = h.body, h.icon or ed.icon
            if ns.editorBox then ns.editorBox:SetText(ed.body) end
            app:Refresh()
        end } },
    })
    local histBase = hist.Refresh
    function hist:Refresh()
        histBase(self)
        local open = ed.showHistory and #ns.History(ed.ref) > 0
        self:SetShown(open)
        if not open then stack:SetHeightOf(self, 0) end
    end
    hist:Refresh()
    ns.historyList = hist
end

-- Move the open macro to the other kind (account <-> character); in combat once, after combat.
function ns.EditorMove(to)
    if not ed.ref then return end
    local ref = ed.ref
    local id = "move:" .. RefId(ref)
    if pending[id] then CancelLater(id) return end
    Later(id, ref.name .. " will be moved to " .. ScopeWord(to) .. " macros", "Moving after combat", function()
        local ok, msg = ns.MoveGame(ref, to)
        if ok and SameAsEditor(ref) then
            ed.ref = ns.Fresh({ kind = "game", scope = to, name = ref.name })
            ed.as = to
        end
        Say(ok, msg)
    end)
end

------------------------------------------------------------------------
-- The Macros page: the list on the left, the editor on the right
------------------------------------------------------------------------
local LEFT_W, PUT_W = 330, 80

-- A tick box in a list row (bulk delete).
local function Tick(r, T, onClick)
    local b = CreateFrame("Button", nil, r)
    b:SetSize(16, 16)
    b:SetPoint("LEFT", r, "LEFT", 8, 0)
    UI.Util.Solid(b, "BACKGROUND", unpack(T.surfaceHi)):SetAllPoints()
    UI.Util.Border(b, 1, unpack(T.border))
    b.mark = b:CreateTexture(nil, "ARTWORK")
    b.mark:SetAllPoints()
    UI.SetIcon(b.mark, "check")
    b.mark:SetVertexColor(unpack(T.accent))
    function b:SetOn(on) self.on = on and true or false; self.mark:SetShown(self.on) end
    b:SetScript("OnClick", function(self) onClick(r.item, self) end)
    UI.Tooltip(b, "Select", "Tick macros, then \"Delete selected\" deletes them all at once (Undo puts them back).")
    b:SetOn(false)
    return b
end

app:Section("macros", "Macros", function(holder, _, s)
    local T = app.T
    local f = app.window
    local panelW = math.max(700, math.floor((f and f:GetWidth() or 1026) - (UI.SIDEBAR_W or 196) - 2))

    local left = CreateFrame("Frame", nil, holder)
    left:SetPoint("TOPLEFT", 16, -16)
    left:SetPoint("BOTTOMLEFT", 16, 16)
    left:SetWidth(LEFT_W)
    local leftScroll = UI.ScrollPage(left)
    local lw = LEFT_W - 18
    leftScroll.child:SetWidth(lw)
    local ls = UI.Stack(leftScroll.child, lw, T)

    local line = UI.Util.Solid(holder, "ARTWORK", unpack(T.divider))
    line:SetWidth(1)
    line:SetPoint("TOPLEFT", LEFT_W + 24, -16)
    line:SetPoint("BOTTOMLEFT", LEFT_W + 24, 16)

    local rightW = panelW - (LEFT_W + 32) - 8
    local right = CreateFrame("Frame", nil, holder)
    right:SetPoint("TOPLEFT", LEFT_W + 32, -16)
    right:SetPoint("BOTTOMRIGHT", -8, 16)
    local rightScroll = UI.ScrollPage(right)
    local rw = rightW - 18
    rightScroll.child:SetWidth(rw)
    local es = UI.Stack(rightScroll.child, rw, T, { cards = true })

    -- left: New, the slots, the search, the list
    UI.ButtonRow(ls, {
        { label = "New macro", width = 120, onClick = function() ns.EditNew() end, desc = "An empty macro in the editor." },
        { label = "New mouseover macro", width = 144, onClick = function() app:ShowSection("builder") end,
            desc = "Pick a spell for a friend and one for an enemy: the builder writes the macro for you." },
        search = false,
    })
    UI.Note(ls, CountsLine)
    local searchBox = UI.Input(ls, {
        placeholder = "Search: a spell, a name or any text", width = lw, search = false,
        onChange = function(text) search = text or ""; ls:RefreshAll() end,
    })
    ns.macroSearch = searchBox.box

    -- the last delete, with Undo. Both fold away (no height, no gap) while there is nothing to say, so the list sits
    -- right under the search box.
    local function Fold(frame, on, h)
        local e = frame.stackEntry
        frame:SetShown(on)
        if not e then return end
        local gap = on and T.rowGap or 0
        if e.height == (on and h or 0) and e.gap == gap then return end
        e.height, e.gap = on and h or 0, gap
        ls:Relayout()
    end
    local stNote = UI.Note(ls, function() return status and ("|cff62cf88" .. Esc(status.text) .. "|r") or "" end)
    function stNote:Refresh()
        self.text:SetText(status and ("|cff62cf88" .. Esc(status.text) .. "|r") or "")
        Fold(self, status ~= nil, math.max(14, self.text:GetStringHeight() + 2))
    end
    stNote:Refresh()
    local undoRow = UI.ButtonRow(ls, {
        { label = "Undo", width = 90, onClick = function() if pending.undo then CancelLater("undo") else ns.Undo() end end },
        search = false,
        refresh = function(row)
            Fold(row, status ~= nil, 26)
            row.buttons[1]:SetText(pending.undo and "Cancel" or "Undo")
        end,
    })
    ns.statusNote, ns.undoButton = stNote, undoRow.buttons[1]

    local list = UI.List(ls, {
        items = MacroItems,
        rowHeight = 40,
        empty = "No macros yet. \"New mouseover macro\" makes one for your spells in a few clicks.",
        icon = function(r) return MacroIcon(r) end,
        title = function(r) return Esc(r.readable or r.name) end,
        detail = function(r)
            local p = pending["del:" .. RefId(r)] or pending["move:" .. RefId(r)]
            if p then return "|cffffd27f" .. p.text .. "...|r" end
            return "|cff8d94a3" .. (r.readable and (Esc(r.name) .. "  ") or "") .. ScopeWord(r.scope) .. (r.ours and "  /mom" or "") .. "|r"
        end,
        tooltip = function(r)
            local t = { r.name, ns.Cost(r), " " }
            for l in (r.body or ""):gmatch("[^\n]+") do t[#t + 1] = Esc(l) end
            t[#t + 1] = " "
            t[#t + 1] = "|cff8d94a3Click to edit; drag onto an action bar.|r"
            return PickUpTip(t)
        end,
        onClick = function(r) ns.Edit(r) end,
        drag = function(r) PickUp(r) end,
        buttons = {
            { label = "Put on bar", width = PUT_W, onClick = function(r) PickUp(r) end },
        },
    })
    -- the tick box left of the icon, and the open macro lit
    local base = list.Refresh
    function list:Refresh()
        base(self)
        for _, r in ipairs(self.rows) do
            if not r.tick then
                r.tick = Tick(r, T, function(item)
                    if not item then return end
                    local id = RefId(item)
                    selected[id] = not selected[id] or nil
                    ls:RefreshAll()
                end)
                if r.icon then r.icon:ClearAllPoints(); r.icon:SetPoint("LEFT", 32, 0) end
                r.title:ClearAllPoints()
                r.title:SetPoint("TOPLEFT", 58, -6)
                r.title:SetPoint("RIGHT", -(6 + PUT_W + 6 + 4), 0)
                r:HookScript("OnLeave", function(self) if self.item and SameAsEditor(self.item) then self.bg:SetVertexColor(unpack(T.accentDim)) end end)
            end
            local it = r.item
            if it then
                r.tick:SetOn(selected[RefId(it)])
                r.bg:SetVertexColor(unpack(SameAsEditor(it) and T.accentDim or T.surface))
            end
        end
    end
    ns.macroList = list
    list:Refresh()

    local delRow = UI.ButtonRow(ls, {
        { label = "Delete selected", width = 170, onClick = function() ns.DeleteMacros(Selected()) end,
            desc = "Deletes every ticked macro at once. They go to the bin under Backups; Undo puts them all back." },
        search = false,
        refresh = function(row)
            local n = #Selected()
            Fold(row, n > 0, 26)
            row.buttons[1]:SetText("Delete selected (" .. n .. ")")
        end,
    })
    ns.deleteSelected = delRow.buttons[1]
    UI.Note(ls, "|cff8d94a3Drag a row onto an action bar, or Put on bar.|r")

    -- right: the editor
    BuildEditor(es)

    local function finish(st, scroll) st:Finish(); scroll.UpdateBar() end
    -- the app refreshes a page through its stack: both sides here
    s.stack = {
        stacks = { ls, es },
        widgets = es.widgets,
        RefreshAll = function()
            ls:RefreshAll(); es:RefreshAll()
            finish(ls, leftScroll); finish(es, rightScroll)
        end,
    }
    ns.listStack, ns.editStack = ls, es
    s.stack.RefreshAll()
end, { panel = true, icon = "list", show = function(_, _, s) if s.stack then s.stack.RefreshAll() end end,
    desc = "Every macro: click one to edit it, drag it onto your bars." })

------------------------------------------------------------------------
-- The mouseover builder
------------------------------------------------------------------------
-- bd: what the builder holds (friend / enemy spells and ranks, the options, the name if the player typed one).
local bd = { fallback = true, stop = false, whisper = true }
ns.bd = bd

local function MaxRank(spell)
    if not spell then return nil end
    for _, s in ipairs(ns.SpellBook()) do if s.name == spell then return s.rank end end
end

local function Built() return ns.BuildMouseover(bd) end
local function BuiltName()
    local _, sug = Built()
    local typed = bd.name and ns.Trim(bd.name) or ""
    return typed ~= "" and typed or sug
end
ns.BuiltName = BuiltName

-- Create: a free slot (character, else account), then onto the cursor to drop on a bar.
function ns.CreateBuilt()
    local body = Built()
    if not body then app:Print("pick a spell for a friend, one for an enemy, or both.") return false end
    local name = BuiltName()
    local id = "build:" .. name
    if pending[id] then CancelLater(id) return false end
    return Later(id, name .. " will be made", "Making after combat", function()
        local scope = ns.FreeScope(DefaultScope())
        if not scope then
            app:Print("|cffff6060no free macro slot:|r your account and character macros are all used. Delete one first.")
            return
        end
        local n = ns.FreeName(name, scope)
        local ok, msg = ns.CreateGame(scope, n, QM, body)
        if not ok then Say(false, msg) return end
        local ref = ns.Fresh({ kind = "game", scope = scope, name = n })
        bd.last = ref
        local onCursor = ref and CanPickUp() and PickupMacro
        if onCursor then PickupMacro(ref.index) end
        app:Print(("made %s (%s slot)%s"):format(Esc(n), scope == "account" and "an account" or "a character",
            onCursor and ": it's on your cursor, click an action bar slot to drop it." or ": drag it from Macros to a bar."))
        app:Refresh()
    end) or true
end

local QUICK_BUTTON = { new = "Create", missing = "Create", legacy = "Adopt", differs = "Update", stale = "Update", ok = "Up to date" }
local quickSearch = ""

local function QuickItems()
    local out = {}
    local q = quickSearch:lower()
    local function match(...)
        if q == "" then return true end
        local hay = table.concat({ ... }, "\n"):lower()
        for w in q:gmatch("%S+") do if not hay:find(w, 1, true) then return false end end
        return true
    end
    for _, t in ipairs(ns.Templates()) do
        if match(t.title, t.desc, t.body) then
            local i = ns.Resolve("t:" .. t.id)
            out[#out + 1] = { t = t, ref = i and ns.GameRef(i) or nil }
        end
    end
    for _, e in ipairs(ns.Entries()) do
        if match(e.spell, e.key, e.desc or "", e.body) then out[#out + 1] = { e = e, ref = e.index and ns.GameRef(e.index) or nil } end
    end
    return out
end
ns.QuickItems = QuickItems

app:Section("builder", "Mouseover builder", function(stack)
    UI.Header(stack, "Build a mouseover macro", "One button for your spells: the friend under your mouse gets one spell, the enemy under it the other. "
        .. "Pick either or both. It never casts on you.")
    local friend = SpellPicker(stack, {
        label = "On a friend", placeholder = "Type a spell: Flash Heal",
        desc = "Cast on the friendly player under your mouse (and your friendly target, with the fallback on).",
        get = function() return bd.friend or "" end,
        set = function(v) bd.friend = v; bd.friendRank = nil end,
    })
    UI.Dropdown(stack, {
        label = "Friend's rank", width = 220, search = false,
        items = function()
            local out = { { value = 0, text = "Highest rank" } }
            for r = (MaxRank(bd.friend) or 0), 1, -1 do out[#out + 1] = { value = r, text = "Rank " .. r } end
            return out
        end,
        get = function() return bd.friendRank or 0 end, set = function(v) bd.friendRank = v ~= 0 and v or nil end,
        disabled = function() return (MaxRank(bd.friend) or 0) < 2 end,
    })
    local enemy = SpellPicker(stack, {
        label = "On an enemy", placeholder = "Type a spell: Devouring Plague",
        desc = "Cast on the enemy under your mouse (and your enemy target, with the fallback on).",
        get = function() return bd.enemy or "" end,
        set = function(v) bd.enemy = v; bd.enemyRank = nil end,
    })
    UI.Dropdown(stack, {
        label = "Enemy's rank", width = 220, search = false,
        items = function()
            local out = { { value = 0, text = "Highest rank" } }
            for r = (MaxRank(bd.enemy) or 0), 1, -1 do out[#out + 1] = { value = r, text = "Rank " .. r } end
            return out
        end,
        get = function() return bd.enemyRank or 0 end, set = function(v) bd.enemyRank = v ~= 0 and v or nil end,
        disabled = function() return (MaxRank(bd.enemy) or 0) < 2 end,
    })
    ns.builderFriend, ns.builderEnemy = friend, enemy
    UI.Toggle(stack, { label = "Fall back to my target", search = false,
        desc = "With nobody under the mouse, it casts on your target (a friend gets the friend's spell, an enemy the enemy's).",
        get = function() return bd.fallback end, set = function(v) bd.fallback = v end })
    UI.Toggle(stack, { label = "Stop casting first", search = false,
        desc = "Cancels the spell you are casting, for an interrupt or an emergency heal.",
        get = function() return bd.stop end, set = function(v) bd.stop = v end })
    UI.Toggle(stack, { label = "Power Infusion whisper", search = false,
        desc = "Whispers a funny line to whoever gets Power Infusion (once a minute per person).",
        get = function() return bd.whisper end, set = function(v) bd.whisper = v end,
        disabled = function() return bd.friend ~= "Power Infusion" and bd.enemy ~= "Power Infusion" end })
    UI.Input(stack, {
        label = "Name", width = 220, search = false,
        get = function() return BuiltName() or "" end,
        set = function(v) bd.name = v end,
    })
    UI.Note(stack, function()
        local body = Built()
        if not body then return "|cff8d94a3The macro shows here as you pick spells.|r" end
        local n = #body
        return "|cffffffff" .. Esc(body) .. "|r\n" .. (n > ns.MAX_BODY and "|cffff6060" or "|cff62cf88") .. n .. " / " .. ns.MAX_BODY .. " characters|r"
    end)
    ns.builderCreate = UI.ButtonRow(stack, {
        { label = "Create", width = 150, style = "accent", onClick = function() ns.CreateBuilt() end,
            desc = "Saves it in a free macro slot (character, else account) and puts it on your cursor: drop it on an action bar." },
        search = false,
        refresh = function(row)
            local name = Built() and BuiltName()
            row.buttons[1]:SetText(name and pending["build:" .. name] and "Cancel" or "Create")
            row.buttons[1]:SetUsable(name ~= nil)
        end,
    }).buttons[1]

    UI.Header(stack, "Quick picks", "Ready-made macros for your class: Create makes one (or brings it up to date). "
        .. "The switches choose what \"Make my whole mouseover set\" makes.")
    local qs = UI.Input(stack, {
        placeholder = "Search: devouring, heal, trinkets...", width = 300, search = false,
        onChange = function(text) quickSearch = text or ""; stack:RefreshAll() end,
    })
    ns.quickSearch = qs.box
    UI.ButtonRow(stack, {
        { label = "Make my whole mouseover set", width = 230, onClick = function() ns.InstallAll() end,
            desc = "Every switched-on macro of the set for spells you know. Ours are edited in place, so your bars keep working." },
        { label = "All on", width = 80, onClick = function()
            for _, e in ipairs(ns.Entries()) do ns.SetOn(e.key, true) end
            app:Refresh()
        end },
        { label = "All off", width = 80, onClick = function()
            for _, e in ipairs(ns.Entries()) do ns.SetOn(e.key, false) end
            app:Refresh()
        end },
        search = false,
    })
    local quick = UI.List(stack, {
        items = QuickItems,
        rowHeight = 40,
        empty = "Nothing ready-made matches.",
        toggle = {
            get = function(it) return it.e and it.e.on or false end,
            set = function(it, on) if it.e then ns.SetOn(it.e.key, on) end end,
        },
        icon = function(it)
            if it.e then return ns.SpellIcon(it.e.spell) end
            local first = ns.WhatItDoes(it.t.body):match("^[^,]+")
            return first and ns.SpellIcon(first) or QM
        end,
        title = function(it)
            if it.t then return Esc(it.t.title) .. (it.ref and ("  |cff8d94a3" .. Esc(it.ref.name) .. "|r") or "") end
            return Esc(it.e.spell) .. "  |cff8d94a3" .. Esc(it.e.macro) .. "|r"
        end,
        detail = function(it)
            if ns.queue.keys[it.e and it.e.key or ""] or ns.queue.all and it.e then return "|cffffd27fCreating after combat...|r" end
            if it.t then
                if pending["tmpl:" .. it.t.id] then return "|cffffd27fMaking after combat...|r" end
                return "|cff8d94a3" .. Esc(it.t.desc) .. "|r"
            end
            local e = it.e
            if e.clash then return "|cffffb347" .. ns.ClashNote(e) .. "|r" end
            if e.deleted and not e.index then return "|cff8d94a3you deleted it - Create makes it again|r" end
            if not e.known and not e.index then return "|cff8d94a3not learned yet - made when you learn it|r" end
            return ns.STATUS[e.status] .. ns.Where(e) .. "  |cff8d94a3-  " .. e.desc .. "|r"
        end,
        tooltip = function(it)
            if it.t then
                local out = { it.t.title, it.t.desc, " " }
                for l in it.t.body:gmatch("[^\n]+") do out[#out + 1] = Esc(l) end
                return out
            end
            local e = it.e
            local t = { e.key .. " - " .. e.spell, e.desc .. (e.why and (" (" .. e.why .. ")") or ""),
                (e.known and "" or "|cff8d94a3Not learned yet.|r ") .. (e.default and "On by default." or "Off by default (situational)."),
                ns.STATUS[e.status] .. ns.Where(e), "Macro name: " .. e.macro .. (e.index and "" or " (when created)") }
            if e.clash then t[#t + 1] = "|cffffb347" .. ns.ClashNote(e) .. "|r" end
            t[#t + 1] = " "
            t[#t + 1] = Esc(e.body)
            return PickUpTip(t)
        end,
        onClick = function(it) if it.ref then ns.Edit(it.ref) end end,
        drag = function(it) if it.ref then PickUp(it.ref) end end,
        buttons = {
            { width = 90,
                label = function(it)
                    if it.e then return QUICK_BUTTON[it.e.status] end
                    if pending["tmpl:" .. it.t.id] then return "Cancel" end
                    return it.ref and "Update" or "Create"
                end,
                usable = function(it) return not it.e or it.e.status ~= "ok" end,
                onClick = function(it)
                    if it.e then ns.InstallOne(it.e) return end
                    local id = "tmpl:" .. it.t.id
                    if pending[id] then CancelLater(id) return end
                    Later(id, it.t.title .. " will be made", "Making after combat", function() Say(ns.MakeTemplate(it.t)) end)
                end },
            { label = "Put on bar", width = 84, shown = function(it) return it.ref ~= nil end, onClick = function(it) PickUp(it.ref) end },
        },
    })
    ns.quickList = quick
    UI.Note(stack, "Switched-on macros for spells you know are also made on a character's first login (see Options), and spells you learn later get theirs then. "
        .. "/mom only ever changes the _mom macros it made itself.")
end, { icon = "target", desc = "A mouseover macro for your spells in a few clicks; ready-made ones for your class." })

------------------------------------------------------------------------
-- Backups: the bin, export and import
------------------------------------------------------------------------
local exportWhich, importAs = "mine", "same"
app:Section("backups", "Backups", function(stack)
    UI.Header(stack, "Deleted macros", "The last 100 macros deleted here. Restore makes them again (in the other kind of slot when its own is full).")
    UI.List(stack, {
        items = function() return ns.db.bin end,
        rowHeight = 40,
        empty = "Nothing deleted.",
        icon = function(b) return b.icon or QM end,
        title = function(b) return Esc(b.name) .. "  |cff8d94a3" .. ScopeWord(b.scope) .. "|r" end,
        detail = function(b)
            if pending["restore:" .. tostring(b)] then return "|cffffd27fRestoring after combat...|r" end
            return "|cff8d94a3" .. Date(b.t) .. "  -  " .. Esc(FirstLine(b.body)) .. "|r"
        end,
        tooltip = function(b)
            local t = { b.name, Date(b.t), " " }
            for l in (b.body or ""):gmatch("[^\n]+") do t[#t + 1] = Esc(l) end
            return t
        end,
        buttons = { { label = function(b) return pending["restore:" .. tostring(b)] and "Cancel" or "Restore" end, width = 80, onClick = function(b)
            local id = "restore:" .. tostring(b)
            if pending[id] then CancelLater(id) return end
            Later(id, b.name .. " will be restored", "Restoring after combat", function() Say(RestoreNow(b)) end)
        end } },
    })

    UI.Header(stack, "Export", "A set of macros as text, to keep or to give to a friend. Click the text, Ctrl+A, Ctrl+C.")
    UI.Dropdown(stack, {
        label = "Which macros", width = 260,
        items = { { value = "mine", text = "Made by /mom" }, { value = "account", text = "Account macros" },
            { value = "char", text = "This character's macros" }, { value = "all", text = "All of them" } },
        get = function() return exportWhich end, set = function(v) exportWhich = v end,
    })
    local out = UI.TextArea(stack.parent, stack.width, 90)
    stack:Add(out, 90)
    ns.exportBox = out.box
    UI.ButtonRow(stack, { { label = "Export", width = 120, onClick = function()
        local refs = exportWhich == "all" and ns.List(nil) or ns.List(exportWhich)
        out.box:SetText(ns.Export(refs))
        out.box:SetFocus()
        out.box:HighlightText()
        app:Print(("exported %d macro%s."):format(#refs, #refs == 1 and "" or "s"))
    end } })

    UI.Header(stack, "Import", "Paste an export, choose where the macros go, Import. Nothing is replaced: a name that is taken gets a number.")
    UI.Dropdown(stack, {
        label = "Import as", width = 260,
        items = { { value = "same", text = "As they were exported" }, { value = "c", text = "Character macros" }, { value = "a", text = "Account macros" } },
        get = function() return importAs end, set = function(v) importAs = v end,
    })
    local inp = UI.TextArea(stack.parent, stack.width, 90)
    stack:Add(inp, 90)
    ns.importBox = inp.box
    UI.ButtonRow(stack, { { label = "Import", width = 120, style = "accent", onClick = function()
        local list, err = ns.ParseExport(inp.box:GetText())
        if not list then Say(false, err) return end
        local ok, msg = ns.Import(list, importAs ~= "same" and importAs or nil)
        if ok then inp.box:SetText("") end
        Say(ok, msg)
    end } })
end)

app:Section("options", "Options", function(stack)
    UI.Header(stack, "Options")
    app:Widget(stack, "takeover")
    app:Widget(stack, "where")
    app:Widget(stack, "autoselfcast")
    app:Widget(stack, "autosetup")
    UI.Note(stack, "Slots: the game allows " .. ns.MaxAccount() .. " account macros and " .. ns.MaxChar() .. " per character, 255 characters each; no addon can raise that. "
        .. "Account macros are on all your characters: when your character macros are full, new ones go there.")
end)

------------------------------------------------------------------------
-- Saved variables and login
------------------------------------------------------------------------
ns.OnLoad = function(db, cdb)
    UI.Util.FillDefaults(db, ns.MANAGER_DEFAULTS)
    UI.Util.FillDefaults(cdb, ns.MANAGER_CHAR_DEFAULTS)
end
-- extended macros of 0.3.9 become normal macros; the ring's key (out of combat)
ns.OnWorld = function()
    ns.Defer("setting up", function() ns.MigrateExt(); ns.ApplyBindings() end, false)
end

app:Command("new", "new [account|char]", "open the editor on a new macro", function(rest)
    local as = (rest or ""):match("^%s*(%a+)")
    ns.EditNew(as == "account" and "account" or as == "char" and "char" or nil)
end)
app:Command("build", "build", "open the mouseover builder", function() app:Open("builder") end, { "mouseover" })
app:Command("undo", "undo", "put the last deleted macro(s) back", function() ns.Undo() end)
app:Command("blizzard", "blizzard", "open Blizzard's own macro window (also while /macro opens this one)", function() ns.OpenBlizzard() end)

------------------------------------------------------------------------
-- /macro and Blizzard's macro window
------------------------------------------------------------------------
-- /macro is an ordinary slash command (SlashCmdList.MACRO; the secure ones live in a separate list
-- addons can't reach), so replacing that entry is safe. The game menu's and the chat menu's "Macros"
-- call ShowMacroFrame(): a hooksecurefunc hook (Blizzard's function itself is never replaced) opens ours
-- next to it. Blizzard's window is never closed by /mom (no Hide-UI-panel calls): both stay open, side by side,
-- and the player closes each one when they like (NoAutoClose / BlizzMove users rely on that).
local allowBlizzard -- Blizzard's window was opened on purpose (/mom blizzard, our buttons): leave it
local blizzSlash

local function Takeover() return not ns.db or ns.db.takeover ~= false end

-- The page /macro opens: the Macros page (with the editor as it was, unsaved changes included).
function ns.OpenForMacro() app:Open("macros") end

local function ShowBlizzard()
    allowBlizzard = true
    if ShowMacroFrame then
        ShowMacroFrame()
    elseif C_AddOns and C_AddOns.LoadAddOn and C_AddOns.LoadAddOn("Blizzard_MacroUI") and MacroFrame_Show then
        MacroFrame_Show()
    end
    if not (MacroFrame and MacroFrame:IsShown()) then allowBlizzard = nil end
end

ns.ShowBlizzardMacros = ShowBlizzard

-- Blizzard's own macro window, whatever the setting. Ours closes (asking first about unsaved changes).
function ns.OpenBlizzard()
    if app:IsShown() then
        if Dirty() then return ns.Guard(function() baseClose(app); ShowBlizzard() end) end
        baseClose(app)
    end
    ShowBlizzard()
end

if SlashCmdList then
    blizzSlash = SlashCmdList.MACRO
    local function slash(msg)
        if Takeover() or not blizzSlash then ns.OpenForMacro() else blizzSlash(msg) end
    end
    SlashCmdList.MACRO = slash
    -- the chat box caches a command's function on first use: point a cached /macro at ours too
    if type(hash_SlashCmdList) == "table" then
        for i = 1, 9 do
            local cmd = _G["SLASH_MACRO" .. i]
            if type(cmd) == "string" and hash_SlashCmdList[cmd:upper()] then hash_SlashCmdList[cmd:upper()] = slash end
        end
    end
end

if type(ShowMacroFrame) == "function" then
    hooksecurefunc("ShowMacroFrame", function()
        if allowBlizzard or not Takeover() then return end
        ns.OpenForMacro() -- ours opens too; Blizzard's stays open
    end)
end

-- A button in Blizzard's macro window that opens ours (Blizzard_MacroUI loads when first opened).
local macroButton
local function OnMacroUI()
    if macroButton or not MacroFrame then return end
    macroButton = CreateFrame("Button", nil, MacroFrame, "UIPanelButtonTemplate")
    macroButton:SetSize(84, 22)
    macroButton:SetPoint("BOTTOMLEFT", MacroFrame, "BOTTOMLEFT", 88, 4) -- between Delete and New
    macroButton:SetText("Open /mom")
    macroButton:SetScript("OnClick", function()
        ns.OpenForMacro() -- ours opens next to it; Blizzard's window stays open
    end)
    macroButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("EverlookDB Macros", 1, 1, 1)
        GameTooltip:AddLine("Opens /mom: the macro editor, the mouseover builder, backups and the ring.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    macroButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    MacroFrame:HookScript("OnHide", function() allowBlizzard = nil end)
    ns.macroButton = macroButton
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name) if name == "Blizzard_MacroUI" then OnMacroUI() end end)
OnMacroUI()
