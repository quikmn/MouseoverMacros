-- MouseoverMacros: the ring. Hold the ring key (default: middle mouse button), move the mouse toward a
-- slice, let go: that slice is used. A sub-ring slice opens its own ring around the same point; then
-- click a slice (or press and let go of the key again toward it). Escape, a right click, or letting
-- go in the middle closes it.
--
-- Combat: everything that acts is secure. The key clicks MoMRingTrigger (a SecureActionButton); a
-- wrapped OnClick snippet runs in the restricted environment of MoMRingHeader: on the press it shows
-- the ring at the cursor, on the release it works out the direction from owner:GetMousePosition(),
-- copies the chosen slice's action (type/macrotext/macro attributes) onto the trigger, and lets the
-- click go on to SecureActionButton_OnClick, which does it. While a sub-ring is open a full-screen
-- MoMRingCatcher runs the same snippet for mouse clicks. Slices are SecureActionButtons holding their
-- action and direction as attributes; they are set out of combat only (rebuilt when bags, spells,
-- macros or equipment sets change, and frozen in combat: a change then waits for combat to end).
--
-- The picture is insecure: one plain frame per ring follows its secure frame's OnShow/OnHide, fades in
-- and out in 0.08 s and, only while shown, highlights the slice the cursor points at (OnUpdate).
local _, ns = ...

-- Events differ between clients (LEARNED_SPELL_IN_TAB is gone on Forever): register only ones that exist.
function ns.SafeRegister(frame, event)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then return false end
    return pcall(frame.RegisterEvent, frame, event)
end
local R = ns.Ring
local UI = LibStub("EverlookUI-1")

R.DEAD = 22          -- dead zone radius: letting go inside it does nothing
R.TILE = 38          -- a slice
R.RADIUS = 74        -- the top ring
R.FADE = 0.08        -- seconds
local RINGS = R.MAX_TOP -- sub-rings 1..8 (one per top slot) plus the top ring 0

local function SubRadius(n) return math.max(R.RADIUS, (n * (R.TILE + 12)) / (2 * math.pi)) end
R.SubRadius = SubRadius

-- The restricted snippet, shared by the trigger (the key) and the catcher (clicks while a sub-ring is
-- open). Globals here (MODE, CX, CY) live in the header's restricted environment. R.Pick is the same sum.
R.SNIPPET = [=[
    local isCatcher = self:GetAttribute("mom-catcher")
    local catcher = owner:GetFrameRef("catcher")
    local mx, my = owner:GetMousePosition()
    if MODE ~= nil and isCatcher and button == "RightButton" then
        owner:GetFrameRef("ring" .. MODE):Hide()
        catcher:Hide()
        owner:ClearBindings()
        MODE = nil
        return false
    end
    if down then
        if MODE == nil and not isCatcher and mx then
            CX, CY = mx * owner:GetWidth(), my * owner:GetHeight()
            owner:SetAttribute("cx", CX)
            owner:SetAttribute("cy", CY)
            local top = owner:GetFrameRef("ring0")
            top:ClearAllPoints()
            top:SetPoint("CENTER", owner, "BOTTOMLEFT", CX, CY)
            top:Show()
            MODE = 0
        end
        return false
    end
    if MODE == nil then return false end
    local ring = owner:GetFrameRef("ring" .. MODE)
    local pick
    if mx then
        local dx, dy = mx * owner:GetWidth() - CX, my * owner:GetHeight() - CY
        local d2 = dx * dx + dy * dy
        local dead = owner:GetAttribute("dead") or 0
        local outer = ring:GetAttribute("outer")
        if d2 >= dead * dead and not (isCatcher and outer and d2 > outer * outer) then
            local best
            for i = 1, 12 do
                local s = owner:GetFrameRef("s" .. MODE .. "_" .. i)
                if s and s:GetAttribute("on") then
                    local d = dx * s:GetAttribute("vx") + dy * s:GetAttribute("vy")
                    if best == nil or d > best then best, pick = d, s end
                end
            end
        end
    end
    ring:Hide()
    local sub = pick and pick:GetAttribute("sub")
    if sub then
        local r = owner:GetFrameRef("ring" .. sub)
        r:ClearAllPoints()
        r:SetPoint("CENTER", owner, "BOTTOMLEFT", CX, CY)
        r:Show()
        MODE = sub
        catcher:Show()
        owner:SetBindingClick(true, "ESCAPE", "MoMRingCatcher", "RightButton")
        return false
    end
    catcher:Hide()
    owner:ClearBindings()
    MODE = nil
    if not pick or not pick:GetAttribute("type") then return false end
    self:SetAttribute("type", pick:GetAttribute("type"))
    self:SetAttribute("macrotext", pick:GetAttribute("macrotext"))
    self:SetAttribute("macro", pick:GetAttribute("macro"))
    return button
]=]

