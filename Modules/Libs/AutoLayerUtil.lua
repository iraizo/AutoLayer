local _, addonTable = ...

--- Pure helpers for config parsing, message matching and whisper formatting.
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
