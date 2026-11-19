-- MouseoverMacros: the Ring page of the /mom window and /mom ring in chat. Editing the ring: the key,
-- the 8 directions, sub-rings and their slices (drag spells, items, macros, mounts or equipment sets
-- onto a direction, or add a dynamic slice like "Best food"). Every change rebuilds the ring; in
-- combat the ring keeps what it had until combat ends.
local _, ns = ...
local R = ns.Ring
local UI = LibStub("EverlookUI-1")
local app = ns.app
local QM = ns.QUESTION_MARK

local function Ring() return ns.db.ring end
local function Esc(s) return UI.Util.Escape(s or "") end
local sel = 3 -- the direction being edited (right)
R.Selected = function() return sel end

------------------------------------------------------------------------
-- Changes
------------------------------------------------------------------------
-- After every change: rebuild (or wait for combat to end) and redraw.
local function Changed()
    if not R.Rebuild() then
        app:Print("|cffffb347in combat:|r the ring changes when combat ends.")
    end
    app:Refresh()
end
R.Changed = Changed

function R.SetSlot(i, slice) Ring().top[i] = slice or false end

-- Onto a direction: a sub-ring takes it as one more slice; a single slice or an empty one is replaced.
-- Returns ok, message.
function R.Drop(i, slice)
    local s = Ring().top[i]
    if s and s.kind == "ring" then
        s.items = s.items or {}
        if #s.items >= R.MAX_SUB then return false, "a sub-ring holds " .. R.MAX_SUB .. " slices" end
        s.items[#s.items + 1] = slice
        return true, ("%s: added %s to %s"):format(R.DIRS[i], R.Describe(slice), s.name or "the sub-ring")
    end
    Ring().top[i] = slice
    return true, ("%s: %s"):format(R.DIRS[i], R.Describe(slice))
end

-- A direction becomes a sub-ring (its slice, if any, goes in first), or back to a single slice.
function R.MakeSub(i, name)
    local s = Ring().top[i]
    if s and s.kind == "ring" then
        if name and name ~= "" then s.name = name end
        return
    end
    Ring().top[i] = { kind = "ring", name = (name and name ~= "") and name or R.DIRS[i], items = s and { s } or {} }
end
function R.MakeSingle(i)
    local s = Ring().top[i]
    if s and s.kind == "ring" then Ring().top[i] = (s.items and s.items[1]) or false end
end

function R.Swap(a, b)
    local top = Ring().top
    top[a], top[b] = top[b], top[a]
end

function R.MoveItem(i, k, delta)
    local s = Ring().top[i]
    local items = s and s.items
    if not items or not items[k] or not items[k + delta] then return end
    items[k], items[k + delta] = items[k + delta], items[k]
end

function R.RemoveItem(i, k)
    local s = Ring().top[i]
    if s and s.items and s.items[k] then table.remove(s.items, k) end
end

-- What is on the cursor, as a slice (and the cursor is cleared), or nil.
function R.FromCursor()
    if not GetCursorInfo then return nil end
    local kind, a, b, c, d = GetCursorInfo()
    local slice
    if kind == "spell" then
        local id = tonumber(c) or tonumber(d) or tonumber(a)
        local name = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        if id then slice = { kind = "spell", id = id, name = name } end
    elseif kind == "mount" and C_MountJournal and C_MountJournal.GetMountInfoByID then
        local name, spellID = C_MountJournal.GetMountInfoByID(a)
        if spellID then slice = { kind = "spell", id = spellID, name = name } end
    elseif kind == "item" then
        slice = { kind = "item", id = tonumber(a) }
    elseif kind == "macro" then
        local name = GetMacroInfo(a)
        if name then slice = { kind = "macro", name = name } end
    elseif kind == "equipmentset" then
        local name = a
        if type(a) == "number" and C_EquipmentSet and C_EquipmentSet.GetEquipmentSetInfo then name = C_EquipmentSet.GetEquipmentSetInfo(a) end
        if name then slice = { kind = "equipset", name = name } end
    end
    if slice and ClearCursor then ClearCursor() end
    return slice
end

local function DropCursor(i)
    local slice = R.FromCursor()
    if not slice then return false end
    local ok, msg = R.Drop(i, slice)
    app:Print((ok and "" or "|cffff6060") .. Esc(msg) .. (ok and "" or "|r"))
    Changed()
    return true
end

------------------------------------------------------------------------
-- Key capture: a key, a mouse button or the wheel (with modifiers). Left and right click alone are
-- never the ring key.
------------------------------------------------------------------------
local MODIFIER_ONLY = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true }
local MOUSE = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

