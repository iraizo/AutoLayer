local _, addonTable = ...

--- Pure helpers for config parsing, message matching, map resolution and whisper formatting.
--- Nothing in here touches addon state, so it can be exercised with plain Lua.
local util = {}
addonTable.util = util

-- A whisper is capped at 255 characters; the "[AutoLayer] " prefix takes 12 of them.
util.MAX_WHISPER_TEMPLATE_LENGTH = 243

local MAX_LAYER = 20
local PATTERN_MAGIC = "([%^%$%(%)%%%.%[%]%*%+%-%?])"

--- Escapes Lua pattern magic characters so arbitrary user text can be matched literally.
---@param text string
---@return string
function util.EscapePattern(text)
	return (text:gsub(PATTERN_MAGIC, "%%%1"))
end

--- Trims leading and trailing whitespace.
---@param text string
---@return string
function util.Trim(text)
	return (text:match("^%s*(.-)%s*$"))
end

--- Splits a comma separated setting into trimmed, non-empty entries.
---@param raw string|nil
---@return table<string>
function util.SplitConfigList(raw)
	local entries = {}
	for entry in string.gmatch(raw or "", "[^,]+") do
		local trimmed = util.Trim(entry)
		if trimmed ~= "" then
			entries[#entries + 1] = trimmed
		end
	end
	return entries
end

--- "Name-Realm" -> "Name" without allocating a strsplit table.
---@param name string|nil
---@return string|nil
function util.RemoveRealmName(name)
	return name and name:match("^[^-]+") or name
end

---@param name string|nil
---@return string
function util.NormalizeCharacterName(name)
	return string.lower(util.RemoveRealmName(name or ""))
end

--- Removes chat color codes so addon prefixes like "[NWB]" still match.
---@param msg string|nil
---@return string|nil
function util.StripColorCodes(msg)
	if not msg then
		return msg
	end
	msg = msg:gsub("|c%x%x%x%x%x%x%x%x", "")
	msg = msg:gsub("|r", "")
	return msg
end

--- Whole word, case insensitive matcher for one trigger.
---@param trigger string
---@return string
function util.TriggerPattern(trigger)
	return "%f[%w]" .. util.EscapePattern(string.lower(trigger)) .. "%f[%W]"
end

--- Anchored channel matcher where "*" is the only wildcard.
---@param channel string
---@return string
function util.ChannelPattern(channel)
	local escaped = util.EscapePattern(string.lower(channel))
	return "^" .. (escaped:gsub("%%%*", ".*")) .. "$"
end

---@param lowerMsg string
---@param triggers table<{word: string, pattern: string}>
---@return string|false @The matching trigger, or false.
function util.FindMatchingTrigger(lowerMsg, triggers)
	for i = 1, #triggers do
		local trigger = triggers[i]
		if string.find(lowerMsg, trigger.pattern) then
			return trigger.word
		end
	end
	return false
end

--- Plain substring match (no Lua patterns) against lowercased entries.
---@param lowerMsg string
---@param words table<{word: string}>
---@return string|false @The matching word, or false.
function util.FindMatchingWord(lowerMsg, words)
	for i = 1, #words do
		local word = words[i].word
		if string.find(lowerMsg, word, 1, true) then
			return word
		end
	end
	return false
end

---@param lowerChannelName string
---@param channels table<{name: string, pattern: string}>
---@return string|nil @The configured channel name, or nil.
function util.FindMatchingChannel(lowerChannelName, channels)
	for i = 1, #channels do
		local channel = channels[i]
		if string.match(lowerChannelName, channel.pattern) then
			return channel.name
		end
	end
	return nil
end

--- Extracts unique, sorted layer numbers from a message, expanding "1-3" ranges.
---@param message string
---@return table<number>
function util.ParseLayers(message)
	local layers = {}

	for num in string.gmatch(message, "%d+") do
		local n = tonumber(num)
		if n and n >= 1 and n <= MAX_LAYER then
			layers[#layers + 1] = n
		end
	end

	-- Expand ranges, e.g. "layer 1-3" is the same as "layer 1,2,3"
	for rangeStart, rangeEnd in string.gmatch(message, "(%d+)%-(%d+)") do
		local startNum = tonumber(rangeStart)
		local endNum = tonumber(rangeEnd)
		-- but what if someone is a freak and says "layer 3-1" instead of "layer 1-3"?
		if startNum > endNum then
			startNum, endNum = endNum, startNum
		end

		-- Skip ranges entirely outside the valid layer range
		if startNum <= MAX_LAYER and endNum >= 1 then
			startNum = math.max(1, math.min(startNum, MAX_LAYER))
			endNum = math.max(1, math.min(endNum, MAX_LAYER))
			for i = startNum, endNum do
				layers[#layers + 1] = i
			end
		end
	end

	table.sort(layers)

	local uniqueLayers = {}
	for i = 1, #layers do
		if layers[i] ~= layers[i - 1] then
			uniqueLayers[#uniqueLayers + 1] = layers[i]
		end
	end

	return uniqueLayers
end

--- Reads the live layer table from the NWBdatabase saved variable.
---@param savedDatabase table|nil
---@param realmName string|nil
---@param factionName string|nil
---@return table|nil
function util.GetNWBLayerTable(savedDatabase, realmName, factionName)
	local global = savedDatabase and savedDatabase.global
	local realmData = global and realmName and global[realmName]
	local factionData = realmData and factionName and realmData[factionName]
	if factionData and type(factionData.layers) == "table" then
		return factionData.layers
	end
	return nil
end

--- Lists the layer numbers NovaWorldBuffs exposes for one world.
--- NWB <= 3.41 stores layers flat (capital city zoneID -> layer data); NWB 3.48 nests
--- them per world ([storageID][capital city zoneID] -> layer data). NWB numbers a world's
--- layers 1..N by sorted zone ID, so only the entry count matters here.
---@param layers table|nil
---@param storageID number|nil Only used for the nested (NWB 3.48+) layout.
---@return table<number>
function util.GetNWBLayerNumbers(layers, storageID)
	if type(layers) ~= "table" then
		return {}
	end

	-- Storage IDs are small sequential numbers (1 = Azeroth, 2 = Outland); layer IDs are
	-- capital city zone IDs, so any small numeric key identifies the nested layout. Scan all
	-- keys because pairs() order is undefined and the table may hold non-numeric keys.
	local nested = false
	for key in pairs(layers) do
		if type(key) == "number" and key < 100 then
			nested = true
			break
		end
	end

	local layerData = layers
	if nested then
		layerData = storageID and layers[storageID] or nil
	end
	if type(layerData) ~= "table" then
		return {}
	end

	local count = 0
	for layerID in pairs(layerData) do
		if type(layerID) == "number" then
			count = count + 1
		end
	end

	local numbers = {}
	for i = 1, count do
		numbers[i] = i
	end
	return numbers
end

--- Resolves which world's layer table NovaWorldBuffs tracks.
---@param layers table NWB layer data (flat or nested).
---@param zoneID number|nil NWB_CurrentLayerZoneID: the capital city zone ID where NWB found the layer.
---@param segment string|nil AutoLayer segment: "AZ" (Azeroth) or "OL" (Outland).
---@return number storageID
function util.GetNWBStorageID(layers, zoneID, segment)
	-- The current map is authoritative; NWB's zone ID can outlive a world change.
	if segment == "OL" then
		return 2
	elseif segment == "AZ" then
		return 1
	end

	-- Instances have no segment, so fall back to the world NWB detected the layer in.
	if zoneID and zoneID > 0 then
		for storageID, layerData in pairs(layers) do
			if type(layerData) == "table" and layerData[zoneID] then
				return storageID
			end
		end
	end
	return 1
end

--- Resolves the layer segment for a UiMap by walking up its parent chain.
--- The starting map is checked as well: C_Map.GetBestMapForUnit can return a map that has
--- no parent (a continent/world map while flying, or an instance map), so a lookup that only
--- inspects ancestors misses valid segments and always fails for top-level maps.
---@param mapID number|nil
---@param getMapInfo fun(mapID: number): table|nil C_Map.GetMapInfo
---@param segmentMapIDs table<string, number>
---@param overrides table<number, string>|nil
---@return string|nil segment
function util.ResolveLayerSegment(mapID, getMapInfo, segmentMapIDs, overrides)
	for _ = 1, 32 do
		if not mapID or mapID == 0 then
			return nil
		end
		if overrides and overrides[mapID] then
			return overrides[mapID]
		end
		for segment, segmentMapID in pairs(segmentMapIDs) do
			if mapID == segmentMapID then
				return segment
			end
		end

		local mapInfo = getMapInfo(mapID)
		if not mapInfo then
			return nil
		end
		mapID = mapInfo.parentMapID
	end
	return nil
end

--- Map types that own a UiMap in the layered open world.
--- Enum.UIMapType: Cosmic=0, World=1, Continent=2, Zone=3, Dungeon=4, Micro=5, Orphan=6.
--- Micro, orphan and dungeon maps are not layer-owned (e.g. Ruins of Lordaeron is an orphan row
--- on clients that ship it), so a missing segment there must not be reported as a bug.
---@param mapType number|nil
---@return boolean
function util.IsOpenWorldMapType(mapType)
	return mapType == 1 or mapType == 2 or mapType == 3
end

---@param number number
---@param list table<number>
---@return boolean
function util.IsNumberInList(number, list)
	for i = 1, #list do
		if list[i] == number then
			return true
		end
	end
	return false
end

--- Fills {layer} and %s placeholders without treating any other "%" as a format specifier.
---@param template string
---@param currentLayer number|string
---@return string
function util.FormatWhisperMessage(template, currentLayer)
	local layerText = tostring(currentLayer)
	template = template:gsub("{layer}", function()
		return layerText
	end)
	template = template:gsub("%%s", function()
		return layerText
	end)
	return template
end

---@param template string
---@return true|string @True when valid, otherwise the error message AceConfig shows.
function util.CheckWhisperTemplateLength(template)
	local length = #util.FormatWhisperMessage(template, "99")
	if length > util.MAX_WHISPER_TEMPLATE_LENGTH then
		return "Value is too long. Maximum length is " .. util.MAX_WHISPER_TEMPLATE_LENGTH .. " characters."
	end
	return true
end

--- Finds the group leader unit token for both parties ("partyN") and raids ("raidN").
---@return string|nil
function util.FindGroupLeaderUnit()
	local unitPrefix = IsInRaid() and "raid" or "party"
	for i = 1, GetNumGroupMembers() do
		local unitID = unitPrefix .. i
		if UnitIsGroupLeader(unitID) then
			return unitID
		end
	end
	return nil
end
