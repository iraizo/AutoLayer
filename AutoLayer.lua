---@diagnostic disable: inject-field

local addonName, addonTable = ...
local GetAddOnMetadata = C_AddOns.GetAddOnMetadata

local isBurningCrusade = WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC
addonTable.flavor = isBurningCrusade and "bcc" or "classic"
-- On Forever the WOW_PROJECT_BURNING_CRUSADE_CLASSIC comparison is false (WOW_PROJECT_ID is WOW_PROJECT_CAMELOT = 18
-- on current builds), so Forever intentionally falls into flavor == "classic" (segment protocol).
-- Do not add a third flavor.
local compat = addonTable.compat
local util = addonTable.util

local ADDON_VERSION_FALLBACK = "1.9.12"
local addonVersion = GetAddOnMetadata(addonName, "Version") or ADDON_VERSION_FALLBACK
addonTable.version = addonVersion

AutoLayer = LibStub("AceAddon-3.0"):NewAddon("AutoLayer", "AceConsole-3.0", "AceEvent-3.0")
addonTable.AceGUI = LibStub("AceGUI-3.0")
local minimap_icon = LibStub("LibDBIcon-1.0")
local CTL = _G.ChatThrottleLib
local ChatFrameAddMessageEventFilter = ChatFrameUtil.AddMessageEventFilter
local ChatFrameRemoveMessageEventFilter = ChatFrameUtil.RemoveMessageEventFilter

addonTable.icons = {
	enabled = [[Interface\AddOns\AutoLayer\Textures\AutoLayer_enabled_icon]],
	disabled = [[Interface\AddOns\AutoLayer\Textures\AutoLayer_disabled_icon]],
}

local annoyingSounds = {
	567490, -- invite sent
	567451, -- invite accepted
	539839,
	540356,
	540778,
	540941,
	540984,
	542585,
	542862,
	540287,
	540579,
	541222,
	542952,
	542659,
	539901,
	541298,
	543146,
	543174, -- "they can't join our group"
	539218, -- BloodElfMale_AlreadyInGroup
	539307, -- BloodElfFemale_AlreadyInGroup
	539481, -- DraeneiMale_AlreadyInGroup
	539729, -- DraeneiFemale_AlreadyInGroup
	-- When the group is full, mute the sound that plays for the failed invitation, this can happen on busy realms
	539272, -- BloodElfFemale_CantInvite
	539274, -- BloodElfMale_CantInvite
	539663, -- DraeneiFemale_CantInvite
	539503, -- DraeneiMale_CantInvite
	539844, -- DwarfFemale_CantInvite
	539947, -- DwarfMale_CantInvite
	540320, -- GnomeFemale_CantInvite
	540404, -- GnomeMale_CantInvite
	540798, -- HumanMale_CantInvite
	540559, -- HumanFemale_CantInvite
	540933, -- NightElfFemale_CantInvite
	540967, -- NightElfMale_CantInvite
	541188, -- OrcFemale_CantInvite
	541258, -- OrcMale_CantInvite
	542828, -- TaurenFemale_CantInvite
	542912, -- TaurenMale_CantInvite
	543102, -- TrollFemale_CantInvite
	542912, -- TrollMale_CantInvite
}

local systemMessages = {
	ERR_INVITE_PLAYER_S,
	ERR_JOINED_GROUP_S,
	ERR_DECLINE_GROUP_S,
	ERR_GROUP_DISBANDED,
	ERR_LEFT_GROUP_S,
	ERR_LEFT_GROUP_YOU,
	ERR_DUNGEON_DIFFICULTY_CHANGED_S,
	ERR_ALREADY_IN_GROUP_S,
	ERR_GROUP_FULL,
	ERR_NOT_IN_GROUP,
	ERR_SET_LOOT_FREEFORALL,
	ERR_SET_LOOT_GROUP,
	ERR_SET_LOOT_ROUNDROBIN,
	ERR_SET_LOOT_NBG,
	ERR_SET_LOOT_THRESHOLD_S,
}

-- Errors the game prints when an invite or an addon message targets a player who is no longer online
local notFoundMessages = {
	ERR_BAD_PLAYER_NAME_S,
	ERR_CHAT_PLAYER_NOT_FOUND_S,
}

-- Layers are sometimes segmented by different areas, this table determines the segments to look for (values should be a name that can be returned by C_Map.GetMapInfo()).
addonTable.layerSegments = {
	["AZ"] = "Azeroth",
	["OL"] = "Outland",
}

-- Zone names can be localized in the game client, so sometimes we need to match against their mapID instead of name
addonTable.layerSegmentMapIDs = {
	["AZ"] = 947,
	["OL"] = 1945,
}

