-- MouseoverMacros: the /mom window. Sidebar: Mine, Account, Character, Extended, Templates, Edit,
-- Backups, Options.
local _, ns = ...
local UI = LibStub("EverlookUI-1")
local app = ns.app
local QM = ns.QUESTION_MARK

-- Messages carry macro names, which may hold a "|": escaped so chat shows them as typed.
local function Say(ok, msg)
    if msg and msg ~= "queued" then app:Print((ok and "" or "|cffff6060") .. UI.Util.Escape(msg) .. (ok and "" or "|r")) end
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

local function Esc(s) return UI.Util.Escape(s or "") end

------------------------------------------------------------------------
-- The editor's state
------------------------------------------------------------------------
-- ed.ref: the macro being edited (nil: a new one); ed.as: for a new one, "char", "account" or "ext".
-- ed.base: what the editor held when it was opened or last saved (unsaved changes are measured against it).
-- ed.pending: a save waiting for combat to end; ed.status: how the last save after combat went.
local ed = { name = "", icon = QM, body = "", as = "char" }
ns.ed = ed

local function Snapshot() ed.base = { name = ed.name, icon = ed.icon, body = ed.body, as = ed.as } end
Snapshot()

-- Unsaved changes: the name, icon or text, or (a new macro) its kind. A save waiting for combat is a
-- save already chosen (it saves the latest text), so it doesn't count.
local function Dirty()
    if ed.pending then return false end
    local b = ed.base
    return ed.name ~= b.name or ed.icon ~= b.icon or ed.body ~= b.body or (ed.ref == nil and ed.as ~= b.as)
end
ns.EditorDirty = Dirty

local function Values() return { ref = ed.ref, as = ed.as, name = ns.Trim(ed.name), icon = ed.icon, body = ed.body } end

-- Leaving a macro whose save waits for combat: that save keeps the text as it is now.
local function Detach()
    local p = ed.pending
    if p then p.values, p.live, ed.pending = Values(), false, nil end
    ed.status = nil
end

local function OpenRef(ref)
    Detach()
    ref = ns.Fresh(ref) or ref
    ed.ref = ref
    ed.name, ed.icon, ed.body = ref.name, ref.icon or QM, ref.body or ""
    ed.picking = false
    Snapshot()
    app:Open("edit")
    app:Refresh()
end

local function OpenNew(as)
    Detach()
    ed.ref = nil
    ed.as = as or "char"
    ed.name, ed.icon, ed.body = "", QM, "#showtooltip\n"
    ed.picking = false
    Snapshot()
    app:Open("edit")
    app:Refresh()
end

local function EdKind() return ed.ref and ed.ref.kind or (ed.as == "ext" and "ext" or "game") end
local function EdLimit() return EdKind() == "ext" and ns.MAX_EXT or ns.MAX_BODY end

-- Save v ({ ref, as, name, icon, body }) now (out of combat). Returns ok, message, the saved macro.
local function SaveNow(v, asCopy)
    local ok, msg, id, ref
    local name, icon, body = v.name, v.icon, v.body
    if v.ref and not asCopy then
        if v.ref.kind == "ext" then
            ok, msg = ns.SaveExt(v.ref, name, icon, body)
            if ok then ref = ns.ExtRef(v.ref.id) end
        else
            ok, msg = ns.SaveGame(v.ref, name, icon, body)
            if ok then ref = ns.Fresh({ kind = "game", scope = v.ref.scope, name = name }) end
        end
    else
        local as = v.ref and (v.ref.kind == "ext" and "ext" or v.ref.scope) or v.as
        if asCopy and v.ref and as ~= "ext" and ns.EachMacro(as, function(_, n) return n == name end) then
            name = name:sub(1, ns.MAX_NAME - 2) .. " 2"
        end
        if as == "ext" then
            ok, msg, id = ns.CreateExt(name, icon, body)
            if ok and id then ref = ns.ExtRef(id) end
        else
            ok, msg = ns.CreateGame(as, name, icon, body)
            if ok then ref = ns.Fresh({ kind = "game", scope = as, name = name }) end
        end
    end
    return ok, msg, ref
end