------------------------------------------------------------------------
-- Secure frames (made once, at load, out of combat)
------------------------------------------------------------------------
local header, trigger, catcher
local ringFrames, slices = {}, {}   -- ringFrames[r], slices[r][i]
R.refs = {}                         -- the header's frame refs, by name (the tests read them)
R.displays = {}

local function Ref(name, frame)
    header:SetFrameRef(name, frame)
    R.refs[name] = frame
end

local ShowDisplay, HideDisplay

local function CreateSecure()
    header = CreateFrame("Frame", "MoMRingHeader", UIParent, "SecureHandlerBaseTemplate")
    header:SetAllPoints(UIParent)
    header:EnableMouse(false)
    header:SetAttribute("dead", R.DEAD)
    trigger = CreateFrame("Button", "MoMRingTrigger", UIParent, "SecureActionButtonTemplate")
    trigger:Hide()
    trigger:RegisterForClicks("AnyDown", "AnyUp")
    trigger:SetAttribute("useOnKeyDown", false) -- acts on the release, which is when the direction is known
    catcher = CreateFrame("Button", "MoMRingCatcher", header, "SecureActionButtonTemplate")
    catcher:SetAllPoints(header)
    catcher:SetFrameStrata("DIALOG")
    catcher:RegisterForClicks("AnyDown", "AnyUp")
    catcher:SetAttribute("useOnKeyDown", false)
    catcher:SetAttribute("mom-catcher", true)
    catcher:Hide()
    Ref("catcher", catcher)
    for r = 0, RINGS do
        local f = CreateFrame("Frame", nil, header, "SecureHandlerBaseTemplate")
        f:SetSize(1, 1)
        f:SetPoint("CENTER")
        f:Hide()
        f:SetScript("OnShow", function() ShowDisplay(r) end)
        f:SetScript("OnHide", function() HideDisplay(r) end)
        ringFrames[r] = f
        Ref("ring" .. r, f)
        slices[r] = {}
        for i = 1, (r == 0 and R.MAX_TOP or R.MAX_SUB) do
            local s = CreateFrame("Button", nil, f, "SecureActionButtonTemplate")
            s:EnableMouse(false)
            s:Hide()
            slices[r][i] = s
            Ref("s" .. r .. "_" .. i, s)
        end
    end
    SecureHandlerWrapScript(trigger, "OnClick", header, R.SNIPPET)
    SecureHandlerWrapScript(catcher, "OnClick", header, R.SNIPPET)
end
R.Frames = function() return header, trigger, catcher, ringFrames, slices end

------------------------------------------------------------------------
-- The picture (insecure)
------------------------------------------------------------------------
local T = UI.Theme
local accent = { 0.25, 0.75, 1.0 }