function R.SetKey(key)
    if key then
        local plain = not key:find("-", 1, true)
        if plain and (key == "BUTTON1" or key == "BUTTON2") then
            return false, "left and right click can't be the ring key on their own (add Shift, Ctrl or Alt)"
        end
    end
    Ring().key = key
    local waited = not R.ApplyKey()
    return true, (key and ("ring key: " .. R.KeyText(key)) or "ring key cleared") .. (waited and " (after combat)" or "")
end

local capture
local function Capture()
    if capture then return capture end
    local c = CreateFrame("Frame", nil, UIParent)
    c:SetAllPoints(UIParent)
    c:SetFrameStrata("FULLSCREEN_DIALOG")
    c:EnableMouse(true)
    c:EnableKeyboard(true)
    if c.EnableMouseWheel then c:EnableMouseWheel(true) end
    UI.Util.Solid(c, "BACKGROUND", 0, 0, 0, 0.45):SetAllPoints()
    local text = UI.Text(c, 14, UI.Theme.text)
    text:SetPoint("CENTER")
    text:SetJustifyH("CENTER")
    text:SetText("Press the key or mouse button for the ring (with Shift / Ctrl / Alt if you like).\nEscape cancels.")
    c:Hide()
    local function done(key)
        c:Hide()
        if not key then app:Print("ring key not changed."); app:Refresh() return end
        local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
        local ok, msg = R.SetKey(combo)
        app:Print((ok and "" or "|cffff6060") .. msg .. (ok and "" or "|r"))
        app:Refresh()
    end
    c:SetScript("OnKeyDown", function(_, key)
        if MODIFIER_ONLY[key] then return end
        done(key ~= "ESCAPE" and key or nil)
    end)
    c:SetScript("OnMouseDown", function(_, button) done(MOUSE[button] or button) end)
    c:SetScript("OnMouseWheel", function(_, delta) done(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)
    capture = c
    R.capture = c
    return c
end

------------------------------------------------------------------------
-- The compass: 8 directions, click to edit one, drag one onto another to swap, drop a spell or item
------------------------------------------------------------------------
local TILE, RADIUS = 40, 66

local function SlotIcon(i)
    local e = R.layout and R.layout[0] and R.layout[0].slots[i]
    if e then return e.icon end
    return Ring().top[i] and QM or nil
end

local function Compass(stack)
    local T = stack.T
    local f = CreateFrame("Frame")
    f:SetParent(stack.parent)
    local cx, cy = 96, -96
    local hub = UI.Util.Solid(f, "ARTWORK", T.accent[1], T.accent[2], T.accent[3], 0.6)
    hub:SetSize(6, 6)
    hub:SetPoint("CENTER", f, "TOPLEFT", cx, cy)
    local info = UI.Text(f, T.font, T.text)
    info:SetPoint("TOPLEFT", 214, -14)
    info:SetPoint("RIGHT", -4, 0)
    f.info = info
    local ghost = f:CreateTexture(nil, "OVERLAY")
    ghost:SetSize(TILE - 6, TILE - 6)
    ghost:SetAlpha(0.8)
    ghost:Hide()
    local dragFrom
    f.tiles = {}
    for i = 1, R.MAX_TOP do
        local vx, vy = R.TopVector(i)
        local t = CreateFrame("Button", nil, f)
        t:SetSize(TILE, TILE)
        t:SetPoint("CENTER", f, "TOPLEFT", cx + vx * RADIUS, cy + vy * RADIUS)
        t.bg = UI.Util.Solid(t, "BACKGROUND", UI.Util.rgba(T.surface))
        t.bg:SetAllPoints()
        t.border = UI.Util.Border(t, 1, UI.Util.rgba(T.border))
        t.icon = t:CreateTexture(nil, "ARTWORK")
        t.icon:SetPoint("TOPLEFT", 3, -3)
        t.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t.more = UI.Util.Solid(t, "OVERLAY", T.accent[1], T.accent[2], T.accent[3], 0.9)
        t.more:SetSize(6, 6)
        t.more:SetPoint("TOPRIGHT", -1, -1)
        t.plus = UI.Text(t, T.fontHuge, T.muted)
        t.plus:SetPoint("CENTER")
        t.plus:SetText("+")
        t:RegisterForDrag("LeftButton")
        t:SetScript("OnClick", function()
            sel = i
            if not DropCursor(i) then app:Refresh() end
        end)
        t:SetScript("OnReceiveDrag", function() sel = i; DropCursor(i) end)
        t:SetScript("OnDragStart", function()
            if (GetCursorInfo and GetCursorInfo()) or not Ring().top[i] then return end
            dragFrom = i
            ghost:SetTexture(SlotIcon(i) or QM)
            ghost:Show()
            f:SetScript("OnUpdate", function()
                local x, y = GetCursorPosition()
                local s = f:GetEffectiveScale()
                ghost:ClearAllPoints()
                ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
            end)
        end)
        t:SetScript("OnDragStop", function()
            f:SetScript("OnUpdate", nil)
            ghost:Hide()
            local from = dragFrom
            dragFrom = nil
            if not from then return end
            for j, other in ipairs(f.tiles) do
                if j ~= from and other:IsMouseOver() then
                    R.Swap(from, j)
                    sel = j
                    app:Print(("swapped %s and %s"):format(R.DIRS[from], R.DIRS[j]))
                    Changed()
                    return
                end
            end
        end)
        t:SetScript("OnEnter", function(self)
            self.bg:SetVertexColor(UI.Util.rgba(T.surfaceHi))
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(R.DIRS[i], 1, 1, 1)
            GameTooltip:AddLine(R.Describe(Ring().top[i]), nil, nil, nil, true)
            GameTooltip:AddLine("Click to edit. Drag onto another direction to swap. Drop a spell, item, macro, mount or equipment set here.", 0.55, 0.58, 0.64, true)
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", function(self) self.bg:SetVertexColor(UI.Util.rgba(T.surface)); GameTooltip:Hide() end)
        f.tiles[i] = t
    end
    function f:Refresh()
        for i, t in ipairs(self.tiles) do
            local s = Ring().top[i]
            local icon = SlotIcon(i)
            t.icon:SetShown(icon ~= nil)
            if icon then t.icon:SetTexture(icon) end
            t.plus:SetShown(not s)
            t.more:SetShown(s and s.kind == "ring" or false)
            t.border:SetColor(UI.Util.rgba(i == sel and T.accent or T.border))
        end
        local s = Ring().top[sel]
        local lines = { ("|cffffffff%s|r"):format(R.DIRS[sel]), "|cff8d94a3" .. Esc(R.Describe(s)) .. "|r" }
        if s and s.kind == "ring" then
            local sub = R.layout and R.layout[sel]
            lines[#lines + 1] = "|cff8d94a3" .. (sub and sub.n or 0) .. " slices now on this character|r"
        end
        lines[#lines + 1] = " "
        lines[#lines + 1] = "|cff8d94a3Drop a spell, item, macro, mount or equipment set on a direction. Drag one direction onto another to swap them.|r"
        self.info:SetText(table.concat(lines, "\n"))
    end
    stack:Add(f, 196)
    f:Refresh()
    R.compass = f
    return f
end

------------------------------------------------------------------------
-- The page
------------------------------------------------------------------------
local function AddChoices()
    local out = {}
    for _, k in ipairs(R.DYNAMIC_ORDER) do out[#out + 1] = { value = "dyn:" .. k, text = R.DYNAMIC[k].label } end
    for _, x in ipairs(ns.List("ext")) do out[#out + 1] = { value = "ext:" .. x.id, text = "Extended: " .. x.name } end
    for _, s in ipairs(R.EquipmentSets()) do out[#out + 1] = { value = "set:" .. s.name, text = "Equipment set: " .. s.name } end
    return out
end

local function SliceFromChoice(v)
    local kind, rest = tostring(v):match("^(%a+):(.*)$")
    if kind == "dyn" then return { kind = rest } end
    if kind == "ext" then return { kind = "ext", id = tonumber(rest) } end
    if kind == "set" then return { kind = "equipset", name = rest } end
end

-- A page row shown only while cond() is true (it takes no room while hidden).
local function When(stack, w, cond)
    local e = w.stackEntry
    local h, gap = e.height, e.gap
    local base = w.Refresh
    function w:Refresh()
        local on = cond() and true or false
        self:SetShown(on)
        e.gap, e.height = on and gap or 0, on and h or 0
        stack:Relayout()
        if on and base then base(self) end -- a list sets its own height
    end
    local listed = false
    for _, x in ipairs(stack.widgets) do if x == w then listed = true end end
    if not listed then stack.widgets[#stack.widgets + 1] = w end
    w:Refresh()
    return w
end

app:Setting({
    key = "ring", type = "bool", label = "Ring on",
    desc = "Hold the ring key to open the ring. Off: the key does what it did before.",
    get = function() return Ring().on end, set = function(v) Ring().on = v end, after = function() R.ApplyKey() end,
})

app:Section("ring", "Ring", function(stack)
    UI.Header(stack, "Ring", "Hold the key, move the mouse toward a slice and let go. A sub-ring (blue corner) opens its own ring: "
        .. "click a slice, or press the key and let go toward it. Letting go in the middle, Escape or a right click closes it. Works in combat.")
    app:Widget(stack, "ring")
    UI.Note(stack, function()
        local r = Ring()
        local cap = capture and capture:IsShown()
        return ("Key: |cffffffff%s|r%s"):format(R.KeyText(r.key), r.on and "" or "  |cff8d94a3(the ring is off)|r")
            .. ((r.on and ns.ringReplaces) and ("\n|cff8d94a3Instead of " .. ns.ringReplaces .. " (your binding comes back when the ring key is cleared or the ring is off).|r") or "")
            .. (R.keyPending and "\n|cffffd27fThe key changes when combat ends.|r" or "")
            .. (cap and "\n|cffffd27fPress the key or mouse button now; Escape cancels.|r" or "")
    end)
    UI.ButtonRow(stack, {
        { label = "Set key", width = 110, style = "accent", onClick = function()
            local c = Capture()
            if c:IsShown() then c:Hide(); app:Print("ring key not changed.") else c:Show() end
            app:Refresh()
        end, desc = "Then press a key or a mouse button (middle, 4, 5, the wheel), with Shift / Ctrl / Alt if you like." },
        { label = "Middle mouse", width = 120, onClick = function() local ok, msg = R.SetKey("BUTTON3"); app:Print(msg); app:Refresh() end },
        { label = "Clear key", width = 100, onClick = function() local ok, msg = R.SetKey(nil); app:Print(msg); app:Refresh() end,
            desc = "No key: the key goes back to what it did before." },
    })
    stack.parent:HookScript("OnHide", function() if capture and capture:IsShown() then capture:Hide() end end)

    UI.Header(stack, "Directions", "Click a direction to edit it.")
    Compass(stack)

    local function isSub() local x = Ring().top[sel]; return x and x.kind == "ring" or false end
    UI.ButtonRow(stack, {
        { label = "Make sub-ring", width = 150, onClick = function()
            if isSub() then R.MakeSingle(sel) else R.MakeSub(sel) end
            Changed()
        end, desc = "A sub-ring opens a ring of its own (the slice here becomes its first). A single slice keeps the sub-ring's first." },
        { label = "Clear direction", width = 140, confirm = true, onClick = function()
            R.SetSlot(sel, false)
            Changed()
        end },
        refresh = function(row) row.buttons[1]:SetText(isSub() and "Make single slice" or "Make sub-ring") end,
    })
    When(stack, UI.Input(stack, {
        label = "Sub-ring name", width = 240,
        get = function() local x = Ring().top[sel]; return x and x.name or "" end,
        set = function(v)
            local x = Ring().top[sel]
            if x and x.kind == "ring" and UI.Util.Trim(v) ~= "" then x.name = UI.Util.Trim(v) end
        end,
        after = function() Changed() end,
    }), isSub)
    local function choose(v)
        local slice = SliceFromChoice(v)
        if not slice then return end
        local ok, msg = R.Drop(sel, slice)
        app:Print((ok and "" or "|cffff6060") .. Esc(msg) .. (ok and "" or "|r"))
        Changed()
    end
    local DESC = "Dynamic slices pick what fits now: the best food in your bags, the spells you know. Spells, items, macros, mounts and equipment sets: drag them onto a direction."
    When(stack, UI.Dropdown(stack, { label = "Add a slice to this sub-ring", width = 300, placeholder = "Choose...",
        items = AddChoices, get = function() return nil end, set = choose, desc = DESC }), isSub)
    When(stack, UI.Dropdown(stack, { label = "Set this direction to", width = 300, placeholder = "Choose...",
        items = AddChoices, get = function() return nil end, set = choose, desc = DESC }), function() return not isSub() end)
    When(stack, UI.List(stack, {
        items = function()
            local x = Ring().top[sel]
            local out = {}
            for k, item in ipairs(x and x.kind == "ring" and x.items or {}) do out[k] = { k = k, s = item } end
            return out
        end,
        rowHeight = 40,
        empty = "Nothing in this sub-ring yet: add a slice above, or drop a spell or item on the direction.",
        icon = function(row)
            local e = R.Expand(row.s, R.ctx or R.Context())[1]
            return e and e.icon or QM
        end,
        title = function(row) return Esc(R.Describe(row.s)) end,
        detail = function(row)
            local list = R.Expand(row.s, R.ctx or R.Context())
            if #list == 0 then return "|cff8d94a3nothing on this character now|r" end
            local names = {}
            for _, e in ipairs(list) do names[#names + 1] = Esc(e.label) end
            return "|cff8d94a3" .. table.concat(names, ", ") .. "|r"
        end,
        buttons = {
            { label = "Up", width = 44, onClick = function(row) R.MoveItem(sel, row.k, -1); Changed() end, usable = function(row) return row.k > 1 end },
            { label = "Down", width = 54, onClick = function(row) R.MoveItem(sel, row.k, 1); Changed() end,
                usable = function(row) local x = Ring().top[sel]; return x and x.items and row.k < #x.items or false end },
            { label = "Remove", width = 74, onClick = function(row) R.RemoveItem(sel, row.k); Changed() end },
        },
    }), isSub)
    UI.Header(stack, "Start over")
    UI.ButtonRow(stack, {
        { label = "Default ring", width = 140, confirm = true, onClick = function()
            local key, on = Ring().key, Ring().on
            ns.db.ring = R.Defaults()
            ns.db.ring.key, ns.db.ring.on = key, on
            Changed()
            app:Print("the ring is back to the default (your key stays).")
        end, desc = "Right: Consumables. Left: Professions. Down: Fishing. Up: Hearthstone." },
    })
    UI.Note(stack, "/mom ring help lists the chat commands.")
end)

-- The Ring page sits before Options in the sidebar.
do
    local order = app.order
    for i, id in ipairs(order) do
        if id == "ring" then table.remove(order, i) break end
    end
    local at = #order + 1
    for i, id in ipairs(order) do if id == "options" then at = i break end end
    table.insert(order, at, "ring")
end

------------------------------------------------------------------------
-- /mom ring ...
------------------------------------------------------------------------
-- A slice from chat text: a dynamic kind ("food"), a spell you know, or an item by name or ID.
local function SliceFromText(text)
    text = UI.Util.Trim(text)
    if text == "" then return nil end
    local lower = text:lower()
    if R.DYNAMIC[lower] then return { kind = lower } end
    for k, d in pairs(R.DYNAMIC) do if d.label:lower() == lower then return { kind = k } end end
    local itemID = tonumber(text:match("^item:(%d+)$") or text:match("^(%d+)$"))
    if itemID then return { kind = "item", id = itemID } end
    local sp = R.Spell(text)
    if sp then return { kind = "spell", id = sp.id, name = sp.name } end
    local id = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(text)
    if id then return { kind = "item", id = id } end
    if GetMacroIndexByName and (GetMacroIndexByName(text) or 0) > 0 then return { kind = "macro", name = text } end
end

local HELP = {
    "/mom ring - the Ring page",
    "/mom ring on | off",
    "/mom ring key <KEY> | middle | clear - e.g. BUTTON3, BUTTON4, SHIFT-F, ALT-BUTTON3",
    "/mom ring list - what each direction holds",
    "/mom ring set <direction> <slice> - one slice: food, drink, hpot, mpot, bandage, buffs, professions, fishing, hearthstone ..., a spell, an item name or ID, a macro",
    "/mom ring add <direction> <slice> - into that direction's sub-ring (made if needed)",
    "/mom ring sub <direction> [name] - make a direction a sub-ring (or rename it)",
    "/mom ring clear <direction>   /mom ring swap <direction> <direction>   /mom ring reset",
    "Directions: up, upright, right, downright, down, downleft, left, upleft (or 1-8).",
}

local function Say(ok, msg) app:Print((ok and "" or "|cffff6060") .. Esc(msg) .. (ok and "" or "|r")) end

local function RingCommand(rest)
    local verb, args = UI.Util.Trim(rest):match("^(%S*)%s*(.-)$")
    verb = (verb or ""):lower()
    if verb == "" then app:Open("ring") return end
    if verb == "help" then for _, l in ipairs(HELP) do DEFAULT_CHAT_FRAME:AddMessage("  " .. l) end return end
    if verb == "on" or verb == "off" then
        Ring().on = verb == "on"
        local waited = not R.ApplyKey()
        Say(true, "ring " .. verb .. (waited and " (the key changes after combat)" or ""))
        app:Refresh()
        return
    end
    if verb == "key" then
        local k = UI.Util.Trim(args):upper()
        if k == "" then Say(true, "ring key: " .. R.KeyText(Ring().key)) return end
        if k == "CLEAR" or k == "NONE" then Say(R.SetKey(nil)) elseif k == "MIDDLE" then Say(R.SetKey("BUTTON3")) else Say(R.SetKey(k)) end
        app:Refresh()
        return
    end
    if verb == "list" then
        DEFAULT_CHAT_FRAME:AddMessage(("  key %s, %s"):format(R.KeyText(Ring().key), Ring().on and "on" or "off"))
        for i = 1, R.MAX_TOP do
            local s = Ring().top[i]
            if s then
                local line = ("  |cff40c0ff%s|r %s"):format(R.DIRS[i], Esc(R.Describe(s)))
                if s.kind == "ring" then
                    local names = {}
                    for _, it in ipairs(s.items or {}) do names[#names + 1] = R.Describe(it) end
                    line = line .. ": " .. Esc(table.concat(names, ", "))
                end
                DEFAULT_CHAT_FRAME:AddMessage(line)
            end
        end
        return
    end
    if verb == "reset" then app:HandleReset("ring") return end -- asks first, like /mom reset ring
    local dirWord, tail = args:match("^(%S*)%s*(.-)$")
    local i = R.Dir(dirWord)
    if not i then Say(false, "which direction? up, upright, right, downright, down, downleft, left, upleft (or 1-8). /mom ring help") return end
    if verb == "clear" then
        R.SetSlot(i, false); Changed(); Say(true, R.DIRS[i] .. ": empty")
    elseif verb == "swap" then
        local j = R.Dir(tail)
        if not j then Say(false, "swap with which direction?") return end
        R.Swap(i, j); Changed(); Say(true, ("swapped %s and %s"):format(R.DIRS[i], R.DIRS[j]))
    elseif verb == "sub" then
        R.MakeSub(i, UI.Util.Trim(tail)); Changed(); Say(true, R.DIRS[i] .. ": " .. R.Describe(Ring().top[i]))
    elseif verb == "set" or verb == "add" then
        local slice = SliceFromText(tail)
        if not slice then Say(false, "no slice called '" .. tail .. "': a dynamic kind (food, buffs ...), a spell you know, an item or a macro") return end
        if verb == "set" then
            R.SetSlot(i, slice)
            Say(true, R.DIRS[i] .. ": " .. R.Describe(slice))
        else
            local cur = Ring().top[i]
            if not (cur and cur.kind == "ring") then R.MakeSub(i) end
            Say(R.Drop(i, slice))
        end
        Changed()
    else
        Say(false, "unknown: /mom ring " .. verb .. ". /mom ring help")
    end
end
R.Command = RingCommand

app:Command("ring", "ring [help|on|off|key|list|set|add|sub|clear|swap|reset]", "the ring: hold a key, flick toward a slice (/mom ring help)", RingCommand)
-- "/mom reset ring" (or "/mom ring reset"): the default slices back; your key and on/off stay. Asks first.
app:Reset("ring", "the ring's slices (your key stays)", function()
    local key, on = Ring().key, Ring().on
    ns.db.ring = R.Defaults()
    ns.db.ring.key, ns.db.ring.on = key, on
    Changed()
end)