-- The editor now holds the saved macro: no longer "New ...", and nothing unsaved.
local function Saved(ref)
    if ref then ed.ref = ref; ed.name = ref.name end
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
        local err = ns.CheckText(v.name, v.body, EdLimit())
        if err then Say(false, err) return false, err end
        local p = { live = true, asCopy = asCopy }
        ed.pending = p
        ns.Defer("saving " .. Esc(v.name), function() FinishPending(p) end)
        app:Refresh()
        return true, "queued"
    end
    local ok, msg, ref = SaveNow(v, asCopy)
    if ok then Saved(ref) end
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
    if not ref or not cur or ref.kind ~= cur.kind then return false end
    if ref.kind == "ext" then return ref.id == cur.id end
    return ref.scope == cur.scope and ref.name == cur.name
end

function ns.Edit(ref)
    -- the macro already in the editor, with changes or a save waiting: just show it
    if SameAsEditor(ref) and (Dirty() or ed.pending) then app:Open("edit") return end
    ns.Guard(function() OpenRef(ref) end)
end

function ns.EditNew(as) ns.Guard(function() OpenNew(as) end) end

-- Leaving the editor page and closing the window ask first too (sidebar, x, Escape, /mom).
local baseShowSection, baseClose, baseCreateWindow = app.ShowSection, app.Close, app.CreateWindow
function app:ShowSection(id)
    if self.current == "edit" and id ~= "edit" and self:IsShown() and Dirty() then
        return ns.Guard(function() baseShowSection(self, id) end)
    end
    return baseShowSection(self, id)
end
function app:Close()
    if self:IsShown() and Dirty() then return ns.Guard(function() baseClose(self) end) end
    return baseClose(self)
end
function app:CreateWindow()
    local f = baseCreateWindow(self)
    f.close:SetScript("OnClick", function() app:Close() end)
    local onKey = f:GetScript("OnKeyDown")
    f:SetScript("OnKeyDown", function(frame, key)
        if key == "ESCAPE" and Dirty() and not UI.IsPopupShown() then
            if not InCombatLockdown() then frame:SetPropagateKeyboardInput(false) end
            app:Close()
            return
        end
        if onKey then onKey(frame, key) end
    end)
    return f
end

------------------------------------------------------------------------
-- Lists of macros
------------------------------------------------------------------------
local filters = {}

local function Matches(ref, text)
    if not text or text == "" then return true end
    text = text:lower()
    return ref.name:lower():find(text, 1, true) or (ref.body or ""):lower():find(text, 1, true)
end

local function CountsLine()
    local a, maxA, c, maxC, x = ns.Counts()
    local function col(n, max) return n >= max and "|cffff8a8a" or "|cffffffff" end
    return ("Account %s%d/%d|r   Character %s%d/%d|r   Extended |cffffffff%d|r (no slots)"):format(
        col(a, maxA), a, maxA, col(c, maxC), c, maxC, x)
end
ns.CountsLine = CountsLine

local function PickUp(ref)
    if ref.kind == "ext" then
        local bar = ns.ExtBarMacro(ref.id)
        if bar and PickupMacro then PickupMacro(bar.index) end
        return
    end
    local cur = ns.Fresh(ref)
    if cur and PickupMacro then PickupMacro(cur.index) end
end
ns.PickUp = PickUp

local EMPTY = {
    mine = "Nothing made by /mom yet. Templates makes your class's mouseover set; \"New extended macro\" makes one past the slot limits.",
    account = "No account macros yet. \"New account macro\" makes one.",
    char = "No macros on this character yet. \"New character macro\" makes one.",
    ext = "No extended macros yet. \"New extended macro\" makes one; they need no slot.",
}

