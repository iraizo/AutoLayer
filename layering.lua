local addonName, addonTable = ...
local CTL = _G.ChatThrottleLib

local playersInvitedRecently = {}
local recentLayerRequests = {}
local kicked_player_queue = {}

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

local function formatWhisperMessage(template, currentLayer)
	if template:find("{layer}") then
		template = template:gsub("{layer}", currentLayer)
	end
	if template:find("%%s") then
		template = string.format(template, currentLayer)
	end
	return template
end

function AutoLayer:pruneCache()
	for i, cachedPlayer in ipairs(playersInvitedRecently) do
		-- delete players that are over 5 minutes old
		if cachedPlayer.time + 300 < time() then
			self:DebugPrint("Removing ", cachedPlayer.name, " from players invited recently")
			table.remove(playersInvitedRecently, i)
		end
	end
	for i, cachedPlayer in ipairs(recentLayerRequests) do
		-- delete players that are over 1 minute old
		if cachedPlayer.time + 60 < time() then
			self:DebugPrint("Removing ", cachedPlayer.name, " from recent layer requests")
			table.remove(recentLayerRequests, i)
		end
	end
end

--- @param number number The number to check for in the list.
--- @param list table<number> The list of numbers to check against.
--- @return boolean is_in_list Whether the number is in the list.
local function isNumberInList(number, list)
	for _, value in ipairs(list) do
		if value == number then
			return true
		end
	end
	return false
end

local function removeRealmName(name)
	return ({ strsplit("-", name) })[1]
end

--- Checks if a message contains any word from a given list, with an option to respect word boundaries.
--- @param msg string The message to search through.
--- @param listOfWords table<string> A list of words to search for in the message.
--- @param respectWordBoundaries boolean? (optional) Whether to respect word boundaries in the search. Defaults to true.
--- @return boolean The first word found in the message that matches a word from the list; false otherwise.
local function containsAnyWordFromList(msg, listOfWords, respectWordBoundaries)
	-- Default to true if not explicitly set
	respectWordBoundaries = respectWordBoundaries ~= false
	local lowerMsg = string.lower(msg)

	for _, word in ipairs(listOfWords) do
		local lowerWord = string.lower(word)
		local pattern

		if respectWordBoundaries then
			pattern = "%f[%a]" .. lowerWord .. "%f[%A]"
		else
			pattern = lowerWord
		end

		if string.find(lowerMsg, pattern) then
			return word -- Return the matched word
		end
	end

	return false -- Return false if nothing matched
end

local function containsAnyTriggersFromList(msg, listOfTriggers)
	local lowermsg = string.lower(msg)

	for _, trigger in ipairs(listOfTriggers) do
		local pattern = string.gsub(trigger, "%*", ".*")

		if string.match(lowermsg, "^" .. pattern .. "$") then
			return trigger -- Return the trigger that matched
		end
	end

	return false
end

local function containsAnyChannelFromList(channelName, listOfChannelNames)
	local lowerName = string.lower(channelName)

	for _, pattern in ipairs(listOfChannelNames) do
		local luaPattern = string.gsub(pattern, "%*", ".*")

		if string.match(lowerName, "^" .. luaPattern .. "$") then
			return channelName -- Return the original channel name if it matches
		end
	end

	return nil
end