-- Some zones are not in the same layer segment as the rest of their continent (e.g. they are technically in Azeroth, but part of the Outland layer segment).
-- Since the regular checks won't work for them, we need to override them to ensure players in those zones get invited correctly.
addonTable.layerSegmentOverrides = {
	[1941] = "OL", -- Eversong Woods, Eastern Kingdoms
	[1942] = "OL", -- Ghostlands, Eastern Kingdoms
	[1943] = "OL", -- Azuremyst Isle, Kalimdor
	[1947] = "OL", -- The Exodar, Kalimdor
	[1950] = "OL", -- Bloodmyst Isle, Kalimdor
	[1954] = "OL", -- Silvermoon City, Eastern Kingdoms
	[1957] = "OL", -- Isle of Quel'Danas, Eastern Kingdoms
}

-- The Undercity courtyard can be its own orphan world-map row (Ruins of Lordaeron). Its chain can
-- stop before Azeroth, and some clients ship the row without the parent map it points at.
addonTable.layerSegmentOverrides[908] = "AZ"

-- Forever's starter islands are separate instance maps directly under Azeroth (947), so players there
-- cannot share a layer with the continents (map IDs from Questie docs/forever-development.md).
if compat.isForever then
	addonTable.layerSegments["ZI"] = "Zephras Isle"
	addonTable.layerSegments["DI"] = "Darkspear Islands"
	addonTable.layerSegmentOverrides[2521] = "ZI"
	addonTable.layerSegmentOverrides[2524] = "DI"
	-- Zephras Isle also has a second, parentless world-map row for the same zone.
	addonTable.layerSegmentOverrides[2665] = "ZI"
end

-- Determine in which layer segment the given unitID is. Defaults to the player if no unitID is given.
-- This is necessary for the addon to work correctly in different segments (e.g. Azeroth vs Outland), as layers are specific to them.
---@return string|nil segment
---@return number|nil mapID The best map for the unit, returned even when no segment matched.
function AutoLayer:GetLayerSegment(unitID)
	unitID = unitID or "player"
	self:DebugPrint("Determining layer segment for", unitID, "(", UnitName(unitID), ")")
	local mapID = C_Map.GetBestMapForUnit(unitID)
	if not mapID then return nil end

	local segment = util.ResolveLayerSegment(
		mapID,
		C_Map.GetMapInfo,
		addonTable.layerSegmentMapIDs,
		addonTable.layerSegmentOverrides
	)
	if segment then
		self:DebugPrint(UnitName(unitID), "is in segment:", addonTable.layerSegments[segment] or segment, "( mapID", mapID, ")")
		return segment, mapID
	end

	if unitID == "player" and not IsActiveBattlefieldArena() and not self:IsInMaplessInstance() then
		-- Arenas and instances that lack a UiMap get no segment. Otherwise this is probably a new zone.
		local mapInfo = C_Map.GetMapInfo(mapID)
		self:DebugPrint("Layer segment could not be determined for mapID", mapID, "map name", mapInfo and mapInfo.name or "unknown")
	end

	return nil, mapID
end

-- Determine if the party leader is in the same layer segment as the player, if layer segments are enabled.
function AutoLayer:CompareLayerSegments()
	if not self.db.profile.layerSegments then
		return nil, nil -- Layer segments not enabled, so we don't care about the party leader's segment
	end

	if GetNumGroupMembers() == 0 then
		self:DebugPrint("Player is not in a party, so no party leader segment to compare to")
		return nil, nil
	end

	-- Works for parties ("partyN") and raids ("raidN")
	local partyLeaderUnit = util.FindGroupLeaderUnit()
	if not partyLeaderUnit then
		self:DebugPrint("Could not find party leader unitID")
		return nil, nil
	end
	self:DebugPrint("Found party leader unitID:", partyLeaderUnit)

	local playerSegment = addonTable.currentLayerSegment or self:GetLayerSegment("player")
	local leaderSegment = self:GetLayerSegment(partyLeaderUnit)

	if not playerSegment or not leaderSegment then
		self:DebugPrint("Could not determine layer segment for player or party leader, cannot compare segments")
		return nil, nil
	end

	self:DebugPrint("Player segment:", playerSegment, "Leader segment:", leaderSegment)

	return playerSegment, leaderSegment
end

