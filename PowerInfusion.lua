-- /mom pi: a funny whisper to whoever your Power Infusion goes to. Used as a line in the PI macros:
-- the friend under the mouse, else (no enemy under the mouse) your friendly target; never you. Only when the spell
-- is ready, and not twice to the same person within a minute, so mashing the button doesn't spam them.
local _, ns = ...
local app = ns.app

ns.PI_LINES = {
    "%s, Power Infusion incoming. Please spend it on something better than auto-attacks.",
    "%s: you have been Power Infused. Side effects may include big numbers and a smug face.",
    "%s, PI on you. If you don't top the meters now, we need to talk.",
    "Power Infusion on you, %s. My mana, your glory.",
    "%s, I just made you a lot more dangerous. Don't waste it.",
    "%s: free Power Infusion. Terms and conditions: pump.",
    "%s, you're Power Infused. Go press the big buttons.",
    "%s, the Light has chosen you. Mostly because you were under my mouse.",
    "PI on you, %s. Remember who loves you when you're on top of the meters.",
    "%s: Power Infusion applied. Please hold still while you become amazing.",
}

local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Is(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, r = pcall(fn, ...)
    return ok and not Secret(r) and r and true or false
end

-- The unit the PI macro casts on: [@mouseover,help,nodead] PI; [@mouseover,harm,nodead][harm,nodead] other; [help,nodead] PI
function ns.PIUnit()
    if Is(UnitExists, "mouseover") and not Is(UnitIsDeadOrGhost, "mouseover") then
        if Is(UnitCanAssist, "player", "mouseover") then return "mouseover" end
        if Is(UnitCanAttack, "player", "mouseover") then return nil end
    end
    if Is(UnitCanAttack, "player", "target") then return nil end
    if Is(UnitExists, "target") and Is(UnitCanAssist, "player", "target") and not Is(UnitIsDeadOrGhost, "target") then return "target" end
    return nil
end

local function Ready()
    local spell = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(10060)) or "Power Infusion"
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, cd = pcall(C_Spell.GetSpellCooldown, spell)
        if ok and type(cd) == "table" and not Secret(cd.duration) and not Secret(cd.startTime) then
            return not (cd.startTime and cd.startTime > 0 and (cd.duration or 0) > 2)
        end
    end
    return true   -- can't tell (or a secret in combat): let it through, the per-person minute still holds
end

local last = {}
function ns.PISay()
    local unit = ns.PIUnit()
    if not unit or Is(UnitIsUnit, unit, "player") or not Is(UnitIsPlayer, unit) then return false end
    local ok, name = pcall(GetUnitName, unit, true)
    if not ok or Secret(name) or type(name) ~= "string" or name == "" then return false end
    if not Ready() then return false end
    local now = GetTime and GetTime() or 0
    if last[name] and now - last[name] < 60 then return false end
    last[name] = now
    local text = ns.PI_LINES[math.random(#ns.PI_LINES)]:format((name:gsub("%-.*$", "")))
    SendChatMessage(text, "WHISPER", nil, name)
    return true, text
end

app:Command("pi", "pi", "whisper a funny line to whoever your Power Infusion goes to (a line in the PI macros)", function()
    ns.PISay()
end)