local function MacroList(stack, which)
    UI.Input(stack, {
        placeholder = "Search names and text", width = 300,
        onChange = function(text) filters[which] = text; stack:RefreshAll() end,
    })
    return UI.List(stack, {
        items = function()
            local out = {}
            for _, r in ipairs(ns.List(which)) do if Matches(r, filters[which]) then out[#out + 1] = r end end
            return out
        end,
        rowHeight = 40,
        empty = EMPTY[which] or "Nothing here.",
        icon = function(r) return r.icon or QM end,
        title = function(r)
            local tag = r.kind == "ext" and "  |cff40c0ffextended|r" or (r.ours and "  |cff62cf88made by /mom|r" or "")
            return Esc(r.name) .. tag
        end,
        detail = function(r) return "|cff8d94a3" .. ns.Cost(r) .. "  -  " .. Esc(FirstLine(r.body)) .. "|r" end,
        tooltip = function(r)
            local t = { r.name, ns.Cost(r), " " }
            for line in (r.body or ""):gmatch("[^\n]+") do t[#t + 1] = Esc(line) end
            return t
        end,
        onClick = function(r) ns.Edit(r) end,
        buttons = {
            { label = "Edit", width = 60, onClick = function(r) ns.Edit(r) end },
            { label = "Pick up", width = 70, onClick = function(r) PickUp(r) end,
                shown = function(r) return r.kind == "game" or ns.ExtBarMacro(r.id) ~= nil end },
        },
    })
end

app:Section("mine", "Mine", function(stack)
    UI.Header(stack, "Made by /mom", "Macros /mom made for you (_mom names) and your extended macros. Click one to edit it.")
    UI.Note(stack, CountsLine)
    UI.ButtonRow(stack, {
        { label = "New extended macro", width = 170, style = "accent", onClick = function() ns.EditNew("ext") end,
            desc = "Stored by /mom, up to 1023 characters, no macro slot. Run it with a key, or put it on a bar through a one-line macro (one slot)." },
    })
    MacroList(stack, "mine")
end)

app:Section("account", "Account", function(stack)
    UI.Header(stack, "Account macros", "Shared by all your characters. Yours and /mom's alike: edit any of them here.")
    UI.Note(stack, CountsLine)
    UI.ButtonRow(stack, { { label = "New account macro", width = 170, style = "accent", onClick = function() ns.EditNew("account") end } })
    MacroList(stack, "account")
end)

app:Section("char", "Character", function(stack)
    UI.Header(stack, "Character macros", "Only this character's. The game allows " .. ns.MaxChar() .. "; when they are full, use account or extended macros.")
    UI.Note(stack, CountsLine)
    UI.ButtonRow(stack, { { label = "New character macro", width = 170, style = "accent", onClick = function() ns.EditNew("char") end } })
    MacroList(stack, "char")
end)

app:Section("ext", "Extended", function(stack)
    UI.Header(stack, "Extended macros", "Past the slot limits: as many as you like, up to 1023 characters each, on every character. "
        .. "Each one runs from a hidden button. Give it a key (no slot), or \"Put on a bar\" makes a one-line macro that clicks it (one slot).")
    UI.Note(stack, CountsLine)
    UI.ButtonRow(stack, { { label = "New extended macro", width = 170, style = "accent", onClick = function() ns.EditNew("ext") end } })
    MacroList(stack, "ext")
end)

------------------------------------------------------------------------
-- Templates: the class's mouseover set and a few common ones
------------------------------------------------------------------------
local BUTTON = { new = "Create", missing = "Create", legacy = "Adopt", differs = "Update", ok = "Up to date" }

app:Section("templates", "Templates", function(stack)
    UI.Header(stack, "Mouseover set", "Switched-on macros are made by \"Create / update all\". /mom only ever changes the _mom macros it made itself; your own macros are never touched.")
    UI.ButtonRow(stack, {
        { label = "Create / update all", width = 180, style = "accent", onClick = function() ns.InstallAll() end,
            desc = "Every switched-on macro. Ours are edited in place, so your action bars keep working." },
        { label = "All on", width = 90, onClick = function() ns.db.off = {}; app:Refresh() end },
        { label = "All off", width = 90, onClick = function()
            for _, e in ipairs(ns.Entries()) do ns.db.off[e.key] = true end
            app:Refresh()
        end },
    })
    UI.List(stack, {
        items = ns.Entries,
        rowHeight = 40,
        empty = "No mouseover set for your class yet (Priest so far).",
        toggle = { get = function(e) return e.on end, set = function(e, on) ns.db.off[e.key] = (not on) or nil end },
        icon = function(e) return ns.SpellIcon(e.spell) end,
        title = function(e)
            local name = e.index and e.status ~= "legacy" and ("|cffffffff" .. e.macro .. "|r") or ("|cff8d94a3" .. e.macro .. "|r")
            return e.key .. "  " .. name .. "  |cff8d94a3" .. e.spell .. "|r"
        end,
        -- the state first: the row is too narrow for everything, and the tooltip has the rest
        detail = function(e)
            if e.clash then return "|cffffb347" .. ns.ClashNote(e) .. "|r" end
            return ns.STATUS[e.status] .. ns.Where(e) .. "  |cff8d94a3-  " .. e.desc .. "|r"
        end,
        tooltip = function(e)
            local t = { e.key .. " - " .. e.spell, e.desc, ns.STATUS[e.status] .. ns.Where(e),
                "Macro name: " .. e.macro .. (e.index and "" or " (when created)") }
            if e.clash then t[#t + 1] = "|cffffb347" .. ns.ClashNote(e) .. "|r" end
            t[#t + 1] = " "
            t[#t + 1] = Esc(e.body)
            return t
        end,
        buttons = {
            { label = function(e) return BUTTON[e.status] end,
                width = 90, onClick = function(e) ns.InstallOne(e) end, usable = function(e) return e.status ~= "ok" end },
            { label = "Pick up", width = 74, onClick = function(e) if e.index and PickupMacro then PickupMacro(e.index) end end,
                shown = function(e) return e.index ~= nil end },
        },
    })
    UI.Header(stack, "More templates", "Made as a _mom macro (one slot, /mom keeps it up to date) or as an extended macro (no slot).")
    UI.List(stack, {
        items = ns.Templates,
        rowHeight = 40,
        icon = function() return QM end,
        title = function(t)
            local i, name = ns.Resolve("t:" .. t.id)
            return t.title .. (i and ("  |cffffffff" .. name .. "|r") or "")
        end,
        detail = function(t) return "|cff8d94a3" .. t.desc .. "|r" end,
        tooltip = function(t)
            local out = { t.title, t.desc, " " }
            for line in t.body:gmatch("[^\n]+") do out[#out + 1] = Esc(line) end
            return out
        end,
        buttons = {
            { label = function(t) return ns.Resolve("t:" .. t.id) and "Update" or "Make" end, width = 70,
                onClick = function(t) Say(ns.MakeTemplate(t)) end },
            { label = "Extended", width = 80, onClick = function(t) Say(ns.MakeTemplate(t, true)) end },
        },
    })
    UI.Note(stack, "Pick up puts the macro on your cursor: drop it on an action bar slot. Bar addons show a macro's name under the button (\"_mom4821\"); Bartender4 can hide it with its \"Hide Macro Text\" option.")
end)

------------------------------------------------------------------------
-- Editor
------------------------------------------------------------------------
local INSERTS = {
    { "#showtooltip", "#showtooltip\n" }, { "/cast", "/cast " }, { "/use", "/use " }, { "/stopcasting", "/stopcasting\n" },
    { "mouseover friend", "[@mouseover,help,nodead][help,nodead] " }, { "mouseover enemy", "[@mouseover,harm,nodead][harm,nodead] " },
    { "mouseover any", "[@mouseover,exists,nodead][exists,nodead] " }, { "mouseover dead", "[@mouseover,help,dead][help,dead] " },
    { "focus", "[@focus,exists,nodead] " }, { "shift", "[mod:shift] " }, { "ctrl", "[mod:ctrl] " }, { "alt", "[mod:alt] " },
}

local ICON_COLS, ICON_ROWS, ICON_SIZE = 16, 4, 30

app:Section("edit", "Edit", function(stack)
    local T = stack.T
    UI.Note(stack, function()
        if ed.ref then
            return ("|cffffffff%s|r  -  %s%s"):format(Esc(ed.ref.name), ns.Cost(ed.ref),
                ed.ref.kind == "game" and not ed.ref.ours and "  |cff8d94a3(yours: /mom only changes it when you save it here)|r" or "")
        end
        local full = ed.as ~= "ext" and not ns.Room(ed.as)
        return "|cffffffffNew " .. (ed.as == "ext" and "extended" or ed.as == "account" and "account" or "character") .. " macro|r  -  " ..
            (ed.as == "ext" and "no slot" or "takes one " .. (ed.as == "account" and "account" or "character") .. " slot") ..
            (full and "  |cffff8a8a(all used: choose another kind below, or Extended, which needs no slot)|r" or "")
    end)
    UI.Dropdown(stack, {
        label = "Kind (new macros)", width = 260,
        items = { { value = "char", text = "Character macro (255)" }, { value = "account", text = "Account macro (255)" }, { value = "ext", text = "Extended macro (1023, no slot)" } },
        get = function() return ed.as end, set = function(v) ed.as = v end, after = function() app:Refresh() end,
        disabled = function() return ed.ref ~= nil end,
    })
    UI.Input(stack, {
        label = "Name", width = 260,
        get = function() return ed.name end, set = function(v) ed.name = v end,
        onChange = function(text) ed.name = text end,
    })

    -- icon: the current one, "Change icon" opens the picker
    local iconRow = CreateFrame("Frame")
    iconRow:SetParent(stack.parent)
    local tex = iconRow:CreateTexture(nil, "ARTWORK")
    tex:SetSize(26, 26)
    tex:SetPoint("LEFT")
    local change = UI.Button(iconRow, "Change icon", function() ed.picking = not ed.picking; stack:RefreshAll() end, 120)
    change:SetPoint("LEFT", 36, 0)
    local dyn = UI.Button(iconRow, "Icon from the spell", function() ed.icon = QM; stack:RefreshAll() end, 170)
    dyn:SetPoint("LEFT", change, "RIGHT", 8, 0)
    UI.Tooltip(dyn, "Icon from the spell", "Uses the question mark icon: with #showtooltip on the first line, the button shows the icon of the spell it will cast.")
    function iconRow:Refresh() tex:SetTexture(ed.icon or QM) end
    stack:Add(iconRow, 28)
    iconRow:Refresh()

    -- icon picker (shown while picking)
    local picker = CreateFrame("Frame")
    picker:SetParent(stack.parent)
    local search = UI.EditBox(picker, 240, 24)
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
        stack:SetHeightOf(self, ed.picking and pickerH or 1)
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
    stack:Add(picker, 1)
    picker:Refresh()

    -- the text
    local area = UI.TextArea(stack.parent, stack.width, 150)
    local box = area.box
    box:SetScript("OnTextChanged", function(self, user)
        if user then ed.body = self:GetText(); stack:RefreshAll() end
    end)
    function area:Refresh() if not box:HasFocus() then box:SetText(ed.body or "") end end
    stack:Add(area, 150)
    area:Refresh()
    ns.editorBox = box

    -- live count and line check
    UI.Note(stack, function()
        local n, limit = #(ed.body or ""), EdLimit()
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
    -- three rows of four: the page is 625 px wide (two rows of six ran past the window's edge)
    local rows = { {}, {}, {} }
    for i, d in ipairs(INSERTS) do
        local r = math.floor((i - 1) / 4) + 1
        local row = rows[r]
        row[#row + 1] = { label = d[1], width = r == 2 and 124 or 96, onClick = function() Insert(d[2]) end, desc = "Inserts " .. (d[2]:gsub("\n", "")) }
    end
    for _, row in ipairs(rows) do UI.ButtonRow(stack, row) end

    local saveRow = UI.ButtonRow(stack, {
        { label = "Save", width = 90, style = "accent", onClick = function() if not ed.pending then ns.EditorSave() end end },
        { label = "Save as copy", width = 120, onClick = function() if not ed.pending and ed.ref then ns.EditorSave(true) end end },
        { label = "Pick up", width = 80, onClick = function() if ed.ref then PickUp(ed.ref) end end },
        { label = "Move", width = 170, onClick = function()
            if not ed.ref or ed.ref.kind ~= "game" then return end
            local ok, msg = ns.MoveGame(ed.ref, ed.ref.scope == "account" and "char" or "account")
            if ok and msg ~= "queued" then ed.ref = ns.Fresh({ kind = "game", scope = ed.ref.scope == "account" and "char" or "account", name = ed.ref.name }) end
            Say(ok, msg)
        end, desc = "A moved macro is a new macro: put it on your bars again." },
        { label = "Delete", width = 90, confirm = true, onClick = function()
            if not ed.ref then return end
            local ok, msg
            local kind = ed.ref.kind == "ext" and "ext" or ed.ref.scope
            if ed.ref.kind == "ext" then ok, msg = ns.DeleteExt(ed.ref) else ok, msg = ns.DeleteGame(ed.ref) end
            Say(ok, msg)
            if ok and msg ~= "queued" then OpenNew(kind) end
        end },
        refresh = function(row)
            local b = row.buttons
            -- a save waiting for combat: Save and Save as copy greyed out (their tooltip says why)
            local waiting = ed.pending ~= nil
            b[3]:SetUsable(ed.ref ~= nil and (ed.ref.kind == "game" or ns.ExtBarMacro(ed.ref.id) ~= nil))
            b[4]:SetText(ed.ref and ed.ref.kind == "game" and (ed.ref.scope == "account" and "Move to character" or "Move to account") or "Move")
            b[4]:SetUsable(ed.ref ~= nil and ed.ref.kind == "game")
            b[5]:SetUsable(ed.ref ~= nil)
            b[2]:SetUsable(ed.ref ~= nil)
            b[1]:SetUsable(true)
            if waiting then b[1]:SetAlpha(0.4); b[2]:SetAlpha(0.4) end
        end,
    })
    for i = 1, 2 do
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
        if ed.pending then return "|cffffd27fWill save when combat ends.|r" end
        local s = ed.status
        if not s then return "" end
        return (s.ok and "|cff62cf88" or "|cffff6060") .. Esc(s.text) .. "|r"
    end)

    -- extended: key binding and bar macro
    -- a modifier on its own is not a key to bind (the Windows key neither: it opens the Start menu)
    local MODIFIER_ONLY = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true }
    local capture = CreateFrame("Frame", nil, UIParent)
    UI.Note(stack, function()
        if not ed.ref or ed.ref.kind ~= "ext" then return "" end
        local key = ns.cdb.binds[ed.ref.id]
        local bar = ns.ExtBarMacro(ed.ref.id)
        return ("Key on this character: |cffffffff%s|r   Bar macro: |cffffffff%s|r"):format(key or "none", bar and bar.name or "none")
            .. (capture:IsShown() and "\n|cffffd27fPress the key now (with Shift / Ctrl / Alt if you like); Escape cancels.|r" or "")
    end)
    capture:Hide()
    capture:EnableKeyboard(true)
    capture:SetFrameStrata("FULLSCREEN_DIALOG")
    capture:SetScript("OnKeyDown", function(self, key)
        if MODIFIER_ONLY[key] then return end -- keep waiting for a real key
        self:Hide()
        if key == "ESCAPE" then app:Print("key not changed."); app:Refresh() return end
        local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
        if ed.ref and ed.ref.kind == "ext" then Say(ns.BindExt(ed.ref, combo)) else app:Refresh() end
    end)
    -- closing the window or leaving the page cancels: a key pressed later (W to walk) must not be bound
    local function cancelCapture()
        if capture:IsShown() then capture:Hide(); app:Print("key not changed.") end
    end
    stack.parent:HookScript("OnHide", cancelCapture)
    if app.window then app.window:HookScript("OnHide", cancelCapture) end
    ns.keyCapture = capture
    UI.ButtonRow(stack, {
        { label = "Set key", width = 100, onClick = function()
            if not ed.ref or ed.ref.kind ~= "ext" then return end
            -- a second click while it waits cancels, so it never asks twice
            if capture:IsShown() then cancelCapture(); app:Refresh() return end
            capture:Show()
            app:Print("press the key (with Shift / Ctrl / Alt if you like) for " .. Esc(ed.ref.name) .. "; Escape cancels.")
            app:Refresh()
        end, desc = "Runs this macro on this character. While set it overrides what the key normally does." },
        { label = "Clear key", width = 100, onClick = function() if ed.ref and ed.ref.kind == "ext" then Say(ns.BindExt(ed.ref, nil)) end end },
        { label = "Put on a bar", width = 130, onClick = function()
            if not ed.ref or ed.ref.kind ~= "ext" then return end
            local ok, msg, index = ns.ExtToBar(ed.ref)
            if ok and index and PickupMacro then PickupMacro(index) end
            Say(ok, msg)
        end, desc = "Makes a one-line _mom macro that clicks this one (takes one slot) and puts it on your cursor." },
        refresh = function(row)
            local on = ed.ref ~= nil and ed.ref.kind == "ext"
            for _, b in ipairs(row.buttons) do b:SetShown(on) end
            row.buttons[1]:SetText(capture:IsShown() and "Press a key..." or "Set key")
        end,
    })

    -- backups of this macro
    UI.Header(stack, "Earlier versions", "Every save keeps the text it replaced (the last 10). Restore puts it in the editor; Save keeps it.")
    UI.List(stack, {
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
end)

------------------------------------------------------------------------
-- Backups: the bin, export and import
------------------------------------------------------------------------
local exportWhich, importAs = "mine", "same"
app:Section("backups", "Backups", function(stack)
    UI.Header(stack, "Deleted macros", "The last 20 macros deleted here. Restore makes them again (as an extended macro when there is no room).")
    UI.List(stack, {
        items = function() return ns.db.bin end,
        rowHeight = 40,
        empty = "Nothing deleted.",
        icon = function(b) return b.icon or QM end,
        title = function(b) return Esc(b.name) .. "  |cff8d94a3" .. (b.kind == "ext" and "extended" or b.scope == "account" and "account" or "character") .. "|r" end,
        detail = function(b) return "|cff8d94a3" .. Date(b.t) .. "  -  " .. Esc(FirstLine(b.body)) .. "|r" end,
        buttons = { { label = "Restore", width = 80, onClick = function(b)
            local kind = b.kind == "ext" and "x" or (b.scope == "account" and "a" or "c")
            if kind ~= "x" and not ns.Room(b.scope) then kind = "x" end
            local function restore()
                local ok, msg = ns.Import({ { kind = kind, icon = b.icon, name = b.name, body = b.body } })
                if ok then for i, x in ipairs(ns.db.bin) do if x == b then table.remove(ns.db.bin, i) break end end end
                Say(ok, msg)
            end
            ns.Defer("restoring " .. b.name, restore)
        end } },
    })

    UI.Header(stack, "Export", "A set of macros as text, to keep or to give to a friend. Click the text, Ctrl+A, Ctrl+C.")
    UI.Dropdown(stack, {
        label = "Which macros", width = 260,
        items = { { value = "mine", text = "Made by /mom and extended" }, { value = "account", text = "Account macros" },
            { value = "char", text = "This character's macros" }, { value = "ext", text = "Extended macros" }, { value = "all", text = "All of them" } },
        get = function() return exportWhich end, set = function(v) exportWhich = v end,
    })
    local out = UI.TextArea(stack.parent, stack.width, 90)
    stack:Add(out, 90)
    ns.exportBox = out.box
    UI.ButtonRow(stack, { { label = "Export", width = 120, onClick = function()
        local refs = exportWhich == "all" and ns.List(nil) or ns.List(exportWhich)
        if exportWhich == "all" then for _, r in ipairs(ns.List("ext")) do refs[#refs + 1] = r end end
        out.box:SetText(ns.Export(refs))
        out.box:SetFocus()
        out.box:HighlightText()
        app:Print(("exported %d macro%s."):format(#refs, #refs == 1 and "" or "s"))
    end } })

    UI.Header(stack, "Import", "Paste an export, choose where the macros go, Import. Nothing is replaced: a name that is taken gets a number.")
    UI.Dropdown(stack, {
        label = "Import as", width = 260,
        items = { { value = "same", text = "As they were exported" }, { value = "x", text = "Extended macros (no slots)" },
            { value = "c", text = "Character macros" }, { value = "a", text = "Account macros" } },
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
    app:Widget(stack, "where")
    app:Widget(stack, "autoselfcast")
    UI.Note(stack, "Slots: the game allows " .. ns.MaxAccount() .. " account macros and " .. ns.MaxChar() .. " per character, 255 characters each; no addon can raise that. Extended macros live in /mom instead and need no slot.")
end)

------------------------------------------------------------------------
-- Saved variables and login
------------------------------------------------------------------------
ns.OnLoad = function(db, cdb)
    UI.Util.FillDefaults(db, ns.MANAGER_DEFAULTS)
    UI.Util.FillDefaults(cdb, ns.MANAGER_CHAR_DEFAULTS)
end
ns.OnWorld = function() ns.SyncExt() end

app:Command("new", "new [ext|account|char]", "open the editor on a new macro", function(rest)
    local as = (rest or ""):match("^%s*(%a+)")
    as = as == "ext" and "ext" or as == "account" and "account" or "char"
    ns.EditNew(as)
end)
