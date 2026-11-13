-- /mom : create or update this class's mouseover macros as character macros.
-- An existing macro with the same name (account or character) is edited in place,
-- so anything already on your action bars keeps working.

local QUESTION_MARK = 134400 -- with #showtooltip the button shows the spell icon anyway

-- Friendly: whoever the mouse is over, else your friendly target. Never yourself:
-- if neither exists the macro does nothing.
local function Help(spell)
    return "#showtooltip " .. spell .. "\n/cast [@mouseover,help,nodead][help,nodead] " .. spell
end
-- Hostile: whoever the mouse is over, else your target.
local function Harm(spell)
    return "#showtooltip " .. spell .. "\n/cast [@mouseover,harm,nodead][harm,nodead] " .. spell
end
-- Either side (Dispel Magic: cleanse a friend or purge an enemy): mouseover, else target. Never yourself.
local function Any(spell)
    return "#showtooltip " .. spell .. "
/cast [@mouseover,exists,nodead][exists,nodead] " .. spell
end
-- Res: mouseover corpse, else dead target.
local function Res(spell)
    return "#showtooltip " .. spell .. "\n/cast [@mouseover,help,dead][help,dead] " .. spell
end

local MACROS = {
    PRIEST = {
        { "renew",  Help("Renew") },
        { "lheal",  Help("Lesser Heal") },
        { "heal",   Help("Heal") },
        { "fheal",  Help("Flash Heal") },
        { "dgrace", Help("Divine Grace") },
        { "shield", Help("Power Word: Shield") },
        { "fort",   Help("Power Word: Fortitude") },
        { "curedis", Help("Cure Disease") },
        { "dispel", Any("Dispel Magic") },
        { "swp",    Harm("Shadow Word: Pain") },
        { "smite",  Harm("Smite") },
        { "mblast", Harm("Mind Blast") },
        { "dplague", Harm("Devouring Plague") },
        { "shackle", Harm("Shackle Undead") },
        { "rez",    Res("Resurrection") },
    },
}

local function Install()
    if InCombatLockdown() then
        print("|cff40c0ffMouseoverMacros|r: can't edit macros in combat.")
        return
    end
    local _, class = UnitClass("player")
    local list = MACROS[class]
    if not list then
        print("|cff40c0ffMouseoverMacros|r: no macros defined for " .. tostring(class) .. " yet.")
        return
    end

    local created, updated, failed = {}, {}, {}
    for _, m in ipairs(list) do
        local name, body = m[1], m[2]
        local index = GetMacroIndexByName(name)
        if index and index > 0 then
            EditMacro(index, name, nil, body)
            table.insert(updated, name)
        else
            local _, numChar = GetNumMacros()
            if numChar < (MAX_CHARACTER_MACROS or 18) and CreateMacro(name, QUESTION_MARK, body, true) then
                table.insert(created, name)
            else
                table.insert(failed, name)
            end
        end
    end

    print(("|cff40c0ffMouseoverMacros|r: created %d, updated %d%s. Drag them from /macro (Character tab) to your bars.")
        :format(#created, #updated, #failed > 0 and (", |cffff4040no room for: " .. table.concat(failed, ", ") .. "|r") or ""))
end

SLASH_MOUSEOVERMACROS1 = "/mom"
SlashCmdList.MOUSEOVERMACROS = Install

-- The game's "Auto Self Cast" setting makes plain spell buttons fall back to you when you have
-- no friendly target. Keep it off on every login.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if C_CVar and C_CVar.GetCVar("autoSelfCast") then
        C_CVar.SetCVar("autoSelfCast", "0")
    elseif GetCVar and GetCVar("autoSelfCast") then
        SetCVar("autoSelfCast", "0")
    end
end)