---  Extracts unique, sorted layer numbers from a message.
---  Identifies individual and ranged layer numbers (e.g., "1", "1-3") in a message,
---  compiling them into a sorted list without duplicates.
---
--- @param message string The input string containing layer numbers.
--- @return table<number> layer_numbers List of sorted, unique layer numbers.
local function parseLayers(message)
	local layers = {}

	-- Add individual layers
	for num in string.gmatch(message, "%d+") do
		layers[#layers + 1] = tonumber(num)
	end

	-- Expand ranges, e.g. "layer 1-3" is the same as "layer 1,2,3"
	for rangeStart, rangeEnd in string.gmatch(message, "(%d+)%-(%d+)") do
		local startNum = tonumber(rangeStart)
		local endNum = tonumber(rangeEnd)
		-- but what if someone is a freak and says "layer 3-1" instead of "layer 1-3"?
		if startNum > endNum then
			startNum, endNum = endNum, startNum -- Swap values if out of order
		end
		for i = startNum, endNum do
			layers[#layers + 1] = i
		end
	end

	-- Sort layers
	table.sort(layers)

	-- Make a new list without duplicates (this code assumes the list is already sorted)
	local uniqueLayers = {}
	uniqueLayers[1] = layers[1]
	for i = 2, #layers do
		if layers[i] ~= layers[i - 1] then
			uniqueLayers[#uniqueLayers + 1] = layers[i]
		end
	end

	return uniqueLayers
end

function AutoLayer:addNWBToAddonTable()
	for name in LibStub("AceAddon-3.0"):IterateAddons() do
		if name == "NovaWorldBuffs" then
			addonTable.NWB = LibStub("AceAddon-3.0"):GetAddon("NovaWorldBuffs")
			return
		end
	end
end

--- Finds the current layer from NovaWorldBuffs
--- @return number? layer The current layer number, or nil if the layer is unknown.
function AutoLayer:getCurrentLayer()
	if addonTable.NWB == nil then
		return
	end -- No NWB, nothing to do here

	if NWB_CurrentLayer == nil or tonumber(NWB_CurrentLayer) == nil or NWB_CurrentLayer <= 0 then
		return 0
	end
	return tonumber(NWB_CurrentLayer)
end

-- Autoexec?
C_Timer.After(0.1, function()
	AutoLayer:addNWBToAddonTable()
	if addonTable.NWB == nil then
		AutoLayer:Print("Could not find NovaWorldBuffs, disabling NovaWorldBuffs integration")
	end
end)

function AutoLayer:FindOfflineMembersToKick()
	for i = 1, GetNumGroupMembers() do
		local name, _, _, _, _, _, _, online, _, _, _, _ = GetRaidRosterInfo(i)

		if online == false then
			table.insert(kicked_player_queue, name)
		end
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
	if not self.db.profile.enabled or isPlayerLoggingOut() then
		return
	end

	if event ~= "CHAT_MSG_GUILD" and self.db.profile.guildOnly then
		return
	end

	local name_without_realm = removeRealmName(name)
	if name_without_realm == UnitName("player") then
		return
	end

	local triggerMatch = containsAnyTriggersFromList(msg, AutoLayer:ParseTriggers())
	if not triggerMatch then
		return
	end

	local blacklistMatch = containsAnyWordFromList(msg, AutoLayer:ParseBlacklist(), false)
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

	if self.db.profile.channelFiltering == "inclusive" then
		local inclusiveChannelMatch = containsAnyChannelFromList(channelBaseName, AutoLayer:ParseFilteredChannels())
		if not inclusiveChannelMatch then
			self:DebugPrint(
				"Did not match an included channel. Request came from player: '",
				name,
				"' in channel: '",
				channelBaseName,
				"' but currenty only allowing these channels: '",
				AutoLayer:GetFilteredChannels(),
				"'"
			)
			return
		end
	elseif self.db.profile.channelFiltering == "exclusive" then
		local exclusiveChannelMatch = containsAnyChannelFromList(channelBaseName, AutoLayer:ParseFilteredChannels())
		if exclusiveChannelMatch then
			self:DebugPrint(
				"Matched excluded request from player: '",
				name,
				"' in excluded channel: '",
				exclusiveChannelMatch,
				"' from list of excluded channels: '",
				AutoLayer:GetFilteredChannels(),
				"'"
			)
			return
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

	if self.db.profile.turnOffWhileRaidAssist and IsInRaid() and UnitIsGroupAssistant("player") then
		self:DebugPrint("Ignoring request because we are raid assist!")
		return
	end

	local currentLayer = AutoLayer:getCurrentLayer()
	local isHighPriorityRequest = (event == "CHAT_MSG_WHISPER")

	if string.find(msg, "%d+") then -- Uh oh, this player is picky and wants a specific layer!
		if not currentLayer or currentLayer <= 0 then
			self:DebugPrint(
				"Message requested a specific layer, but we don't know what layer we're in! NWB says: ",
				NWB_CurrentLayer
			)
			return
		end
		local requestedLayers = parseLayers(msg)
		if not requestedLayers or next(requestedLayers) == nil then
			self:DebugPrint("Message requested a specific layer, but we couldn't parse the message successfully!")
			return
		end

		local requestIsInverted = containsAnyWordFromList(msg, AutoLayer:ParseInvertKeywords(), false)
		local currLayerMatchesRequest = isNumberInList(currentLayer, requestedLayers)

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

	-- used to check if we should invite with or without realm name below
	-- due to the fact that era has mega servers (multiple realms in one server)
	-- where we have to invite with the realm name
	-- since those do not exist on anniversary servers and where HasActiveSeason() is true
	-- we can validate it like this for now.
	local isSeasonal = C_Seasons.HasActiveSeason()

	---@diagnostic disable-next-line: undefined-global
	if not isHighPriorityRequest and (not self.db.profile.inviteWhisper or not currentLayer or currentLayer <= 0) then
		self:DebugPrint(
			"Auto-whisper is turned off or we can't provide a helpful whisper, delaying our invite by 500 miliseconds"
		)
		C_Timer.After(0.5, function()
			if isSeasonal then
				C_PartyInfo.InviteUnit(name_without_realm)
			else
				C_PartyInfo.InviteUnit(name)
			end
		end)
	else
		if isSeasonal then
			C_PartyInfo.InviteUnit(name_without_realm)
		else
			C_PartyInfo.InviteUnit(name)
		end
	end

	table.insert(recentLayerRequests, { name = name_without_realm, time = time() })
	self:DebugPrint("Added", name_without_realm, "to list of recent layer requests")

	local max_group_size = 4

	if IsInRaid() then
		max_group_size = 39
	end

	-- check if group is full
	if self.db.profile.autokick and GetNumGroupMembers() == max_group_size then
		self:DebugPrint("Group is full, kicking")

		-- kick last member of raid
		local lastMember = GetRaidRosterInfo(GetNumGroupMembers())
		table.insert(kicked_player_queue, lastMember)

		return
	end
end

---@diagnostic disable-next-line: inject-field
function AutoLayer:ProcessSystemMessages(_, SystemMessages)
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
				table.insert(playersInvitedRecently, { name = playerNameWithoutRealm, time = time() - 100 })
				break -- Found the player, no need to continue checking
			end
		end
	end

	characterName = SystemMessages:match("^" .. ERR_DECLINE_GROUP_S:format("(.+)"))
	-- X declines your invite
	if characterName then
		local playerNameWithoutRealm = removeRealmName(characterName)
		self:DebugPrint("ERR_DECLINE_GROUP_S", playerNameWithoutRealm, "found !")
		table.insert(playersInvitedRecently, { name = playerNameWithoutRealm, time = time() }) --Extend this timer, they don't want in right now
		self:DebugPrint("Adding ", playerNameWithoutRealm, " to cache, reason: declined invite")
	end

	characterName = SystemMessages:match("^" .. ERR_INVITE_PLAYER_S:format("(.+)"))
	if characterName then
		local playerNameWithoutRealm = removeRealmName(characterName)
		self:DebugPrint("ERR_INVITE_PLAYER_S", playerNameWithoutRealm, "found !")
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
			local finalMessage2 = "[AutoLayer] " .. string.format(self.db.profile.inviteWhisperTemplateReminder)
			CTL:SendChatMessage("NORMAL", characterName, finalMessage2, "WHISPER", nil, characterName)
		end
	end
end

function AutoLayer:HandleAutoKick()
	if not self.db.profile.enabled then
		return
	end

	if self.db.profile.autokick and #kicked_player_queue >= 0 then
		local name = table.remove(kicked_player_queue, 1)

		if name == nil then
			return
		end

		if not UnitInRaid(name) and not UnitInParty(name) then
			return
		end

		self:DebugPrint("Kicking ", name)
		C_PartyInfo.UninviteUnit(name)
	end
end

function AutoLayer:ProcessRosterUpdate()
	self:getCurrentLayer()
end

AutoLayer:RegisterEvent("CHAT_MSG_CHANNEL", "ProcessMessage")
AutoLayer:RegisterEvent("CHAT_MSG_WHISPER", "ProcessMessage")
AutoLayer:RegisterEvent("CHAT_MSG_GUILD", "ProcessMessage")
AutoLayer:RegisterEvent("CHAT_MSG_SYSTEM", "ProcessSystemMessages")
AutoLayer:RegisterEvent("GROUP_ROSTER_UPDATE", "ProcessRosterUpdate")

function JoinLayerChannel()
	JoinChannelByName("layer")
	local channel_num = GetChannelName("layer")
	if channel_num == 0 then
		print("Failed to join Layer channel")
	end

	for i = 1, 10 do
		if _G["ChatFrame" .. i] then
			ChatFrame_RemoveChannel(_G["ChatFrame" .. i], "layer")
		end
	end
end

function ProccessQueue()
	AutoLayer:HandleAutoKick()
	if #addonTable.send_queue > 0 then
		local payload = table.remove(addonTable.send_queue, 1)
		local l_channel_num = GetChannelName("layer")
		if l_channel_num == 0 then
			JoinLayerChannel()
			do
				return
			end
		end
		CTL:SendChatMessage("BULK", "layer", payload, "CHANNEL", nil, l_channel_num)
	end
end

C_Timer.After(1, function()
	WorldFrame:HookScript("OnMouseDown", function(self, button)
		local l_channel_num = GetChannelName("layer")
		if l_channel_num == 0 then
			JoinLayerChannel()
			do
				return
			end
		end

		AutoLayer:HandleAutoKick()
		ProccessQueue()
	end)
end)

local f = CreateFrame("Frame", "Test", UIParent)
f:SetScript("OnKeyDown", ProccessQueue)
f:SetPropagateKeyboardInput(true)
