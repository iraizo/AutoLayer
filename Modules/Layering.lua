local addonName, addonTable = ...
local CTL = _G.ChatThrottleLib
local compat = addonTable.compat
local util = addonTable.util

local formatWhisperMessage = util.FormatWhisperMessage
local removeRealmName = util.RemoveRealmName
local normalizeCharacterName = util.NormalizeCharacterName

local JoinLayerChannel

local playersInvitedRecently = {}
local pendingPlayerInvites = {}
local groupInviteTimes = {}
local recentLayerRequests = {}
local kicked_player_queue = {}
local queuedKickNames = {}
local compatibilityNoticeExpiry = {}
local pendingCompatibilityNotices = {}
local nextCompatibilityNoticeToken = 0
local zoneMismatchNoticeExpiry = {}
local runtimeStats = {
	matchedRequests = 0,
	invitesSent = 0,
	joinsCompleted = 0,
	declinesReceived = 0,
	inviteTimeouts = 0,
	autoKicksExecuted = 0,
}

-- Dynamic channel name system with date-based hashing
local failedChannels = {} -- Track channels that failed to join (no retries)
addonTable.activeLayerChannel = nil
addonTable.hasNWB = false

-- Channel list - will be populated after all addons load
local LAYER_CHANNELS = {}

-- Generate dynamic channel names based on server date and realm name
local function GenerateLayerChannels()
	local channels = {}

	-- Always include the static "layer" channel first as primary/fallback
	table.insert(channels, "layer")

    local t = C_DateAndTime.GetCurrentCalendarTime()
	local realmName = GetRealmName() or "Unknown"

	-- Need LibDeflate for hashing
	local LibDeflate = addonTable.LibDeflate or LibStub and LibStub("LibDeflate")
	if not LibDeflate then
		AutoLayer:Print("Error: LibDeflate not found, using fallback channel names")
		return {"layer", "layer2", "layer3"}
	end

	-- Three date formats for three different channel names
	local dateFormats = {
		string.format("%02d-%02d-%04d", t.monthDay, t.month, t.year),  -- dd-mm-yyyy
		string.format("%04d-%02d-%02d", t.year, t.month, t.monthDay),  -- yyyy-mm-dd
		string.format("%02d-%02d-%04d", t.month, t.monthDay, t.year),  -- mm-dd-yyyy
	}

	for i, dateStr in ipairs(dateFormats) do
		local saltedInput = realmName .. "-" .. dateStr
		local hash = LibDeflate:Adler32(saltedInput)
		-- Convert hash to hex string and take first 8 characters
		local hashStr = string.format("%08x", hash)
		table.insert(channels, "layer" .. hashStr)
	end

	return channels
end

-- Leave all old layer_* channels that are not in today's channel list
local function CleanupOldLayerChannels()
	-- Build a lookup table for today's valid channels
	local validChannels = {}
	for _, channelName in ipairs(LAYER_CHANNELS) do
		validChannels[channelName] = true
	end

	AutoLayer:DebugPrint("CleanupOldLayerChannels: Checking for old channels to leave...")

	-- Check all joined channels and leave old layer_* ones
	for i = 1, Constants.ChatFrameConstants.MaxChatChannels do
		local _, channelName = GetChannelName(i)
		if channelName then
			AutoLayer:DebugPrint("  Found channel: " .. channelName)
		end
		if channelName and string.match(channelName, "^layer%x%x%x%x%x%x%x%x$") then
			if not validChannels[channelName] then
				AutoLayer:DebugPrint("  LEAVING old layer channel: " .. channelName)
				LeaveChannelByName(channelName)
			else
				AutoLayer:DebugPrint("  KEEPING valid layer channel: " .. channelName)
			end
		end
	end
end

-- Fix layer channels that displaced default Blizzard channels (General, Trade, etc.)
-- WoW's chat cache can rejoin layer channels before defaults on next login,
-- causing /1 to land in a layer channel instead of General.
local MAX_DEFAULT_CHANNEL_SLOT = 5
local function FixMisplacedChannels()
	local channelsLeft = false

	for _, channelName in ipairs(LAYER_CHANNELS) do
		local slot = GetChannelName(channelName)
		if slot > 0 and slot <= MAX_DEFAULT_CHANNEL_SLOT then
			AutoLayer:DebugPrint("FixMisplacedChannels: Layer channel '" .. channelName .. "' in slot " .. slot .. " - leaving to free default slot")
			LeaveChannelByName(channelName)
			channelsLeft = true
		end
	end

	if channelsLeft then
		AutoLayer:DebugPrint("FixMisplacedChannels: Scheduling rejoin in 30 seconds for default channels to establish")
		C_Timer.After(30, JoinLayerChannel)
	end
end

--- @return boolean is_logging_out Whether the current player is logging out
local function isPlayerLoggingOut()
	local isLoggingOut = false
	StaticPopup_ForEachShownDialog(function(frame)
		if frame and frame:IsShown() and frame.which == "CAMP" then
			isLoggingOut = true
			return true
		end
	end)
	return isLoggingOut
