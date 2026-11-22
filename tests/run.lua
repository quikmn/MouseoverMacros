-- Offline tests for EverlookDB Macros against wowmock.lua: macro bodies, _mom names and ownership,
-- migration of old plain-named macros, the on/off switches, where new macros go, the combat queue,
-- Auto Self Cast, every slash command and the window.
local ROOT = ...
local ADDON = "MouseoverMacros"
local ns = {}
local failures, passes = {}, 0

local function step(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passes = passes + 1
		print("  ok   " .. name)
	else
		failures[#failures + 1] = name .. ": " .. tostring(err)
		print("  FAIL " .. name .. "\n         " .. tostring(err))
	end
end
local function check(cond, msg) if not cond then error(msg, 2) end end
local function last() return MOCK.log[#MOCK.log] or "" end
local function logHas(s) for _, l in ipairs(MOCK.log) do if l:find(s, 1, true) then return true end end return false end

-- Macro API: account macros are indexes 1-120, character macros 121-138.
local macros = { account = {}, char = {} }
MOCK.macros = macros
MAX_ACCOUNT_MACROS, MAX_CHARACTER_MACROS = 120, 18
local function all()
	local t = {}
	for i, m in ipairs(macros.account) do t[i] = m end
	for i, m in ipairs(macros.char) do t[120 + i] = m end
	return t
end
local edits = 0
GetNumMacros = function() return #macros.account, #macros.char end
GetMacroIndexByName = function(name) for i, m in pairs(all()) do if m.name == name then return i end end return 0 end
GetMacroInfo = function(i) local m = all()[i]; if m then return m.name, m.icon, m.body end end
CreateMacro = function(name, icon, body, perChar)
	if MOCK.combat then error("ADDON_ACTION_BLOCKED: CreateMacro in combat", 2) end
	check(#body <= 255, "body over 255: " .. name)
	local list = perChar and macros.char or macros.account
	if #list >= (perChar and 18 or 120) then return nil end
	list[#list + 1] = { name = name, icon = icon, body = body }
	return true
end
EditMacro = function(i, name, icon, body)
	if MOCK.combat then error("ADDON_ACTION_BLOCKED: EditMacro in combat", 2) end
	local m = all()[i]; m.name = name or m.name; m.body = body or m.body; m.icon = icon or m.icon
	edits = edits + 1
	return i
end
DeleteMacro = function(i)
	if i > 120 then table.remove(macros.char, i - 120) else table.remove(macros.account, i) end
end
MOCK.picked = nil
PickupMacro = function(i) MOCK.picked = i end
MOCK.cvars = { autoSelfCast = "1" }
C_CVar = { GetCVar = function(k) return MOCK.cvars[k] end, SetCVar = function(k, v) MOCK.cvars[k] = v end }
UnitClass = function() return "Priest", "PRIEST", 5 end
C_Spell = C_Spell or {}
C_Spell.GetSpellTexture = function() return 135953 end
-- Spell names by ID: nil (the English name in Classes.lua is used) unless a test gives the client's own name.
MOCK.spellNames = {}
C_Spell.GetSpellName = function(id) return MOCK.spellNames[id] end
-- Known spells by ID: every spell unless a test sets MOCK.knownIds (then only those).
MOCK.knownIds = nil
IsPlayerSpell = function(id) return MOCK.knownIds == nil or MOCK.knownIds[id] == true end
IsSpellKnown = function(id, pet) if pet then return MOCK.knownPet ~= nil and MOCK.knownPet[id] == true end return IsPlayerSpell(id) end
time = time or function() return 1700000000 end

local function find(name) for _, m in pairs(all()) do if m.name == name then return m end end end
local function isMom(n) return n and n:match("^_mom%d%d%d%d$") ~= nil end
local function entry(key) return ns.Find(key) end
-- Answer the editor's "not saved" question: "save", "discard" or "cancel".
local function answer(what)
	local d = ns.unsavedDialog
	check(d and d:IsShown(), "the unsaved-changes question is not shown")
	local b = d[what]
	b:GetScript("OnClick")(b)
end

-- The owner's macros before this version: old /mom macros under plain names, plus his own ones.
local OLD_HEAL = "#showtooltip Heal\n/cast [@mouseover,help,nodead][help,nodead] Heal"
local OLD_DISPEL_V1 = "#showtooltip Dispel Magic\n/cast [@mouseover,help,nodead][help,nodead] Dispel Magic"
local OLD_RENEW = "#showtooltip Renew\n/cast [@mouseover,help,nodead][help,nodead] Renew"
local PLAYER_FORT = "#showtooltip\n/cast [@focus] Power Word: Fortitude"
macros.char = {
	{ name = "heal", icon = 134400, body = OLD_HEAL },
	{ name = "fort", icon = 1, body = PLAYER_FORT },              -- the player's own: never touched
	{ name = "renew", icon = 134400, body = OLD_RENEW .. "\n" },  -- trailing newline only: still ours
	{ name = "Mount", icon = 2, body = "/cast Riding Turtle" },
}
macros.account = {
	{ name = "dispel", icon = 134400, body = OLD_DISPEL_V1 },     -- the first version's Dispel
	{ name = "smite", icon = 3, body = "#showtooltip Smite\n/cast Smite" }, -- same name, other text: the player's
	{ name = "_mom1234", icon = 4, body = "/say a player's macro that happens to look like ours" },
}

-- Blizzard's macro window as on this client: /macro (an ordinary slash command) and the game menu
-- call ShowMacroFrame(), which loads Blizzard_MacroUI on demand and shows MacroFrame.
SLASH_MACRO1 = "/macro"
MOCK.blizzSlash = 0
ShowMacroFrame = function()
	if not MacroFrame then
		CreateFrame("Frame", "MacroFrame", UIParent)
		MacroFrame:Hide()
		MOCK.Fire("ADDON_LOADED", "Blizzard_MacroUI")
	end
	MacroFrame:Show()
end
HideUIPanel = function(f) f:Hide() end
SlashCmdList.MACRO = function() MOCK.blizzSlash = MOCK.blizzSlash + 1; ShowMacroFrame() end

-- The ring: secure wraps are recorded (the tests run the snippet themselves); bags, items and spells stubbed.
MOCK.wraps = {}
SecureHandlerWrapScript = function(frame, script, header, pre) table.insert(MOCK.wraps, { frame = frame, script = script, header = header, pre = pre }) end
MOCK.bags = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} } -- bags[bag][slot] = { itemID, count }
MOCK.items = {}  -- [itemID] = { name, ilvl, minLevel, classID, subclassID, subType, spell, unusable }
MOCK.level = 30
UnitLevel = function() return MOCK.level end
C_Container = {
	GetContainerNumSlots = function(bag) return MOCK.bags[bag] and 16 or 0 end,
	GetContainerItemInfo = function(bag, slot)
		local x = MOCK.bags[bag] and MOCK.bags[bag][slot]
		if x then return { itemID = x[1], stackCount = x[2] } end
	end,
	GetItemCooldown = function() return 0, 0, 1 end,
}
C_Item = {
	GetItemInfo = function(id)
		local it = MOCK.items[id]
		if it then return it.name, "link", 1, it.ilvl or 1, it.minLevel or 0, "Consumable", it.subType or "Consumable", 20, "", 1000 + id, 1, it.classID or 0, it.subclassID or 0 end
	end,
	GetItemSpell = function(id) local it = MOCK.items[id]; if it and it.spell then return it.spell, 1 end end,
	GetItemCount = function(id)
		local n = 0
		for _, b in pairs(MOCK.bags) do for _, x in pairs(b) do if x[1] == id then n = n + x[2] end end end
		return n
	end,
	IsUsableItem = function(id) local it = MOCK.items[id]; return not (it and it.unusable) end,
}
MOCK.known = {}  -- spell name -> ID: spells this character knows
do
	local base = C_Spell.GetSpellInfo
	C_Spell.GetSpellInfo = function(x)
		if type(x) == "string" and MOCK.known[x] then return { name = x, spellID = MOCK.known[x], iconID = 2000 + MOCK.known[x] } end
		return base(x)
	end
end
MOCK.cursor = nil -- { kind, a, b, c, d }
GetCursorInfo = function() if MOCK.cursor then return unpack(MOCK.cursor) end end
ClearCursor = function() MOCK.cursor = nil end

local globalWrites = {}
local addonEnv = setmetatable({}, { __index = _G, __newindex = function(_, k, v) globalWrites[k] = true; _G[k] = v end })

step("load TOC files; defaults on a fresh install", function()
	local toc = assert(io.open(ROOT .. "/" .. ADDON .. ".toc")):read("*a")
	check(toc:find("## SavedVariablesPerCharacter: MouseoverMacrosCharDB", 1, true), "per-character saved variables")
	check(toc:find("## Title: EverlookDB Macros", 1, true), "the TOC title is EverlookDB Macros")
	for line in toc:gmatch("[^\r\n]+") do
		if not line:match("^%s*#") and line:match("%.lua%s*$") then
			local chunk, err = loadfile(ROOT .. "/" .. line:gsub("\\", "/"):gsub("%s+$", ""))
			if not chunk then error("syntax: " .. err) end
			setfenv(chunk, addonEnv)
			chunk(ADDON, ns)
		end
	end
	MOCK.Fire("ADDON_LOADED", ADDON)
	local db = MouseoverMacrosDB
	check(db and db.autoSelfCastOff == true and db.where == "character" and next(db.off) == nil, "defaults")
	check(next(db.owned) == nil and next(MouseoverMacrosCharDB.owned) == nil, "no ownership yet")
end)

step("macro bodies: the old text plus a #mom marker line, all within 255", function()
	local want = {
		renew = "#showtooltip Renew\n/cast [@mouseover,help,nodead][help,nodead] Renew\n#mom renew",
		poh = "#showtooltip Prayer of Healing\n/cast [@mouseover,help,nodead][help,nodead][@player] Prayer of Healing\n#mom poh",
		dispel = "#showtooltip Dispel Magic\n/cast [@mouseover,exists,nodead][exists,nodead] Dispel Magic\n#mom dispel",
		swp = "#showtooltip Shadow Word: Pain\n/cast [@mouseover,harm,nodead][harm,nodead] Shadow Word: Pain\n#mom swp",
		swd = "#showtooltip Shadow Word: Death\n/stopcasting\n/cast [@mouseover,harm,nodead][harm,nodead] Shadow Word: Death\n#mom swd",
		rez = "#showtooltip Resurrection\n/cast [@mouseover,help,dead][help,dead][] Resurrection\n#mom rez",
	}
	local n = 0
	for _, e in ipairs(ns.Entries()) do
		n = n + 1
		if want[e.key] then check(e.body == want[e.key], e.key .. " body changed:\n" .. e.body) end
		check(#e.body <= 255, e.key .. " too long")
		check(not e.body:find("@player") or e.key == "poh", e.key .. " casts on you")
		-- every current body without the marker is one of the legacy bodies (what older /mom wrote)
		local plain = e.body:gsub("\n#mom %w+$", "")
		local found = false
		for _, b in ipairs(ns.LEGACY.PRIEST[e.key] or { plain }) do if b == plain then found = true end end -- new macros have no old text
		check(found or e.key == "curedis", e.key .. " has no legacy body matching the current one") -- curedis: Abolish once known
	end
	check(n == 56, "56 priest macros (41 + 15 heal ranks), got " .. n)
	-- a body with no room for the marker goes without it
	local long = ns.Body({ "x", ("A"):rep(96), "help" })
	check(not long:find("#mom", 1, true) and #long <= 255, "marker past 255")
end)

step("before login nothing is touched; states before migration", function()
	check(edits == 0, "edited before login")
	check(entry("heal").status == "legacy" and entry("dispel").status == "legacy", "legacy seen")
	check(entry("fort").status == "new" and entry("fort").clash, "player's fort is a clash")
	check(entry("smite").clash and entry("smite").status == "new", "player's smite (other text) is a clash")
	check(isMom(entry("fort").macro), "planned name: " .. tostring(entry("fort").macro))
	check(entry("fort").macro == entry("fort").macro, "planned name is stable")
end)

step("migration at login: identical old macros renamed in place, the player's left alone", function()
	MOCK.log = {}
	MOCK.Fire("PLAYER_LOGIN")
	MOCK.Fire("PLAYER_ENTERING_WORLD")
	local heal, renew = macros.char[1], macros.char[3]
	check(isMom(heal.name) and heal.icon == 134400, "heal renamed in place: " .. heal.name)
	check(heal.body == entry("heal").body, "heal body brought up to date")
	check(isMom(renew.name), "renew (trailing newline) adopted")
	check(isMom(macros.account[1].name), "dispel (first version's text) adopted")
	check(macros.char[2].name == "fort" and macros.char[2].body == PLAYER_FORT, "player's fort touched")
	check(macros.account[2].name == "smite" and macros.account[2].body == "#showtooltip Smite\n/cast Smite", "player's smite touched")
	check(macros.account[3].body:find("player's", 1, true), "player's _mom1234 touched")
	check(macros.char[4].name == "Mount", "unrelated macro touched")
	local cdb, db = MouseoverMacrosCharDB, MouseoverMacrosDB
	check(cdb.owned.heal and cdb.owned.heal.name == heal.name and cdb.owned.heal.scope == "char" and cdb.owned.heal.created, "heal record")
	check(db.owned.dispel and db.owned.dispel.scope == "account" and not cdb.owned.dispel, "dispel record (account)")
	check(logHas("renamed 3 old /mom macros"), "migration message")
	check(entry("heal").status == "ok" and entry("dispel").status == "ok", "now ours and up to date")
	-- all names unique
	local seen = {}
	for _, m in pairs(all()) do check(not seen[m.name:lower()], "duplicate " .. m.name); seen[m.name:lower()] = true end
	-- a second login migrates nothing more
	local before = edits
	ns.RunMigration()
	check(edits == before, "second migration edited")
end)

step("Auto Self Cast is turned off at login (option on by default)", function()
	check(MOCK.cvars.autoSelfCast == "0", "not turned off")
	MOCK.cvars.autoSelfCast = "1"
	SlashCmdList.MOUSEOVERMACROS("autoselfcast off")
	check(MouseoverMacrosDB.autoSelfCastOff == false and last():find("off", 1, true), "option off: " .. last())
	MOCK.Fire("PLAYER_LOGIN")
	check(MOCK.cvars.autoSelfCast == "1", "changed the CVar with the option off")
	SlashCmdList.MOUSEOVERMACROS("autoselfcast on")
	check(MOCK.cvars.autoSelfCast == "0", "switching it on didn't apply it")
end)

step("bare /mom opens the window (no macros made); Escape closes it", function()
	local before = edits + #macros.char + #macros.account
	SlashCmdList.MOUSEOVERMACROS("")
	local f = MouseoverMacrosOptionsWindow
	check(f and f:IsShown(), "window not shown")
	check(edits + #macros.char + #macros.account == before, "bare /mom changed macros")
	f:GetScript("OnKeyDown")(f, "ESCAPE")
	check(not f:IsShown(), "escape didn't close")
end)

step("a clash: ours is made under a _mom name, the player's fort stays", function()
	local planned = entry("fort").macro
	SlashCmdList.MOUSEOVERMACROS("create fort")
	check(find("fort").body == PLAYER_FORT, "player's fort overwritten")
	local m = find(planned)
	check(m and m.body == entry("fort").body, "ours not made as " .. planned)
	check(entry("fort").status == "ok" and not entry("fort").clash, "fort now ours")
	check(last():find(planned, 1, true), "reply names the macro: " .. last())
end)

step("install all: switched-off skipped, character first then account, nothing of the player's edited", function()
	SlashCmdList.MOUSEOVERMACROS("off penance")
	check(MouseoverMacrosDB.off.penance, "off")
	SlashCmdList.MOUSEOVERMACROS("off nosuch")
	check(last():find("no macro called", 1, true) and last():find("renew", 1, true), "unknown macro reply: " .. last())
	SlashCmdList.MOUSEOVERMACROS("off")
	check(last():find("Example: /mom off renew", 1, true), "missing name reply: " .. last())
	SlashCmdList.MOUSEOVERMACROS("install")
	check(entry("penance").status == "new", "switched-off macro created")
	check(#macros.char == 18, "character macros filled first: " .. #macros.char)
	check(last():find("created 26, updated 4", 1, true) and last():find("26 switched off", 1, true), "summary: " .. last())
	check(find("fort").body == PLAYER_FORT and find("smite").body == "#showtooltip Smite\n/cast Smite"
		and find("_mom1234").body:find("player's", 1, true) and find("Mount"), "player's macros changed")
	for _, e in ipairs(ns.Entries()) do
		if e.on then check(e.status == "ok" and isMom(e.macro), e.key .. " " .. e.status) end
	end
	SlashCmdList.MOUSEOVERMACROS("on penance")
	SlashCmdList.MOUSEOVERMACROS("all")
	check(last():find("created 1, updated 30", 1, true), "second install: " .. last())
	check(MouseoverMacrosDB.owned.penance and MouseoverMacrosDB.owned.penance.scope == "account", "account record when character is full")
end)

step("ours changed by hand shows as changed; Update restores; renamed by the player is found by its marker", function()
	local m = find(entry("heal").macro)
	m.body = "/cast Heal\n#mom heal"
	check(entry("heal").status == "differs", "not seen as changed")
	SlashCmdList.MOUSEOVERMACROS("create heal")
	check(entry("heal").status == "ok" and m.body == entry("heal").body, "create didn't restore it")
	check(ns.Find("HEAL") ~= nil, "keys are case-insensitive")
	m.name = "MyHeal"
	local e = entry("heal")
	check(e.status == "ok" and e.macro == "MyHeal", "renamed macro not found: " .. e.status)
	check(MouseoverMacrosCharDB.owned.heal.name == "MyHeal", "record follows the rename")
	SlashCmdList.MOUSEOVERMACROS("create heal")
	check(m.name == "MyHeal", "update renamed it back")
end)

step("deleted by the player: missing, Create makes a new one with a new name", function()
	local old = entry("rez").macro
	local i = GetMacroIndexByName(old)
	DeleteMacro(i)
	local e = entry("rez")
	check(e.status == "missing" and e.macro ~= old and isMom(e.macro), "missing state: " .. e.status)
	SlashCmdList.MOUSEOVERMACROS("create rez")
	check(entry("rez").status == "ok" and entry("rez").macro ~= old, "not recreated")
end)

step("new names never collide (random retries)", function()
	local seq = { 1234, 1234, 4821 }
	local real = math.random
	math.random = function() return table.remove(seq, 1) or real(0, 9999) end
	local n = ns.NewName()
	math.random = real
	check(n == "_mom4821", "collision not retried: " .. tostring(n))
end)

step("full everywhere: clear message, nothing created", function()
	DeleteMacro(GetMacroIndexByName(entry("swp").macro))
	local saveA, saveC = macros.account, macros.char
	macros.account, macros.char = {}, {}
	for i = 1, 120 do macros.account[i] = saveA[i] or { name = "acc" .. i, body = "/say " .. i } end
	for i = 1, 18 do macros.char[i] = saveC[i] or { name = "chr" .. i, body = "/say " .. i } end
	SlashCmdList.MOUSEOVERMACROS("create swp")
	check(last():find("no room for swp", 1, true) and last():find("all used", 1, true), "full reply: " .. last())
	macros.account, macros.char = saveA, saveC
	SlashCmdList.MOUSEOVERMACROS("create swp")
	check(entry("swp").status == "ok", "swp back")
end)

step("new macros go to account macros when chosen", function()
	DeleteMacro(GetMacroIndexByName(entry("smite").macro))
	DeleteMacro(GetMacroIndexByName(entry("renew").macro))
	SlashCmdList.MOUSEOVERMACROS("where account")
	check(MouseoverMacrosDB.where == "account", "where")
	SlashCmdList.MOUSEOVERMACROS("create smite")
	check(MouseoverMacrosDB.owned.smite and MouseoverMacrosDB.owned.smite.scope == "account", "not an account macro")
	SlashCmdList.MOUSEOVERMACROS("where somewhere")
	check(last():find("character, account", 1, true), "bad choice reply: " .. last())
	SlashCmdList.MOUSEOVERMACROS("where character")
	SlashCmdList.MOUSEOVERMACROS("create renew")
	check(MouseoverMacrosCharDB.owned.renew.scope == "char", "character again")
end)

step("combat: nothing touched, the request is queued and runs when combat ends", function()
	DeleteMacro(GetMacroIndexByName(entry("mblast").macro))
	MOCK.combat = true
	SlashCmdList.MOUSEOVERMACROS("create mblast")
	check(last():find("in combat", 1, true) and last():find("when combat ends", 1, true), "combat reply: " .. last())
	SlashCmdList.MOUSEOVERMACROS("install")
	check(last():find("in combat", 1, true), "combat reply (install)")
	check(entry("mblast").status == "missing", "made in combat")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check(entry("mblast").status == "ok", "queue didn't run")
	check(ns.queue.all == false and next(ns.queue.keys) == nil, "queue not emptied")
end)

-- Rows of a list now shown (the Macros list unless another is given).
local function shownRows(list)
	list = list or ns.macroList
	local out = {}
	for _, r in ipairs(list.rows) do if r.item ~= nil and r:IsShown() then out[#out + 1] = r end end
	return out
end
local function rowFor(pred, list) for _, r in ipairs(shownRows(list)) do if pred(r.item) then return r end end end
local function click(b) b:GetScript("OnClick")(b) end
local function typeInto(box, text)
	box:SetText(text)
	box:GetScript("OnTextChanged")(box, true)
end
local function searchFor(text) typeInto(ns.macroSearch, text) end   -- the Macros list's search
local function quickFor(text) typeInto(ns.quickSearch, text) end    -- the quick picks' search
-- A game macro by name (account or character), as the window sees it.
local function named(name) return ns.Fresh({ kind = "game", scope = "account", name = name }) or ns.Fresh({ kind = "game", scope = "char", name = name }) end
local function template(id) for _, t in ipairs(ns.TEMPLATES) do if t.id == id then return t end end end
-- The text of a note on the editor's side saying `s`.
local function editorSays(s)
	for _, w in ipairs(ns.editStack.widgets) do
		if w.text and (w.text:GetText() or ""):find(s, 1, true) then return true end
	end
end

step("quick picks: the set and the templates, with Create / Update / Put on bar, drag and the switches", function()
	ns.app:Open("templates") -- the old page: the mouseover builder and its quick picks
	check(ns.app.current == "builder", "templates did not open the builder: " .. tostring(ns.app.current))
	local list = ns.quickList
	local rows = shownRows(list)
	check(#rows == #ns.Entries() + #ns.Templates(), "rows: " .. #rows)
	local smite = rowFor(function(it) return it.e and it.e.key == "smite" end, list)
	local dplague = rowFor(function(it) return it.e and it.e.key == "dplague" end, list)
	check(smite.switch:IsShown(), "the on/off switch")
	check(smite.buttons[1]:GetText() == "Up to date" and smite.buttons[2]:IsShown(), "existing macro row")
	check(smite.title:GetText():find(entry("smite").macro, 1, true), "row shows the macro name")
	click(smite.buttons[2])
	check(MOCK.picked == GetMacroIndexByName(entry("smite").macro), "Put on bar")
	MOCK.picked = nil
	smite:GetScript("OnDragStart")(smite)
	check(MOCK.picked == GetMacroIndexByName(entry("smite").macro), "drag a quick pick onto a bar")
	-- in combat the game blocks PickupMacro: the game's macro window opens instead, one line, nothing queued
	MOCK.picked = nil
	local realShow, opened = ns.ShowBlizzardMacros, 0
	ns.ShowBlizzardMacros = function() opened = opened + 1 end
	MOCK.combat = true
	MOCK.Fire("PLAYER_REGEN_DISABLED")
	local jobs = #ns.queue.jobs
	click(smite.buttons[2])
	check(MOCK.picked == nil and opened > 0 and logHas("Put on bar works after combat"), "Put on bar in combat: " .. last())
	ns.PickUp(ns.List("account")[1])
	check(MOCK.picked == nil and #ns.queue.jobs == jobs, "ns.PickUp in combat picked up or queued")
	ns.ShowBlizzardMacros = realShow
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	DeleteMacro(GetMacroIndexByName(entry("dplague").macro))
	MOCK.Fire("UPDATE_MACROS")
	ns.app:Refresh()
	check(dplague.buttons[1]:GetText() == "Create" and not dplague.buttons[2]:IsShown(), "missing macro row")
	check(dplague.detail:GetText():find("missing", 1, true), "missing state shown: " .. dplague.detail:GetText())
	click(dplague.buttons[1])
	check(entry("dplague").status == "ok", "Create button")
	dplague.switch:GetScript("OnMouseDown")(dplague.switch)
	check(MouseoverMacrosDB.off.dplague, "row switch")
	ns.app:Close()
end)

step("lost saved variables: a _mom name with our marker is recognised; the player's _mom1234 is not", function()
	local healName = entry("heal").macro
	MouseoverMacrosCharDB.owned.shield = nil
	local e = entry("shield")
	check(e.status == "ok", "marker+name not recognised: " .. e.status)
	check(not ns.IsOurs("_mom1234"), "player's _mom1234 taken as ours")
	check(healName == "MyHeal", "heal kept its player name")
end)

-- Phase 2: the macro manager -------------------------------------------------
local KNOWN = { Renew = true, Heal = true, ["Inner Focus"] = true, ["Greater Heal"] = true, Shoot = true }
C_Spell.GetSpellInfo = function(x)
	if MOCK.known[x] then return { name = x, spellID = MOCK.known[x], iconID = 2000 + MOCK.known[x] } end
	if KNOWN[x] then return { name = x } end
end
C_Item.GetItemInfoInstant = function(x) if x == "Hearthstone" then return 6948 end end
GetMacroIcons = function(t) for _, v in ipairs({ 135953, 136000, "Spell_Holy_Renew", "INV_Misc_Bag_07" }) do t[#t + 1] = v end end
GetMacroItemIcons = function(t) t[#t + 1] = 133784 end

step("every page opens; the sidebar is Macros, Mouseover builder, Ring, Backups, Options; old pages land on Macros", function()
	for _, id in ipairs({ "macros", "builder", "backups", "ring", "options" }) do
		ns.app:Open(id)
		check(ns.app.current == id and ns.app.sections[id].stack, id .. " not built")
	end
	for _, id in ipairs({ "mine", "account", "char", "ext", "edit", "list" }) do
		ns.app:Open(id)
		check(ns.app.current == "macros", id .. " -> " .. tostring(ns.app.current))
	end
	local o = ns.app.order
	check(table.concat(o, ",") == "macros,builder,ring,backups,options", "sidebar order: " .. table.concat(o, ","))
	local nav = ns.app.window.navButtons
	check(nav.macros:IsShown() and nav.builder:IsShown() and nav.ring:IsShown(), "sidebar buttons")
	local line = ns.CountsLine()
	check(line:find("Account", 1, true) and line:find("Character", 1, true) and not line:find("Extended", 1, true), "counts line: " .. line)
	ns.app:Close()
end)

step("editor: any macro opens next to the list; the player's own can be edited; limits; history and restore", function()
	local mount = ns.GameRef(GetMacroIndexByName("Mount"))
	check(not mount.ours, "Mount is not ours")
	ns.app:Open("macros")
	searchFor("riding")
	local row = rowFor(function(it) return it.name == "Mount" end)
	check(row and row.title:GetText() == "Riding Turtle" and row.detail:GetText():find("Mount", 1, true)
		and row.detail:GetText():find("character", 1, true), "readable name first, macro name and kind after")
	click(row)
	check(ns.app.current == "macros" and ns.ed.ref and ns.ed.ref.name == "Mount" and ns.ed.body == "/cast Riding Turtle", "editor loaded")
	-- the open macro's row and the editor's icon go onto the bars
	MOCK.picked = nil
	row:GetScript("OnDragStart")(row)
	check(MOCK.picked == GetMacroIndexByName("Mount"), "drag the row")
	MOCK.picked = nil
	ns.editorIcon:GetScript("OnDragStart")(ns.editorIcon)
	check(MOCK.picked == GetMacroIndexByName("Mount"), "drag the editor's icon")
	MOCK.picked = nil
	click(ns.putOnBar)
	check(MOCK.picked == GetMacroIndexByName("Mount"), "Put on bar")
	MOCK.picked = nil
	click(row.buttons[1])
	check(MOCK.picked == GetMacroIndexByName("Mount"), "the row's Put on bar")
	searchFor("")
	ns.ed.body = "/cast Riding Turtle\n/say off we go"
	local ok = ns.EditorSave()
	check(ok and find("Mount").body == "/cast Riding Turtle\n/say off we go", "saved")
	check(ns.History(ns.ed.ref)[1].body == "/cast Riding Turtle", "history")
	ns.ed.name = "A name over sixteen"
	check(not ns.EditorSave(), "long name accepted")
	ns.ed.name, ns.ed.body = "Mount", ("x"):rep(256)
	check(not ns.EditorSave(), "256 characters accepted in a game macro")
	ns.ed.body = ns.History(ns.ed.ref)[1].body
	ns.EditorSave()
	check(find("Mount").body == "/cast Riding Turtle", "restore")
	-- earlier versions are tucked away until opened
	ns.app:Refresh()
	check(not ns.historyList:IsShown() and ns.historyToggle:GetText():find("Earlier versions (2)", 1, true), "history folded: " .. ns.historyToggle:GetText())
	click(ns.historyToggle)
	check(ns.historyList:IsShown(), "history opens")
	click(ns.historyToggle)
	ns.ed.name = "Mount2"
	ns.EditorSave()
	check(find("Mount2") and ns.ed.ref.name == "Mount2" and #ns.History(ns.ed.ref) == 2, "rename keeps the history")
	ns.EditorInsert("[mod:shift] ")
	check(ns.ed.body:find("[mod:shift]", 1, true), "insert")
	check(not find("_mom1234").body:find("#mom", 1, true), "player's _mom1234 untouched")
end)

step("a new macro: a character slot, else an account one (and says why); both full: says so plainly, makes nothing", function()
	ns.EditNew() -- the insert above is not saved: it asks
	answer("discard")
	check(ns.ed.ref == nil and ns.ed.as == "char", "a new macro starts as a character macro")
	check(editorSays("it goes to an account slot (character macros are full)"), "the editor says where it goes")
	ns.ed.name, ns.ed.body = "Hearth", "/use Hearthstone"
	local ok, msg = ns.EditorSave()
	check(ok and ns.ed.ref and ns.ed.ref.scope == "account", "character full: account: " .. tostring(msg))
	check(msg:find("character macros are full", 1, true) and ns.ed.status.text:find("account macro", 1, true), "says why: " .. msg)
	ns.EditNew("account")
	ns.ed.name, ns.ed.body = "AccOne", "/say hi"
	check(ns.EditorSave() and ns.ed.ref.scope == "account", "account macro")
	check(ns.EditorSave(true) and ns.ed.ref.name == "AccOne 2" and named("AccOne"), "save as copy: " .. ns.ed.ref.name)
	-- every slot used: one plain line, nothing made, never somewhere hidden
	local saveA = macros.account
	macros.account = {}
	for i = 1, 120 do macros.account[i] = saveA[i] or { name = "acc" .. i, body = "/say " .. i } end
	ns.EditNew()
	ns.ed.name, ns.ed.body = "NoSlot", "/say none"
	ok, msg = ns.EditorSave()
	check(not ok and msg:find("no free macro slot", 1, true) and msg:find("Delete one first", 1, true) and not named("NoSlot"), "both full: " .. tostring(msg))
	check(editorSays("no free macro slot"), "the editor doesn't say there is no slot")
	macros.account = saveA
	ns.app:Close()
	answer("discard")
	ns.DeleteGame(named("AccOne 2"))
	ns.DeleteGame(named("AccOne"))
end)

step("move to account / character respects the slot limits; ours keeps its record", function()
	local heal = ns.Fresh({ kind = "game", scope = "char", name = "MyHeal" })
	check(heal and heal.ours and heal.scope == "char", "heal is a character macro of ours")
	local ok, msg = ns.MoveGame(heal, "account")
	check(ok and find("MyHeal") and GetMacroIndexByName("MyHeal") <= 120, "moved: " .. tostring(msg))
	check(MouseoverMacrosDB.owned.heal and MouseoverMacrosDB.owned.heal.scope == "account" and not MouseoverMacrosCharDB.owned.heal, "record moved")
	check(entry("heal").status == "ok", "still ours")
	ok = ns.MoveGame(ns.Fresh({ kind = "game", scope = "account", name = "MyHeal" }), "char")
	check(ok, "moved back")
	ok, msg = ns.MoveGame(named("Hearth"), "char")
	check(not ok and msg:find("no room", 1, true), "full move: " .. tostring(msg))
	-- the editor's "Stored as" moves the open macro
	ns.Edit(named("Hearth"))
	ns.EditorMove("char")
	check(named("Hearth").scope == "account" and logHas("no room"), "Stored as moved it into a full list")
	ns.app:Close()
end)

step("delete: one click, into the bin, the editor starts a new macro; Undo on the list puts it back; Backups restores", function()
	ns.Edit(named("Hearth"))
	local del = ns.saveRow.buttons[4]
	check(del:GetText() == "Delete", "Delete button: " .. tostring(del:GetText()))
	click(del)
	check(not find("Hearth"), "not deleted on the first click")
	check(MouseoverMacrosDB.bin[1].name == "Hearth", "not in the bin")
	check(ns.app.current == "macros" and ns.ed.ref == nil and ns.ed.as == "account", "the editor still holds the deleted macro")
	check(last():find("deleted Hearth", 1, true) and last():find("/mom undo", 1, true), "chat: " .. last())
	check(ns.Status() and ns.undoButton:GetParent():IsShown() and ns.statusNote.text:GetText():find("Deleted Hearth", 1, true), "status line with Undo")
	click(ns.undoButton)
	check(find("Hearth") and find("Hearth").body == "/use Hearthstone", "undo")
	check(not ns.Status() and not ns.undoButton:GetParent():IsShown(), "Undo still shown")
	check(not MouseoverMacrosDB.bin[1] or MouseoverMacrosDB.bin[1].name ~= "Hearth", "undo left it in the bin")
	SlashCmdList.MOUSEOVERMACROS("undo")
	check(last():find("nothing to undo", 1, true), "second undo: " .. last())
	ns.DeleteMacros({ named("Hearth") })
	check(not find("Hearth"), "ns.DeleteMacros")
	ns.app:Open("backups")
	local list
	for _, w in ipairs(ns.app.sections.backups.stack.widgets) do if w.rows and not list then list = w end end
	click(list.rows[1].buttons[1])
	check(find("Hearth") and find("Hearth").body == "/use Hearthstone", "restore from the bin")
	ns.app:Close()
end)

step("export / import round trip; nothing replaced; an older export's extended ones become macros", function()
	local odd = "#showtooltip\n/say a|b; c, d 100%\n/cast Renew"
	check(ns.CreateGame("account", "Odd one", "Spell_Holy_Renew", odd), "made")
	local text = ns.Export({ named("Odd one"), named("Hearth") })
	check(text:match("^MOM1\n") and not text:find("|", 1, true), "export text: " .. text)
	local list = assert(ns.ParseExport(text))
	check(#list == 2 and list[1].body == odd and list[1].icon == "Spell_Holy_Renew" and list[2].kind == "a", "parse")
	local ok, msg = ns.Import({ list[2] })
	check(ok and find("Hearth 2") and find("Hearth").body == "/use Hearthstone", "taken name numbered, original kept")
	ok, msg = ns.Import({ { kind = "x", name = "OldExt", icon = 134400, body = "/say old" }, { kind = "x", name = "TooLong", body = ("x"):rep(300) } })
	check(ok and named("OldExt") and named("OldExt").scope == "account" and msg:find("not made: TooLong", 1, true), "an old extended import: " .. tostring(msg))
	check(not ns.ParseExport("hello"), "garbage accepted")
	ns.app:Open("backups")
	local exportRow
	for _, w in ipairs(ns.app.sections.backups.stack.widgets) do
		if w.buttons and w.buttons[1]:GetText() == "Export" then exportRow = w end
	end
	click(exportRow.buttons[1])
	check(ns.exportBox:GetText():match("^MOM1"), "export button")
	ns.app:Close()
	for _, n in ipairs({ "Odd one", "Hearth 2", "OldExt" }) do ns.DeleteGame(named(n)) end
end)

step("line check: unknown spells, #showtooltip placement, slots and sequences", function()
	local p = ns.CheckLines("#showtooltip Renew\n/cast [@mouseover,help,nodead][help,nodead] Renew\n/cast Renwe\n#showtooltip\n/use 13\n/use Hearthstone\n/castsequence reset=3 Renew, Heal, Smiite")
	local lines = {}
	for _, x in ipairs(p) do lines[#lines + 1] = x.line .. ":" .. x.text end
	local s = table.concat(lines, "\n")
	check(#p == 3, "problems:\n" .. s)
	check(s:find('3:"Renwe"', 1, true) and s:find("4:#showtooltip only", 1, true) and s:find('7:"Smiite"', 1, true), s)
	check(#ns.CheckLines(("x"):rep(300), 255) == 1, "length")
	-- the editor's live check
	ns.EditNew()
	ns.ed.name, ns.ed.body = "Check", "#showtooltip\n/cast Renwe"
	ns.app:Refresh()
	check(editorSays("24 / 255 characters") and editorSays('line 2:'), "live check")
	ns.EditorRevert()
	ns.app:Refresh()
	check(editorSays("every spell and item name checks out"), "a clean text")
	ns.app:Close()
end)

step("templates: a _mom macro, updated, never duplicated", function()
	local t = ns.Templates()[1]
	check(t.id == "trinkets", "first template")
	local ok, msg = ns.MakeTemplate(t)
	check(ok and ns.Resolve("t:trinkets"), "made: " .. tostring(msg))
	local _, name = ns.Resolve("t:trinkets")
	local before = GetNumMacros()
	ns.MakeTemplate(t)
	check(GetNumMacros() == before and select(2, ns.Resolve("t:trinkets")) == name, "duplicated")
	local ids = {}
	for _, x in ipairs(ns.Templates()) do ids[x.id] = true end
	check(ids.wand and ids.ifheal and ids.dpfheal and ids.dppi, "priest templates")
	check(template("dpfheal").body == "#showtooltip\n/cast [@mouseover,help,nodead] Flash Heal(Rank 1); [@mouseover,harm,nodead][harm,nodead] Devouring Plague; [help,nodead] Flash Heal(Rank 1)",
		"the Devouring Plague / Flash Heal rank 1 text")
end)

step("icon search: ? first, file names and IDs", function()
	local all = ns.SearchIcons("")
	check(all[1] == 134400 and #all == 6, "all icons: " .. #all)
	local r = ns.SearchIcons("renew")
	check(r[1] == 134400 and r[2] == "Spell_Holy_Renew" and #r == 2, "by name")
	check(#ns.SearchIcons("1359") == 2, "by ID")
	ns.EditNew()
	ns.ed.picking = true
	ns.app:Refresh()
	check(ns.picker:IsShown(), "picker shown")
	click(ns.picker.cells[2])
	check(ns.ed.icon == 135953 and not ns.ed.picking, "pick an icon")
	ns.app:Close() -- a new icon is a change: closing asks
	check(ns.app:IsShown(), "closed with an unsaved icon")
	answer("discard")
	check(not ns.app:IsShown() and ns.ed.icon == 134400, "discard did not close and revert")
end)

step("extended macros of 0.3.9 become normal macros at login: bars edited in place, keys named, ring slices, the bin", function()
	local db, cdb = MouseoverMacrosDB, MouseoverMacrosCharDB
	local BIG = "#showtooltip Renew\n/cast [@mouseover,help,nodead][help,nodead] Renew"
	db.ext = {
		[1] = { name = "Big renew", icon = 135953, body = BIG },
		[2] = { name = "Hearth X", body = "/use Hearthstone" },
		[3] = { name = "Huge", body = "/say " .. ("x"):rep(400) },
	}
	db.extNext = 4
	db.history.x1 = { { t = 1, body = "/cast Renew" } }
	db.owned.x1 = { name = "_mom5555", scope = "account" }
	cdb.binds = { [1] = "CTRL-1", [3] = "F5" }
	-- Big renew is on the bars twice (two bar macros); Huge once
	check(CreateMacro("_mom5555", 134400, "#showtooltip Renew\n/click MoMX_1 LeftButton 1\n#mom x1", false), "bar 1")
	check(CreateMacro("_mom5556", 134400, "#showtooltip\n/click MoMX_1\n#mom x1", false), "bar 2")
	check(CreateMacro("_mom5557", 134400, "/click MoMX_3 LeftButton 1\n#mom x3", false), "bar 3")
	local barIndex = GetMacroIndexByName("_mom5555")
	db.ring.top[2] = { kind = "ext", id = 2 }
	local sub = db.ring.top[3]
	local nItems = #sub.items
	sub.items[#sub.items + 1] = { kind = "ext", id = 3 }
	-- in combat: waits
	MOCK.combat = true
	MOCK.Fire("PLAYER_ENTERING_WORLD")
	check(db.ext and db.ext[1] and find("_mom5555"), "changed in combat")
	MOCK.log = {}
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check(db.ext == nil and db.extNext == nil, "the extended table is still there")
	local big = named("Big renew")
	check(big and big.index == barIndex and big.body == BIG and big.icon == 135953, "the bar macro was not turned into it in place")
	check(not find("_mom5556") and not find("_mom5557"), "the second bar macro and Huge's are left over")
	check(named("Hearth X") and named("Hearth X").scope == "account", "no bar: made in an account slot")
	check(db.bin[1].name == "Huge" and #db.bin[1].body > 255, "Huge not in the bin")
	check(logHas("kept in the bin under Backups") and logHas("Huge (405 characters"), "Huge not named in chat")
	check(logHas("2 became normal macros (Big renew, Hearth X)"), "summary line")
	check(logHas("key bindings on this character are gone: CTRL-1, F5"), "keys line")
	check(cdb.binds == nil and db.owned.x1 == nil and db.history.x1 == nil, "leftovers")
	check(#ns.History(big) == 1 and ns.History(big)[1].body == "/cast Renew", "history moved")
	check(db.ring.top[2].kind == "macro" and db.ring.top[2].name == "Hearth X", "ring slice: " .. tostring(db.ring.top[2].kind))
	check(#sub.items == nItems, "the binned one's ring slice is still there")
	check(db.extMoved[1].name == "Big renew", "moved record")
	for _, m in pairs(all()) do check(not m.body:find("MoMX_", 1, true), "a /click MoMX_ macro is left: " .. m.name) end
	-- a second login changes nothing
	local before = edits
	MOCK.Fire("PLAYER_ENTERING_WORLD")
	check(edits == before, "migrated twice")
	-- another character's bar macro for it: turned into the macro there too
	local saved = macros.char[18]
	macros.char[18] = { name = "_mom7777", icon = 134400, body = "#showtooltip\n/click MoMX_1 LeftButton 1\n#mom x1" }
	MOCK.Fire("PLAYER_ENTERING_WORLD")
	check(macros.char[18].body == BIG and macros.char[18].name == "Big renew", "another character's bar: " .. macros.char[18].name)
	macros.char[18] = saved
	db.ring.top[2] = false
	ns.Ring.Rebuild()
	ns.DeleteGame(named("Hearth X"))
	ns.DeleteGame(named("Big renew"))
end)

step("mouseover builder: the text for a friend, an enemy or both; ranks; options; a short name; never a self cast", function()
	local B = ns.BuildMouseover
	local body, name = B({ friend = "Flash Heal", friendRank = 1, enemy = "Devouring Plague" })
	check(body == template("dpfheal").body, "both: " .. tostring(body))
	check(name == "DP / FH r1", "name: " .. tostring(name))
	body, name = B({ friend = "Power Infusion", enemy = "Devouring Plague" })
	check(body == template("dppi").body and name == "DP / PI", "Power Infusion: the whisper line: " .. body)
	check(not B({ friend = "Power Infusion", enemy = "Devouring Plague", whisper = false }):find("/mom pi", 1, true), "whisper off")
	body, name = B({ friend = "Renew" })
	check(body == "#showtooltip Renew\n/cast [@mouseover,help,nodead][help,nodead] Renew" and name == "Renew", "friend only: " .. body)
	body, name = B({ enemy = "Shadow Word: Pain", fallback = false, stop = true })
	check(body == "#showtooltip Shadow Word: Pain\n/stopcasting\n/cast [@mouseover,harm,nodead] Shadow Word: Pain" and name == "SWP", "enemy only, no fallback: " .. body .. " / " .. name)
	body = B({ friend = "Flash Heal", enemy = "Smite", fallback = false })
	check(body == "#showtooltip\n/cast [@mouseover,help,nodead] Flash Heal; [@mouseover,harm,nodead] Smite", "both, no fallback: " .. body)
	body, name = B({ friend = "Heal", friendRank = 2 })
	check(body:find("Heal(Rank 2)", 1, true) and name == "Heal r2", "a rank: " .. name)
	check(B({}) == nil and B({ friend = "", enemy = "" }) == nil, "nothing picked")
	for _, o in ipairs({ { friend = "Heal" }, { enemy = "Smite" }, { friend = "Heal", enemy = "Smite" }, { friend = "Heal", enemy = "Smite", fallback = false } }) do
		local t = B(o)
		check(not t:find("@player", 1, true) and not t:find("target=player", 1, true) and #t <= 255, "a self cast: " .. t)
	end
end)

MOCK.book = { { "Flash Heal", "Rank 7" }, { "Flash Heal", "Rank 1" }, { "Devouring Plague", "Rank 6" }, { "Power Infusion", "" },
	{ "Spirit Tap", "Passive", true }, { "Renew", "Rank 10" } }
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 1 end,
	GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #MOCK.book } end,
	GetSpellBookItemInfo = function(slot)
		local b = MOCK.book[slot]
		if b then return { name = b[1], subName = b[2], spellID = 9000 + slot, iconID = 3000 + slot, isPassive = b[3] or false } end
	end,
}

step("mouseover builder page: spells from the spellbook with their ranks, a suggested name; Create saves it and puts it on the cursor", function()
	local book = ns.SpellBook()
	local names = {}
	for _, s in ipairs(book) do names[#names + 1] = s.name .. ":" .. tostring(s.rank) end
	check(table.concat(names, ",") == "Devouring Plague:6,Flash Heal:7,Power Infusion:nil,Renew:10", "spellbook: " .. table.concat(names, ","))
	ns.app:Open("builder")
	check(ns.builderCreate:GetAlpha() < 1, "Create usable with nothing picked")
	local f, e = ns.builderFriend, ns.builderEnemy
	typeInto(f.box, "flash")
	local rows = shownRows(f.list)
	check(f.list:IsShown() and #rows == 1 and rows[1].item.name == "Flash Heal" and rows[1].title:GetText():find("Rank 7", 1, true), "friend picker")
	click(rows[1])
	check(ns.bd.friend == "Flash Heal" and not f.list:IsShown() and f.box:GetText() == "Flash Heal", "picked")
	typeInto(e.box, "devour")
	click(shownRows(e.list)[1])
	check(ns.bd.enemy == "Devouring Plague", "enemy picked")
	ns.bd.friendRank = 1 -- the rank dropdown
	ns.app:Refresh()
	check(ns.BuiltName() == "DP / FH r1" and ns.builderCreate:GetAlpha() == 1, "suggested name: " .. tostring(ns.BuiltName()))
	-- Create: the character list is full, so an account slot; on the cursor at once
	MOCK.picked = nil
	local a0 = #macros.account
	MOCK.log = {}
	click(ns.builderCreate)
	local m = named("DP / FH r1")
	check(m and m.scope == "account" and #macros.account == a0 + 1 and m.body == template("dpfheal").body, "not made")
	check(MOCK.picked == m.index and last():find("on your cursor", 1, true), "not on the cursor: " .. last())
	-- again: a new macro under a numbered name, nothing replaced
	click(ns.builderCreate)
	check(named("DP / FH r1 2") and named("DP / FH r1").body == m.body, "second Create")
	-- in combat: said at once, made once after combat
	MOCK.combat = true
	click(ns.builderCreate)
	check(last():find("will be made when combat ends", 1, true) and not named("DP / FH r1 3"), "combat: " .. last())
	check(ns.builderCreate:GetText() == "Cancel", "Create while it waits: " .. ns.builderCreate:GetText())
	click(ns.builderCreate)
	check(last():find("cancelled", 1, true), "cancel: " .. last())
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check(not named("DP / FH r1 3"), "made although cancelled")
	MOCK.combat = true
	click(ns.builderCreate)
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check(named("DP / FH r1 3") and not named("DP / FH r1 4") and ns.builderCreate:GetText() == "Create", "after combat")
	-- every slot used: says so plainly, makes nothing
	local saveA = macros.account
	macros.account = {}
	for i = 1, 120 do macros.account[i] = saveA[i] or { name = "acc" .. i, body = "/say " .. i } end
	click(ns.builderCreate)
	check(last():find("no free macro slot", 1, true) and last():find("Delete one first", 1, true), "both full: " .. last())
	macros.account = saveA
	-- a typed name wins over the suggestion
	ns.bd.name = "Mine"
	check(ns.BuiltName() == "Mine", "typed name")
	ns.bd.name = ""
	check(ns.BuiltName() == "DP / FH r1", "an empty name goes back to the suggestion")
	for _, n in ipairs({ "DP / FH r1", "DP / FH r1 2", "DP / FH r1 3" }) do ns.DeleteGame(named(n)) end
	ns.bd.friend, ns.bd.enemy, ns.bd.friendRank = nil, nil, nil
	-- the editor's Insert spell: a spell from the spellbook into the text
	ns.EditNew()
	ns.app:Refresh()
	typeInto(ns.insertSpell.box, "renew")
	local r = shownRows(ns.insertSpell.list)[1]
	check(r and r.item.name == "Renew" and r.buttons[2]:IsShown(), "insert picker")
	click(r.buttons[1])
	check(ns.ed.body:find("Renew", 1, true) and not ns.insertSpell.list:IsShown(), "Insert: " .. ns.ed.body)
	ns.EditorRevert()
	ns.app:Close()
end)

step("help, list, settings and unknown commands", function()
	MOCK.log = {}
	SlashCmdList.MOUSEOVERMACROS("help")
	local s = table.concat(MOCK.log, "\n")
	for _, c in ipairs({ "install", "create <macro>", "on <macro>", "off <macro>", "list", "undo", "new", "build" }) do
		check(s:find("/mom " .. c, 1, true), "help lacks " .. c)
	end
	MOCK.log = {}
	SlashCmdList.MOUSEOVERMACROS("list")
	check(#MOCK.log == 56, "list lines: " .. #MOCK.log)
	check(table.concat(MOCK.log, "\n"):find("_mom", 1, true), "list shows names")
	SlashCmdList.MOUSEOVERMACROS("settings")
	SlashCmdList.MOUSEOVERMACROS("bogus")
	check(last():find("/mom help", 1, true), "unknown reply")
	check(last():find("EverlookDB Macros|r: ", 1, true), "chat prefix: " .. last())
	SlashCmdList.MOUSEOVERMACROS("build")
	check(ns.app:IsShown() and ns.app.current == "builder", "/mom build")
	SlashCmdList.MOUSEOVERMACROS("new account")
	check(ns.app.current == "macros" and ns.ed.ref == nil and ns.ed.as == "account", "/mom new account")
	ns.app:Close()
end)

step("the name is EverlookDB Macros; /emacros is an alias of /mom", function()
	check(ns.app.name == "EverlookDB Macros", "app name " .. tostring(ns.app.name))
	check(SLASH_MOUSEOVERMACROS1 == "/mom" and SLASH_MOUSEOVERMACROS2 == "/emacros", "slash words")
	MOCK.log = {}
	SlashCmdList.MOUSEOVERMACROS("help")
	check(table.concat(MOCK.log, "\n"):find("/emacros", 1, true), "help names /emacros")
end)

step("chat commands follow the shared pattern: get/set, a setting by on/off, suggestions, reset asks", function()
	SlashCmdList.MOUSEOVERMACROS("set takeover off")
	check(MouseoverMacrosDB.takeover == false or ns.app:GetSetting("takeover").get() == false, "set")
	SlashCmdList.MOUSEOVERMACROS("on takeover")
	check(ns.app:GetSetting("takeover").get() == true and last():find(": on", 1, true), "on <setting>: " .. last())
	SlashCmdList.MOUSEOVERMACROS("get where")
	check(last():find("Where new macros go", 1, true), "get: " .. last())
	SlashCmdList.MOUSEOVERMACROS("instal")
	check(last():find("Did you mean /mom install?", 1, true), "typo: " .. last())
	SlashCmdList.MOUSEOVERMACROS("reset")
	check(last():find("/mom reset ring", 1, true), "reset without a section: " .. last())
	MOCK.log = {}
	SlashCmdList.MOUSEOVERMACROS("?")
	local s = table.concat(MOCK.log, "\n")
	check(s:find("/mom reset ring", 1, true) and s:find("/mom search <words>", 1, true) and s:find("/mom get [setting]", 1, true), "help: " .. s)
end)

step("slot limits come from Constants.MacroConsts (30 character macros on this client)", function()
	Constants = { MacroConsts = { MAX_ACCOUNT_MACROS = 120, MAX_CHARACTER_MACROS = 30 } }
	check(ns.MaxChar() == 30 and ns.MaxAccount() == 120, "limits: " .. ns.MaxChar() .. "/" .. ns.MaxAccount())
	check(ns.CountsLine():find("/30", 1, true), "counts line: " .. ns.CountsLine())
	Constants = nil
	check(ns.MaxChar() == 18, "falls back to the global")
end)

step("every button row on every page fits the page width", function()
	for _, id in ipairs(ns.app.order) do
		ns.app:Open(id)
		local st = ns.app.sections[id].stack
		for _, sub in ipairs(st.stacks or { st }) do
			for _, e in ipairs(sub.entries) do
				local f = e.frame
				if f and f.buttons and not f.rows then
					local w = 0
					for i, b in ipairs(f.buttons) do w = w + b:GetWidth() + (i > 1 and 8 or 0) end
					check(w <= sub.width, ("%s: a row of buttons is %d px on a %d px page"):format(id, w, sub.width))
				end
			end
		end
	end
	ns.app:Close()
end)

step("the ring's key: when it takes over a key in use, says once what it replaced and how to change it", function()
	GetBindingAction = function(k) if k == "BUTTON3" then return "MOVEANDSTEER" end return "" end
	BINDING_NAME_MOVEANDSTEER = "Move and Steer"
	MouseoverMacrosCharDB.ringTold = nil
	local n = #MOCK.log
	ns.ApplyBindings(); ns.ApplyBindings()
	local said = 0
	for i = n + 1, #MOCK.log do if MOCK.log[i]:find("which did Move and Steer before", 1, true) then said = said + 1 end end
	check(said == 1, "told " .. said .. " times")
	check(logHas("/mom ring key <key>"), "says how to change it")
	check(ns.ringReplaces == "Move and Steer", "the Ring page shows it")
	GetBindingAction = function() return "" end
	n = #MOCK.log
	ns.ApplyBindings()
	check(#MOCK.log == n, "free key: no line")
	check(ns.ringReplaces == nil, "nothing replaced")
	GetBindingAction, BINDING_NAME_MOVEANDSTEER = nil, nil
end)

step("delete in the editor: a fresh editor of the same kind", function()
	check(ns.CreateGame("account", "DelMe", nil, "/say one"), "made")
	ns.SaveGame(named("DelMe"), "DelMe", nil, "/say two")
	check(#ns.History(named("DelMe")) == 1, "history")
	ns.Edit(named("DelMe"))
	click(ns.saveRow.buttons[4])
	check(not named("DelMe"), "not deleted")
	check(ns.ed.ref == nil and ns.ed.as == "account" and ns.ed.body == "#showtooltip\n" and ns.ed.name == "", "editor kept the deleted text")
	ns.app:Close()
end)

step("restore from the bin in combat: waits, then restores and leaves the bin", function()
	check(ns.CreateGame("account", "BinMe", nil, "/say bin"), "made")
	ns.DeleteGame(named("BinMe"))
	check(MouseoverMacrosDB.bin[1].name == "BinMe", "in the bin")
	ns.app:Open("backups")
	local list
	for _, w in ipairs(ns.app.sections.backups.stack.widgets) do if w.rows and not list then list = w end end
	MOCK.combat = true
	click(list.rows[1].buttons[1])
	check(MouseoverMacrosDB.bin[1].name == "BinMe", "left the bin in combat")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check(MouseoverMacrosDB.bin[1] == nil or MouseoverMacrosDB.bin[1].name ~= "BinMe", "still in the bin after combat")
	check(named("BinMe"), "not restored after combat")
	ns.DeleteGame(named("BinMe"))
	ns.app:Close()
end)

step("unsaved changes: another macro, New, another page, x, Escape and /mom ask Save / Discard / Cancel", function()
	check(ns.CreateGame("account", "Other", nil, "/say other"), "made")
	ns.EditNew()
	check(not (ns.unsavedDialog and ns.unsavedDialog:IsShown()), "asked with nothing changed")
	ns.ed.name, ns.ed.body = "Guarded", "/say guarded"
	local w = ns.app.window
	for _, leave in ipairs({
		function() ns.Edit(named("Other")) end,
		function() ns.EditNew("account") end,
		function() ns.app:ShowSection("builder") end,
		function() ns.app:Close() end,
		function() w.close:GetScript("OnClick")(w.close) end,
		function() w:GetScript("OnKeyDown")(w, "ESCAPE") end,
		function() SlashCmdList.MOUSEOVERMACROS("") end,
	}) do
		leave()
		answer("cancel")
		check(ns.app:IsShown() and ns.app.current == "macros" and ns.ed.name == "Guarded" and ns.ed.ref == nil, "cancel lost the editor")
	end
	check(not named("Guarded"), "saved without being asked")
	ns.EditNew("account")
	answer("save")
	check(named("Guarded") and ns.ed.ref == nil and ns.ed.as == "account", "save then new")
	ns.Edit(named("Guarded"))
	ns.ed.body = "/say changed"
	ns.app:ShowSection("builder")
	answer("discard")
	check(ns.app.current == "builder" and named("Guarded").body == "/say guarded" and ns.ed.body == "/say guarded", "discard")
	-- a save that fails stays in the editor
	ns.EditNew()
	ns.ed.body = "/say no name"
	ns.app:Close()
	answer("save")
	check(ns.app:IsShown() and ns.ed.body == "/say no name" and not ns.unsavedDialog:IsShown(), "failed save left the editor")
	-- the same macro, changed: just shows it again
	ns.Edit(named("Guarded"))
	answer("discard")
	ns.ed.body = "/say again"
	ns.app:ShowSection("backups")
	answer("cancel")
	ns.Edit(named("Guarded"))
	check(not ns.unsavedDialog:IsShown() and ns.ed.body == "/say again", "same macro asked or reloaded")
	-- Escape in combat with unsaved changes: left to the game (no question on top of the Game Menu)
	MOCK.combat = true
	MOCK.Fire("PLAYER_REGEN_DISABLED")
	w:GetScript("OnKeyDown")(w, "ESCAPE")
	check(not LibStub("EverlookUI-1").IsPopupShown() and not ns.unsavedDialog:IsShown(), "asked about unsaved changes in combat")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	ns.EditorRevert()
	ns.app:Close()
	check(not ns.app:IsShown(), "not closed")
	ns.DeleteGame(named("Guarded"))
	ns.DeleteGame(named("Other"))
	check(next(StaticPopupDialogs) == nil, "a StaticPopup was used")
end)

step("save in combat: waits once, saves the latest text after combat, never a duplicate", function()
	ns.EditNew("account")
	ns.ed.name, ns.ed.body = "CombatSave", "/say one"
	MOCK.combat = true
	local jobs = #ns.queue.jobs
	local ok, msg = ns.EditorSave()
	check(ok and msg == "queued" and ns.ed.pending and #ns.queue.jobs == jobs + 1, "not queued")
	check(last():find("in combat", 1, true) and last():find("when combat ends", 1, true), "combat reply: " .. last())
	local save, copy = ns.saveRow.buttons[1], ns.saveRow.buttons[3]
	check(save:GetAlpha() < 1 and copy:GetAlpha() < 1, "Save not greyed out")
	click(save)
	ns.EditorSave()
	check(#ns.queue.jobs == jobs + 1, "a second save was queued")
	check(editorSays("it will be saved when combat ends"), "no 'saved when combat ends' line")
	ns.ed.body = "/say two"
	check(not ns.EditorDirty(), "a queued save counts as unsaved")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	local made = named("CombatSave")
	check(made and made.body == "/say two" and not named("CombatSave 2"), "after combat")
	check(ns.ed.ref and ns.ed.ref.name == "CombatSave" and not ns.ed.pending, "editor still on a new macro")
	check(ns.ed.status and ns.ed.status.ok and ns.ed.status.text == "Saved after combat.", "status")
	check(logHas("after combat: created CombatSave as an account macro") and save:GetAlpha() == 1, "chat line / Save still grey")
	check(not ns.EditorDirty(), "saved text counts as unsaved")
	ns.DeleteGame(made)

	-- it fails after combat: says so in red, the text stays
	ns.EditNew("account")
	ns.ed.name, ns.ed.body = "NoRoom", "/say three"
	MOCK.combat = true
	ns.EditorSave()
	MOCK.combat = false
	local create = CreateMacro
	CreateMacro = function() return nil end
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	CreateMacro = create
	check(ns.ed.status and not ns.ed.status.ok and ns.ed.status.text:find("Not saved after combat", 1, true), "failure status")
	check(ns.ed.ref == nil and ns.ed.body == "/say three" and ns.EditorDirty(), "text lost after a failed save")
	ns.app:Close()
	answer("discard")

	-- left for another macro while it waits: it still saves the text as it was left
	ns.EditNew("account")
	ns.ed.name, ns.ed.body = "LeftBehind", "/say four"
	MOCK.combat = true
	ns.EditorSave()
	ns.ed.body = "/say five"
	ns.EditNew("account")
	check(not ns.unsavedDialog:IsShown() and ns.ed.ref == nil and ns.ed.name == "", "leaving a queued save asked")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	made = named("LeftBehind")
	check(made and made.body == "/say five", "left-behind save")
	check(ns.ed.ref == nil and ns.ed.name == "", "the editor jumped to the saved macro")
	ns.DeleteGame(made)
	ns.app:Close()
end)

step("/macro and the game menu open /mom (on the Macros page); Blizzard's window one click away", function()
	check(MouseoverMacrosDB.takeover == true, "takeover is not on by default")
	if ns.app:IsShown() then ns.app:Close() end
	SlashCmdList.MACRO("")
	check(ns.app:IsShown() and ns.app.current == "macros" and MOCK.blizzSlash == 0 and not MacroFrame, "/macro: " .. tostring(ns.app.current))
	ns.app:Close()
	ShowMacroFrame()
	check(MacroFrame and MacroFrame:IsShown() and ns.app:IsShown() and ns.app.current == "macros", "game menu")
	MacroFrame:Hide()
	check(ns.macroButton and ns.macroButton:GetParent() == MacroFrame, "no button in Blizzard's window")
	SlashCmdList.MOUSEOVERMACROS("blizzard")
	check(MacroFrame:IsShown() and not ns.app:IsShown(), "/mom blizzard")
	ShowMacroFrame()
	check(MacroFrame:IsShown() and not ns.app:IsShown(), "Blizzard's window taken away while open on purpose")
	ns.macroButton:GetScript("OnClick")(ns.macroButton)
	check(MacroFrame:IsShown() and ns.app:IsShown(), "Open /mom button")
	MacroFrame:Hide()
	ns.app:Close()
	ShowMacroFrame()
	check(MacroFrame:IsShown() and ns.app:IsShown(), "takeover not back")
	MacroFrame:Hide()
	local footer = ns.app.window.footer[1]
	check(footer and footer:GetText() == "Blizzard's macro window", "sidebar button")
	footer:GetScript("OnClick")(footer)
	check(MacroFrame:IsShown() and not ns.app:IsShown(), "sidebar button did not open Blizzard's window")
	MacroFrame:Hide()
	MOCK.combat = true
	ShowMacroFrame()
	check(MacroFrame:IsShown(), "closed Blizzard's window in combat")
	ns.app:Close()
	MacroFrame:Hide()
	SlashCmdList.MACRO("")
	check(ns.app:IsShown() and not MacroFrame:IsShown(), "/macro in combat")
	ns.app:Close()
	MOCK.combat = false
	-- unsaved changes: /macro opens the editor as it was
	ns.EditNew()
	ns.ed.body = "/say unsaved"
	ns.app.window:Hide()
	SlashCmdList.MACRO("")
	check(ns.app.current == "macros" and ns.ed.body == "/say unsaved", "/macro left unsaved changes")
	ns.app:Close()
	answer("discard")
	SlashCmdList.MOUSEOVERMACROS("takeover off")
	check(MouseoverMacrosDB.takeover == false, "setting")
	SlashCmdList.MACRO("")
	check(MOCK.blizzSlash == 1 and MacroFrame:IsShown() and not ns.app:IsShown(), "/macro with the takeover off")
	MacroFrame:Hide()
	ShowMacroFrame()
	check(MacroFrame:IsShown() and not ns.app:IsShown(), "game menu with the takeover off")
	MacroFrame:Hide()
	SlashCmdList.MOUSEOVERMACROS("takeover on")
end)

------------------------------------------------------------------------
-- The ring
------------------------------------------------------------------------
local Ring = ns.Ring

step("ring: picking a slice from the direction, the dead zone and the outer edge", function()
	local all = {}
	for i = 1, 8 do local x, y = Ring.TopVector(i); all[i] = { x, y } end
	local function at(deg, r, slots, n, dead, outer)
		local a = math.rad(deg)
		return Ring.Pick(math.sin(a) * (r or 100), math.cos(a) * (r or 100), slots, n or 8, dead or 22, outer)
	end
	-- eight slices: 45 degrees each, slot 1 straight up, clockwise (0 degrees = up, 90 = right)
	for deg = 1, 359, 4 do
		local want = math.floor(((deg + 22.5) % 360) / 45) + 1
		check(at(deg, 100, all) == want, ("8 slices: %d degrees gave %s, want %d"):format(deg, tostring(at(deg, 100, all)), want))
	end
	-- four (up, right, down, left): 90 degrees each
	local four = { all[1], false, all[3], false, all[5], false, all[7], false }
	check(at(40, 100, four) == 1 and at(50, 100, four) == 3 and at(181, 100, four) == 5 and at(260, 100, four) == 7, "4 slices")
	check(Ring.Pick(1, 1, four, 8, 0) == 1, "a tie goes to the lower slot")
	-- the dead zone cancels; its edge already picks
	check(at(90, 21, all) == nil and Ring.Pick(0, 0, all, 8, 22) == nil, "inside the dead zone")
	check(at(90, 22, all) == 3, "on the edge of the dead zone")
	check(at(90, 300, all, 8, 22, 200) == nil and at(90, 150, all, 8, 22, 200) == 3, "beyond the outer edge (sub-ring clicks)")
	check(Ring.Pick(50, 50, { false, false }, 2, 22) == nil, "an empty ring picks nothing")
	-- sub-rings: n evenly, the first at the top
	local three = {}
	for i = 1, 3 do local x, y = Ring.SubVector(i, 3); three[i] = { x, y } end
	check(at(0, 100, three, 3) == 1 and at(120, 100, three, 3) == 2 and at(240, 100, three, 3) == 3 and at(59, 100, three, 3) == 1 and at(61, 100, three, 3) == 2, "3 in a sub-ring")
	check(Ring.Dir("right") == 3 and Ring.Dir("Up-Left") == 8 and Ring.Dir("5") == 5 and Ring.Dir("sideways") == nil, "direction words")
end)

-- A character with a bag full of consumables.
local function Bag(list) local b = {}; for i, x in ipairs(list) do b[i] = x end; return b end
MOCK.items = {
	[100] = { name = "Tough Jerky", spell = "Food", minLevel = 5, ilvl = 15 },
	[101] = { name = "Roasted Quail", spell = "Food", minLevel = 35, ilvl = 45 },              -- level 35: too high
	[102] = { name = "Smoked Desert Dumplings", spell = "Food", minLevel = 25, ilvl = 45 },
	[103] = { name = "Conjured Sourdough", spell = "Food", minLevel = 25, ilvl = 35 },
	[110] = { name = "Refreshing Spring Water", spell = "Drink", minLevel = 5, ilvl = 15 },
	[112] = { name = "Moonberry Juice", spell = "Drink", minLevel = 25, ilvl = 35 },
	[113] = { name = "Bottled Winterspring Water", classID = 0, subclassID = 5, minLevel = 25, ilvl = 30 }, -- retail class data only
	[120] = { name = "Healing Potion", spell = "Healing Potion", minLevel = 12, ilvl = 22 },
	[121] = { name = "Greater Healing Potion", spell = "Healing Potion", minLevel = 21, ilvl = 31 },
	[130] = { name = "Mana Potion", spell = "Restore Mana", minLevel = 22, ilvl = 32, unusable = true }, -- the game says not usable
	[131] = { name = "Lesser Mana Potion", spell = "Restore Mana", minLevel = 14, ilvl = 24 },
	[140] = { name = "Heavy Silk Bandage", spell = "First Aid", ilvl = 40 },
	[141] = { name = "Silk Bandage", spell = "First Aid", ilvl = 30 },
	[150] = { name = "Shiny Bauble", spell = "Increase Fishing" },
	[160] = { name = "Strong Fishing Pole", classID = 2, subclassID = 20, subType = "Fishing Poles", minLevel = 10, ilvl = 20 },
	[161] = { name = "Fishing Pole", classID = 2, subclassID = 20, subType = "Fishing Poles", ilvl = 5 },
	[6948] = { name = "Hearthstone", spell = "Hearthstone" },
	[200] = { name = "Linen Cloth", classID = 7 },
}

step("ring: the best food, drink, potions and bandage from the bags", function()
	MOCK.bags[0] = Bag({ { 100, 20 }, { 101, 5 }, { 102, 3 }, { 103, 12 }, { 110, 10 }, { 112, 4 }, { 113, 2 }, { 200, 20 } })
	MOCK.bags[1] = Bag({ { 120, 2 }, { 121, 1 }, { 130, 3 }, { 131, 5 }, { 140, 5 }, { 141, 10 }, { 150, 2 }, { 160, 1 }, { 161, 1 }, { 6948, 1 }, { 102, 2 } })
	local items = Ring.ScanBags()
	local function best(cat) local it = Ring.Best(items, cat); return it and it.id end
	check(best("food") == 102, "food: usable, level 25, the higher item level (not Roasted Quail at level 35): " .. tostring(best("food")))
	check(best("drink") == 112, "drink: " .. tostring(best("drink")))
	check(best("hpot") == 121 and best("mpot") == 131, "potions: Greater Healing; Lesser Mana because the game says Mana Potion is not usable")
	check(best("bandage") == 140 and best("lure") == 150 and best("pole") == 160, "bandage, lure, pole")
	for _, it in ipairs(items) do if it.id == 102 then check(it.count == 5, "stacks in several bags add up") end end
	check(Ring.Classify(MOCK.items[113]).drink and not Ring.Classify(MOCK.items[200]).food, "item class decides when there is no use spell")
	-- at level 40 the quail becomes the best
	MOCK.level = 40
	check(Ring.Best(Ring.ScanBags(), "food").id == 101, "after levelling up")
	MOCK.level = 30
	-- the dynamic slices give macro text for the secure buttons
	local ctx = Ring.Context()
	local food = Ring.Expand({ kind = "food" }, ctx)[1]
	check(food.macrotext == "/use item:102" and food.itemID == 102, "food slice: " .. tostring(food.macrotext))
	local lure = Ring.Expand({ kind = "lures" }, ctx)[1]
	check(lure.macrotext == "/use item:150\n/use 16", "a lure goes on the fishing pole")
	check(Ring.Expand({ kind = "fishgear" }, ctx)[1].macrotext == "/equip Strong Fishing Pole", "no Fishing set: the best pole")
	check(#Ring.Expand({ kind = "buffs" }, ctx) == 0, "no buff spells known yet")
	MOCK.known = { ["Power Word: Fortitude"] = 1243, ["Inner Fire"] = 588, Fishing = 7620, Tailoring = 3908, Disenchant = 13262, ["Basic Campfire"] = 818 }
	local buffs = Ring.Expand({ kind = "buffs" }, ctx)
	check(#buffs == 2 and buffs[1].macrotext == "/cast Power Word: Fortitude" and buffs[2].macrotext == "/cast Inner Fire", "the priest's buffs that are known")
	for _, b in ipairs(buffs) do check(not b.macrotext:find("@player"), "a buff never targets you by itself") end
	local prof = Ring.Expand({ kind = "professions" }, ctx)
	check(#prof == 1 and prof[1].label == "Tailoring", "professions (Disenchant and the campfire have their own slices)")
	check(Ring.Expand({ kind = "campfire" }, ctx)[1].macrotext == "/cast Basic Campfire", "campfire")
	C_EquipmentSet = {
		GetEquipmentSetIDs = function() return { 1, 2 } end,
		GetEquipmentSetInfo = function(id) if id == 1 then return "Healing", 111 end return "Fishing", 222 end,
	}
	check(Ring.Expand({ kind = "fishgear" }, ctx)[1].macrotext == "/equipset [equipped:Fishing Poles] Healing; Fishing", "a Fishing set toggles")
end)

-- The restricted environment, simulated: frame handles over the mock frames, one environment per header.
local header = MoMRingHeader
local renv
local function Handle(f)
	if not f then return nil end
	return setmetatable({}, { __index = {
		GetAttribute = function(_, k) return f.__attrs[k] end,
		SetAttribute = function(_, k, v) f.__attrs[k] = v end, -- restricted code may, also in combat
		Show = function() f:Show() end,
		Hide = function() f:Hide() end,
		ClearAllPoints = function() end,
		SetPoint = function() end,
		GetFrameRef = function(_, name) return Handle(Ring.refs[name]) end,
		GetMousePosition = function() return MOCK.mx, MOCK.my end,
		GetWidth = function() return 1000 end,
		GetHeight = function() return 1000 end,
		SetBindingClick = function(_, _, key, name, button) MOCK.ringBinds[key] = name .. " " .. button end,
		ClearBindings = function() MOCK.ringBinds = {} end,
	} })
end
MOCK.ringBinds = {}
-- Click a wrapped button at a mouse position (0..1 of the screen). Returns what the snippet returned
-- and, when the click went on to the action, the action.
local function Click(frame, button, down, mx, my)
	MOCK.mx, MOCK.my = mx, my
	local snippet
	for _, w in ipairs(MOCK.wraps) do if w.frame == frame then snippet = w.pre end end
	check(snippet, "button not wrapped")
	local fn = assert(loadstring("local self, button, down = ...\n" .. snippet))
	renv = renv or setmetatable({}, { __index = { owner = Handle(header) } }) -- nothing else: no globals in restricted code
	setfenv(fn, renv)
	local r = fn(Handle(frame), button, down)
	if r == false then return false end
	return r, frame.__attrs.type, frame.__attrs.macrotext or frame.__attrs.macro
end
local function shownRing()
	local open = {}
	for r = 0, 8 do if Ring.refs["ring" .. r]:IsShown() then open[#open + 1] = r end end
	return table.concat(open, ",")
end

step("ring: the key's press opens it, the release picks; sub-rings, clicks, the dead zone and Escape (secure snippet)", function()
	check(MoMRingTrigger and MoMRingCatcher and MoMRingTrigger.__protected and MoMRingCatcher.__protected, "secure buttons")
	check(MOCK.wraps[1].header == header and MOCK.wraps[2].header == header and MOCK.wraps[1].script == "OnClick", "wrapped in the header")
	check(MoMRingTrigger.__attrs.useOnKeyDown == false, "the trigger acts on the release")
	check(Ring.Rebuild(), "rebuilt")
	local trig, catch = MoMRingTrigger, MoMRingCatcher
	-- the slices carry their action and direction as attributes
	local up = Ring.refs.s0_1
	check(up.__protected and up.__attrs.on and up.__attrs.type == "macro" and up.__attrs.macrotext == "/use item:6948", "up: Hearthstone")
	check(Ring.refs.s0_3.__attrs.sub == 3 and Ring.refs.s0_3.__attrs.type == nil, "right: the Consumables sub-ring")
	check(Ring.refs.s0_2.__attrs.on == nil, "up-right: empty")
	-- quick flick up: press, release up -> Hearthstone at once
	check(Click(trig, "LeftButton", true, 0.5, 0.5) == false and shownRing() == "0", "the press shows the ring")
	check(header.__attrs.cx == 500 and header.__attrs.cy == 500, "centred on the cursor")
	local r, kind, text = Click(trig, "LeftButton", false, 0.51, 0.62)
	check(r == "LeftButton" and kind == "macro" and text == "/use item:6948" and shownRing() == "", "flick up: " .. tostring(text))
	-- release in the middle: nothing
	Click(trig, "LeftButton", true, 0.3, 0.3)
	check(Click(trig, "LeftButton", false, 0.31, 0.3) == false and shownRing() == "", "the dead zone cancels")
	-- right: the sub-ring opens around the same point; the catcher takes clicks; Escape is bound
	Click(trig, "LeftButton", true, 0.5, 0.5)
	check(Click(trig, "LeftButton", false, 0.62, 0.5) == false and shownRing() == "3" and catch:IsShown(), "sub-ring open")
	check(MOCK.ringBinds.ESCAPE == "MoMRingCatcher RightButton", "Escape closes it")
	-- its first slice (top) is the best food; a click toward it uses it
	local sub = Ring.layout[3]
	check(sub.slots[1].macrotext == "/use item:102", "the sub-ring's first slice is the best food")
	check(Click(catch, "LeftButton", true, 0.5, 0.6) == false, "the press of a click does nothing")
	r, kind, text = Click(catch, "LeftButton", false, 0.5, 0.6)
	check(r == "LeftButton" and text == "/use item:102" and shownRing() == "" and not catch:IsShown() and next(MOCK.ringBinds) == nil, "click: food, closed")
	-- the key again instead of a click: the release toward a slice uses it
	Click(trig, "LeftButton", true, 0.5, 0.5)
	Click(trig, "LeftButton", false, 0.62, 0.5)
	local vx, vy = sub.slots[2].vx, sub.slots[2].vy
	check(Click(trig, "LeftButton", true, 0.5, 0.5) == false and shownRing() == "3", "a second press keeps the sub-ring")
	r, kind, text = Click(trig, "LeftButton", false, 0.5 + vx * 0.1, 0.5 + vy * 0.1)
	check(r and text == "/use item:112", "second slice: the best drink, " .. tostring(text))
	-- right click (Escape is a right click on the catcher), a click far away: closed, nothing used
	Click(trig, "LeftButton", true, 0.5, 0.5); Click(trig, "LeftButton", false, 0.62, 0.5)
	check(Click(catch, "RightButton", true, 0.5, 0.6) == false and shownRing() == "" and not catch:IsShown(), "right click closes")
	Click(trig, "LeftButton", true, 0.5, 0.5); Click(trig, "LeftButton", false, 0.62, 0.5)
	check(Click(catch, "LeftButton", false, 0.95, 0.5) == false and shownRing() == "", "a click far outside closes")
	-- the snippet agrees with Ring.Pick (what the picture highlights) all the way round
	local v = {}
	for i = 1, 8 do local e = Ring.layout[0].slots[i]; v[i] = e and { e.vx, e.vy } or false end
	for k = 0, 71 do
		local a = math.rad(k * 5 + 1)
		Click(trig, "LeftButton", true, 0.5, 0.5)
		local _, _, got = Click(trig, "LeftButton", false, 0.5 + math.sin(a) * 0.1, 0.5 + math.cos(a) * 0.1)
		local e = Ring.layout[0].slots[Ring.Pick(math.sin(a) * 100, math.cos(a) * 100, v, 8, Ring.DEAD)]
		if e.sub then
			check(got == nil and shownRing() == tostring(e.sub), "angle " .. (k * 5 + 1) .. ": sub-ring " .. e.sub)
			Click(catch, "RightButton", true, 0.5, 0.5)
		else
			check(got == e.macrotext, "angle " .. (k * 5 + 1) .. ": " .. tostring(got))
		end
	end
end)

step("ring: the picture fades in, follows the cursor and fades out; no OnUpdate while closed", function()
	local d = Ring.displays[0]
	for _, x in pairs(Ring.displays) do Ring.DisplayUpdate(x, 0.1) end -- the fades from the clicks above
	check(not d:IsShown(), "closed: hidden, so its OnUpdate doesn't run")
	Click(MoMRingTrigger, "LeftButton", true, 0.5, 0.5)
	check(d:IsShown() and d:GetAlpha() == 0, "shown, starting transparent")
	Ring.DisplayUpdate(d, 0.04)
	check(d:GetAlpha() > 0 and d:GetAlpha() < 1, "fading in")
	Ring.DisplayUpdate(d, 0.05)
	check(d:GetAlpha() == 1, "faded in within 0.1 s")
	-- the mock cursor is at 400, 300 and the centre at 500, 500: down and a bit left -> down (5)
	check(d.lit == 5 and d.tiles[5].label:IsShown() and not d.tiles[3].label:IsShown(), "highlights down, with its label")
	check(d.tiles[1].count:GetText() == "", "one Hearthstone: no count")
	Click(MoMRingTrigger, "LeftButton", false, 0.5, 0.5)
	check(d:IsShown(), "still fading out")
	Ring.DisplayUpdate(d, 0.1)
	check(not d:IsShown(), "gone within 0.1 s")
	-- a stack shows its count; a used-up item shows greyed
	local sd = Ring.displays[3]
	Click(MoMRingTrigger, "LeftButton", true, 0.5, 0.5); Click(MoMRingTrigger, "LeftButton", false, 0.62, 0.5)
	check(sd.tiles[1].count:GetText() == 5 and sd.tiles[1].icon:GetAlpha() == 1, "dumplings: 5")
	Click(MoMRingCatcher, "RightButton", true, 0.5, 0.5)
	MOCK.combat = true
	MOCK.bags[0][3], MOCK.bags[1][11] = nil, nil -- every dumpling eaten in combat
	Click(MoMRingTrigger, "LeftButton", true, 0.5, 0.5); Click(MoMRingTrigger, "LeftButton", false, 0.62, 0.5)
	check(sd.tiles[1].icon:GetAlpha() < 1 and sd:IsShown(), "used up: greyed, still there until combat ends")
	Click(MoMRingCatcher, "RightButton", true, 0.5, 0.5)
	MOCK.Fire("BAG_UPDATE_DELAYED")
	MOCK.RunTimers()
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check(Ring.layout[3].slots[1].macrotext == "/use item:103", "after combat the next best food takes its place")
end)

step("ring: changes in combat wait for combat to end (bags, the editor, the key)", function()
	check(not Ring.dirty, "clean")
	local s31 = Ring.refs.s3_1
	local before = s31.__attrs.macrotext
	MOCK.combat = true
	MOCK.bags[2] = Bag({ { 101, 1 } })
	MOCK.level = 40 -- the quail is now usable and the best
	MOCK.Fire("BAG_UPDATE_DELAYED")
	MOCK.RunTimers() -- the rebuild runs, sees combat, waits (the mock throws on SetAttribute in combat)
	check(Ring.dirty and s31.__attrs.macrotext == before, "frozen in combat")
	MOCK.log = {}
	Ring.Command("set upright food")
	check(logHas("when combat ends") and Ring.refs.s0_2.__attrs.on == nil, "an edit in combat waits")
	local ok, msg = Ring.SetKey("BUTTON4")
	check(ok and msg:find("after combat", 1, true) and MOCK.bindings.BUTTON3 == "MoMRingTrigger" and not MOCK.bindings.BUTTON4, "the key waits too")
	-- still works in combat with what it had
	Click(MoMRingTrigger, "LeftButton", true, 0.5, 0.5)
	local _, _, text = Click(MoMRingTrigger, "LeftButton", false, 0.51, 0.62)
	check(text == "/use item:6948", "the ring works in combat")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check(not Ring.dirty and s31.__attrs.macrotext == "/use item:101", "rebuilt after combat: " .. tostring(s31.__attrs.macrotext))
	check(Ring.refs.s0_2.__attrs.on and Ring.refs.s0_2.__attrs.macrotext == "/use item:101", "the edit applied")
	check(MOCK.bindings.BUTTON4 == "MoMRingTrigger" and not MOCK.bindings.BUTTON3, "the key moved")
	MOCK.level = 30
	Ring.Command("clear upright")
	Ring.SetKey("BUTTON3")
end)

step("ring: the key goes through /mom's bindings; off gives the button back; left/right click refused", function()
	check(MOCK.bindings.BUTTON3 == "MoMRingTrigger", "middle mouse opens the ring")
	SlashCmdList.MOUSEOVERMACROS("ring off")
	check(MOCK.bindings.BUTTON3 == nil, "off: middle mouse is the game's again")
	SlashCmdList.MOUSEOVERMACROS("ring on")
	check(MOCK.bindings.BUTTON3 == "MoMRingTrigger", "on again")
	local ok = Ring.SetKey("BUTTON1")
	check(not ok and ns.db.ring.key == "BUTTON3", "left click alone refused")
	check(Ring.SetKey("SHIFT-BUTTON2") and MOCK.bindings["SHIFT-BUTTON2"] == "MoMRingTrigger", "shift + right click is fine")
	Ring.SetKey("BUTTON3")
end)

step("ring: the Ring page and /mom ring edit it (drop, sub-ring, reorder, reset)", function()
	ns.app:Open("ring")
	local c = Ring.compass
	check(c and #c.tiles == 8, "the compass")
	-- click Left, drop the Hearthstone on it: Left is a sub-ring, so it is added there
	c.tiles[7]:GetScript("OnClick")(c.tiles[7])
	check(Ring.Selected() == 7, "Left selected")
	MOCK.cursor = { "item", 6948 }
	c.tiles[7]:GetScript("OnReceiveDrag")(c.tiles[7])
	local left = ns.db.ring.top[7]
	check(left.kind == "ring" and left.items[#left.items].kind == "item" and left.items[#left.items].id == 6948 and MOCK.cursor == nil, "added to Professions")
	-- a spell dropped on an empty direction becomes that direction
	MOCK.cursor = { "spell", 5, "spell", 7620 }
	C_Spell.GetSpellName = function(id) return id == 7620 and "Fishing" or ("Spell" .. id) end
	c.tiles[2]:GetScript("OnReceiveDrag")(c.tiles[2])
	check(ns.db.ring.top[2].kind == "spell" and ns.db.ring.top[2].name == "Fishing" and Ring.refs.s0_2.__attrs.macrotext == "/cast Fishing", "up-right: Fishing")
	-- reorder inside a sub-ring, remove, make single, swap
	Ring.MoveItem(7, #left.items, -1)
	check(left.items[#left.items - 1].id == 6948, "moved up")
	Ring.RemoveItem(7, #left.items - 1)
	check(left.items[#left.items].kind ~= "item", "removed")
	Ring.Swap(2, 8)
	check(ns.db.ring.top[2] == false and ns.db.ring.top[8].name == "Fishing", "swapped")
	SlashCmdList.MOUSEOVERMACROS("ring add upleft hpot")
	check(ns.db.ring.top[8].kind == "ring" and ns.db.ring.top[8].items[1].name == "Fishing" and ns.db.ring.top[8].items[2].kind == "hpot", "add makes a sub-ring")
	SlashCmdList.MOUSEOVERMACROS("ring sub upleft Quick")
	check(ns.db.ring.top[8].name == "Quick", "renamed")
	ns.app:Refresh()
	MOCK.log = {}
	SlashCmdList.MOUSEOVERMACROS("ring list")
	check(logHas("Right") and logHas("Consumables") and logHas("Quick"), "list")
	SlashCmdList.MOUSEOVERMACROS("ring set sideways food")
	check(logHas("which direction"), "a bad direction says so")
	SlashCmdList.MOUSEOVERMACROS("ring set up nothing-called-this")
	check(logHas("no slice called"), "an unknown slice says so")
	SlashCmdList.MOUSEOVERMACROS("ring reset")
	check(ns.db.ring.top[8] ~= false and logHas("/mom reset ring again within 10 s"), "ring reset didn't ask first")
	SlashCmdList.MOUSEOVERMACROS("ring reset")
	check(ns.db.ring.top[8] == false and ns.db.ring.top[3].name == "Consumables" and ns.db.ring.key == "BUTTON3", "reset keeps the key")
	ns.app:Close()
end)

step("never touches other windows (UIPanelWindows, Show/HideUIPanel, UISpecialFrames, closing windows)", function()
	for _, file in ipairs({ "RingData.lua", "Ring.lua", "RingPage.lua", "Window.lua", "Manager.lua", "MouseoverMacros.lua" }) do
		local src = assert(io.open(ROOT .. "/" .. file)):read("*a")
		for _, bad in ipairs({ "UIPanelWindows", "ShowUIPanel", "HideUIPanel", "UISpecialFrames", "CloseAllWindows", "CloseSpecialWindows", "CloseWindows" }) do
			check(not src:find(bad, 1, true), file .. " uses " .. bad)
		end
	end
	check(next(UISpecialFrames) == nil, "UISpecialFrames touched")
end)

step("priest heal ranks: their own macros, off by default, exact rank only", function()
	local by = {}
	for _, m in ipairs(ns.MACROS.PRIEST) do by[m[1]] = m end
	for _, k in ipairs({ "lhealr1", "lhealr2", "healr1", "healr3", "fhealr6", "ghealr1", "ghealr4" }) do
		check(by[k] and by[k].on == false and by[k].rank, "missing rank entry " .. k)
	end
	check(not by.lhealr3 and not by.healr4 and not by.ghealr5, "the top rank is the plain macro")
	check(ns.SpellName(by.healr2):find("^%w+%(Rank 2%)$"), ns.SpellName(by.healr2))
	check(ns.Body(by.healr2):find("%[@mouseover,help,nodead%]%[help,nodead%] %w+%(Rank 2%)"), ns.Body(by.healr2))
end)

step("Power Infusion whisper: the PI target only, never you or an enemy, once a minute each", function()
	local saved = { UnitExists, UnitIsDeadOrGhost, UnitCanAssist, UnitCanAttack, UnitIsUnit, UnitIsPlayer, GetUnitName, SendChatMessage, GetTime }
	local units, sent, now = {}, {}, 1000
	UnitExists = function(u) return units[u] ~= nil end
	UnitIsDeadOrGhost = function() return false end
	UnitCanAssist = function(_, u) return units[u] == "friend" end
	UnitCanAttack = function(_, u) return units[u] == "enemy" end
	UnitIsUnit = function(a, b) return a == b end
	UnitIsPlayer = function(u) return units[u] ~= nil end
	GetUnitName = function(u) return u == "mouseover" and "Bob-Realm" or "Ann" end
	SendChatMessage = function(text, kind, _, to) sent[#sent + 1] = { text, kind, to } end
	GetTime = function() return now end
	units = { mouseover = "friend", target = "enemy" }
	check(ns.PIUnit() == "mouseover" and ns.PISay(), "mouseover friend")
	check(sent[1][2] == "WHISPER" and sent[1][3] == "Bob-Realm" and sent[1][1]:find("Bob", 1, true) and not sent[1][1]:find("Realm", 1, true), "whisper to Bob")
	check(not ns.PISay() and #sent == 1, "twice within a minute")
	units = { mouseover = "enemy", target = "friend" }
	check(ns.PIUnit() == nil, "an enemy under the mouse gets the other spell")
	units = { target = "friend" }
	check(ns.PIUnit() == "target" and ns.PISay() and sent[2][3] == "Ann", "friendly target")
	units = { target = "enemy" }
	check(ns.PIUnit() == nil and not ns.PISay(), "enemy target")
	local by = {}
	for _, m in ipairs(ns.MACROS.PRIEST) do by[m[1]] = m end
	check(ns.Body(by.pinf):find("^#showtooltip [^\n]+\n/mom pi\n/cast "), ns.Body(by.pinf))
	UnitExists, UnitIsDeadOrGhost, UnitCanAssist, UnitCanAttack, UnitIsUnit, UnitIsPlayer, GetUnitName, SendChatMessage, GetTime = unpack(saved)
end)

step("the Mine list names what each _mom macro casts", function()
	local W = ns.WhatItDoes
	check(W("#showtooltip\n/cast [@mouseover,help,nodead][help,nodead] Abolish Disease\n#mom x") == "Abolish Disease", "mouseover heal")
	check(W("/stopcasting\n/cast [@mouseover,harm,nodead][harm,nodead] !Shoot") == "Shoot", "stopcasting + !Shoot")
	local two = W("/cast Inner Focus\n/cast [help] Greater Heal; [harm] Smite")
	check(two == "Inner Focus, Greater Heal, Smite", two)
	check(W("/castsequence reset=3 Smite, Smite") == "Smite", "castsequence")
	check(W("/say hi") == "", "nothing cast")
end)

-- the ring tests gave every spell ID a made-up name: back to the client's names (the English ones)
C_Spell.GetSpellName = function(id) return MOCK.spellNames[id] end

step("Macros page: every macro in one list; the search finds devouring / plague; the quick picks find the templates", function()
	check(ns.CreateGame("account", "MyDP", nil, "#showtooltip\n/cast [@mouseover,harm][] Devouring Plague"), "made")
	ns.app:Open("macros")
	searchFor("")
	local a, _, c = ns.Counts()
	check(#shownRows() == a + c, "all macros, account and character together: " .. #shownRows() .. " of " .. (a + c))
	for _, q in ipairs({ "devouring", "plague", "DEVOURING Plague" }) do
		searchFor(q)
		check(rowFor(function(it) return it.name == "MyDP" end), q .. ": your own macro casting it")
		check(rowFor(function(it) return it.index == entry("dplague").index end), q .. ": the set macro")
	end
	local row = rowFor(function(it) return it.index == entry("dplague").index end)
	check(row.title:GetText() == entry("dplague").spell and row.detail:GetText():find(entry("dplague").macro, 1, true), "the set macro's spell first: " .. row.title:GetText())
	searchFor("")
	ns.app:Open("builder")
	for _, q in ipairs({ "devouring", "plague", "power infusion", "DEVOURING Plague" }) do
		quickFor(q)
		local tmpl = rowFor(function(it) return it.t and it.t.id == "dppi" end, ns.quickList)
		check(tmpl and tmpl.title:GetText():find("Devouring Plague / Power Infusion", 1, true), q .. ": no Devouring Plague / Power Infusion row")
		if q ~= "power infusion" then
			check(rowFor(function(it) return it.e and it.e.key == "dplague" end, ns.quickList), q .. ": no Devouring Plague set macro")
			check(rowFor(function(it) return it.t and it.t.id == "dpfheal" end, ns.quickList), q .. ": no Devouring Plague / Flash Heal row")
		end
	end
	quickFor("devouring")
	local tmpl = rowFor(function(it) return it.t and it.t.id == "dppi" end, ns.quickList)
	check(tmpl.buttons[1]:GetText() == "Create" and not tmpl.buttons[2]:IsShown(), "not made: Create, nothing to put on a bar")
	click(tmpl.buttons[1])
	check(ns.Resolve("t:dppi") and tmpl.buttons[1]:GetText() == "Update" and tmpl.buttons[2]:IsShown(), "made")
	MOCK.picked = nil
	click(tmpl.buttons[2])
	check(MOCK.picked == ns.Resolve("t:dppi"), "Put on bar")
	quickFor("")
	-- in the Macros list it shows as the template's title, its macro name after
	ns.app:Open("macros")
	searchFor("power infusion")
	local r = rowFor(function(it) return it.index == ns.Resolve("t:dppi") end)
	check(r and r.title:GetText() == "Devouring Plague / Power Infusion", "the template's title")
	searchFor("")
	ns.DeleteGame(named("MyDP"))
	ns.app:Close()
end)

step("bulk delete: tick boxes, Delete selected (N), one line; Undo puts them all back", function()
	for i = 1, 3 do check(ns.CreateGame("account", "Bulk" .. i, nil, "/say bulk " .. i), "made") end
	ns.app:Open("macros")
	searchFor("bulk")
	local rows = shownRows()
	check(#rows == 3, "three rows: " .. #rows)
	local del = ns.deleteSelected
	check(not del:GetParent():IsShown(), "nothing ticked: Delete selected shown")
	for _, r in ipairs(rows) do click(r.tick) end
	check(rows[1].tick.on and del:GetParent():IsShown() and del:GetText() == "Delete selected (3)", "ticked: " .. del:GetText())
	click(rows[2].tick)
	check(del:GetText() == "Delete selected (2)", "untick")
	click(rows[2].tick)
	local n = #MOCK.log
	click(del)
	check(not named("Bulk1") and not named("Bulk2") and not named("Bulk3"), "not all deleted")
	check(#MOCK.log == n + 1 and last():find("deleted 3 macros", 1, true) and last():find("/mom undo", 1, true), "one summary line: " .. last())
	check(ns.statusNote.text:GetText():find("Deleted 3 macros", 1, true) and next(ns.selected) == nil, "status / selection")
	SlashCmdList.MOUSEOVERMACROS("undo")
	check(named("Bulk1") and named("Bulk2") and named("Bulk3"), "undo did not put them all back")
	check(last():find("put back", 1, true), "undo line: " .. last())
	for i = 1, 3 do ns.DeleteGame(named("Bulk" .. i)) end
	searchFor("")
	ns.app:Close()
end)

step("in combat: delete, move and restore say so at once, show as waiting, never queue twice, and can be cancelled", function()
	check(ns.CreateGame("account", "CombatDel", nil, "/say x"), "made")
	ns.Edit(named("CombatDel"))
	local del = ns.saveRow.buttons[4]
	MOCK.combat = true
	local jobs = #ns.queue.jobs
	click(del)
	check(last():find("CombatDel will be deleted when combat ends", 1, true), "said at once: " .. last())
	check(#ns.queue.jobs == jobs + 1 and named("CombatDel"), "queued once, not deleted yet")
	check(del:GetText() == "Cancel", "editor's Delete: " .. del:GetText())
	check(editorSays("CombatDel will be deleted when combat ends"), "the editor doesn't say it waits")
	ns.DeleteMacros({ named("CombatDel") })
	check(#ns.queue.jobs == jobs + 1 and last():find("already waiting", 1, true), "queued twice: " .. last())
	searchFor("CombatDel")
	local row = rowFor(function(it) return it.name == "CombatDel" end)
	check(row.detail:GetText():find("Deleting after combat", 1, true), "row: " .. row.detail:GetText())
	click(del)
	check(last():find("cancelled", 1, true) and not ns.pending["del:account:CombatDel"] and del:GetText() == "Delete", "cancel")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check(named("CombatDel"), "deleted although cancelled")
	MOCK.combat = true
	ns.DeleteMacros({ named("CombatDel") })
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check(not named("CombatDel") and logHas("deleted CombatDel"), "not deleted after combat")
	-- move ("Stored as"): said at once; choosing again cancels
	local heal = ns.Fresh({ kind = "game", scope = "char", name = "MyHeal" })
	ns.Edit(heal)
	MOCK.combat = true
	jobs = #ns.queue.jobs
	ns.EditorMove("account")
	check(last():find("MyHeal will be moved to account macros when combat ends", 1, true), "move: " .. last())
	check(editorSays("MyHeal will be moved to account macros when combat ends"), "the editor doesn't say the move waits")
	ns.EditorMove("account")
	check(last():find("cancelled", 1, true) and #ns.queue.jobs == jobs + 1, "move cancel")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check(ns.Fresh(heal) and ns.Fresh(heal).scope == "char", "moved although cancelled")
	-- restore from the bin: said at once
	ns.app:Open("backups")
	local list
	for _, w in ipairs(ns.app.sections.backups.stack.widgets) do if w.rows and not list then list = w end end
	MOCK.combat = true
	click(list.rows[1].buttons[1])
	check(last():find("will be restored when combat ends", 1, true) and list.rows[1].buttons[1]:GetText() == "Cancel", "restore: " .. last())
	click(list.rows[1].buttons[1])
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	ns.app:Open("macros")
	searchFor("")
	ns.app:Close()
end)

step("a set macro deleted in /mom: Create / update all leaves it out; Undo or Create brings it back", function()
	local name = entry("renew").macro
	ns.DeleteMacros({ ns.GameRef(GetMacroIndexByName(name)) })
	local e = entry("renew")
	check(not find(name) and e.deleted and not e.index, "not deleted")
	SlashCmdList.MOUSEOVERMACROS("install")
	check(not entry("renew").index and last():find("you deleted left out", 1, true), "install made it again: " .. last())
	ns.Undo()
	check(find(name) and entry("renew").index and not entry("renew").deleted, "undo: " .. entry("renew").status)
	ns.DeleteMacros({ ns.GameRef(GetMacroIndexByName(name)) })
	SlashCmdList.MOUSEOVERMACROS("create renew")
	check(entry("renew").status == "ok" and not entry("renew").deleted, "Create did not make it again")
end)
step("the player's macros were never changed", function()
	check(find("fort").body == PLAYER_FORT and find("Mount2").body == "/cast Riding Turtle", "changed") -- Mount2: renamed by the player in the editor
	check(find("smite").body == "#showtooltip Smite\n/cast Smite", "smite changed")
end)

step("no taint: only our own globals", function()
	local allowed = { MouseoverMacrosDB = true, MouseoverMacrosCharDB = true, SLASH_MOUSEOVERMACROS1 = true, SLASH_MOUSEOVERMACROS2 = true, LibStub = true }
	for k in pairs(globalWrites) do check(allowed[k], "addon assigned the global " .. tostring(k)) end
	check(next(StaticPopupDialogs) == nil and next(UISpecialFrames) == nil, "Blizzard lists touched")
end)

step("no Lua errors reported", function()
	check(#MOCK.errors == 0, table.concat(MOCK.errors, "\n"))
end)

print(("\n%d passed, %d failed"):format(passes, #failures))
return #failures
