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
	check(n == 24, "24 priest macros, got " .. n)
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
	check(last():find("created 19, updated 4", 1, true) and last():find("1 switched off", 1, true), "summary: " .. last())
	check(find("fort").body == PLAYER_FORT and find("smite").body == "#showtooltip Smite\n/cast Smite"
		and find("_mom1234").body:find("player's", 1, true) and find("Mount"), "player's macros changed")
	for _, e in ipairs(ns.Entries()) do
		if e.on then check(e.status == "ok" and isMom(e.macro), e.key .. " " .. e.status) end
	end
	SlashCmdList.MOUSEOVERMACROS("on penance")
	SlashCmdList.MOUSEOVERMACROS("all")
	check(last():find("created 1, updated 23", 1, true), "second install: " .. last())
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
	check(list and #list.rows == 24, "24 rows")
	local smite, dplague
	for _, r in ipairs(list.rows) do
		if r.item.key == "smite" then smite = r end
		if r.item.key == "dplague" then dplague = r end
	end
	check(smite.buttons[1]:GetText() == "Up to date" and smite.buttons[2]:IsShown(), "existing macro row")
	check(smite.title:GetText():find(entry("smite").macro, 1, true), "row shows the macro name")
	smite.buttons[2]:GetScript("OnClick")(smite.buttons[2])
	check(MOCK.picked == GetMacroIndexByName(entry("smite").macro), "pick up")
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
C_Spell.GetSpellInfo = function(x) if KNOWN[x] then return { name = x } end end
C_Item = { GetItemInfoInstant = function(x) if x == "Hearthstone" then return 6948 end end }
GetMacroIcons = function(t) for _, v in ipairs({ 135953, 136000, "Spell_Holy_Renew", "INV_Misc_Bag_07" }) do t[#t + 1] = v end end
GetMacroItemIcons = function(t) t[#t + 1] = 133784 end

step("every section of the window opens", function()
	for _, id in ipairs({ "mine", "account", "char", "ext", "templates", "edit", "backups", "options" }) do
		ns.app:Open(id)
		check(ns.app.sections[id].stack, id .. " not built")
	end
	check(#ns.app.order == 8 and ns.app.order[1] == "mine", "sidebar order")
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
	ns.EditNew("account")
	ns.ed.name, ns.ed.body = "Hearth", "/use Hearthstone"
	check(ns.EditorSave() and ns.ed.ref and ns.ed.ref.scope == "account", "account macro")
	ns.EditNew("char")
	ns.ed.name, ns.ed.body = "CharOne", "/say hi"
	local ok, msg = ns.EditorSave()
	check(not ok and msg:find("character macros are full", 1, true), "full character reply: " .. tostring(msg))
	ns.EditNew("ext")
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
	ns.app:Close()
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
	check(#MOCK.log == 24, "list lines: " .. #MOCK.log)
	check(table.concat(MOCK.log, "\n"):find("_mom", 1, true), "list shows names")
	SlashCmdList.MOUSEOVERMACROS("settings")
	SlashCmdList.MOUSEOVERMACROS("bogus")
	check(last():find("/mom help", 1, true), "unknown reply")
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