end

function AutoLayer:pruneCache()
	local currentTime = time()
	-- Iterate backwards: table.remove shifts every later entry, so a forward loop skips entries.
	for i = #playersInvitedRecently, 1, -1 do
		local cachedPlayer = playersInvitedRecently[i]
		-- delete players that are over 5 minutes old
		if cachedPlayer.time + 300 < currentTime then
			self:DebugPrint("Removing", cachedPlayer.name, "from players invited recently")
			table.remove(playersInvitedRecently, i)
		end
	end
	for i = #recentLayerRequests, 1, -1 do
		local cachedPlayer = recentLayerRequests[i]
		-- delete players that are over 1 minute old
		if cachedPlayer.time + 60 < currentTime then
			self:DebugPrint("Removing", cachedPlayer.name, "from recent layer requests")
			table.remove(recentLayerRequests, i)
		end
	end
	for i = #pendingPlayerInvites, 1, -1 do
		local cachedPlayer = pendingPlayerInvites[i]
		-- delete pending invites for players that are over 3 minutes old
		-- The per-invite timer counts the timeout, so it is not counted again here.
		if cachedPlayer.time + 180 < currentTime then
			self:DebugPrint("Removing", cachedPlayer.name, "from pending player invites")
			table.remove(pendingPlayerInvites, i)
		end
	end
end

function AutoLayer:GetRuntimeStats()
	return runtimeStats
end

function AutoLayer:GetPendingInviteCount()
	return #pendingPlayerInvites
end

function AutoLayer:GetPrimaryLayerChannel()
	return LAYER_CHANNELS[1]
end

local function queueCompatibilityNoticeForInvite(target)
	local normalized = normalizeCharacterName(target)
	if normalized ~= "" then
		nextCompatibilityNoticeToken = nextCompatibilityNoticeToken + 1
		local token = nextCompatibilityNoticeToken
		pendingCompatibilityNotices[normalized] = token
		C_Timer.After(180, function()
			if pendingCompatibilityNotices[normalized] == token then
				pendingCompatibilityNotices[normalized] = nil
			end
		end)
	end
end

local function sendCompatibilityNoticeOnce(target)
	local normalized = normalizeCharacterName(target)
	if normalized == "" then
		return
	end

	local currentTime = time()
	if not compatibilityNoticeExpiry[normalized] or compatibilityNoticeExpiry[normalized] <= currentTime then
		compatibilityNoticeExpiry[normalized] = currentTime + 300
		AutoLayer:SendLayerCompatibilityWhisper(target)
	end
end

--- Consumes the pending compatibility notice for the given character, if one was queued for
--- their invite, and delivers it through sendCompatibilityNoticeOnce (which applies its own
--- throttle). Shared by accepted party (ERR_JOINED_GROUP_S) and raid (ERR_RAID_MEMBER_ADDED_S)
--- joins so the notice is delivered when either invite type is accepted.
--- @param characterName string The character name as it appeared in the join system message.
local function deliverPendingCompatibilityNotice(characterName)
	local normalizedPlayerName = normalizeCharacterName(characterName)
	local compatibilityNoticeToken = pendingCompatibilityNotices[normalizedPlayerName]
	pendingCompatibilityNotices[normalizedPlayerName] = nil
	if compatibilityNoticeToken then
		sendCompatibilityNoticeOnce(characterName)
	end
end

local function sendZoneMismatchNoticeOnce(target)
	if not AutoLayer.db.profile.zoneMismatchWhisper then
		return
	end

	local normalized = normalizeCharacterName(target)

	if normalized == "" then
		return
	end

	local currentTime = time()
	if not zoneMismatchNoticeExpiry[normalized] or zoneMismatchNoticeExpiry[normalized] <= currentTime then
		zoneMismatchNoticeExpiry[normalized] = currentTime + 300
		CTL:SendChatMessage(
			"NORMAL",
			target,
			"[AutoLayer] Layer invites only work within the same zone; no invite was sent.",
			"WHISPER",
			nil,
			target
		)
	end
end

--- Detects NovaWorldBuffs. NWB <= 3.41 registers itself with AceAddon, while NWB 3.48 keeps
--- its addon table local and only publishes NWB_CurrentLayer, NWB_CurrentLayerZoneID and the
--- NWB_LayerUpdated() hook. addonTable.NWB therefore stays nil on modern NWB.
function AutoLayer:addNWBToAddonTable()
	addonTable.NWB = LibStub("AceAddon-3.0"):GetAddon("NovaWorldBuffs", true)
	local loaded = false
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		loaded = C_AddOns.IsAddOnLoaded("NovaWorldBuffs")
	elseif IsAddOnLoaded then
		loaded = IsAddOnLoaded("NovaWorldBuffs")
	end
	addonTable.hasNWB = addonTable.NWB ~= nil or NWB_CurrentLayer ~= nil or loaded == true
end

