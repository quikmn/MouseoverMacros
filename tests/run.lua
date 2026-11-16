-- Offline tests for MouseoverMacros against wowmock.lua: macro bodies, creating and updating,
-- the on/off switches, where new macros go, Auto Self Cast, every slash command and the window.
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

-- Macro API: account macros are indexes 1-120, character macros 121-138.
local macros = { account = {}, char = {} }
MAX_ACCOUNT_MACROS, MAX_CHARACTER_MACROS = 120, 18
local function all()
	local t = {}
	for i, m in ipairs(macros.account) do t[i] = m end
	for i, m in ipairs(macros.char) do t[120 + i] = m end
	return t
end
GetNumMacros = function() return #macros.account, #macros.char end
GetMacroIndexByName = function(name) for i, m in pairs(all()) do if m.name == name then return i end end return 0 end
GetMacroInfo = function(i) local m = all()[i]; if m then return m.name, m.icon, m.body end end
CreateMacro = function(name, icon, body, perChar)
	local list = perChar and macros.char or macros.account
	if #list >= (perChar and 18 or 120) then return nil end
	list[#list + 1] = { name = name, icon = icon, body = body }
	return true
end
EditMacro = function(i, name, icon, body) local m = all()[i]; m.name = name or m.name; m.body = body end
MOCK.picked = nil
PickupMacro = function(i) MOCK.picked = i end
MOCK.cvars = { autoSelfCast = "1" }
C_CVar = { GetCVar = function(k) return MOCK.cvars[k] end, SetCVar = function(k, v) MOCK.cvars[k] = v end }
UnitClass = function() return "Priest", "PRIEST", 5 end
C_Spell = C_Spell or {}
C_Spell.GetSpellTexture = function() return 135953 end

local globalWrites = {}
local addonEnv = setmetatable({}, { __index = _G, __newindex = function(_, k, v) globalWrites[k] = true; _G[k] = v end })

step("load TOC files; defaults on a fresh install", function()
	local toc = assert(io.open(ROOT .. "/" .. ADDON .. ".toc")):read("*a")
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
end)

step("macro bodies are exactly the old ones", function()
	local want = {
		renew = "#showtooltip Renew\n/cast [@mouseover,help,nodead][help,nodead] Renew",
		poh = "#showtooltip Prayer of Healing\n/cast [@mouseover,help,nodead][help,nodead][@player] Prayer of Healing",
		dispel = "#showtooltip Dispel Magic\n/cast [@mouseover,exists,nodead][exists,nodead] Dispel Magic",
		swp = "#showtooltip Shadow Word: Pain\n/cast [@mouseover,harm,nodead][harm,nodead] Shadow Word: Pain",
		rez = "#showtooltip Resurrection\n/cast [@mouseover,help,dead][help,dead] Resurrection",
	}
	local n = 0
	for _, e in ipairs(ns.Entries()) do
		n = n + 1
		if want[e.name] then check(e.body == want[e.name], e.name .. " body changed:\n" .. e.body) end
		check(not e.body:find("@player") or e.name == "poh", e.name .. " casts on you")
	end
	check(n == 20, "20 priest macros, got " .. n)
end)

step("Auto Self Cast is turned off at login (option on by default)", function()
	MOCK.Fire("PLAYER_LOGIN")
	check(MOCK.cvars.autoSelfCast == "0", "not turned off")
	MOCK.cvars.autoSelfCast = "1"
	SlashCmdList.MOUSEOVERMACROS("autoselfcast off")
	check(MouseoverMacrosDB.autoSelfCastOff == false and last():find("off", 1, true), "option off: " .. last())
	MOCK.Fire("PLAYER_LOGIN")
	check(MOCK.cvars.autoSelfCast == "1", "changed the CVar with the option off")
	SlashCmdList.MOUSEOVERMACROS("autoselfcast on")
	check(MOCK.cvars.autoSelfCast == "0", "switching it on didn't apply it")
end)

step("bare /mom opens the window (no longer creates macros); Escape closes it", function()
	SlashCmdList.MOUSEOVERMACROS("")
	local f = MouseoverMacrosOptionsWindow
	check(f and f:IsShown(), "window not shown")
	check(#macros.char == 0 and #macros.account == 0, "bare /mom created macros")
	f:GetScript("OnKeyDown")(f, "ESCAPE")
	check(not f:IsShown(), "escape didn't close")
end)

step("switches: off macros are skipped by install; on/off from chat and the window", function()
	SlashCmdList.MOUSEOVERMACROS("off renew")
	check(MouseoverMacrosDB.off.renew, "off")
	SlashCmdList.MOUSEOVERMACROS("off nosuch")
	check(last():find("no macro called", 1, true) and last():find("renew", 1, true), "unknown macro reply: " .. last())
	SlashCmdList.MOUSEOVERMACROS("off")
	check(last():find("Example: /mom off renew", 1, true), "missing name reply: " .. last())
	SlashCmdList.MOUSEOVERMACROS("install")
	check(GetMacroIndexByName("renew") == 0, "switched-off macro created")
	check(#macros.char == 18 and #macros.account == 1, "character first, then account when full: " .. #macros.char .. "/" .. #macros.account)
	check(last():find("created 19", 1, true) and last():find("1 switched off", 1, true), "summary: " .. last())
	SlashCmdList.MOUSEOVERMACROS("on renew")
	check(not MouseoverMacrosDB.off.renew, "on")
	SlashCmdList.MOUSEOVERMACROS("all")
	check(last():find("created 1, updated 19", 1, true), "second install: " .. last())
end)

step("a macro edited by hand shows as changed and Update puts ours back", function()
	local i = GetMacroIndexByName("heal")
	EditMacro(i, "heal", nil, "/cast Heal")
	check(ns.Find("heal").status == "differs", "not seen as changed")
	SlashCmdList.MOUSEOVERMACROS("create heal")
	check(ns.Find("heal").status == "ok", "create didn't restore it")
	check(ns.Find("HEAL") ~= nil, "names are case-insensitive")
end)

step("new macros go to account macros when chosen", function()
	macros.account, macros.char = {}, {}
	SlashCmdList.MOUSEOVERMACROS("where account")
	check(MouseoverMacrosDB.where == "account", "where")
	SlashCmdList.MOUSEOVERMACROS("create smite")
	check(#macros.account == 1 and #macros.char == 0, "not an account macro")
	SlashCmdList.MOUSEOVERMACROS("where somewhere")
	check(last():find("character, account", 1, true), "bad choice reply: " .. last())
	SlashCmdList.MOUSEOVERMACROS("where character")
end)

step("no editing in combat", function()
	MOCK.combat = true
	SlashCmdList.MOUSEOVERMACROS("create renew")
	check(last():find("combat", 1, true), "combat reply: " .. last())
	SlashCmdList.MOUSEOVERMACROS("install")
	check(last():find("combat", 1, true), "combat reply (install)")
	MOCK.combat = false
end)

step("the window list: switches, Create / Update / Pick up buttons", function()
	ns.app:Open()
	local list
	for _, w in ipairs(ns.app.sections.macros.stack.widgets) do if w.rows then list = w end end
	check(list and #list.rows == 20, "20 rows")
	local smite
	for _, r in ipairs(list.rows) do if r.item.name == "smite" then smite = r end end
	check(smite.buttons[1]:GetText() == "Up to date" and smite.buttons[2]:IsShown(), "existing macro row")
	smite.buttons[2]:GetScript("OnClick")(smite.buttons[2])
	check(MOCK.picked == GetMacroIndexByName("smite"), "pick up")
	local renew = list.rows[1]
	check(renew.item.name == "renew" and renew.buttons[1]:GetText() == "Create" and not renew.buttons[2]:IsShown(), "missing macro row")
	renew.buttons[1]:GetScript("OnClick")(renew.buttons[1])
	check(GetMacroIndexByName("renew") > 0, "Create button")
	MOCK.Fire("UPDATE_MACROS")
	renew.switch:GetScript("OnMouseDown")(renew.switch)
	check(MouseoverMacrosDB.off.renew, "row switch")
	ns.app:Close()
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
	check(#MOCK.log == 20, "list lines: " .. #MOCK.log)
	SlashCmdList.MOUSEOVERMACROS("settings")
	SlashCmdList.MOUSEOVERMACROS("bogus")
	check(last():find("/mom help", 1, true), "unknown reply")
end)

step("no taint: only our own globals", function()
	local allowed = { MouseoverMacrosDB = true, SLASH_MOUSEOVERMACROS1 = true, LibStub = true }
	for k in pairs(globalWrites) do check(allowed[k], "addon assigned the global " .. tostring(k)) end
	check(next(StaticPopupDialogs) == nil and next(UISpecialFrames) == nil, "Blizzard lists touched")
end)

step("no Lua errors reported", function()
	check(#MOCK.errors == 0, table.concat(MOCK.errors, "\n"))
end)

print(("\n%d passed, %d failed"):format(passes, #failures))
return #failures