local function Tile(d)
    local t = CreateFrame("Frame", nil, d)
    t:SetSize(R.TILE, R.TILE)
    t.bg = UI.Util.Solid(t, "BACKGROUND", 0.055, 0.062, 0.078, 0.84)
    t.bg:SetAllPoints()
    t.border = UI.Util.Border(t, 1, 0.20, 0.22, 0.27, 0.9)
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetPoint("TOPLEFT", 3, -3)
    t.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t.cd = CreateFrame("Cooldown", nil, t, "CooldownFrameTemplate")
    t.cd:SetAllPoints(t.icon)
    if t.cd.SetDrawEdge then t.cd:SetDrawEdge(false) end
    if t.cd.SetHideCountdownNumbers then t.cd:SetHideCountdownNumbers(true) end
    t.count = UI.Text(t, 10, T.text, "OVERLAY")
    UI.Util.SetFont(t.count, 10, "OUTLINE")
    t.count:SetPoint("BOTTOMRIGHT", -2, 2)
    t.count:SetJustifyH("RIGHT")
    t.more = UI.Util.Solid(t, "OVERLAY", accent[1], accent[2], accent[3], 0.9) -- a sub-ring slice: accent corner
    t.more:SetSize(6, 6)
    t.more:SetPoint("TOPRIGHT", -1, -1)
    t.label = UI.Text(d, 11, T.text, "OVERLAY")
    UI.Util.SetFont(t.label, 11, "OUTLINE")
    t.label:SetWordWrap(false)
    t.label:SetJustifyH("CENTER")
    t.label:Hide()
    return t
end

local function SetHighlight(t, on)
    if on then
        t.border:SetColor(accent[1], accent[2], accent[3], 1)
        t.bg:SetVertexColor(0.10, 0.13, 0.17, 0.94)
        t:SetScale(1.12)
    else
        t.border:SetColor(0.20, 0.22, 0.27, 0.9)
        t.bg:SetVertexColor(0.055, 0.062, 0.078, 0.84)
        t:SetScale(1)
    end
    t.label:SetShown(on and true or false)
end

local function Secret(v) return issecretvalue and issecretvalue(v) or false end

-- Count (items) and cooldown swipe of a tile. Secret values are only handed to widgets.
local function UpdateTile(t, e)
    if not e then return end
    local greyed = e.missing or false
    t.count:SetText("")
    if e.itemID then
        local n = R.ItemCount(e.itemID)
        t.count:SetText(n > 1 and n or "")
        if n == 0 then greyed = true end
        local f = C_Container and C_Container.GetItemCooldown or GetItemCooldown
        local start, dur = nil, nil
        if f then start, dur = f(e.itemID) end
        if start and dur and not Secret(start) and not Secret(dur) and dur > 0 then t.cd:SetCooldown(start, dur) else t.cd:Clear() end
    elseif e.spell and C_Spell then
        if C_Spell.GetSpellCooldownDuration and t.cd.SetCooldownFromDurationObject then
            local obj = C_Spell.GetSpellCooldownDuration(e.spell)
            if obj then t.cd:SetCooldownFromDurationObject(obj) else t.cd:Clear() end
        elseif C_Spell.GetSpellCooldown then
            local info = C_Spell.GetSpellCooldown(e.spell)
            local start, dur = info and info.startTime, info and info.duration
            if start and dur and not Secret(start) and not Secret(dur) and dur > 0 then t.cd:SetCooldown(start, dur) else t.cd:Clear() end
        end
    else
        t.cd:Clear()
    end
    t.icon:SetDesaturated(greyed)
    t.icon:SetAlpha(greyed and 0.45 or 1)
end

local function NewDisplay(r)
    local d = CreateFrame("Frame", nil, UIParent)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:SetSize(1, 1)
    d:EnableMouse(false)
    d:Hide()
    d.r = r
    d.hub = UI.Util.Solid(d, "ARTWORK", accent[1], accent[2], accent[3], 0.55)
    d.hub:SetSize(6, 6)
    d.hub:SetPoint("CENTER")
    d.title = UI.Text(d, 11, T.muted, "OVERLAY")
    UI.Util.SetFont(d.title, 11, "OUTLINE")
    d.title:SetPoint("TOP", d, "CENTER", 0, -8)
    d.title:SetJustifyH("CENTER")
    d.tiles, d.vectors, d.entries, d.n = {}, {}, {}, 0
    d.alpha, d.target = 0, 0
    d:SetScript("OnUpdate", function(self, elapsed) R.DisplayUpdate(self, elapsed) end)
    R.displays[r] = d
    return d