--- Returns the live NWB layer table. NWB 3.48 does not expose its addon table, but the live
--- table still lives in the NWBdatabase saved variable:
--- NWBdatabase.global[realm][faction].layers.
--- @return table|nil
local function getNWBLayerTable()
	local nwb = addonTable.NWB
	if nwb and nwb.data and type(nwb.data.layers) == "table" then
		return nwb.data.layers
	end

	return util.GetNWBLayerTable(_G.NWBdatabase, GetRealmName(), UnitFactionGroup("player"))
end

--- Lists the layer numbers NovaWorldBuffs currently tracks for the player's world.
--- @return table<number>
function AutoLayer:GetAvailableLayers()
	if not addonTable.hasNWB then
		return {}
	end

	local layers = getNWBLayerTable()
	if not layers then
		return {}
	end

	local segment = addonTable.currentLayerSegment or AutoLayer:GetLayerSegment()
	local storageID = util.GetNWBStorageID(layers, tonumber(NWB_CurrentLayerZoneID), segment)
	return util.GetNWBLayerNumbers(layers, storageID)
end

--- Finds the current layer from NovaWorldBuffs
--- @return number? layer The current layer number, or nil if the layer is unknown.
function AutoLayer:getCurrentLayer()
	if not addonTable.hasNWB then
		return
	end -- No NWB, nothing to do here

	local currentLayer = tonumber(NWB_CurrentLayer)
	if not currentLayer or currentLayer <= 0 then
		return 0
	end
	return currentLayer
end

-- Autoexec?
C_Timer.After(0.1, function()
	AutoLayer:addNWBToAddonTable()
	if not addonTable.hasNWB then
		AutoLayer:Print("Could not find NovaWorldBuffs, disabling NovaWorldBuffs integration")
	end

	-- Generate dynamic channel names now that LibDeflate is loaded
	local generatedChannels = GenerateLayerChannels()
	for i, ch in ipairs(generatedChannels) do
		LAYER_CHANNELS[i] = ch
	end

	-- Debug: Show generated channel names
	AutoLayer:DebugPrint("Dynamic layer channels for today:")
	for i, channelName in ipairs(LAYER_CHANNELS) do
		AutoLayer:DebugPrint("  " .. i .. ": " .. channelName)
	end
	-- Cleanup old layer channels from previous days
	CleanupOldLayerChannels()
	FixMisplacedChannels()
end)

function AutoLayer:SelectKickCandidate()
	local playerName = normalizeCharacterName(UnitName("player"))
	local oldestName
	local oldestTime
	local oldestIndex

	for i = 1, GetNumGroupMembers() do
		local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
		local normalizedName = name and normalizeCharacterName(name)

		if name and normalizedName ~= playerName then
			if online == false then
				return name
			end

			local inviteTime = groupInviteTimes[normalizedName]
			if not oldestName
				or (inviteTime and not oldestTime)
				or (inviteTime and oldestTime and inviteTime < oldestTime)
				or ((not inviteTime and not oldestTime) or (inviteTime and oldestTime and inviteTime == oldestTime))
					and i < oldestIndex
			then
				oldestName = name
				oldestTime = inviteTime
				oldestIndex = i
			end
		end
	end

	return oldestName
end

local function queueKickCandidate(name)
	local normalizedName = normalizeCharacterName(name)
	if normalizedName == "" or queuedKickNames[normalizedName] then
		return
	end

	queuedKickNames[normalizedName] = true
	groupInviteTimes[normalizedName] = nil
	table.insert(kicked_player_queue, name)
end

local function clearGroupInviteTimes()
	for name in pairs(groupInviteTimes) do
		groupInviteTimes[name] = nil
	end
end

