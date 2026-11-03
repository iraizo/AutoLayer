local _, addonTable = ...

local compat = {}
addonTable.compat = compat

-- WoW Forever (codename Camelot) reports interface 16xxx. WOW_PROJECT_ID is not usable for detection:
-- it is 1 (Retail's value) on build 69913 and WOW_PROJECT_CAMELOT (18) on current builds.
local interface = select(4, GetBuildInfo())
compat.isForever = type(interface) == "number" and interface >= 16000 and interface < 17000

-- Forever has no C_Seasons API. Only the call result is trusted: the existence of a C_Seasons table
-- is not proof of native support (other addons install shims), and globals are read at call time
-- because they may be defined after this file loads.
function compat.IsSeasonal()
	if C_Seasons and C_Seasons.HasActiveSeason then
		return C_Seasons.HasActiveSeason()
	end
	return false
end

-- Era/Anniversary still define the global LeaveParty, which is preferred to keep their behaviour
-- unchanged. Forever only has C_PartyInfo.LeaveParty.
function compat.LeaveParty()
	if LeaveParty then
		LeaveParty()
	else
		C_PartyInfo.LeaveParty()
	end
end

-- Forever's chat events carry secret values during chat lockdown; string operations on them throw.
-- Returns false if any argument is secret.
function compat.CanAccess(...)
	if not issecretvalue then
		return true
	end
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then
			return false
		end
	end
	return true
end

-- Era defines SetDesaturation natively; Forever does not, but AceGUI's checkbox calls it.
if compat.isForever and not SetDesaturation then
	function SetDesaturation(texture, desaturated)
		texture:SetDesaturated(desaturated)
	end
end