end

-- Fill a ring's picture from its layout (out of combat, with the secure frames).
local function FillDisplay(r, ring)
    local d = R.displays[r] or NewDisplay(r)
    d.entries, d.vectors, d.n = {}, {}, ring.n
    d.title:SetText(ring.name or "")
    local radius = r == 0 and R.RADIUS or SubRadius(ring.n)
    d.outer = radius + R.TILE + 40
    for i = 1, math.max(ring.n, #d.tiles) do
        local e = ring.slots[i]
        local t = d.tiles[i]
        if e then
            t = t or Tile(d)
            d.tiles[i] = t
            t:ClearAllPoints()
            t:SetPoint("CENTER", d, "CENTER", e.vx * radius, e.vy * radius)
            t.icon:SetTexture(e.icon or ns.QUESTION_MARK)
            t.more:SetShown(e.sub ~= nil)
            t.label:ClearAllPoints()
            -- the label sits outside the ring, under or over the tile
            if e.vy < -0.3 then t.label:SetPoint("TOP", t, "BOTTOM", 0, -4) else t.label:SetPoint("BOTTOM", t, "TOP", 0, 4) end
            t.label:SetText(e.label or "")
            SetHighlight(t, false)
            t:Show()
            d.entries[i], d.vectors[i] = e, { e.vx, e.vy }
        elseif t then
            t:Hide()
            t.label:Hide()
            d.vectors[i] = false
        else
            d.vectors[i] = false
        end
    end
    d.lit = nil
    return d
end

-- While shown: fade toward the target alpha, and highlight the slice the cursor points at.
function R.DisplayUpdate(d, elapsed)
    if d.alpha ~= d.target then
        local step = (elapsed or 0) / R.FADE
        d.alpha = d.target > d.alpha and math.min(d.target, d.alpha + step) or math.max(d.target, d.alpha - step)
        d:SetAlpha(d.alpha)
    end
    if d.target == 0 then
        if d.alpha <= 0 then d:Hide() end
        return
    end
    local cx, cy = header:GetAttribute("cx"), header:GetAttribute("cy")
    if not cx then return end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    local pick = R.Pick(x / scale - cx, y / scale - cy, d.vectors, d.n, R.DEAD, d.r ~= 0 and d.outer or nil)
    if pick ~= d.lit then
        if d.lit and d.tiles[d.lit] then SetHighlight(d.tiles[d.lit], false) end
        if pick and d.tiles[pick] then SetHighlight(d.tiles[pick], true) end
        d.lit = pick
    end
end

local shown = {}
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
    for r in pairs(shown) do
        local d = R.displays[r]
        for i, t in pairs(d.tiles) do if d.entries[i] then UpdateTile(t, d.entries[i]) end end
    end
end)
local LIVE = { "BAG_UPDATE", "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN" }

function ShowDisplay(r)
    local d = R.displays[r]
    if not d then return end
    d:ClearAllPoints()
    d:SetPoint("CENTER", UIParent, "BOTTOMLEFT", header:GetAttribute("cx") or 0, header:GetAttribute("cy") or 0)
    for i, t in pairs(d.tiles) do
        if d.entries[i] then UpdateTile(t, d.entries[i]) end
        SetHighlight(t, false)
    end
    d.lit = nil
    d.target = 1
    if not d:IsShown() then d.alpha = 0; d:SetAlpha(0) end
    d:Show()
    if not next(shown) then for _, ev in ipairs(LIVE) do ns.SafeRegister(events, ev) end end
    shown[r] = true
end

function HideDisplay(r)
    local d = R.displays[r]
    if d then d.target = 0 end -- OnUpdate fades it out and hides it
    shown[r] = nil
    if not next(shown) then events:UnregisterAllEvents() end
end

------------------------------------------------------------------------
-- Rebuild: the slices' attributes from the layout (out of combat only)
------------------------------------------------------------------------
R.dirty = true
R.layout = nil

