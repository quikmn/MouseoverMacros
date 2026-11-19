-- Offline tests for MouseoverMacros against wowmock.lua: macro bodies, _mom names and ownership,
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
		rez = "#showtooltip Resurrection\n/cast [@mouseover,help,dead][help,dead] Resurrection\n#mom rez",
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
		check(found, e.key .. " has no legacy body matching the current one")
	end
	check(n == 26, "26 priest macros, got " .. n)
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
	check(last():find("created 21, updated 4", 1, true) and last():find("1 switched off", 1, true), "summary: " .. last())
	check(find("fort").body == PLAYER_FORT and find("smite").body == "#showtooltip Smite\n/cast Smite"
		and find("_mom1234").body:find("player's", 1, true) and find("Mount"), "player's macros changed")
	for _, e in ipairs(ns.Entries()) do
		if e.on then check(e.status == "ok" and isMom(e.macro), e.key .. " " .. e.status) end
	end
	SlashCmdList.MOUSEOVERMACROS("on penance")
	SlashCmdList.MOUSEOVERMACROS("all")
	check(last():find("created 1, updated 25", 1, true), "second install: " .. last())
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

step("the window list: names, states, Create / Update / Pick up buttons", function()
	ns.app:Open("templates")
	local list
	for _, w in ipairs(ns.app.sections.templates.stack.widgets) do if w.rows and not list then list = w end end
	check(list and #list.rows == 26, "26 rows")
	local smite, dplague
	for _, r in ipairs(list.rows) do
		if r.item.key == "smite" then smite = r end
		if r.item.key == "dplague" then dplague = r end
	end
	check(smite.buttons[1]:GetText() == "Up to date" and smite.buttons[2]:IsShown(), "existing macro row")
	check(smite.title:GetText():find(entry("smite").macro, 1, true), "row shows the macro name")
	smite.buttons[2]:GetScript("OnClick")(smite.buttons[2])
	check(MOCK.picked == GetMacroIndexByName(entry("smite").macro), "pick up")
	-- in combat the game blocks PickupMacro: the button greys out, the tooltip says "after combat", a click does nothing
	MOCK.picked = nil
	MOCK.combat = true
	MOCK.Fire("PLAYER_REGEN_DISABLED")
	check(smite.buttons[2]:GetAlpha() < 1, "Pick up greyed out in combat")
	smite.buttons[2]:GetScript("OnClick")(smite.buttons[2])
	check(MOCK.picked == nil, "PickupMacro called in combat")
	ns.PickUp(ns.List("account")[1] or { kind = "game", id = 1 })
	check(MOCK.picked == nil, "ns.PickUp in combat")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check(smite.buttons[2]:GetAlpha() == 1, "Pick up back after combat")
	DeleteMacro(GetMacroIndexByName(entry("dplague").macro))
	MOCK.Fire("UPDATE_MACROS")
	check(dplague.buttons[1]:GetText() == "Create" and not dplague.buttons[2]:IsShown(), "missing macro row")
	check(dplague.detail:GetText():find("missing", 1, true), "missing state shown")
	dplague.buttons[1]:GetScript("OnClick")(dplague.buttons[1])
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

step("every section of the window opens", function()
	for _, id in ipairs({ "mine", "account", "char", "ext", "templates", "edit", "backups", "ring", "options" }) do
		ns.app:Open(id)
		check(ns.app.sections[id].stack, id .. " not built")
	end
	check(#ns.app.order == 9 and ns.app.order[1] == "mine" and ns.app.order[8] == "ring" and ns.app.order[9] == "options", "sidebar order")
	check(ns.CountsLine():find("Account", 1, true) and ns.CountsLine():find("Extended", 1, true), "counts line")
	ns.app:Close()
end)

step("extended macros: no slot, a secure button, 1023 characters, key binding, bar macro", function()
	local a0, c0 = GetNumMacros()
	local long = "#showtooltip Renew\n" .. ("/cast Renew\n"):rep(80)
	check(#long > 255 and #long <= 1023, "test text length")
	local ok, msg, id = ns.CreateExt("Big renew", 135953, long)
	check(ok and id == 1, "create: " .. tostring(msg))
	local a1, c1 = GetNumMacros()
	check(a0 == a1 and c0 == c1, "an extended macro took a slot")
	local b = _G.MoMX_1
	check(b and b:GetAttribute("type") == "macro" and b:GetAttribute("macrotext") == long, "secure button")
	check(b:GetAttribute("useOnKeyDown") == true and #b.__clicks == 1 and b.__clicks[1] == "AnyDown", "acts once, on the press")
	check(not ns.CreateExt("Too long", nil, ("x"):rep(1024)), "1024 accepted")
	check(not ns.CreateExt("", nil, "/say hi"), "empty name accepted")
	ok = ns.SaveExt(ns.ExtRef(1), "Big renew", 135953, "#showtooltip Renew\n/cast [@mouseover,help,nodead][help,nodead] Renew")
	check(ok and b:GetAttribute("macrotext"):find("mouseover", 1, true), "save")
	check(#ns.History(ns.ExtRef(1)) == 1 and ns.History(ns.ExtRef(1))[1].body == long, "history kept the old text")
	ok = ns.BindExt(ns.ExtRef(1), "CTRL-1")
	check(ok and MOCK.bindings["CTRL-1"] == "MoMX_1" and MouseoverMacrosCharDB.binds[1] == "CTRL-1", "binding")
	local ok2, msg2, index = ns.ExtToBar(ns.ExtRef(1))
	check(ok2 and index, "bar macro: " .. tostring(msg2))
	local bar = ns.GameRef(index)
	check(isMom(bar.name) and bar.body:find("\n/click MoMX_1 LeftButton 1\n#mom x1$") and bar.body:find("^#showtooltip Renew"), "bar macro body: " .. bar.body)
	check(ns.Cost(ns.ExtRef(1)):find(bar.name, 1, true), "cost names the bar macro")
	ns.SaveExt(ns.ExtRef(1), "Big renew", 135953, "#showtooltip Heal\n/cast Heal")
	check(ns.Fresh(bar).body:find("^#showtooltip Heal"), "bar macro follows the tooltip line")
	check(#ns.List("ext") == 1 and #ns.List("mine") > 20, "lists")
end)

step("extended macros in combat: queued, applied after", function()
	MOCK.combat = true
	local ok, msg = ns.SaveExt(ns.ExtRef(1), "Big renew", 135953, "/cast Renew")
	check(ok and msg == "queued" and last():find("in combat", 1, true), "combat reply: " .. last())
	check(_G.MoMX_1:GetAttribute("macrotext") == "#showtooltip Heal\n/cast Heal", "changed in combat")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check(_G.MoMX_1:GetAttribute("macrotext") == "/cast Renew", "not applied after combat")
	check(logHas("saved Big renew"), "after-combat report: " .. last())
end)

step("editor: the player's own macro can be edited here; limits; history and restore", function()
	local mount = ns.GameRef(GetMacroIndexByName("Mount"))
	check(not mount.ours, "Mount is not ours")
	ns.Edit(mount)
	check(ns.app.current == "edit" and ns.ed.body == "/cast Riding Turtle", "editor loaded")
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
	ns.ed.name = "Mount2"
	ns.EditorSave()
	check(find("Mount2") and ns.ed.ref.name == "Mount2" and #ns.History(ns.ed.ref) == 2, "rename keeps the history")
	ns.EditorInsert("[mod:shift] ")
	check(ns.ed.body:find("[mod:shift]", 1, true), "insert")
	check(not find("_mom1234").body:find("#mom", 1, true), "player's _mom1234 untouched")
end)

step("a new macro from the editor: character, account, extended", function()
	ns.EditNew("account") -- the insert above is not saved: it asks
	answer("discard")
	ns.ed.name, ns.ed.body = "Hearth", "/use Hearthstone"
	check(ns.EditorSave() and ns.ed.ref and ns.ed.ref.scope == "account", "account macro")
	ns.EditNew("char")
	ns.ed.name, ns.ed.body = "CharOne", "/say hi"
	local ok, msg = ns.EditorSave()
	check(not ok and msg:find("character macros are full", 1, true), "full character reply: " .. tostring(msg))
	ns.EditNew("ext")
	answer("discard") -- CharOne could not be saved: it asks before dropping it
	ns.ed.name, ns.ed.body = "ExtOne", "/say hi"
	check(ns.EditorSave() and ns.ed.ref.kind == "ext", "extended")
	check(ns.EditorSave(true) and ns.ed.ref.kind == "ext" and #ns.List("ext") == 3, "save as copy")
end)

step("move to account / character respects the slot limits; ours keeps its record", function()
	local heal = ns.Fresh({ kind = "game", scope = "char", name = "MyHeal" })
	check(heal and heal.ours and heal.scope == "char", "heal is a character macro of ours")
	local ok, msg = ns.MoveGame(heal, "account")
	check(ok and find("MyHeal") and GetMacroIndexByName("MyHeal") <= 120, "moved: " .. tostring(msg))
	check(MouseoverMacrosDB.owned.heal and MouseoverMacrosDB.owned.heal.scope == "account" and not MouseoverMacrosCharDB.owned.heal, "record moved")
	check(entry("heal").status == "ok", "still ours")
	-- back: character has a free slot now
	ok = ns.MoveGame(ns.Fresh({ kind = "game", scope = "account", name = "MyHeal" }), "char")
	check(ok, "moved back")
	ok, msg = ns.MoveGame(ns.Fresh({ kind = "game", scope = "account", name = "Hearth" }), "char")
	check(not ok and msg:find("no room", 1, true), "full move: " .. tostring(msg))
end)

step("delete asks twice, goes to the bin, restores", function()
	ns.Edit(ns.Fresh({ kind = "game", scope = "account", name = "Hearth" }))
	local row
	for _, w in ipairs(ns.app.sections.edit.stack.widgets) do
		if w.buttons and #w.buttons == 5 then row = w end
	end
	local del = row.buttons[5]
	del:GetScript("OnClick")(del)
	check(find("Hearth"), "deleted on the first click")
	del:GetScript("OnClick")(del)
	check(not find("Hearth"), "not deleted on the second click")
	check(MouseoverMacrosDB.bin[1].name == "Hearth", "not in the bin")
	ns.app:Open("backups")
	local list
	for _, w in ipairs(ns.app.sections.backups.stack.widgets) do if w.rows and not list then list = w end end
	list.rows[1].buttons[1]:GetScript("OnClick")(list.rows[1].buttons[1])
	check(find("Hearth") and find("Hearth").body == "/use Hearthstone", "restore from the bin")
	-- deleting an extended macro takes its bar macro and key with it
	local barName = ns.ExtBarMacro(1).name
	check(ns.DeleteExt(ns.ExtRef(1)), "delete ext")
	check(not find(barName) and MOCK.bindings["CTRL-1"] == nil and not MouseoverMacrosDB.ext[1], "ext leftovers")
end)

step("export / import round trip; nothing replaced", function()
	local odd = "#showtooltip\n/say a|b; c, d 100%\n/cast Renew"
	local _, _, id = ns.CreateExt("Odd one", "Spell_Holy_Renew", odd)
	local text = ns.Export({ ns.ExtRef(id), ns.Fresh({ kind = "game", scope = "account", name = "Hearth" }) })
	check(text:match("^MOM1\n") and not text:find("|", 1, true), "export text: " .. text)
	local list = assert(ns.ParseExport(text))
	check(#list == 2 and list[1].body == odd and list[1].icon == "Spell_Holy_Renew" and list[2].kind == "a", "parse")
	local nExt = #ns.List("ext")
	local ok, msg = ns.Import(list, "x")
	check(ok and #ns.List("ext") == nExt + 2, "import as extended: " .. tostring(msg))
	ok = ns.Import({ list[2] })
	check(ok and find("Hearth 2") and find("Hearth").body == "/use Hearthstone", "taken name numbered, original kept")
	check(not ns.ParseExport("hello"), "garbage accepted")
	-- the window buttons
	ns.app:Open("backups")
	local exportRow
	for _, w in ipairs(ns.app.sections.backups.stack.widgets) do
		if w.buttons and w.buttons[1]:GetText() == "Export" then exportRow = w end
	end
	exportRow.buttons[1]:GetScript("OnClick")(exportRow.buttons[1])
	check(ns.exportBox:GetText():match("^MOM1"), "export button")
end)

step("line check: unknown spells, #showtooltip placement, slots and sequences", function()
	local p = ns.CheckLines("#showtooltip Renew\n/cast [@mouseover,help,nodead][help,nodead] Renew\n/cast Renwe\n#showtooltip\n/use 13\n/use Hearthstone\n/castsequence reset=3 Renew, Heal, Smiite")
	local lines = {}
	for _, x in ipairs(p) do lines[#lines + 1] = x.line .. ":" .. x.text end
	local s = table.concat(lines, "\n")
	check(#p == 3, "problems:\n" .. s)
	check(s:find('3:"Renwe"', 1, true) and s:find("4:#showtooltip only", 1, true) and s:find('7:"Smiite"', 1, true), s)
	check(#ns.CheckLines(("x"):rep(300), 255) == 1, "length")
end)

step("templates: a _mom macro (updated, not duplicated) or an extended one", function()
	local t = ns.Templates()[1]
	check(t.id == "trinkets", "first template")
	local ok, msg = ns.MakeTemplate(t)
	check(ok and ns.Resolve("t:trinkets"), "made: " .. tostring(msg))
	local _, name = ns.Resolve("t:trinkets")
	local before = GetNumMacros()
	ns.MakeTemplate(t)
	check(GetNumMacros() == before and select(2, ns.Resolve("t:trinkets")) == name, "duplicated")
	local nExt = #ns.List("ext")
	check(ns.MakeTemplate(t, true) and #ns.List("ext") == nExt + 1, "extended template")
	local ids = {}
	for _, x in ipairs(ns.Templates()) do ids[x.id] = true end
	check(ids.wand and ids.ifheal, "priest templates")
end)

step("icon search: ? first, file names and IDs", function()
	local all = ns.SearchIcons("")
	check(all[1] == 134400 and #all == 6, "all icons: " .. #all)
	local r = ns.SearchIcons("renew")
	check(r[1] == 134400 and r[2] == "Spell_Holy_Renew" and #r == 2, "by name")
	check(#ns.SearchIcons("1359") == 2, "by ID")
	ns.EditNew("ext")
	ns.ed.picking = true
	ns.app:Refresh()
	check(ns.picker:IsShown(), "picker shown")
	ns.picker.cells[2]:GetScript("OnClick")(ns.picker.cells[2])
	check(ns.ed.icon == 135953 and not ns.ed.picking, "pick an icon")
	ns.app:Close() -- a new icon is a change: closing asks
	check(ns.app:IsShown(), "closed with an unsaved icon")
	answer("discard")
	check(not ns.app:IsShown() and ns.ed.icon == 134400, "discard did not close and revert")
end)

step("extended macros come back after a reload: buttons and bindings", function()
	local _, _, id = ns.CreateExt("Bound", nil, "/say bound")
	ns.BindExt(ns.ExtRef(id), "F5")
	_G["MoMX_" .. id]:SetAttribute("macrotext", nil)
	wipe(MOCK.bindings)
	MOCK.Fire("PLAYER_ENTERING_WORLD")
	check(_G["MoMX_" .. id]:GetAttribute("macrotext") == "/say bound" and MOCK.bindings.F5 == "MoMX_" .. id, "not restored")
end)

step("help, list, settings and unknown commands", function()
	MOCK.log = {}
	SlashCmdList.MOUSEOVERMACROS("help")
	local s = table.concat(MOCK.log, "\n")
	for _, c in ipairs({ "install", "create <macro>", "on <macro>", "off <macro>", "list" }) do
		check(s:find("/mom " .. c, 1, true), "help lacks " .. c)
	end
	MOCK.log = {}
	SlashCmdList.MOUSEOVERMACROS("list")
	check(#MOCK.log == 26, "list lines: " .. #MOCK.log)
	check(table.concat(MOCK.log, "\n"):find("_mom", 1, true), "list shows names")
	SlashCmdList.MOUSEOVERMACROS("settings")
	SlashCmdList.MOUSEOVERMACROS("bogus")
	check(last():find("/mom help", 1, true), "unknown reply")
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
		for _, e in ipairs(st.entries) do
			local f = e.frame
			if f and f.buttons and not f.rows then
				local w = 0
				for i, b in ipairs(f.buttons) do w = w + b:GetWidth() + (i > 1 and 8 or 0) end
				check(w <= st.width, ("%s: a row of buttons is %d px on a %d px page"):format(id, w, st.width))
			end
		end
	end
	ns.app:Close()
end)

step("Set key: closing the window cancels it, so a later key press is not bound", function()
	local _, _, id = ns.CreateExt("KeyTest", nil, "/say key")
	ns.Edit(ns.ExtRef(id))
	ns.keyCapture:Show()
	ns.app:Close()
	check(not ns.keyCapture:IsShown(), "capture still armed after closing the window")
	check(not MouseoverMacrosCharDB.binds[id], "bound")
	-- a key already in use says what it replaces
	GetBindingAction = function(k) if k == "W" then return "MOVEFORWARD" end return "" end
	BINDING_NAME_MOVEFORWARD = "Move Forward"
	local ok, msg = ns.BindExt(ns.ExtRef(id), "W")
	check(ok and msg:find("instead of Move Forward", 1, true), "bind reply: " .. tostring(msg))
	ok, msg = ns.BindExt(ns.ExtRef(id), "F9")
	check(ok and not msg:find("instead", 1, true), "free key reply: " .. tostring(msg))
	GetBindingAction, BINDING_NAME_MOVEFORWARD = nil, nil
	ns.DeleteExt(ns.ExtRef(id))
end)

-- The first button row on a page whose first button reads `label`.
local function rowWith(section, label)
	for _, w in ipairs(ns.app.sections[section].stack.widgets) do
		if w.buttons and w.buttons[1] and w.buttons[1]:GetText() == label then return w end
	end
end

step("Set key: a second click cancels (one chat line each); modifier keys alone are never bound", function()
	local _, _, id = ns.CreateExt("KeyTwice", nil, "/say key")
	ns.Edit(ns.ExtRef(id))
	local row = rowWith("edit", "Set key")
	check(row, "no Set key row")
	local set = row.buttons[1]
	local n = #MOCK.log
	set:GetScript("OnClick")(set)
	check(ns.keyCapture:IsShown() and set:GetText() == "Press a key...", "not waiting: " .. tostring(set:GetText()))
	set:GetScript("OnClick")(set)
	check(not ns.keyCapture:IsShown() and set:GetText() == "Set key", "second click did not cancel")
	check(#MOCK.log - n == 2 and last():find("key not changed", 1, true), "chat lines: " .. (#MOCK.log - n))
	set:GetScript("OnClick")(set)
	local press = ns.keyCapture:GetScript("OnKeyDown")
	for _, k in ipairs({ "LSHIFT", "RCTRL", "LALT", "LMETA", "RMETA" }) do press(ns.keyCapture, k) end
	check(ns.keyCapture:IsShown() and not MouseoverMacrosCharDB.binds[id], "a modifier alone was taken")
	press(ns.keyCapture, "F7")
	check(not ns.keyCapture:IsShown() and MouseoverMacrosCharDB.binds[id] == "F7" and set:GetText() == "Set key", "F7 not bound")
	-- combat starts while it waits: the keyboard is given back at once, nothing bound
	set:GetScript("OnClick")(set)
	check(ns.keyCapture:IsShown(), "waiting again")
	MOCK.combat = true
	MOCK.Fire("PLAYER_REGEN_DISABLED")
	check(not ns.keyCapture:IsShown(), "still holds the keyboard in combat")
	check(last():find("combat started", 1, true), "says why: " .. last())
	-- and in combat it doesn't start waiting
	set:GetScript("OnClick")(set)
	check(not ns.keyCapture:IsShown() and last():find("after combat", 1, true), "Set key in combat")
	-- Escape with unsaved changes in combat: left to the game (no question on top of the Game Menu)
	ns.ed.body = "/say changed"
	local onKey = ns.app.window:GetScript("OnKeyDown")
	onKey(ns.app.window, "ESCAPE")
	check(not LibStub("EverlookUI-1").IsPopupShown(), "asked about unsaved changes in combat")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	ns.ed.body = "/say key"
	ns.app:Close()
	ns.DeleteExt(ns.ExtRef(id))
end)

step("delete in the editor: a fresh editor of the same kind; the macro's history goes with it", function()
	local _, _, id = ns.CreateExt("DelMe", nil, "/say one")
	ns.SaveExt(ns.ExtRef(id), "DelMe", nil, "/say two")
	check(#ns.History(ns.ExtRef(id)) == 1, "history")
	ns.Edit(ns.ExtRef(id))
	local row
	for _, w in ipairs(ns.app.sections.edit.stack.widgets) do
		if w.buttons and #w.buttons == 5 then row = w end
	end
	row.buttons[5]:GetScript("OnClick")(row.buttons[5])
	row.buttons[5]:GetScript("OnClick")(row.buttons[5])
	check(not MouseoverMacrosDB.ext[id], "not deleted")
	check(ns.ed.ref == nil and ns.ed.as == "ext" and ns.ed.body == "#showtooltip\n" and ns.ed.name == "", "editor kept the deleted text")
	check(MouseoverMacrosDB.history["x" .. id] == nil, "history of a deleted macro kept")
	ns.app:Close()
end)

step("restore from the bin in combat: waits, then restores and leaves the bin", function()
	local _, _, id = ns.CreateExt("BinMe", nil, "/say bin")
	ns.DeleteExt(ns.ExtRef(id))
	check(MouseoverMacrosDB.bin[1].name == "BinMe", "in the bin")
	ns.app:Open("backups")
	local list
	for _, w in ipairs(ns.app.sections.backups.stack.widgets) do if w.rows and not list then list = w end end
	MOCK.combat = true
	list.rows[1].buttons[1]:GetScript("OnClick")(list.rows[1].buttons[1])
	check(MouseoverMacrosDB.bin[1].name == "BinMe", "left the bin in combat")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	check(MouseoverMacrosDB.bin[1] == nil or MouseoverMacrosDB.bin[1].name ~= "BinMe", "still in the bin after combat")
	local found
	for _, r in ipairs(ns.List("ext")) do if r.name == "BinMe" then found = true end end
	check(found, "not restored after combat")
	ns.app:Close()
end)

local function extNamed(name)
	local out = {}
	for _, r in ipairs(ns.List("ext")) do if r.name == name then out[#out + 1] = r end end
	return out
end

step("unsaved changes: another macro, New, another page, x, Escape and /mom ask Save / Discard / Cancel", function()
	local _, _, other = ns.CreateExt("Other", nil, "/say other")
	ns.EditNew("ext")
	check(not (ns.unsavedDialog and ns.unsavedDialog:IsShown()), "asked with nothing changed")
	ns.ed.name, ns.ed.body = "Guarded", "/say guarded"
	-- Cancel keeps everything as it was, whichever way the player tried to leave
	local w = ns.app.window
	for _, leave in ipairs({
		function() ns.Edit(ns.ExtRef(other)) end,
		function() ns.EditNew("char") end,
		function() ns.app:ShowSection("mine") end,
		function() ns.app:Close() end,
		function() w.close:GetScript("OnClick")(w.close) end,
		function() w:GetScript("OnKeyDown")(w, "ESCAPE") end,
		function() SlashCmdList.MOUSEOVERMACROS("") end,
	}) do
		leave()
		answer("cancel")
		check(ns.app:IsShown() and ns.app.current == "edit" and ns.ed.name == "Guarded" and ns.ed.ref == nil, "cancel lost the editor")
	end
	check(#extNamed("Guarded") == 0, "saved without being asked")
	-- Save: saves, then goes on
	ns.EditNew("char")
	answer("save")
	check(#extNamed("Guarded") == 1 and ns.ed.ref == nil and ns.ed.as == "char", "save then new")
	-- Discard: back to what was saved, then goes on
	ns.Edit(extNamed("Guarded")[1])
	ns.ed.body = "/say changed"
	ns.app:ShowSection("mine")
	answer("discard")
	check(ns.app.current == "mine" and extNamed("Guarded")[1].body == "/say guarded" and ns.ed.body == "/say guarded", "discard")
	-- a save that fails stays in the editor
	ns.EditNew("ext")
	ns.ed.body = "/say no name"
	ns.app:Close()
	answer("save")
	check(ns.app:IsShown() and ns.ed.body == "/say no name" and not ns.unsavedDialog:IsShown(), "failed save left the editor")
	-- the same macro, changed: just shows it again
	ns.Edit(extNamed("Guarded")[1])
	answer("discard")
	ns.ed.body = "/say again"
	ns.app:ShowSection("ext")
	answer("cancel")
	ns.Edit(extNamed("Guarded")[1])
	check(not ns.unsavedDialog:IsShown() and ns.ed.body == "/say again", "same macro asked or reloaded")
	ns.app:Close()
	answer("discard")
	check(not ns.app:IsShown(), "not closed")
	ns.DeleteExt(extNamed("Guarded")[1])
	ns.DeleteExt(ns.ExtRef(other))
	check(next(StaticPopupDialogs) == nil, "a StaticPopup was used")
end)

step("save in combat: waits once, saves the latest text after combat, never a duplicate", function()
	ns.EditNew("ext")
	ns.ed.name, ns.ed.body = "CombatSave", "/say one"
	MOCK.combat = true
	local jobs = #ns.queue.jobs
	local ok, msg = ns.EditorSave()
	check(ok and msg == "queued" and ns.ed.pending and #ns.queue.jobs == jobs + 1, "not queued")
	check(last():find("in combat", 1, true), "combat reply: " .. last())
	local save, copy = ns.saveRow.buttons[1], ns.saveRow.buttons[2]
	check(save:GetAlpha() < 1 and copy:GetAlpha() < 1, "Save not greyed out")
	save:GetScript("OnClick")(save)
	ns.EditorSave()
	check(#ns.queue.jobs == jobs + 1, "a second save was queued")
	local status
	for _, wd in ipairs(ns.app.sections.edit.stack.widgets) do
		if wd.text and wd.text:GetText() and wd.text:GetText():find("Will save when combat ends", 1, true) then status = wd end
	end
	check(status, "no 'Will save when combat ends' line")
	-- still editable; a queued save is not "unsaved": leaving doesn't ask
	ns.ed.body = "/say two"
	check(not ns.EditorDirty(), "a queued save counts as unsaved")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	local made = extNamed("CombatSave")
	check(#made == 1 and made[1].body == "/say two", "after combat: " .. #made .. " macros")
	check(ns.ed.ref and ns.ed.ref.kind == "ext" and ns.ed.ref.name == "CombatSave" and not ns.ed.pending, "editor still on a new macro")
	check(ns.ed.status and ns.ed.status.ok and ns.ed.status.text == "Saved after combat.", "status")
	check(logHas("after combat: created extended macro CombatSave") and save:GetAlpha() == 1, "chat line / Save still grey")
	check(not ns.EditorDirty(), "saved text counts as unsaved")
	ns.DeleteExt(made[1])

	-- it fails after combat: says so in red, the text stays
	ns.EditNew("char")
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
	ns.EditNew("ext")
	ns.ed.name, ns.ed.body = "LeftBehind", "/say four"
	MOCK.combat = true
	ns.EditorSave()
	ns.ed.body = "/say five"
	ns.EditNew("ext")
	check(not ns.unsavedDialog:IsShown() and ns.ed.ref == nil and ns.ed.name == "", "leaving a queued save asked")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	made = extNamed("LeftBehind")
	check(#made == 1 and made[1].body == "/say five", "left-behind save")
	check(ns.ed.ref == nil and ns.ed.name == "", "the editor jumped to the saved macro")
	ns.DeleteExt(made[1])
	ns.app:Close()
end)

step("bar macros from an older version get the press line at login (out of combat only)", function()
	local _, _, id = ns.CreateExt("OldBar", nil, "#showtooltip Heal\n/cast Heal")
	local _, _, index = ns.ExtToBar(ns.ExtRef(id))
	local old = "#showtooltip Heal\n/click MoMX_" .. id .. "\n#mom x" .. id
	EditMacro(index, nil, nil, old)
	MOCK.combat = true
	MOCK.Fire("PLAYER_ENTERING_WORLD")
	check(ns.Fresh(ns.GameRef(index)).body == old, "changed in combat")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	local bar = ns.ExtBarMacro(id)
	check(GetMacroInfo(bar.index) == bar.name and select(3, GetMacroInfo(bar.index)) == "#showtooltip Heal\n/click MoMX_" .. id .. " LeftButton 1\n#mom x" .. id,
		"not updated: " .. select(3, GetMacroInfo(bar.index)))
	-- up to date: not edited again
	local before = edits
	MOCK.Fire("PLAYER_ENTERING_WORLD")
	check(edits == before, "an up-to-date bar macro was edited again")
	ns.DeleteExt(ns.ExtRef(id))
end)

step("/macro and the game menu open /mom (on the game macros); Blizzard's window one click away", function()
	check(MouseoverMacrosDB.takeover == true, "takeover is not on by default")
	if ns.app:IsShown() then ns.app:Close() end
	SlashCmdList.MACRO("")
	check(ns.app:IsShown() and ns.app.current == "account" and MOCK.blizzSlash == 0 and not MacroFrame, "/macro: " .. tostring(ns.app.current))
	ns.app:Close()
	-- the game menu's / chat menu's Macros: ours opens next to Blizzard's, which stays open (never closed by /mom)
	ShowMacroFrame()
	check(MacroFrame and MacroFrame:IsShown() and ns.app:IsShown() and ns.app.current == "account", "game menu")
	MacroFrame:Hide()
	check(ns.macroButton and ns.macroButton:GetParent() == MacroFrame, "no button in Blizzard's window")
	-- /mom blizzard: Blizzard's window, ours closed; the game menu doesn't take it away while it's open
	SlashCmdList.MOUSEOVERMACROS("blizzard")
	check(MacroFrame:IsShown() and not ns.app:IsShown(), "/mom blizzard")
	ShowMacroFrame()
	check(MacroFrame:IsShown() and not ns.app:IsShown(), "Blizzard's window taken away while open on purpose")
	-- its "Open /mom" button: ours opens, Blizzard's stays
	ns.macroButton:GetScript("OnClick")(ns.macroButton)
	check(MacroFrame:IsShown() and ns.app:IsShown(), "Open /mom button")
	MacroFrame:Hide()
	ns.app:Close()
	-- once closed, the takeover is back
	ShowMacroFrame()
	check(MacroFrame:IsShown() and ns.app:IsShown(), "takeover not back")
	MacroFrame:Hide()
	-- the sidebar button
	local footer = ns.app.window.footer[1]
	check(footer and footer:GetText() == "Blizzard's macro window", "sidebar button")
	footer:GetScript("OnClick")(footer)
	check(MacroFrame:IsShown() and not ns.app:IsShown(), "sidebar button did not open Blizzard's window")
	MacroFrame:Hide()
	-- in combat too, Blizzard's window is left alone
	MOCK.combat = true
	ShowMacroFrame()
	check(MacroFrame:IsShown(), "closed Blizzard's window in combat")
	ns.app:Close()
	MacroFrame:Hide()
	SlashCmdList.MACRO("")
	check(ns.app:IsShown() and not MacroFrame:IsShown(), "/macro in combat")
	ns.app:Close()
	MOCK.combat = false
	-- unsaved changes: /macro opens the editor, not a list
	ns.EditNew("ext")
	ns.ed.body = "/say unsaved"
	ns.app.window:Hide() -- hidden by something else (no question)
	SlashCmdList.MACRO("")
	check(ns.app.current == "edit" and ns.ed.body == "/say unsaved", "/macro left unsaved changes")
	ns.app:Close()
	answer("discard")
	-- switched off: /macro and the game menu are Blizzard's again
	SlashCmdList.MOUSEOVERMACROS("takeover off")
	check(MouseoverMacrosDB.takeover == false, "setting")
	SlashCmdList.MACRO("")
	check(MOCK.blizzSlash == 1 and MacroFrame:IsShown() and not ns.app:IsShown(), "/macro with the takeover off")
	MacroFrame:Hide()
	ShowMacroFrame()
	check(MacroFrame:IsShown() and not ns.app:IsShown(), "game menu with the takeover off")
	MacroFrame:Hide()
	SlashCmdList.MOUSEOVERMACROS("takeover on")
	-- an empty Mine says where the player's own macros are
	ns.app:Open("mine")
	check(ns.EMPTY_MINE and ns.EMPTY_MINE:find("under Account and Character", 1, true), "Mine's empty text")
	ns.app:Close()
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
	local _, _, id = ns.CreateExt("RingKeyTest", nil, "/say hi")
	ns.BindExt(ns.ExtRef(id), "F7")
	check(MOCK.bindings.F7 == "MoMX_" .. id and MOCK.bindings.BUTTON3 == "MoMRingTrigger", "both bound")
	SlashCmdList.MOUSEOVERMACROS("ring off")
	check(MOCK.bindings.BUTTON3 == nil and MOCK.bindings.F7 == "MoMX_" .. id, "off: middle mouse is the game's again")
	SlashCmdList.MOUSEOVERMACROS("ring on")
	check(MOCK.bindings.BUTTON3 == "MoMRingTrigger", "on again")
	local ok = Ring.SetKey("BUTTON1")
	check(not ok and ns.db.ring.key == "BUTTON3", "left click alone refused")
	check(Ring.SetKey("SHIFT-BUTTON2") and MOCK.bindings["SHIFT-BUTTON2"] == "MoMRingTrigger", "shift + right click is fine")
	Ring.SetKey("BUTTON3")
	ns.DeleteExt(ns.ExtRef(id))
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

step("the player's macros were never changed", function()
	check(find("fort").body == PLAYER_FORT and find("Mount2").body == "/cast Riding Turtle", "changed") -- Mount2: renamed by the player in the editor
	check(find("smite").body == "#showtooltip Smite\n/cast Smite", "smite changed")
end)

step("no taint: only our own globals", function()
	local allowed = { MouseoverMacrosDB = true, MouseoverMacrosCharDB = true, SLASH_MOUSEOVERMACROS1 = true, LibStub = true }
	for k in pairs(globalWrites) do check(allowed[k], "addon assigned the global " .. tostring(k)) end
	check(next(StaticPopupDialogs) == nil and next(UISpecialFrames) == nil, "Blizzard lists touched")
end)

step("no Lua errors reported", function()
	check(#MOCK.errors == 0, table.concat(MOCK.errors, "\n"))
end)

print(("\n%d passed, %d failed"):format(passes, #failures))
return #failures