---@diagnostic disable-next-line:inject-field
function AutoLayer:ProcessMessage(
	event,
	msg,
	name,
	languageName,
	channelName,
	playerName2,
	specialFlags,
	zoneChannelID,
	channelIndex,
	channelBaseName
)
	if not compat.CanAccess(msg, name, channelBaseName) then
		self:DebugPrint("Chat messaging lockdown: ignoring chat message")
		return
	end

	if not self.db.profile.enabled or isPlayerLoggingOut() then
		return
	end

	if event ~= "CHAT_MSG_GUILD" and self.db.profile.guildOnly then
		return
	end

	-- Whispers and guild messages carry no channel name; channel filtering must not see nil.
	channelBaseName = channelBaseName or ""

	-- Ignore messages that start with configured prefixes (e.g. addon announcements like "[NWB]")
	local prefixes = self:ParseIgnorePrefixes()
	if #prefixes > 0 and msg then
		local cleanLowerMsg = string.lower(util.StripColorCodes(msg))
		for _, prefix in ipairs(prefixes) do
			if cleanLowerMsg:sub(1, #prefix) == prefix then
				return
			end
		end
	end

	local bccMetadata
	local bccRequiresCompatibilityHandling = false
	local bccShouldNotifyCompatibility = false

	if addonTable.flavor == "bcc" then
		local bccBody
		bccMetadata, bccBody = self:ParseLayerRequestHeader(msg)
		if not bccMetadata then
			bccRequiresCompatibilityHandling = true
			local legacyPrefix = msg:match("^<(%w+)> ")
			if legacyPrefix then
				msg = msg:gsub("^<" .. legacyPrefix .. "> ", "")
			end
			bccShouldNotifyCompatibility = string.match(string.lower(msg), "^inv%s+layer%f[%W]") ~= nil
		else
			msg = bccBody
			bccRequiresCompatibilityHandling = self:IsVersionOlder(bccMetadata.addonVersion, "1.9.5")
			bccShouldNotifyCompatibility = bccRequiresCompatibilityHandling
		end
	else
		-- Check if the message has a layer segment prefix. If it does, it should match our layer segment.
		local segmentPrefix = msg:match("^<(%w+)> ")

		-- Remove the matched prefix from msg, since it could inadvertently trigger things like blacklist or invert keywords
		if segmentPrefix then
			msg = msg:gsub("^<" .. segmentPrefix .. "> ", "")
		end

		if self.db.profile.layerSegments and addonTable.currentLayerSegment and segmentPrefix then
			if segmentPrefix ~= addonTable.currentLayerSegment then
				self:DebugPrint("Message has segment prefix " .. segmentPrefix .. " but we are in segment '" .. addonTable.currentLayerSegment .. "', ignoring")
				return
			end

			self:DebugPrint("Message segment prefix " .. segmentPrefix .. " matches our segment")
		end
	end

	local name_without_realm = removeRealmName(name)
	if name_without_realm == UnitName("player") then
		return
	end

	local lowerMsg = string.lower(msg)

	local triggerMatch = util.FindMatchingTrigger(lowerMsg, self:ParseTriggers())
	if not triggerMatch then
		return
	end

	local blacklistMatch = util.FindMatchingWord(lowerMsg, self:ParseBlacklist())
	if blacklistMatch then
		self:DebugPrint(
			"Matched blacklist: '",
			blacklistMatch,
			"' in message: '",
			msg,
			"' from player '",
			name_without_realm,
			"'"
		)
		return
	end

	local channelFiltering = self.db.profile.channelFiltering
	if channelFiltering ~= "none" then
		local channelMatch = util.FindMatchingChannel(string.lower(channelBaseName), self:ParseFilteredChannels())
		if channelFiltering == "inclusive" and not channelMatch then
			self:DebugPrint(
				"Did not match an included channel. Request came from player: '",
				name,
				"' in channel: '",
				channelBaseName,
				"' but currently only allowing these channels: '",
				self:GetFilteredChannels(),
				"'"
			)
			return
		elseif channelFiltering == "exclusive" and channelMatch then
			self:DebugPrint(
				"Matched excluded request from player: '",
				name,
				"' in excluded channel: '",
				channelBaseName,
				"' from list of excluded channels: '",
				self:GetFilteredChannels(),
				"'"
			)
			return
		end
	end

	if addonTable.flavor == "bcc" then
		if bccRequiresCompatibilityHandling and self.db.profile.layerSegments then
			return
		end

		if bccMetadata and self.db.profile.layerSegments then
			local playerZone = addonTable.currentLayerZone or self:GetLayerZone()
			if playerZone ~= "0" and bccMetadata.scopeID ~= "0" and playerZone ~= bccMetadata.scopeID then
				sendZoneMismatchNoticeOnce(name)
				return
			end
		end
	end

	-- If we got this far, we have a valid match.
	self:DebugPrint(
		"Matched trigger: '",
		triggerMatch,
		"' in message: '",
		msg,
		"' from player '",
		name_without_realm,
		"' in channel: '",
		channelBaseName,
		"'"
	)

	-- Check if player has permission to invite (leader for party, leader or assist for raid)
	if (IsInGroup() or IsInRaid()) then
		local isLeader = UnitIsGroupLeader("player")
		local isRaidAssist = IsInRaid() and UnitIsGroupAssistant("player")
		local turnOffForAssist = self.db.profile.turnOffWhileRaidAssist and isRaidAssist
		
		if turnOffForAssist then
			self:DebugPrint("Ignoring request because we are raid assist and turnOffWhileRaidAssist is enabled!")
			return
		end
		
		if not isLeader and not isRaidAssist then
			self:DebugPrint("Ignoring request because we are not the group leader or raid assist!")
			return
		end
	end

	local currentLayer = AutoLayer:getCurrentLayer()
	local isHighPriorityRequest = (event == "CHAT_MSG_WHISPER")

	if string.find(lowerMsg, "%d+") then -- Uh oh, this player is picky and wants a specific layer!
		if not currentLayer or currentLayer <= 0 then
			self:DebugPrint(
				"Message requested a specific layer, but we don't know what layer we're in! NWB says: ",
				NWB_CurrentLayer
			)
			return
		end
		local requestedLayers = util.ParseLayers(lowerMsg)
		if next(requestedLayers) == nil then
			self:DebugPrint("Message requested a specific layer, but we couldn't parse the message successfully!")
			return
		end

		local requestIsInverted = util.FindMatchingWord(lowerMsg, self:ParseInvertKeywords())
		local currLayerMatchesRequest = util.IsNumberInList(currentLayer, requestedLayers)

		if requestIsInverted then
			self:DebugPrint("Message requested any layers except:", table.concat(requestedLayers, ", "))
		else
			self:DebugPrint("Message requested layers:", table.concat(requestedLayers, ", "))
		end

		if
			(requestIsInverted and currLayerMatchesRequest) or (not requestIsInverted and not currLayerMatchesRequest)
		then
			self:DebugPrint("Request not satisfied. We are in layer ", currentLayer)
			return
		end
	end
	--If we got this far, then the message is a valid layer request that we can fulfill.
	runtimeStats.matchedRequests = runtimeStats.matchedRequests + 1

	-- check if we've already invited this player in the last 5 minutes
	if not isHighPriorityRequest then
		AutoLayer:pruneCache()
		for _, cachedPlayer in ipairs(playersInvitedRecently) do
			if cachedPlayer.name == name_without_realm and cachedPlayer.time + 300 > time() then
				self:DebugPrint("Already invited", name, "in the last 5 minutes")
				return
			end
		end
	end

	local max_group_size = 4

	if IsInRaid() then
		max_group_size = 39
	end

	-- used to check if we should invite with or without realm name below
	-- due to the fact that era has mega servers (multiple realms in one server)
	-- where we have to invite with the realm name
	-- since those do not exist on anniversary servers and where HasActiveSeason() is true
	-- we can validate it like this for now.
	-- On Forever there is no season API, so the full name (with realm) is used.
	local isSeasonal = compat.IsSeasonal()
	local shouldNotifyCompatibilityOnInvite = addonTable.flavor == "bcc"
		and bccRequiresCompatibilityHandling
		and bccShouldNotifyCompatibility

	local function invitePlayer()
		if shouldNotifyCompatibilityOnInvite then
			queueCompatibilityNoticeForInvite(name)
		end
		if isSeasonal then
			C_PartyInfo.InviteUnit(name_without_realm)
		else
			C_PartyInfo.InviteUnit(name)
		end
	end

	---@diagnostic disable-next-line: undefined-global
	if (GetNumGroupMembers() + #pendingPlayerInvites) <= max_group_size then
		self:DebugPrint("Group has room (", GetNumGroupMembers(), "in group +", #pendingPlayerInvites, "pending invites). Inviting", name_without_realm, "to layer", currentLayer)
		if not isHighPriorityRequest and (not self.db.profile.inviteWhisper or not currentLayer or currentLayer <= 0) then
			self:DebugPrint(
				"Auto-whisper is turned off or we can't provide a helpful whisper, delaying our invite by 500 miliseconds"
			)
			C_Timer.After(0.5, invitePlayer)
		else
			invitePlayer()
		end
	else
		self:DebugPrint("Group is already full (", GetNumGroupMembers(), "in group +", #pendingPlayerInvites, "pending invites). Cannot invite", name_without_realm)
	end

	table.insert(recentLayerRequests, { name = name_without_realm, time = time() })
	self:DebugPrint("Added", name_without_realm, "to list of recent layer requests")

	-- Check if group is full
	if self.db.profile.autokick and GetNumGroupMembers() == max_group_size then
		local candidate = self:SelectKickCandidate()
		if candidate then
			self:DebugPrint("Group is full, queueing", candidate, "for manual kick")
			queueKickCandidate(candidate)
		end
		return
	end
end

---@diagnostic disable-next-line: inject-field
function AutoLayer:ProcessSystemMessages(_, SystemMessages)
	if not compat.CanAccess(SystemMessages) then
		return
	end
	if SystemMessages == ERR_GROUP_DISBANDED or SystemMessages == ERR_LEFT_GROUP_YOU then
		clearGroupInviteTimes()
	elseif SystemMessages:match("^" .. ERR_LEFT_GROUP_S:format("(.+)")) then
		clearGroupInviteTimes()
	end
	if not self.db.profile.enabled then
		return
	end

	local characterName = SystemMessages:match("^" .. ERR_JOINED_GROUP_S:format("(.+)"))
	-- X joins the party
	if characterName then
		local playerNameWithoutRealm = removeRealmName(characterName)
		self:DebugPrint("ERR_JOINED_GROUP_S", playerNameWithoutRealm, "found !")
		-- Do AutoLayer stuff only if they actually asked for a layer
		-- (this may be a normal player we're inviting for different reasons)
		for i, entry in ipairs(recentLayerRequests) do
			if entry.name == playerNameWithoutRealm then
				self.db.profile.layered = self.db.profile.layered + 1
				runtimeStats.joinsCompleted = runtimeStats.joinsCompleted + 1
				table.insert(playersInvitedRecently, { name = playerNameWithoutRealm, time = time() - 100 })
				break -- Found the player, no need to continue checking
			end
		end
		-- Player accepted invite, transfer its timestamp and remove it from pending invites.
		local inviteTimestamp = time()
		for i, entry in ipairs(pendingPlayerInvites) do
			if entry.name == playerNameWithoutRealm then
				inviteTimestamp = entry.time or inviteTimestamp
				self:DebugPrint("Removing ", playerNameWithoutRealm, " from pending invites, reason: accepted invite")
				table.remove(pendingPlayerInvites, i)
				break -- Found the player, no need to continue checking
			end
		end
		groupInviteTimes[normalizeCharacterName(playerNameWithoutRealm)] = inviteTimestamp
		deliverPendingCompatibilityNotice(characterName)
		-- Ensure group loot is set as desired
		if self.db.profile.overrideLootSettings and UnitIsGroupLeader("player") then
			local lootMethod, _, _ = C_PartyInfo.GetLootMethod()

			if lootMethod ~= self.db.profile.lootMethod then
				self:DebugPrint("Setting loot method to", self.db.profile.lootMethod)
				C_PartyInfo.SetLootMethod(self.db.profile.lootMethod)
			end

			if GetLootThreshold and SetLootThreshold then
				if self.db.profile.lootMethod == 3 and GetLootThreshold() ~= self.db.profile.lootThreshold then
					self:DebugPrint("Setting loot threshold to", self.db.profile.lootThreshold)
					SetLootThreshold(self.db.profile.lootThreshold)
				end
			end
		end
	end

	characterName = SystemMessages:match("^" .. ERR_RAID_MEMBER_ADDED_S:format("(.+)"))
	-- X joins the raid
	if characterName then
		local playerNameWithoutRealm = removeRealmName(characterName)
		self:DebugPrint("ERR_RAID_MEMBER_ADDED_S", playerNameWithoutRealm, "found !")
		deliverPendingCompatibilityNotice(characterName)
	end

	characterName = SystemMessages:match("^" .. ERR_DECLINE_GROUP_S:format("(.+)"))
	-- X declines your invite
	if characterName then
		local playerNameWithoutRealm = removeRealmName(characterName)
		self:DebugPrint("ERR_DECLINE_GROUP_S", playerNameWithoutRealm, "found !")
		runtimeStats.declinesReceived = runtimeStats.declinesReceived + 1
		table.insert(playersInvitedRecently, { name = playerNameWithoutRealm, time = time() }) --Extend this timer, they don't want in right now
		self:DebugPrint("Adding ", playerNameWithoutRealm, " to cache, reason: declined invite")

		-- Player declined invite, remove from pending invites
		for i, entry in ipairs(pendingPlayerInvites) do
			if entry.name == playerNameWithoutRealm then
				self:DebugPrint("Removing ", playerNameWithoutRealm, " from pending invites, reason: declined invite")
				table.remove(pendingPlayerInvites, i)
				break -- Found the player, no need to continue checking
			end
		end
		pendingCompatibilityNotices[normalizeCharacterName(playerNameWithoutRealm)] = nil
	end

	characterName = SystemMessages:match("^" .. ERR_INVITE_PLAYER_S:format("(.+)"))
	if characterName then
		local playerNameWithoutRealm = removeRealmName(characterName)
		self:DebugPrint("ERR_INVITE_PLAYER_S", playerNameWithoutRealm, "found !")
		runtimeStats.invitesSent = runtimeStats.invitesSent + 1

		-- Player was invited, add to pending invites
		table.insert(pendingPlayerInvites, { name = playerNameWithoutRealm, time = time() })
		self:DebugPrint("Adding ", playerNameWithoutRealm, " to pending invites")
		-- Set a timer for 3 minutes, if after that time they are still in pending invites, remove them and consider the invite timed out
		C_Timer.After(180, function()
			for i, entry in ipairs(pendingPlayerInvites) do
				if entry.name == playerNameWithoutRealm then
					self:DebugPrint("Removing ", playerNameWithoutRealm, " from pending invites, reason: invite timed out")
					runtimeStats.inviteTimeouts = runtimeStats.inviteTimeouts + 1
					table.remove(pendingPlayerInvites, i)
					break -- Found the player, no need to continue checking
				end
			end
		end)

		if self.db.profile.inviteWhisper then
			local currentLayer = AutoLayer:getCurrentLayer()

			-- I guess don't whisper people if we don't know what layer we're in?
			if currentLayer == nil or currentLayer <= 0 then
				self:DebugPrint("Not whispering since we don't know what layer we're in! (", currentLayer, ")")
				return
			end

			-- Don't whisper the player unless they specifically asked for a layer
			-- (this may be a normal player we're inviting for different reasons)
			local isPlayerInvited = false
			for i, entry in ipairs(recentLayerRequests) do
				if entry.name == playerNameWithoutRealm then
					isPlayerInvited = true
					break -- Found the player, no need to continue checking
				end
			end

			if not isPlayerInvited then
				return
			end

			-- Continue with the rest of the function if the player is in the list

			local finalMessage = "[AutoLayer] "
				.. formatWhisperMessage(self.db.profile.inviteWhisperTemplate, currentLayer)
			CTL:SendChatMessage("NORMAL", characterName, finalMessage, "WHISPER", nil, characterName)
		end

		if self.db.profile.inviteWhisperReminder then
			-- No string.format here: a "%" typed into the template must not throw.
			local finalMessage2 = "[AutoLayer] " .. self.db.profile.inviteWhisperTemplateReminder
			CTL:SendChatMessage("NORMAL", characterName, finalMessage2, "WHISPER", nil, characterName)
		end
	end
end

function AutoLayer:HandleAutoKick()
	if not self.db.profile.enabled then
		return
	end

	if self.db.profile.autokick and #kicked_player_queue > 0 then
		local name = table.remove(kicked_player_queue, 1)

		if name == nil then
			return
		end
		queuedKickNames[normalizeCharacterName(name)] = nil

		if not UnitInRaid(name) and not UnitInParty(name) then
			return
		end

		self:DebugPrint("Kicking ", name)
		runtimeStats.autoKicksExecuted = runtimeStats.autoKicksExecuted + 1
		C_PartyInfo.UninviteUnit(name)
	end
end

function AutoLayer:ProcessRosterUpdate()
	self:getCurrentLayer()
end

function AutoLayer:ProcessZoneChange()
	if addonTable.flavor == "bcc" then
		addonTable.currentLayerZone = self:GetLayerZone()
		self:DebugPrint("Current layer zone set to:", addonTable.currentLayerZone)
		return
	end

	if self.db.profile.layerSegments then
		local layer_segment, mapID = self:GetLayerSegment()

		if layer_segment then
			addonTable.currentLayerSegment = layer_segment
			self:DebugPrint("Current layer segment set to:", layer_segment)
		else
			addonTable.currentLayerSegment = nil
			-- Layers only exist in the open world. GetBestMapForUnit can briefly return no map
			-- while crossing zones or on a flight path, and instance/micro/orphan maps (e.g. the
			-- Ruins of Lordaeron orphan row) have no layer chain. Only report a real open-world
			-- map that we could not classify; anything else is an expected client state.
			local inInstance = select(2, IsInInstance()) ~= "none"
			local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
			local mapInfo = mapID and C_Map.GetMapInfo(mapID)
			if util.IsOpenWorldMapType(mapInfo and mapInfo.mapType) and not inInstance and not onTaxi and not self:IsInMaplessInstance() then
				self:Print("|cffff0000ERROR:|r Could not determine layer segment for current zone. This is a bug, please consider reporting it at https://github.com/iraizo/AutoLayer/issues ! Include details about which zone you are in.")
			end
		end
	end
end

function AutoLayer:ProcessGroupJoined()
	if addonTable.flavor == "bcc" then
		if not self.db.profile.layerSegments or UnitIsGroupLeader("player") then
			return
		end

		local pendingLayerHop = addonTable.pendingLayerHop
		if pendingLayerHop and pendingLayerHop.sentAt + 300 < time() then
			addonTable.pendingLayerHop = nil
			pendingLayerHop = nil
		end

		if not pendingLayerHop and not self.db.profile.showLayerWarning then
			return
		end

		self:DebugPrint("Group joined, comparing layer zones with leader...")
		C_Timer.After(2, function()
			local activePendingHop = pendingLayerHop and addonTable.pendingLayerHop == pendingLayerHop
			local playerZone, leaderZone = AutoLayer:CompareLayerZones()
			local leaderUnit = util.FindGroupLeaderUnit()

			if activePendingHop and playerZone and leaderZone and playerZone ~= leaderZone then
				compat.LeaveParty()
				addonTable.pendingLayerHop = nil
				if leaderUnit then
					sendCompatibilityNoticeOnce(UnitName(leaderUnit))
				end
				return
			end

			if activePendingHop and playerZone and leaderZone then
				addonTable.pendingLayerHop = nil
				return
			end

			if self.db.profile.showLayerWarning and leaderUnit then
				local currentZone = AutoLayer:GetLayerZone()
				local currentLeaderZone = AutoLayer:GetLayerZone(leaderUnit)
				self:Print("|cffffff00WARNING:|r You are in " .. AutoLayer:GetLayerZoneName(currentZone) ..
					", while the party leader is in " .. AutoLayer:GetLayerZoneName(currentLeaderZone) ..
					". You will most likely not layer correctly. You can leave the party and try to layer again.")
			end
		end)
		return
	end

	if self.db.profile.layerSegments and self.db.profile.showLayerWarning and not UnitIsGroupLeader("player") then
		self:DebugPrint("Group joined, comparing layer segments with leader...")
		-- Grant the game a little bit of time to process the group join and update any relevant information before we compare segments
		C_Timer.After(2, function()
			local playerSegment, leaderSegment = AutoLayer:CompareLayerSegments()
			if playerSegment ~= leaderSegment then
				self:Print("|cffffff00WARNING:|r You are in " .. (addonTable.layerSegments[playerSegment] or "an unknown segment") ..
							", while the party leader is in " .. (addonTable.layerSegments[leaderSegment] or "an unknown segment") ..
							". You will most likely not layer correctly. You can leave the party and try to layer again.")
			end
		end)
	end
end

AutoLayer:RegisterEvent("CHAT_MSG_CHANNEL", "ProcessMessage")
AutoLayer:RegisterEvent("CHAT_MSG_WHISPER", "ProcessMessage")
AutoLayer:RegisterEvent("CHAT_MSG_GUILD", "ProcessMessage")
AutoLayer:RegisterEvent("CHAT_MSG_SYSTEM", "ProcessSystemMessages")
AutoLayer:RegisterEvent("GROUP_ROSTER_UPDATE", "ProcessRosterUpdate")
AutoLayer:RegisterEvent("ZONE_CHANGED_NEW_AREA", "ProcessZoneChange")
AutoLayer:RegisterEvent("GROUP_JOINED", "ProcessGroupJoined")

local JOIN_ATTEMPT_INTERVAL = 10
local lastJoinAttempt = 0

JoinLayerChannel = function()
	-- Join ALL channels to prevent griefing (so griefers can't become admin in empty channels)
	-- Only try each channel once - if it fails (e.g. password protected), don't retry
	local currentTime = time()
	if currentTime - lastJoinAttempt < JOIN_ATTEMPT_INTERVAL then
		return
	end
	lastJoinAttempt = currentTime

	-- Step 1: Attempt to join all channels that are not marked as failed
	for _, channelName in ipairs(LAYER_CHANNELS) do
		if not failedChannels[channelName] then
			local channel_num = GetChannelName(channelName)
			if channel_num == 0 then
				AutoLayer:DebugPrint("Attempting to join '" .. channelName .. "'")
				if JoinChannelByName then
					JoinChannelByName(channelName)
				else
					JoinPermanentChannel(channelName, nil, DEFAULT_CHAT_FRAME:GetID(), 1)
				end
			end
		else
			AutoLayer:DebugPrint("Channel '" .. channelName .. "' skipped (previously failed to join)")
		end
	end

	-- Step 2: After a short delay, check which channels were actually joined
	C_Timer.After(1, function()
		-- Check which channels could not be joined and mark them as failed
		for _, channelName in ipairs(LAYER_CHANNELS) do
			local channel_num = GetChannelName(channelName)
			if channel_num == 0 and not failedChannels[channelName] then
				failedChannels[channelName] = true
				AutoLayer:DebugPrint("Channel '" .. channelName .. "' marked as failed (could not join)")
			end
		end

		-- Determine which channel to use for sending (priority order matches LAYER_CHANNELS)
		addonTable.activeLayerChannel = nil
		for _, channelName in ipairs(LAYER_CHANNELS) do
			local channel_num = GetChannelName(channelName)
			if channel_num > 0 then
				if not addonTable.activeLayerChannel then
					addonTable.activeLayerChannel = channelName
					AutoLayer:DebugPrint("Active layer channel set to: " .. channelName)
				end
			end
		end

		-- Inform user if we had to use a fallback (first channel in list is primary)
		local primaryChannel = LAYER_CHANNELS[1]
		if addonTable.activeLayerChannel and addonTable.activeLayerChannel ~= primaryChannel then
			AutoLayer:Print("Primary channel unavailable, using fallback: " .. addonTable.activeLayerChannel)
		elseif not addonTable.activeLayerChannel then
			AutoLayer:Print("All layer channels unavailable")
		end

		-- Remove all layer channels from chat frames (so they don't clutter the chat)
		for i = 1, 10 do
			if _G["ChatFrame" .. i] then
				for _, ch in ipairs(LAYER_CHANNELS) do
					_G["ChatFrame" .. i]:RemoveChannel(ch)
				end
			end
		end
	end)
end

local function ProcessQueue()
	if #addonTable.send_queue > 0 then
		local payload = table.remove(addonTable.send_queue, 1)
		local sentToAny = false

		-- Send to ALL available layer channels for maximum reach
		for _, channelName in ipairs(LAYER_CHANNELS) do
			local channel_num = GetChannelName(channelName)
			if channel_num > 0 then
				CTL:SendChatMessage("BULK", channelName, payload, "CHANNEL", nil, channel_num)
				AutoLayer:DebugPrint("Sent message to channel: " .. channelName)
				sentToAny = true
			end
		end

		if not sentToAny then
			JoinLayerChannel()
		end
	end
end

addonTable.ProcessQueue = ProcessQueue

-- One low-frequency pump replaces the WorldFrame mouse hook and the key-hook frame:
-- queued requests are sent within a second without reacting to every click and keypress.
local sendPump

function AutoLayer:StartSendPump()
	if sendPump then
		return
	end
	sendPump = C_Timer.NewTicker(1, function()
		if not AutoLayer.db.profile.enabled then
			return
		end
		if not addonTable.activeLayerChannel then
			JoinLayerChannel()
		end
		ProcessQueue()
	end)
end
