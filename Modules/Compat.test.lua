-- Run from the repo root: lua5.1 Modules/Compat.test.lua

local function load_compat(globals)
	local env = setmetatable({}, { __index = _G })
	for k, v in pairs(globals or {}) do
		rawset(env, k, v)
	end
	local chunk = assert(loadfile("Modules/Compat.lua"))
	setfenv(chunk, env)
	local addonTable = {}
	chunk("AutoLayer", addonTable)
	return addonTable.compat, env
end

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
		print("PASS " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end

local function build(v) return function() return "1.60.1", "69913", "x", v end end

test("isForever true for 16001, 16000, 16999", function()
	for _, v in ipairs({16001, 16000, 16999}) do
		assert(load_compat({GetBuildInfo = build(v)}).isForever == true, v)
	end
end)
test("isForever false for 15999, 17000, Era 11508, Anniversary 20506, Retail 120001", function()
	for _, v in ipairs({15999, 17000, 11508, 20506, 120001}) do
		assert(load_compat({GetBuildInfo = build(v)}).isForever == false, v)
	end
end)
test("IsSeasonal false when C_Seasons is nil", function()
	assert(load_compat({GetBuildInfo = build(16001)}).IsSeasonal() == false)
end)
test("IsSeasonal false when C_Seasons lacks HasActiveSeason", function()
	assert(load_compat({GetBuildInfo = build(16001), C_Seasons = {}}).IsSeasonal() == false)
end)
test("IsSeasonal mirrors HasActiveSeason", function()
	local c = load_compat({GetBuildInfo = build(11508), C_Seasons = {HasActiveSeason = function() return true end}})
	assert(c.IsSeasonal() == true)
	c = load_compat({GetBuildInfo = build(11508), C_Seasons = {HasActiveSeason = function() return false end}})
	assert(c.IsSeasonal() == false)
end)
test("LeaveParty prefers the global when both exist (Era/Anniversary behaviour)", function()
	local calls = {}
	local c = load_compat({GetBuildInfo = build(11508),
		C_PartyInfo = {LeaveParty = function() calls[#calls + 1] = "ns" end},
		LeaveParty = function() calls[#calls + 1] = "global" end})
	c.LeaveParty()
	assert(#calls == 1 and calls[1] == "global")
end)
test("LeaveParty uses C_PartyInfo.LeaveParty when the global is absent (Forever)", function()
	local calls = {}
	local c = load_compat({GetBuildInfo = build(16001),
		C_PartyInfo = {LeaveParty = function() calls[#calls + 1] = "ns" end}})
	c.LeaveParty()
	assert(#calls == 1 and calls[1] == "ns")
end)
test("LeaveParty works when C_PartyInfo is nil", function()
	local calls = {}
	local c = load_compat({GetBuildInfo = build(20506), LeaveParty = function() calls[#calls + 1] = "global" end})
	c.LeaveParty()
	assert(#calls == 1 and calls[1] == "global")
end)
test("CanAccess is true without issecretvalue", function()
	local c = load_compat({GetBuildInfo = build(11508)})
	assert(c.CanAccess("a", nil, "b") == true and c.CanAccess() == true)
end)
test("CanAccess false when any argument is secret, including after a nil and for tables", function()
	local SECRET = {}
	local c = load_compat({GetBuildInfo = build(16001), issecretvalue = function(v) return v == SECRET end})
	assert(c.CanAccess("a", "b") == true)
	assert(c.CanAccess("a", SECRET) == false)
	assert(c.CanAccess(nil, SECRET) == false)
	assert(c.CanAccess({}) == true)
end)
test("CanAccess checks the third argument (msg, name, channelBaseName)", function()
	local SECRET = {}
	local c = load_compat({GetBuildInfo = build(16001), issecretvalue = function(v) return v == SECRET end})
	assert(c.CanAccess("msg", "name", SECRET) == false)
	assert(c.CanAccess("msg", "name", "General") == true)
end)
test("Forever: SetDesaturation installed when missing and forwards to SetDesaturated", function()
	local got
	local _, env = load_compat({GetBuildInfo = build(16001)})
	assert(type(env.SetDesaturation) == "function")
	env.SetDesaturation({SetDesaturated = function(_, v) got = v end}, true)
	assert(got == true)
end)
test("Forever: a native SetDesaturation is never replaced", function()
	local native = function() end
	local _, env = load_compat({GetBuildInfo = build(16001), SetDesaturation = native})
	assert(env.SetDesaturation == native)
end)
test("non-Forever: SetDesaturation is not installed", function()
	local _, env = load_compat({GetBuildInfo = build(20506)})
	assert(rawget(env, "SetDesaturation") == nil)
end)
test("InChatLockdown mirrors C_ChatInfo.InChatMessagingLockdown on Forever", function()
	local locked = true
	local c = load_compat({GetBuildInfo = build(16001),
		C_ChatInfo = {InChatMessagingLockdown = function() return locked end}})
	assert(c.InChatLockdown() == true)
	locked = false
	assert(c.InChatLockdown() == false)
end)
test("InChatLockdown false on Forever when the API is missing", function()
	assert(load_compat({GetBuildInfo = build(16001)}).InChatLockdown() == false)
	assert(load_compat({GetBuildInfo = build(16001), C_ChatInfo = {}}).InChatLockdown() == false)
end)
test("InChatLockdown is always false off Forever, even if the API reports true", function()
	for _, v in ipairs({11508, 20506}) do
		local c = load_compat({GetBuildInfo = build(v),
			C_ChatInfo = {InChatMessagingLockdown = function() return true end}})
		assert(c.InChatLockdown() == false, v)
	end
end)

print(string.format("compat_test: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