if addonTable.flavor == "bcc" then
	local function parseVersion(version)
		local major, minor, patch = tostring(version or ""):match("^(%d+)%.(%d+)%.(%d+)$")
		if not major then
			return nil
		end
		return tonumber(major), tonumber(minor), tonumber(patch)
	end

	function AutoLayer:GetLayerZone(unitID)
		return tostring(C_Map.GetBestMapForUnit(unitID or "player") or 0)
	end

	function AutoLayer:GetLayerZoneName(scopeID)
		local mapInfo = C_Map.GetMapInfo(tonumber(scopeID))
		if mapInfo and mapInfo.name then
			return mapInfo.name
		end
		return "Unknown zone (" .. tostring(scopeID) .. ")"
	end

	function AutoLayer:CompareLayerZones()
		if not self.db.profile.layerSegments then
			return nil, nil
		end

		if GetNumGroupMembers() == 0 then
			return nil, nil
		end

		local leaderUnit = util.FindGroupLeaderUnit()
		if not leaderUnit then
			return nil, nil
		end

		local playerZone = addonTable.currentLayerZone or self:GetLayerZone("player")
		local leaderZone = self:GetLayerZone(leaderUnit)
		if playerZone == "0" or leaderZone == "0" then
			return nil, nil
		end

		return playerZone, leaderZone
	end

	function AutoLayer:BuildLayerRequestHeader(scopeID)
		local major, minor, patch = parseVersion(addonVersion)
		if not major then
			major, minor, patch = parseVersion(ADDON_VERSION_FALLBACK)
		end
		return string.format("<AL2V%d_%d_%dZ%s>", major, minor, patch, tostring(scopeID or 0))
	end

	function AutoLayer:ParseLayerRequestHeader(message)
		local protocolVersion, major, minor, patch, scopeID, body = tostring(message or ""):match(
			"^<AL(%d+)V(%d+)_(%d+)_(%d+)Z(%d+)>(.*)$"
		)
		if not protocolVersion or tonumber(protocolVersion) ~= 2 then
			return nil
		end

		local metadata = {
			protocolVersion = tonumber(protocolVersion),
			addonVersion = string.format("%d.%d.%d", tonumber(major), tonumber(minor), tonumber(patch)),
			scopeID = tostring(tonumber(scopeID)),
		}
		local requestBody = body:gsub("^%s+", "")
		return metadata, requestBody
	end

	function AutoLayer:IsVersionOlder(left, right)
		local leftMajor, leftMinor, leftPatch = parseVersion(left)
		local rightMajor, rightMinor, rightPatch = parseVersion(right)
		if not leftMajor then
			return true
		end
		if not rightMajor then
			return false
		end
		if leftMajor ~= rightMajor then
			return leftMajor < rightMajor
		end
		if leftMinor ~= rightMinor then
			return leftMinor < rightMinor
		end
		return leftPatch < rightPatch
	end

	function AutoLayer:SendLayerCompatibilityWhisper(target)
		if target and target ~= "" then
			CTL:SendChatMessage(
				"NORMAL",
				target,
				"[AutoLayer] Please update to AutoLayer 1.9.5 or later to use zone-aware layer invites.",
				"WHISPER",
				nil,
				target
			)
		end
	end
end

function AutoLayer:IsInMaplessInstance()
	-- Determine if the player is in a "mapless" instance, which is an instance that does not return a mapID
	local maplessInstances = {
		369, -- Deeprun Tram
		449, -- Champions' Hall in Stormwind (Alliance PVP Barracks)
		450, -- Hall of Legends in Orgrimmar (Horde PVP Barracks)
	}

	local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	self:DebugPrint("Current instance ID:", instanceID)

	for _, id in ipairs(maplessInstances) do
		if instanceID == id then
			self:DebugPrint("Player is in a mapless instance with ID:", instanceID)
			return true
		end
	end

	return false
end

local function matchesAnySystemMessage(msg)
	for _, systemMessage in ipairs(systemMessages) do
		-- First escape all Lua pattern special characters
		local pattern = systemMessage:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
		-- Now replace the escaped %%s with capture pattern
		pattern = pattern:gsub("%%%%s", "(.+)")
		if msg:match(pattern) then
			return true
		end
	end
	return false
end

-- Only for players AutoLayer just invited for a layer, so a name mistyped in a manual invite or whisper is still reported
local function matchesNotFoundForLayerRequest(msg)
	for _, notFoundMessage in ipairs(notFoundMessages) do
		local name = msg:match("^" .. util.EscapePattern(notFoundMessage):gsub("%%%%s", "(.+)") .. "$")
		if name and AutoLayer:IsRecentLayerRequest(name) then
			return true
		end
	end
	return false
end

local function formatOnOff(value)
	return value and "on" or "off"
end

