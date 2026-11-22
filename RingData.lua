-- EverlookDB Macros: the ring's data. What a ring holds (db.ring), what each slice turns into on this
-- character right now (best food in the bags, known profession spells ...), and the direction maths.
--
-- db.ring.top: 8 compass slots, 1 = up, then clockwise (3 = right, 5 = down, 7 = left); false = empty.
-- A slot is one slice ({ kind = "spell" | "item" | "macro" | "equipset" | <dynamic> }) or a
-- sub-ring ({ kind = "ring", name, items = { slice, ... } }), whose items open around the cursor.
local _, ns = ...
local R = {}
ns.Ring = R

R.MAX_TOP, R.MAX_SUB = 8, 12
R.DIRS = { "Up", "Up-right", "Right", "Down-right", "Down", "Down-left", "Left", "Up-left" }
local DIR_WORDS = {
    up = 1, n = 1, u = 1, upright = 2, ur = 2, ne = 2, right = 3, r = 3, e = 3, downright = 4, dr = 4, se = 4,
    down = 5, d = 5, s = 5, downleft = 6, dl = 6, sw = 6, left = 7, l = 7, w = 7, upleft = 8, ul = 8, nw = 8,
}
-- "right", "up-left", "3" -> slot number
function R.Dir(word)
    word = tostring(word or ""):lower():gsub("[%s%-_]", "")
    local n = tonumber(word)
    if n and n >= 1 and n <= 8 and n == math.floor(n) then return n end
    return DIR_WORDS[word]
end

------------------------------------------------------------------------
-- Direction maths (the secure snippet in Ring.lua does the same sums; keep them in step)
------------------------------------------------------------------------
-- Unit vector of top slot i (x right, y up): slot 1 straight up, then every 45 degrees clockwise.
function R.TopVector(i)
    local a = (i - 1) * math.pi / 4
    return math.sin(a), math.cos(a)
end
-- Entry i of n in a sub-ring: the first at the top, then evenly clockwise.
function R.SubVector(i, n)
    local a = (i - 1) * 2 * math.pi / n
    return math.sin(a), math.cos(a)
end

-- The slice the cursor points at, from the ring's centre (dx, dy). slots[i] = { vx, vy } or false,
-- for i = 1..n. Nil inside the dead zone, beyond `outer` (when given) or with no slice at all.
-- The nearest slice by angle wins (largest dot product); on a tie the lower number.
function R.Pick(dx, dy, slots, n, dead, outer)
    local d2 = dx * dx + dy * dy
    if d2 < (dead or 0) * (dead or 0) then return nil end
    if outer and d2 > outer * outer then return nil end
    local best, pick
    for i = 1, n do
        local s = slots[i]
        if s then
            local d = dx * s[1] + dy * s[2]
            if best == nil or d > best then best, pick = d, i end
        end
    end
    return pick
end

------------------------------------------------------------------------
-- Game data, never a secret value: anything secret counts as unknown
------------------------------------------------------------------------
local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function Num(v) if v == nil or Secret(v) then return nil end return tonumber(v) end

local function PlayerLevel()
    local l = UnitLevel and UnitLevel("player")
    return Num(l) or 1
end

-- name, icon, minLevel, itemLevel, classID, subclassID, subType
function R.ItemInfo(id)
    local name, _, _, ilvl, minLevel, _, subType, _, _, icon, _, classID, subclassID
    if C_Item and C_Item.GetItemInfo then
        name, _, _, ilvl, minLevel, _, subType, _, _, icon, _, classID, subclassID = C_Item.GetItemInfo(id)
    elseif GetItemInfo then
        name, _, _, ilvl, minLevel, _, subType, _, _, icon, _, classID, subclassID = GetItemInfo(id)
    end
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        R.missingInfo = true
        return nil
    end
    return { id = id, name = name, icon = icon, minLevel = Num(minLevel) or 0, ilvl = Num(ilvl) or 0,
        classID = Num(classID), subclassID = Num(subclassID), subType = subType }
end

local function ItemSpell(id)
    local f = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not f then return nil end
    local name, spellID = f(id)
    if Secret(name) then return nil end
    return name, spellID
end