local function SetSlice(s, e)
    s:SetAttribute("on", e and true or nil)
    s:SetAttribute("vx", e and e.vx or nil)
    s:SetAttribute("vy", e and e.vy or nil)
    s:SetAttribute("sub", e and e.sub or nil)
    local act = e and not e.sub and not e.missing
    s:SetAttribute("type", act and "macro" or nil) -- every action is a macro: macrotext, or a game macro by name
    s:SetAttribute("macrotext", act and not e.macro and e.macrotext or nil)
    s:SetAttribute("macro", act and e.macro or nil)
end

-- Returns true when done, false when it has to wait for combat to end.
function R.Rebuild()
    if not header or not ns.db then return false end
    if InCombatLockdown() then
        R.dirty = true
        return false
    end
    R.missingInfo = false
    R.ctx = R.Context()
    local layout = R.Resolve(ns.db.ring, R.ctx)
    for r = 0, RINGS do
        local ring = layout[r] or { n = 0, name = "", slots = {} }
        for i, s in ipairs(slices[r]) do SetSlice(s, ring.slots[i] or nil) end
        ringFrames[r]:SetAttribute("outer", r == 0 and nil or (SubRadius(ring.n) + R.TILE + 40))
        FillDisplay(r, ring)
    end
    R.layout = layout
    R.dirty = false
    if ns.app then ns.app:Refresh() end
    return true
end

-- Soon (several bag events come at once), and after combat when in combat.
local queued
function R.Schedule()
    R.dirty = true
    if queued then return end
    queued = true
    C_Timer.After(0.25, function()
        queued = false
        if R.dirty then R.Rebuild() end
    end)
end

------------------------------------------------------------------------
-- The key: bound through /mom's override bindings (Manager.lua), out of combat
------------------------------------------------------------------------
function ns.RingBinding()
    local ring = ns.db and ns.db.ring
    if not ring or not ring.on or not ring.key or ring.key == "" then return nil end
    return ring.key, "MoMRingTrigger"
end

-- After the key or on/off changed. In combat it waits.
function R.ApplyKey()
    if InCombatLockdown() then
        R.keyPending = true
        return false
    end
    R.keyPending = false
    if ns.ApplyBindings then ns.ApplyBindings() end
    return true
end

local KEY_NAMES = { BUTTON3 = "Middle mouse button", BUTTON4 = "Mouse button 4", BUTTON5 = "Mouse button 5",
    MOUSEWHEELUP = "Mouse wheel up", MOUSEWHEELDOWN = "Mouse wheel down" }
function R.KeyText(key)
    if not key or key == "" then return "none" end
    local mods, base = key:match("^(.-)([^%-]+)$")
    return (mods or "") .. (KEY_NAMES[base] or base)
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local REBUILD = { "BAG_UPDATE_DELAYED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "EQUIPMENT_SETS_CHANGED", "UPDATE_MACROS",
    "PLAYER_LEVEL_UP", "GET_ITEM_INFO_RECEIVED" }
local ev = CreateFrame("Frame")
for _, e in ipairs(REBUILD) do ns.SafeRegister(ev, e) end
ev:SetScript("OnEvent", function(_, event)
    if event == "GET_ITEM_INFO_RECEIVED" and not R.missingInfo then return end
    R.Schedule()
end)

local baseLoad = ns.OnLoad
ns.OnLoad = function(db, cdb)
    if baseLoad then baseLoad(db, cdb) end
    if type(db.ring) ~= "table" or type(db.ring.top) ~= "table" then db.ring = R.Defaults() end
    for i = 1, R.MAX_TOP do if db.ring.top[i] == nil then db.ring.top[i] = false end end
    if db.ring.on == nil then db.ring.on = true end
end

local baseWorld = ns.OnWorld
ns.OnWorld = function()
    if baseWorld then baseWorld() end -- SyncExt binds the keys, the ring's too
    R.Rebuild()
end

local baseCombatEnd = ns.OnCombatEnd
ns.OnCombatEnd = function()
    if baseCombatEnd then baseCombatEnd() end
    if R.keyPending then R.ApplyKey() end
    if R.dirty then R.Rebuild() end
end

CreateSecure()