local function getCurrentLayerDisplay()
	if not addonTable.hasNWB then
		return "unknown"
	end

	local currentLayer = AutoLayer:getCurrentLayer()
	if not currentLayer or currentLayer <= 0 then
		return "unknown"
	end

	return tostring(currentLayer)
end

local function getCurrentSegmentDisplay()
	if not AutoLayer.db.profile.layerSegments then
		return "off"
	end

	if addonTable.flavor == "bcc" then
		local currentZone = addonTable.currentLayerZone or AutoLayer:GetLayerZone()
		if not currentZone or currentZone == "0" then
			return "unknown"
		end
		return AutoLayer:GetLayerZoneName(currentZone)
	end

	local currentSegment = addonTable.currentLayerSegment or AutoLayer:GetLayerSegment()
	if not currentSegment then
		return "unknown"
	end

	return addonTable.layerSegments[currentSegment] or currentSegment
end

local function getInviteAuthorityDisplay()
	if not IsInGroup() and not IsInRaid() then
		return "leader"
	end

	if UnitIsGroupLeader("player") then
		return "leader"
	end

	if IsInRaid() and UnitIsGroupAssistant("player") then
		return "raid assist"
	end

	return "no invite permissions"
end

function AutoLayer:SlashCommandStatus()
	local enabledState = self.db.profile.enabled and "enabled" or "disabled"
	local activeChannel = addonTable.activeLayerChannel or "unavailable"
	local primaryChannel = self:GetPrimaryLayerChannel() or "layer"

	self:Print("Status:")
	self:Print("State: " .. enabledState)
	self:Print("Current layer: " .. getCurrentLayerDisplay())
	self:Print((addonTable.flavor == "bcc" and "Layer zone: " or "Layer segment: ") .. getCurrentSegmentDisplay())
	self:Print("Invite authority: " .. getInviteAuthorityDisplay())
	self:Print("Layer channel: " .. activeChannel)

	if addonTable.activeLayerChannel and addonTable.activeLayerChannel ~= primaryChannel then
		self:Print("Channel mode: fallback from " .. primaryChannel)
	end

	self:Print("Pending invites: " .. self:GetPendingInviteCount())
	self:Print("Queued requests: " .. #addonTable.send_queue)
	self:Print(
		"Flags: guild only "
			.. formatOnOff(self.db.profile.guildOnly)
			.. ", mute sounds "
			.. formatOnOff(self.db.profile.mutesounds)
	)
	self:Print(
		"Auto-kick: "
			.. formatOnOff(self.db.profile.autokick)
			.. " (one offline/oldest candidate queued when the group is full)"
	)
end

function AutoLayer:SlashCommandStats()
	local stats = self:GetRuntimeStats()

	self:Print("Stats:")
	self:Print("Lifetime layered: " .. self.db.profile.layered)
	self:Print("Session matched requests: " .. stats.matchedRequests)
	self:Print("Session invites sent: " .. stats.invitesSent)
	self:Print("Session joins completed: " .. stats.joinsCompleted)
	self:Print("Session declines: " .. stats.declinesReceived)
	self:Print("Session invite timeouts: " .. stats.inviteTimeouts)
	self:Print("Session auto-kicks: " .. stats.autoKicksExecuted)
end

---@diagnostic disable-next-line: duplicate-set-field
function AutoLayer:OnInitialize()
	LibStub("AceConfig-3.0"):RegisterOptionsTable("AutoLayer", addonTable.options)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("AutoLayer")
	self.db = LibStub("AceDB-3.0"):New("AutoLayerDB", addonTable.defaults)
	self:RunMigrations()

	-- Modern API for adding options
	local AceConfigDialog = LibStub("AceConfigDialog-3.0")
	AceConfigDialog:SetDefaultSize("AutoLayer", 600, 500)

	-- Register slash commands
	self:RegisterChatCommand("autolayer", function(input)
		if input == "" then
			AceConfigDialog:Open("AutoLayer")
		else
			AutoLayer:SlashCommand(input)
		end
	end)

	if self.db.profile.layerSegments then
		if addonTable.flavor == "bcc" then
			addonTable.currentLayerZone = self:GetLayerZone()
		else
			addonTable.currentLayerSegment = self:GetLayerSegment()
		end
	elseif addonTable.flavor == "bcc" then
		addonTable.currentLayerZone = self:GetLayerZone()
	end

	---@diagnostic disable-next-line: missing-fields
	local bunnyLDB = LibStub("LibDataBroker-1.1"):NewDataObject("AutoLayer", {
		type = "data source",
		text = "AutoLayer",
		icon = addonTable.icons.enabled,

		-- listen for right click
		OnClick = function(_, button)
			if button == "LeftButton" then
				AutoLayer:Toggle()
			elseif button == "RightButton" then
				AutoLayer:HopGUI()
			end
		end,

		OnTooltipShow = function(tooltip)
			tooltip:AddLine("AutoLayer")
			tooltip:AddLine("Left-click to toggle AutoLayer")
			tooltip:AddLine("Right-click to hop layers")
			tooltip:AddLine("Layered " .. self.db.profile.layered .. " times")

			if addonTable.hasNWB then
				local currentLayer = AutoLayer:getCurrentLayer()
				if currentLayer == 0 then
					tooltip:AddLine("Current layer: unknown, target an NPC")
				else
					tooltip:AddLine("Current layer: " .. currentLayer)
				end
			end

			if addonTable.flavor == "bcc" then
				local currentZone = addonTable.currentLayerZone
				if currentZone and currentZone ~= "0" then
					tooltip:AddLine("Layer zone: " .. AutoLayer:GetLayerZoneName(currentZone))
				end
			elseif addonTable.currentLayerSegment then
				tooltip:AddLine("Layer segment: " .. addonTable.layerSegments[addonTable.currentLayerSegment])
			end
		end,
	})

	addonTable.bunnyLDB = bunnyLDB
	minimap_icon:Register("AutoLayer", bunnyLDB, self.db.profile.minimap)

	self:SyncRuntimeState()
	self:StartSendPump()
end

function AutoLayer:MuteAnnoyingSounds()
	if not MuteSoundFile then return end -- missing on Forever
	for _, soundFileId in ipairs(annoyingSounds) do
		MuteSoundFile(soundFileId)
	end
end

function AutoLayer:UnmuteAnnoyingSounds()
	if not UnmuteSoundFile then return end -- missing on Forever
	for _, soundFileId in ipairs(annoyingSounds) do
		UnmuteSoundFile(soundFileId)
	end
end

--For hiding outgoing automatic whispers
local whisperInformFilterActive = false

local function whisperInformFilter(_, _, msg, author, ...)
	local filtered = string.sub(msg, 1, 11) == "[AutoLayer]"
	return filtered, msg, author, ...
end

function AutoLayer:filterChatEventAutoLayerWhisperMessages()
	if whisperInformFilterActive then
		return
	end
	whisperInformFilterActive = true
	ChatFrameAddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", whisperInformFilter)
end

function AutoLayer:unfilterChatEventAutoLayerWhisperMessages()
	if not whisperInformFilterActive then
		return
	end
	whisperInformFilterActive = false
	ChatFrameRemoveMessageEventFilter("CHAT_MSG_WHISPER_INFORM", whisperInformFilter)
end

--For hiding group system messages
local systemGroupFilterActive = false

local function systemFilter(_, _, msg, author, ...)
	local filtered = AutoLayer:GetEnabled() and (matchesAnySystemMessage(msg) or matchesNotFoundForLayerRequest(msg))
	return filtered, msg, author, ...
end

function AutoLayer:filterChatEventSystemGroupMessages()
	if systemGroupFilterActive then
		return
	end
	systemGroupFilterActive = true
	ChatFrameAddMessageEventFilter("CHAT_MSG_SYSTEM", systemFilter)
end

function AutoLayer:unfilterChatEventSystemGroupMessages()
	if not systemGroupFilterActive then
		return
	end
	systemGroupFilterActive = false
	ChatFrameRemoveMessageEventFilter("CHAT_MSG_SYSTEM", systemFilter)
end

function AutoLayer:SlashCommand(input)
	local command = self:GetArgs(input, 1)

	if command == "help" then
		return AutoLayer:SlashCommandHelp()
	elseif command == "req" then
		return AutoLayer:SlashCommandRequest(input)
	elseif command == "status" then
		return AutoLayer:SlashCommandStatus()
	elseif command == "stats" then
		return AutoLayer:SlashCommandStats()
	else
		return self:Print("Unknown command " .. command .. ". Type /autolayer help for a list of commands.")
	end
end

function AutoLayer:SlashCommandHelp()
	self:Print("AutoLayer Slash Commands:")
	self:Print("/autolayer - Open the AutoLayer settings GUI.")
	self:Print("/autolayer status - Show runtime addon status and queue state.")
	self:Print("/autolayer stats - Show lifetime and session activity counters.")
	self:Print("/autolayer req [layers] - Send a layer hop request via chat. '[layers]' is a comma-separated list of layer numbers to request. If omitted, requests all layers except the current one.")
end

function AutoLayer:DebugPrint(...)
	if self.db.profile.debug then
		self:Print(...)
	end
end