function R.ItemCount(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    return f and Num(f(id)) or 0
end

local function Usable(info)
    if info.minLevel > PlayerLevel() then return false end
    local f = (C_Item and C_Item.IsUsableItem) or IsUsableItem
    if f then
        local ok = f(info.id)
        if ok ~= nil and not Secret(ok) and not ok then return false end
    end
    return true
end

-- Every item in the bags once: { id, count, name, icon, minLevel, ilvl, classID, subclassID, spell, usable }
function R.ScanBags()
    local seen, out = {}, {}
    local C = C_Container
    local numSlots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
    local itemInfo = (C and C.GetContainerItemInfo) or GetContainerItemInfo
    if not numSlots or not itemInfo then return out end
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, Num(numSlots(bag)) or 0 do
            local info = itemInfo(bag, slot)
            local id, count
            if type(info) == "table" then id, count = info.itemID, info.stackCount
            elseif info then count, id = select(2, itemInfo(bag, slot)), select(10, itemInfo(bag, slot)) end
            id, count = Num(id), Num(count) or 1
            if id then
                if seen[id] then
                    seen[id].count = seen[id].count + count
                else
                    local it = R.ItemInfo(id)
                    if it then
                        it.count = count
                        it.spell = ItemSpell(id)
                        it.usable = Usable(it)
                        seen[id] = it
                        out[#out + 1] = it
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

------------------------------------------------------------------------
-- Consumables: what an item is, and which one is best
------------------------------------------------------------------------
local LURES = { ["shiny bauble"] = true, ["nightcrawlers"] = true, ["bright baubles"] = true, ["aquadynamic fish attractor"] = true,
    ["flesh eating worm"] = true, ["aquadynamic fish lens"] = true, ["sharpened fish hook"] = true }
R.HEARTHSTONE = 6948

-- The categories an item falls in: food, drink, hpot, mpot, bandage, lure, pole. The use spell's name
-- decides first (Food, Drink, Healing Potion, Restore Mana, First Aid), then the item class.
function R.Classify(it)
    local c = {}
    local spell = tostring(it.spell or ""):lower()
    local name = tostring(it.name or ""):lower()
    local consumable = it.classID == 0
    if spell == "food" then c.food = true end
    if spell == "drink" then c.drink = true end
    if spell == "refreshment" or spell == "food & drink" then c.food, c.drink = true, true end
    if consumable and it.subclassID == 5 and not c.food and not c.drink then
        if name:find("water") or name:find("juice") or name:find("milk") or name:find("tea") or name:find("cider") then c.drink = true else c.food = true end
    end
    if spell == "first aid" or name:find("bandage") or (consumable and it.subclassID == 7) then c.bandage = true end
    if spell:find("healing potion") or name:find("healing potion") or name:find("healthstone") then c.hpot = true end
    if spell == "restore mana" or name:find("mana potion") then c.mpot = true end
    if consumable and it.subclassID == 1 and not c.hpot and not c.mpot then
        if name:find("mana") then c.mpot = true elseif name:find("heal") then c.hpot = true end
    end
    if LURES[name] or spell:find("lure") then c.lure = true end
    if (it.classID == 2 and it.subclassID == 20) or tostring(it.subType or ""):lower() == "fishing poles" or name:find("fishing pole") then c.pole = true end
    return c
end

-- Usable first, then the highest required level, then the highest item level, then the bigger stack.
function R.Better(a, b)
    if a.usable ~= b.usable then return a.usable end
    if a.minLevel ~= b.minLevel then return a.minLevel > b.minLevel end
    if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
    if a.count ~= b.count then return a.count > b.count end
    return a.id < b.id
end

-- The items of one category, best first.
function R.Ranked(items, cat)
    local out = {}
    for _, it in ipairs(items) do
        if R.Classify(it)[cat] then out[#out + 1] = it end
    end
    table.sort(out, R.Better)
    return out
end

function R.Best(items, cat) return R.Ranked(items, cat)[1] end

------------------------------------------------------------------------
-- Spells
------------------------------------------------------------------------
-- A spell this character knows, by name: its ID, name and icon, or nil.
function R.Spell(name)
    if not name then return nil end
    local id, icon, real
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(name)
        if not info then return nil end
        id, icon, real = info.spellID, info.iconID, info.name
    elseif GetSpellInfo then
        local n, _, ic, _, _, _, sid = GetSpellInfo(name)
        if not n then return nil end
        id, icon, real = sid, ic, n
    else
        return nil
    end
    if Secret(real) then real = nil end
    return { id = Num(id), name = (type(name) == "string" and name) or real, icon = icon }
end

R.BUFFS = {
    PRIEST = { "Power Word: Fortitude", "Inner Fire", "Divine Spirit", "Shadow Protection", "Fear Ward" },
    MAGE = { "Arcane Intellect", "Molten Armor", "Mage Armor", { "Ice Armor", "Frost Armor" }, "Dampen Magic", "Amplify Magic" },
    DRUID = { "Mark of the Wild", "Thorns", "Omen of Clarity" },
    PALADIN = { "Blessing of Might", "Blessing of Wisdom", "Blessing of Kings", "Righteous Fury" },
    WARLOCK = { { "Fel Armor", "Demon Armor", "Demon Skin" }, "Unending Breath", "Detect Invisibility" },
    HUNTER = { "Aspect of the Hawk", "Trueshot Aura" },
    SHAMAN = { "Lightning Shield", "Water Shield" },
    WARRIOR = { "Battle Shout", "Commanding Shout" },
    ROGUE = {},
}

-- Spells with a dynamic slice of their own: the profession list leaves them out.
R.SEPARATE = { Disenchant = "disenchant", Prospecting = "disenchant", Milling = "disenchant",
    ["Cooking Fire"] = "campfire", ["Basic Campfire"] = "campfire", Smelting = "smelting", Fishing = "fishing" }
R.PROFESSIONS = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring",
    "Jewelcrafting", "Inscription", "Cooking", "First Aid", "Poisons" }

local function SpellEntry(name)
    local s = R.Spell(name)
    if not s then return nil end
    return { label = s.name, icon = s.icon, macrotext = "/cast " .. s.name, spell = s.id or s.name }
end

local function ItemEntry(it, macrotext, label)
    return { label = label or it.name, icon = it.icon, macrotext = macrotext or ("/use item:" .. it.id), itemID = it.id }
end

-- Profession window spells: the names above, plus whatever GetProfessions lists (when the client has it).
local function ProfessionSpells()
    local out, seen = {}, {}
    local function add(name)
        if not name or seen[name] or R.SEPARATE[name] then return end
        seen[name] = true
        local e = SpellEntry(name)
        if e then out[#out + 1] = e end
    end
    for _, name in ipairs(R.PROFESSIONS) do add(name) end
    if GetProfessions and GetProfessionInfo and C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        for _, idx in ipairs({ GetProfessions() }) do
            local _, _, _, _, numSpells, offset = GetProfessionInfo(idx)
            for k = 1, Num(numSpells) or 0 do
                local info = C_SpellBook.GetSpellBookItemInfo((Num(offset) or 0) + k, Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player)
                if info and not info.isPassive and info.name and not Secret(info.name) then add(info.name) end
            end
        end
    end
    return out
end

------------------------------------------------------------------------
-- Dynamic slices
------------------------------------------------------------------------
-- R.DYNAMIC[kind] = { label, desc, many (expands to several), get(ctx) -> entries }
local function bestOf(cat)
    return function(ctx)
        local it = R.Best(ctx.items, cat)
        return it and { ItemEntry(it) } or {}
    end
end

local function EquipmentSets()
    local sets = {}
    local E = C_EquipmentSet
    if not (E and E.GetEquipmentSetIDs and E.GetEquipmentSetInfo) then return sets end
    for _, id in ipairs(E.GetEquipmentSetIDs() or {}) do
        local name, icon = E.GetEquipmentSetInfo(id)
        if name then sets[#sets + 1] = { id = id, name = name, icon = icon } end
    end
    return sets
end
R.EquipmentSets = EquipmentSets

R.DYNAMIC = {
    food = { label = "Best food", desc = "the best food in your bags", get = bestOf("food") },
    drink = { label = "Best drink", desc = "the best drink in your bags", get = bestOf("drink") },
    hpot = { label = "Best healing potion", desc = "the best healing potion or healthstone in your bags", get = bestOf("hpot") },
    mpot = { label = "Best mana potion", desc = "the best mana potion in your bags", get = bestOf("mpot") },
    bandage = { label = "Best bandage", desc = "the best bandage in your bags", get = bestOf("bandage") },
    buffs = { label = "Your buffs", desc = "your class's buff spells that you know", many = true, get = function(ctx)
        local out = {}
        for _, b in ipairs(R.BUFFS[ctx.class] or {}) do
            local alts = type(b) == "table" and b or { b }
            for _, name in ipairs(alts) do
                local e = SpellEntry(name)
                if e then out[#out + 1] = e; break end
            end
        end
        return out
    end },
    professions = { label = "Your professions", desc = "a slice per profession window you have", many = true, get = function() return ProfessionSpells() end },
    disenchant = { label = "Disenchant / Prospecting", desc = "Disenchant, Prospecting and Milling, when known", many = true, get = function()
        local out = {}
        for _, n in ipairs({ "Disenchant", "Prospecting", "Milling" }) do out[#out + 1] = SpellEntry(n) end
        return out
    end },
    campfire = { label = "Cooking fire", desc = "Cooking Fire (Basic Campfire), when known", get = function()
        return { SpellEntry("Cooking Fire") or SpellEntry("Basic Campfire") }
    end },
    smelting = { label = "Smelting", desc = "Smelting, when known", get = function() return { SpellEntry("Smelting") } end },
    fishing = { label = "Fishing", desc = "the Fishing spell, when known", get = function() return { SpellEntry("Fishing") } end },
    fishgear = { label = "Fishing gear", desc = "your \"Fishing\" equipment set (and back), else the best fishing pole in your bags", get = function(ctx)
        local sets, fish, other = EquipmentSets(), nil, nil
        for _, s in ipairs(sets) do
            if s.name:lower() == "fishing" then fish = fish or s else other = other or s end
        end
        if fish then
            local text = other and ("/equipset [equipped:Fishing Poles] " .. other.name .. "; " .. fish.name) or ("/equipset " .. fish.name)
            return { { label = other and ("Fishing set / " .. other.name) or "Fishing set", icon = fish.icon, macrotext = text } }
        end
        local pole = R.Best(ctx.items, "pole")
        return pole and { ItemEntry(pole, "/equip " .. pole.name) } or {}
    end },
    lures = { label = "Fishing lures", desc = "each lure in your bags (up to 3), applied to your fishing pole", many = true, get = function(ctx)
        local out = {}
        for i, it in ipairs(R.Ranked(ctx.items, "lure")) do
            if i > 3 then break end
            out[#out + 1] = ItemEntry(it, "/use item:" .. it.id .. "\n/use 16")
        end
        return out
    end },
    hearthstone = { label = "Hearthstone", desc = "your Hearthstone, when it is in your bags", get = function(ctx)
        for _, it in ipairs(ctx.items) do
            if it.id == R.HEARTHSTONE then return { ItemEntry(it) } end
        end
        return {}
    end },
}
R.DYNAMIC_ORDER = { "food", "drink", "hpot", "mpot", "bandage", "buffs", "professions", "disenchant", "campfire", "smelting",
    "fishing", "fishgear", "lures", "hearthstone" }

------------------------------------------------------------------------
-- Slices -> entries: { label, icon, macrotext | macro, itemID, spell }
------------------------------------------------------------------------
function R.Context()
    local _, class = UnitClass("player")
    return { items = R.ScanBags(), class = class }
end

-- What a slice is, in words (the editor and /mom ring list).
function R.Describe(s)
    if not s then return "empty" end
    local d = R.DYNAMIC[s.kind]
    if d then return d.label end
    if s.kind == "ring" then return "sub-ring \"" .. tostring(s.name or "Ring") .. "\" (" .. #(s.items or {}) .. ")" end
    if s.kind == "spell" then return "spell " .. tostring(s.name or s.id) end
    if s.kind == "item" then
        local it = R.ItemInfo(s.id)
        return "item " .. (it and it.name or ("#" .. tostring(s.id)))
    end
    if s.kind == "macro" then return "macro " .. tostring(s.name) end
    if s.kind == "equipset" then return "equipment set " .. tostring(s.name) end
    return tostring(s.kind)
end

-- The entries one slice gives on this character now (several for "many" dynamic slices).
function R.Expand(s, ctx)
    if not s then return {} end
    local d = R.DYNAMIC[s.kind]
    if d then
        -- a getter's list may have holes (a spell not known): keep the order, drop the holes
        local got, out = d.get(ctx) or {}, {}
        for i = 1, table.maxn(got) do if got[i] then out[#out + 1] = got[i] end end
        return out
    end
    if s.kind == "spell" then
        local name = s.name or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(s.id))
        if not name or Secret(name) then return {} end
        local icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(s.id or name)) or ns.QUESTION_MARK
        return { { label = name, icon = icon, macrotext = "/cast " .. name, spell = s.id or name } }
    end
    if s.kind == "item" then
        local it = R.ItemInfo(s.id)
        if not it then return { { label = "item " .. tostring(s.id), icon = ns.QUESTION_MARK, macrotext = "/use item:" .. s.id, itemID = s.id } } end
        return { ItemEntry(it) }
    end
    if s.kind == "macro" then
        if not s.name or not GetMacroIndexByName or (GetMacroIndexByName(s.name) or 0) == 0 then return {} end
        local _, icon = GetMacroInfo(GetMacroIndexByName(s.name))
        return { { label = s.name, icon = icon or ns.QUESTION_MARK, macro = s.name } }
    end
    if s.kind == "equipset" then
        local icon
        for _, set in ipairs(EquipmentSets()) do if set.name == s.name then icon = set.icon end end
        return { { label = s.name, icon = icon or ns.QUESTION_MARK, macrotext = "/equipset " .. s.name } }
    end
    return {}
end

-- The whole layout for this character: layout[0] = the top ring, layout[r] = the sub-ring in top slot r.
-- Each ring: { n, name, slots = { [i] = entry with vx, vy (and sub = r for a sub-ring slice) or false } }.
function R.Resolve(ring, ctx)
    ctx = ctx or R.Context()
    local layout = { [0] = { n = R.MAX_TOP, name = "", slots = {} } }
    for i = 1, R.MAX_TOP do
        local s = ring.top[i]
        local vx, vy = R.TopVector(i)
        if s and s.kind == "ring" then
            local entries = {}
            for _, item in ipairs(s.items or {}) do
                for _, e in ipairs(R.Expand(item, ctx)) do
                    if #entries < R.MAX_SUB then entries[#entries + 1] = e end
                end
            end
            local sub = { n = #entries, name = s.name or "Ring", slots = {} }
            for k, e in ipairs(entries) do
                e.vx, e.vy = R.SubVector(k, #entries)
                sub.slots[k] = e
            end
            layout[i] = sub
            layout[0].slots[i] = { label = s.name or "Ring", icon = s.icon or (entries[1] and entries[1].icon) or ns.QUESTION_MARK,
                sub = i, vx = vx, vy = vy, count = #entries }
        elseif s then
            local e = R.Expand(s, ctx)[1] or { label = R.Describe(s), icon = ns.QUESTION_MARK, missing = true }
            e.vx, e.vy = vx, vy
            layout[0].slots[i] = e
        else
            layout[0].slots[i] = false
        end
    end
    return layout
end

------------------------------------------------------------------------
-- The default ring
------------------------------------------------------------------------
function R.Defaults()
    return {
        version = 1,
        on = true,
        key = "BUTTON3",
        top = {
            { kind = "hearthstone" },
            false,
            { kind = "ring", name = "Consumables", items = { { kind = "food" }, { kind = "drink" }, { kind = "hpot" }, { kind = "mpot" }, { kind = "bandage" }, { kind = "buffs" } } },
            false,
            { kind = "ring", name = "Fishing", items = { { kind = "fishing" }, { kind = "fishgear" }, { kind = "lures" } } },
            false,
            { kind = "ring", name = "Professions", items = { { kind = "professions" }, { kind = "disenchant" }, { kind = "campfire" }, { kind = "smelting" } } },
            false,
        },
    }
end
