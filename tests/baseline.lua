-- Offline tests for the baseline mouseover sets (Classes.lua) and automatic set-up: every class's set, what is
-- left out, never a self cast, first-login set-up, the player's macros untouched, newly learned spells, a full
-- macro list and combat. tests/run.py runs each case in a fresh Lua state (a fresh login).
local ROOT, CASE = ...
local ADDON = "MouseoverMacros"
local ns = {}
local failures, passes = {}, 0

local function step(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passes = passes + 1
		print("  ok   " .. CASE .. ": " .. name)
	else
		failures[#failures + 1] = name .. ": " .. tostring(err)
		print("  FAIL " .. CASE .. ": " .. name .. "\n         " .. tostring(err))
	end
end
local function check(cond, msg) if not cond then error(msg, 2) end end
local function lines(s) local n = 0; for _ in tostring(s):gmatch("[^\n]+") do n = n + 1 end return n end

------------------------------------------------------------------------
-- The client's macros: 120 account (1-120), 30 per character (121-150), as on WoW Forever.
------------------------------------------------------------------------
local macros = { account = {}, char = {} }
Constants = { MacroConsts = { MAX_ACCOUNT_MACROS = 120, MAX_CHARACTER_MACROS = 30 } }
local function all()
	local t = {}
	for i, m in ipairs(macros.account) do t[i] = m end
	for i, m in ipairs(macros.char) do t[120 + i] = m end
	return t
end
local calls = { create = 0, edit = 0, delete = 0, edited = {} }
GetNumMacros = function() return #macros.account, #macros.char end
GetMacroIndexByName = function(name) for i, m in pairs(all()) do if m.name == name then return i end end return 0 end
GetMacroInfo = function(i) local m = all()[i]; if m then return m.name, m.icon, m.body end end
CreateMacro = function(name, icon, body, perChar)
	if MOCK.combat then error("ADDON_ACTION_BLOCKED: CreateMacro in combat", 2) end
	check(#body <= 255, "body over 255: " .. name)
	local list = perChar and macros.char or macros.account
	if #list >= (perChar and 30 or 120) then return nil end
	list[#list + 1] = { name = name, icon = icon, body = body }
	calls.create = calls.create + 1
	return true
end
EditMacro = function(i, name, icon, body)
	if MOCK.combat then error("ADDON_ACTION_BLOCKED: EditMacro in combat", 2) end
	local m = all()[i]
	calls.edited[#calls.edited + 1] = m.name
	m.name = name or m.name; m.body = body or m.body; m.icon = icon or m.icon
	calls.edit = calls.edit + 1
	return i
end
DeleteMacro = function(i)
	calls.delete = calls.delete + 1
	if i > 120 then table.remove(macros.char, i - 120) else table.remove(macros.account, i) end
end
PickupMacro = function() end
MOCK.cvars = { autoSelfCast = "0" }
C_CVar = { GetCVar = function(k) return MOCK.cvars[k] end, SetCVar = function(k, v) MOCK.cvars[k] = v end }
C_Spell = C_Spell or {}
C_Spell.GetSpellTexture = function() return 135953 end
MOCK.spellNames = {}
C_Spell.GetSpellName = function(id) return MOCK.spellNames[id] end
MOCK.knownIds, MOCK.knownPet = {}, {}
IsPlayerSpell = function(id) return MOCK.knownIds[id] == true end
IsSpellKnown = function(id, pet) if pet then return MOCK.knownPet[id] == true end return MOCK.knownIds[id] == true end
C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() end, GetItemCooldown = function() return 0, 0, 1 end }
C_Item = { GetItemInfo = function() end, GetItemSpell = function() end, GetItemCount = function() return 0 end, IsUsableItem = function() return true end }
UnitLevel = function() return 60 end
SecureHandlerWrapScript = function() end
MOCK.popups = 0
StaticPopup_Show = function() MOCK.popups = MOCK.popups + 1 end

local CLASSES = {
	WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
MOCK.class = "PALADIN"
UnitClass = function() return CLASSES[MOCK.class], MOCK.class, 2 end

local function load()
	local toc = assert(io.open(ROOT .. "/" .. ADDON .. ".toc")):read("*a")
	for line in toc:gmatch("[^\r\n]+") do
		if not line:match("^%s*#") and line:match("%.lua%s*$") then
			local chunk = assert(loadfile(ROOT .. "/" .. line:gsub("\\", "/"):gsub("%s+$", "")))
			chunk(ADDON, ns)
		end
	end
end
local function login()
	MOCK.Fire("ADDON_LOADED", ADDON)
	MOCK.Fire("PLAYER_LOGIN")
	MOCK.Fire("PLAYER_ENTERING_WORLD")
	MOCK.Fire("SPELLS_CHANGED")
	MOCK.RunTimers()
end
-- Know these spells (by the set's keys); returns their IDs.
local function know(...)
	for _, key in ipairs({ ... }) do
		local m = ns.Def(key)
		assert(m, "no entry " .. key .. " for " .. MOCK.class)
		if m.pet then MOCK.knownPet[m.id] = true else MOCK.knownIds[m.id] = true end
	end
end
local function knowAll()
	for _, m in ipairs(ns.MACROS[MOCK.class]) do if m.pet then MOCK.knownPet[m.id] = true else MOCK.knownIds[m.id] = true end end
end
local function ourChar()
	local n = 0
	for _, m in ipairs(macros.char) do if m.name:match("^_mom%d%d%d%d$") then n = n + 1 end end
	return n
end
local function chat(s) local n = 0; for _, l in ipairs(MOCK.log) do if l:find(s, 1, true) then n = n + 1 end end return n end
local function bodiesSafe()
	for _, m in pairs(all()) do
		local b = m.body:lower()
		if m.name:match("^_mom") and not b:find("#mom poh", 1, true) then
			check(not b:find("@player", 1, true) and not b:find("target=player", 1, true) and not b:find("@self", 1, true), "self cast in " .. m.name .. ":\n" .. m.body)
		end
	end
end

-- The player's own macros: never changed, never deleted.
local PLAYER = {
	{ name = "heal me", icon = 1, body = "#showtooltip\n/cast [@player] Holy Light" },
	{ name = "hlight", icon = 2, body = "/cast Holy Light" },           -- called like one of our keys
	{ name = "Mount", icon = 3, body = "/cast Summon Warhorse" },
}
local function copyPlayer(list) for _, m in ipairs(PLAYER) do list[#list + 1] = { name = m.name, icon = m.icon, body = m.body } end end
local function playerUntouched()
	for _, want in ipairs(PLAYER) do
		local found
		for _, m in pairs(all()) do if m.name == want.name and m.body == want.body and m.icon == want.icon then found = true end end
		check(found, "the player's " .. want.name .. " was changed or deleted")
	end
	for _, n in ipairs(calls.edited) do check(n:match("^_mom%d%d%d%d$"), "edited a macro that isn't ours: " .. n) end
	check(calls.delete == 0, "deleted a macro")
end

------------------------------------------------------------------------
local CASES = {}

CASES.sets = function()
	load()
	MOCK.Fire("ADDON_LOADED", ADDON)
	step("every class has a set; keys unique across classes; entries well formed", function()
		local keys = {}
		for class in pairs(CLASSES) do
			local set = ns.MACROS[class]
			check(set and #set >= 5, class .. " has no set")
			local on = 0
			for _, m in ipairs(set) do
				check(type(m[1]) == "string" and m[1]:match("^[a-z]+$") and #m[1] <= 10, class .. " key " .. tostring(m[1]))
				check(not keys[m[1]], "key " .. m[1] .. " in " .. class .. " and " .. tostring(keys[m[1]]))
				keys[m[1]] = class
				check(ns.KINDS[m[3]], m[1] .. ": kind " .. tostring(m[3]))
				check(type(m.id) == "number" and m.id > 0, m[1] .. ": no spell ID")
				check(type(m.on) == "boolean", m[1] .. ": no default")
				check(type(m.why) == "string" and m.why ~= "", m[1] .. ": no reason")
				check(m[3] ~= "helpOrSelf" or m[1] == "poh", m[1] .. ": a self-cast kind (only the owner's Prayer of Healing may)")
				if m.on then on = on + 1 end
			end
			print(("         %-8s %2d macros, %2d on by default"):format(class, #set, on))
		end
		for k in pairs(ns.MACROS) do check(CLASSES[k], "set for unknown class " .. k) end
	end)
	step("left out: self-only, stances, forms, auras, totems, ground spells, pet-only, raid-wide buffs", function()
		local NEVER = { "Stealth", "Ice Armor", "Frost Armor", "Blizzard", "Flamestrike", "Rain of Fire", "Consecration",
			"Hurricane", "Volley", "Flare", "Distract", "Bear Form", "Cat Form", "Travel Form", "Battle Stance", "Defensive Stance",
			"Devotion Aura", "Retribution Aura", "Searing Totem", "Healing Stream Totem", "Grounding Totem", "Lightning Shield",
			"Arcane Explosion", "Frost Nova", "Holy Nova", "Psychic Scream", "Prowl", "Vanish", "Levitate", "Slow Fall",
			"Lightwell", "Gift of the Wild", "Arcane Brilliance", "Battle Shout", "Trueshot Aura", "Mend Pet", "Health Funnel",
			"Seal of Righteousness", "Righteous Fury", "Divine Shield", "Freezing Trap", "Aspect of the Hawk", "Life Tap",
			"Inner Fire", "Fade", "Shadowform", "Evasion", "Ghost Wolf", "Moonkin Form", "Barkskin", "Ice Block" }
		for class, set in pairs(ns.MACROS) do
			local names = {}
			for _, m in ipairs(set) do names[m[2]] = true end
			for _, n in ipairs(NEVER) do check(not names[n], class .. " has " .. n) end
			for _, x in ipairs(ns.EXCLUDED[class] or {}) do check(not names[x[1]], class .. " has excluded " .. x[1]) end
			check(ns.EXCLUDED[class] and #ns.EXCLUDED[class] >= 5, class .. ": no list of what is left out")
		end
	end)
	step("never a self cast: every generated body of every class scanned for @player / target=player", function()
		local n = 0
		for class in pairs(CLASSES) do
			MOCK.class = class
			for _, e in ipairs(ns.Entries()) do
				n = n + 1
				local b = e.body:lower()
				check(#e.body <= 255, e.key .. " too long")
				check(b:find("@mouseover", 1, true), e.key .. " has no mouseover")
				if e.key ~= "poh" then -- the owner's own exception (Prayer of Healing heals the target's party, else yours)
					check(not b:find("@player", 1, true) and not b:find("target=player", 1, true) and not b:find("@self", 1, true)
						and not b:find("[]", 1, true), class .. " " .. e.key .. " casts on you:\n" .. e.body)
				end
				if e.kind == "help" then check(b:find("[@mouseover,help,nodead][help,nodead]", 1, true), e.key .. " help conditions") end
				if e.kind == "harm" then check(b:find("[@mouseover,harm,nodead][harm,nodead]", 1, true), e.key .. " harm conditions") end
				if e.kind == "res" then check(b:find("[@mouseover,help,dead][help,dead]", 1, true), e.key .. " res conditions") end
				if e.kind == "any" then check(b:find("[@mouseover,exists,nodead][exists,nodead]", 1, true), e.key .. " any conditions") end
				check(not b:find("rank", 1, true), e.key .. " names a rank")
			end
		end
		check(n > 150, "only " .. n .. " macros")
		MOCK.class = "PALADIN"
	end)
	step("names come from the client (any language), English only as the fallback", function()
		MOCK.spellNames[1022] = "Segen des Schutzes"
		local e = ns.Find("bop")
		check(e.spell == "Segen des Schutzes" and e.body:find("/cast [@mouseover,help,nodead][help,nodead] Segen des Schutzes", 1, true), e.body)
		MOCK.spellNames[1022] = nil
		check(ns.Find("bop").spell == "Blessing of Protection", "fallback")
		-- a macro /mom wrote under the English name still counts as ours, unchanged (updated, not kept as the player's)
		check(ns.OurOldText(ns.Def("bop"), "#showtooltip Blessing of Protection\n/cast [@mouseover,help,nodead][help,nodead] Blessing of Protection\n#mom bop"), "old text")
	end)
	step("known: by ID, a pet's spell in the pet's spellbook", function()
		MOCK.class = "WARLOCK"
		check(not ns.Find("spelllock").known, "Spell Lock known without a Felhunter")
		MOCK.knownPet[19244] = true
		check(ns.Find("spelllock").known, "pet spell not seen")
		MOCK.knownIds[172] = true
		check(ns.Find("corrupt").known and not ns.Find("fear").known, "player spells")
		MOCK.class = "PALADIN"
	end)
end

CASES.firstlogin = function()
	load()
	copyPlayer(macros.char)
	know("hlight", "fol", "bom", "bow", "bok", "bop", "purify", "redemp", "hoj", "loh", "exo", "dinterv", "judge", "turnund")
	MOCK.log = {}
	login()
	local cdb = MouseoverMacrosCharDB
	step("the set for the spells it knows, as character macros, in one chat line, no popup", function()
		-- 14 known; Divine Intervention and Judgement are off by default
		check(ourChar() == 12, "made " .. ourChar())
		check(#macros.account == 0, "used account macros")
		check(cdb.auto == true, "auto state " .. tostring(cdb.auto))
		check(chat("made 12 mouseover macros for your Paladin; /mom to change.") == 1, "chat: " .. table.concat(MOCK.log, " | "))
		check(#MOCK.log == 1, "more than one chat line: " .. table.concat(MOCK.log, " | "))
		check(MOCK.popups == 0 and next(StaticPopupDialogs or {}) == nil, "a popup")
		check(ns.Find("hlight").status == "ok" and ns.Find("hlight").macro:match("^_mom"), "ours, under a _mom name")
		check(ns.Find("dinterv").status == "new" and ns.Find("cleanse").status == "new", "off by default / not known: made")
		bodiesSafe()
		playerUntouched()
	end)
	step("a second login makes nothing more", function()
		local before = calls.create
		MOCK.log = {}
		MOCK.Fire("PLAYER_ENTERING_WORLD")
		MOCK.RunTimers()
		ns.AutoSetup(true)
		check(calls.create == before and #MOCK.log == 0, "made more")
	end)
	step("Create / update all: only switched-on spells you know; the player's macros untouched", function()
		MOCK.log = {}
		ns.InstallAll()
		check(MOCK.log[1]:find("created 0, updated 12", 1, true) and MOCK.log[1]:find("haven't learned yet", 1, true), MOCK.log[1])
		playerUntouched()
	end)
end

CASES.alreadysetup = function()
	load()
	copyPlayer(macros.char)
	-- set up by hand before automatic set-up existed: a record of ours, and the macro
	macros.char[#macros.char + 1] = { name = "_mom0001", icon = 1, body = "#showtooltip Holy Light\n/cast [@mouseover,help,nodead][help,nodead] Holy Light\n#mom hlight" }
	MouseoverMacrosCharDB = { owned = { hlight = { name = "_mom0001", scope = "char", created = 1 } } }
	knowAll()
	MOCK.log = {}
	login()
	step("a character set up before is left alone (no new macros, no chat)", function()
		check(MouseoverMacrosCharDB.auto == false, "auto " .. tostring(MouseoverMacrosCharDB.auto))
		check(ourChar() == 1 and #MOCK.log == 0, "made macros: " .. ourChar())
		MOCK.Fire("LEARNED_SPELL_IN_SKILL_LINE", 1022, 1)
		MOCK.RunTimers()
		check(ourChar() == 1, "learned spell made one on a set-up character")
		playerUntouched()
	end)
end

CASES.autooff = function()
	load()
	MouseoverMacrosDB = { autoSetup = false }
	knowAll()
	login()
	step("automatic set-up switched off (account-wide): nothing made", function()
		check(calls.create == 0 and MouseoverMacrosCharDB.auto == nil, "made " .. calls.create)
		check(ns.app:GetSetting("autosetup") ~= nil, "no setting")
	end)
	step("the setting switches back on with /mom", function()
		SlashCmdList.MOUSEOVERMACROS("set autosetup on")
		check(MouseoverMacrosDB.autoSetup == true, "not on")
	end)
end

CASES.learned = function()
	load()
	copyPlayer(macros.char)
	know("hlight", "fol", "hoj")
	login()
	step("learned spells: one batch, one chat line", function()
		check(ourChar() == 3, "first login made " .. ourChar())
		MOCK.log = {}
		know("cleanse", "bosac", "hshock", "sjudge") -- Swift Judgement is off by default
		MOCK.Fire("LEARNED_SPELL_IN_SKILL_LINE", 4987, 2)
		MOCK.Fire("SPELLS_CHANGED")
		MOCK.Fire("LEARNED_SPELL_IN_SKILL_LINE", 1311606, 2)
		MOCK.Fire("LEARNED_SPELL_IN_TAB", 6940, 2)
		MOCK.Fire("SPELLS_CHANGED")
		check(ourChar() == 3, "made before the batch ran")
		MOCK.RunTimers()
		check(ourChar() == 6, "made " .. ourChar())
		check(#MOCK.log == 1 and MOCK.log[1]:find("made 3 mouseover macros for new spells: Blessing of Sacrifice, Cleanse, Holy Shock", 1, true), table.concat(MOCK.log, " | "))
		check(ns.Find("hshock").body:find("[@mouseover,exists,nodead][exists,nodead] Holy Shock", 1, true), "Holy Shock either side")
		check(ns.Find("sjudge").status == "new", "an off-by-default spell was made")
		bodiesSafe()
	end)
	step("one learned spell: its name and macro in the line", function()
		MOCK.log = {}
		know("bof")
		MOCK.Fire("LEARNED_SPELL_IN_SKILL_LINE", 1044, 2)
		MOCK.RunTimers()
		check(#MOCK.log == 1 and MOCK.log[1]:find("made a mouseover macro for Blessing of Freedom (_mom", 1, true), table.concat(MOCK.log, " | "))
	end)
	step("a macro of ours the player deleted is never made again on its own", function()
		DeleteMacro(GetMacroIndexByName(ns.Find("cleanse").macro))
		calls.delete = 0
		MOCK.log = {}
		MOCK.Fire("SPELLS_CHANGED")
		MOCK.RunTimers()
		check(ns.Find("cleanse").status == "missing" and #MOCK.log == 0, "recreated")
		-- also when the record is gone (deleted in /mom's editor)
		MouseoverMacrosCharDB.owned.cleanse = nil
		MOCK.Fire("SPELLS_CHANGED")
		MOCK.RunTimers()
		check(ns.Find("cleanse").status == "new" and #MOCK.log == 0, "recreated without a record")
	end)
	step("an unchanged older text of ours is updated by Create / update all; one changed by hand is kept", function()
		local hl = macros.char[GetMacroIndexByName(ns.Find("hlight").macro) - 120]
		hl.body = "#showtooltip Holy Light\n/cast [@mouseover,help,nodead][help,nodead] Holy Light" -- no marker: an older /mom
		check(ns.Find("hlight").status == "ok" or ns.Find("hlight").status == "stale", ns.Find("hlight").status)
		local fol = macros.char[GetMacroIndexByName(ns.Find("fol").macro) - 120]
		fol.body = "#showtooltip\n/stopcasting\n/cast [@mouseover,help,nodead][help,nodead] Flash of Light\n#mom fol"
		check(ns.Find("fol").status == "differs", "hand change not seen")
		MOCK.log = {}
		ns.InstallAll()
		check(ns.Find("hlight").status == "ok", "older text not updated")
		check(fol.body:find("/stopcasting", 1, true), "hand-changed macro overwritten")
		check(MOCK.log[1]:find("kept 1 you changed by hand (fol", 1, true), MOCK.log[1])
		playerUntouched()
	end)
end

CASES.overflow = function()
	load()
	for i = 1, 20 do macros.char[i] = { name = "mine" .. i, icon = 1, body = "/say " .. i } end
	knowAll()
	MOCK.log = {}
	login()
	step("a nearly full character list: fills to 3 free, says plainly what didn't fit, no account macros", function()
		check(#macros.char == 27, "character macros " .. #macros.char)
		check(#macros.account == 0, "used account macros")
		local line = MOCK.log[1] or ""
		check(#MOCK.log == 1 and line:find("made 7 mouseover macros for your Paladin; /mom to change.", 1, true), table.concat(MOCK.log, " | "))
		check(line:find("didn't fit", 1, true) and line:find("27 of 30 character macros used", 1, true) and line:find("keeps 3 free", 1, true)
			and line:find("account macros in /mom", 1, true), line)
	end)
	step("later learned spells: no room, said once per session, nothing created", function()
		MOCK.log = {}
		MOCK.Fire("SPELLS_CHANGED"); MOCK.RunTimers()
		MOCK.Fire("SPELLS_CHANGED"); MOCK.RunTimers()
		check(#macros.char == 27 and #MOCK.log == 1 and MOCK.log[1]:find("no room for a mouseover macro", 1, true), table.concat(MOCK.log, " | "))
	end)
	step("a free slot later: the next batch fills it (still keeping 3)", function()
		table.remove(macros.char, 1)
		MOCK.Fire("SPELLS_CHANGED"); MOCK.RunTimers()
		check(#macros.char == 27, "character macros " .. #macros.char)
	end)
end

CASES.combat = function()
	load()
	know("hlight", "fol")
	MOCK.combat = true
	MOCK.log = {}
	login() -- logged in mid-fight: CreateMacro would be blocked (the mock raises an error)
	step("first login in combat: waits, makes the set after combat", function()
		check(ourChar() == 0 and #MOCK.errors == 0, "made in combat")
		MOCK.combat = false
		MOCK.Fire("PLAYER_REGEN_ENABLED")
		check(ourChar() == 2 and MOCK.log[#MOCK.log]:find("made 2 mouseover macros for your Paladin", 1, true), table.concat(MOCK.log, " | "))
	end)
	step("a spell learned in combat: after combat", function()
		MOCK.combat = true
		know("bop")
		MOCK.Fire("LEARNED_SPELL_IN_SKILL_LINE", 1022, 2)
		MOCK.RunTimers()
		check(ourChar() == 2, "made in combat")
		MOCK.combat = false
		MOCK.Fire("PLAYER_REGEN_ENABLED")
		check(ourChar() == 3, "not made after combat")
		check(#MOCK.errors == 0, table.concat(MOCK.errors, "\n"))
	end)
	step("nothing is ever cast: no CastSpell, no combat log", function()
		for _, file in ipairs({ "Classes.lua", "MouseoverMacros.lua", "Manager.lua", "Window.lua" }) do
			local src = assert(io.open(ROOT .. "/" .. file)):read("*a")
			for _, bad in ipairs({ "COMBAT_LOG_EVENT", "CastSpell", "CastSpellByName", "RunMacroText", "UseAction" }) do
				check(not src:find(bad, 1, true), file .. " uses " .. bad)
			end
		end
	end)
end

CASES.classes = function()
	load()
	step("first login for every class at 60: a set made, all character macros, no self casts", function()
		-- one class per Lua state would be truer; the set-up here is re-armed per class instead
		MOCK.Fire("ADDON_LOADED", ADDON)
		for class in pairs(CLASSES) do
			MOCK.class = class
			macros.char = {}
			MouseoverMacrosCharDB.owned, MouseoverMacrosCharDB.made, MouseoverMacrosCharDB.auto = {}, {}, nil
			MOCK.knownIds, MOCK.knownPet = {}, {}
			knowAll()
			MOCK.log = {}
			ns.AutoSetup(true)
			local on = 0
			for _, m in ipairs(ns.MACROS[class]) do if m.on then on = on + 1 end end
			check(ourChar() == math.min(on, 27), class .. ": made " .. ourChar() .. " of " .. on)
			check(#macros.account == 0, class .. " used account macros")
			check(#MOCK.log == 1 and MOCK.log[1]:find("for your " .. CLASSES[class], 1, true), class .. ": " .. table.concat(MOCK.log, " | "))
			bodiesSafe()
		end
	end)
end

------------------------------------------------------------------------
if CASE == "list" then
	local names = {}
	for k in pairs(CASES) do names[#names + 1] = k end
	table.sort(names)
	return table.concat(names, ",")
end
CASES[CASE]()
step("no Lua errors reported", function() check(#MOCK.errors == 0, table.concat(MOCK.errors, "\n")) end)
return #failures, passes
