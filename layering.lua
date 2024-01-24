local addonName, addonTable = ...;
local CTL = _G.ChatThrottleLib

local player_cache = {}
local kick_player = nil

local function containsNumber(str, number)
    for match in string.gmatch(str, "%d+") do
        if tonumber(number) == tonumber(match) then
            return true
        end
    end
    return false
end

--- Checks if a message contains any word from a given list, with an option to respect word boundaries.
-- @param msg The message to search through.
-- @param listOfWords A list of words to search for in the message.
-- @param respectWordBoundaries (optional) Whether to respect word boundaries in the search. Defaults to true.
-- @return The first word found in the message that matches a word from the list; false otherwise.
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

--- Extracts unique, sorted layer numbers from a message.
-- Identifies individual and ranged layer numbers (e.g., "1", "1-3") in a message,
-- compiling them into a sorted list without duplicates.
--
-- @param message string The input string containing layer numbers.
-- @return table List of sorted, unique layer numbers.
local function parseLayers(message)
    local layers = {}

    -- Add individual layers
    for num in string.gmatch(message, "%d+") do
        layers[#layers + 1] = tonumber(num)
    end

    -- Expand ranges
    for rangeStart, rangeEnd in string.gmatch(message, "(%d+)%-(%d+)") do
        for i = tonumber(rangeStart), tonumber(rangeEnd) do
            layers[#layers + 1] = i
        end
    end

    -- Sort layers
    table.sort(layers)

    -- Remove duplicates
    local uniqueLayers = {}
    uniqueLayers[1] = layers[1]
    for i = 2, #layers do
        if layers[i] ~= layers[i - 1] then
            uniqueLayers[#uniqueLayers + 1] = layers[i]
        end
    end

    return uniqueLayers
end


C_Timer.After(0.1, function()
    for name in LibStub("AceAddon-3.0"):IterateAddons() do
        if name == "NovaWorldBuffs" then
            addonTable.NWB = LibStub("AceAddon-3.0"):GetAddon("NovaWorldBuffs")
            return
        end
    end

    if addonTable.NWB == nil then
        AutoLayer:Print("Could not find NovaWorldBuffs, disabling NovaWorldBuffs integration")
    end
end)

---@diagnostic disable-next-line:inject-field
function AutoLayer:ProcessMessage(event, msg, name, _, channel)
    if not self.db.profile.enabled then
        return
    end

    local name_without_realm = ({ strsplit("-", name) })[1]
    --if name_without_realm == UnitName("player") then
    --    return
    --end

    local triggerMatch = containsAnyWordFromList(msg, AutoLayer:ParseTriggers(), true)
    if not triggerMatch then
        return
    end

    local blacklistMatch = containsAnyWordFromList(msg, AutoLayer:ParseBlacklist(), false)
    if blacklistMatch then
        self:DebugPrint("Matched blacklist: '", blacklistMatch, "' in message: '", msg, "' from player '", name_without_realm, "'")
        return
    end

    -- If we got this far, we have a valid match.
    self:DebugPrint("Matched trigger: '", triggerMatch, "' in message: '", msg, "' from player '", name_without_realm, "'")

    if string.find(msg, "%d+") then
        self:DebugPrint(name, "requested specific layer", msg)
        if string.find(string.lower(msg), "not.-%d+") then
            self:DebugPrint(name, "contains 'not' in layer request, ignoring for now:", msg)
            return
        end
        if not containsNumber(msg, addonTable.NWB.currentLayer) then
            self:DebugPrint(name, "layer condition unsatisfied:", msg)
            self:DebugPrint("Current layer:", addonTable.NWB.currentLayer)
            return
        end
        self:DebugPrint(name, "layer condition satisfied", msg)
    end

    -- check if we've already invited this player in the last 5 minutes
    if event ~= "CHAT_MSG_WHISPER" then
        for i, player in ipairs(player_cache) do
            -- delete players from cache that are over 5 minutes old
            if player.time + 300 < time() then
                self:DebugPrint("Removing ", player.name, " from cache")
                table.remove(player_cache, i)
            end

            --self:DebugPrint("Checking ", player.name, " against ", name)
            --self:DebugPrint("Time: ", player.time, " + 300 < ", time(), " = ", player.time + 300 < time())

            local player_name_without_realm = ({ strsplit("-", player.name) })[1]

            -- dont invite player if they got invited in the last 5 minutes

            if player.name == name_without_realm or player_name_without_realm == name_without_realm and player.time + 300 > time() then
                self:DebugPrint("Already invited", name, "in the last 5 minutes")
                return
            end
        end
    end

    --end

    ---@diagnostic disable-next-line: undefined-global
    InviteUnit(name)

    -- check if group is full
    if self.db.profile.autokick and GetNumGroupMembers() >= 4 then
        self:DebugPrint("Group is full, kicking")

        -- kick first member after group leader
        for i = 4, GetNumGroupMembers() do
            if UnitIsGroupLeader("player") and i ~= 1 then
                kick_player = GetRaidRosterInfo(i)
            end
        end

        return
    end
end

---@diagnostic disable-next-line: inject-field
function AutoLayer:ProcessSystemMessages(_, a)
    if not self.db.profile.enabled then
        return
    end

    local segments = { strsplit(" ", a) }

    -- X joins the party
    if segments[2] == "joins" then
        self.db.profile.layered = self.db.profile.layered + 1

        table.insert(player_cache, { name = segments[1], time = time() - 100 })
    end

    if segments[2] == "declines" then
        table.insert(player_cache, { name = segments[1], time = time() })
        self:DebugPrint("Adding ", segments[1], " to cache, reason: declined invite")
    end

    if segments[3] == "invited" then
        if addonTable.NWB ~= nil and addonTable.NWB.currentLayer ~= 0 and self.db.profile.whisper == true then
            CTL:SendChatMessage("NORMAL", segments[4], "[AutoLayer] invited to layer " .. addonTable.NWB.currentLayer,
                "WHISPER", nil,
                segments[4])
        end
    end
end

function AutoLayer:HandleAutoKick()
    if not self.db.profile.enabled then
        return
    end

    if self.db.profile.autokick and kick_player ~= nil then
        self:DebugPrint("Kicking ", kick_player)
        UninviteUnit(kick_player)
        kick_player = nil
    end
end

AutoLayer:RegisterEvent("CHAT_MSG_CHANNEL", "ProcessMessage")
AutoLayer:RegisterEvent("CHAT_MSG_WHISPER", "ProcessMessage")
AutoLayer:RegisterEvent("CHAT_MSG_GUILD", "ProcessMessage")
AutoLayer:RegisterEvent("CHAT_MSG_SYSTEM", "ProcessSystemMessages")

function JoinLayerChannel()
    JoinChannelByName("layer")
    local channel_num = GetChannelName("layer")
    if channel_num == 0 then
        print("Failed to join Layer channel")
    else
        print("Successfully joined Layer channel.")
    end

    for i = 1, 10 do
        if _G['ChatFrame' .. i] then
            ChatFrame_RemoveChannel(_G['ChatFrame' .. i], "layer")
        end
    end
end

function ProccessQueue()
    if #addonTable.send_queue > 0 then
        local payload = table.remove(addonTable.send_queue, 1)
        local l_channel_num = GetChannelName("layer")
        if l_channel_num == 0 then
            JoinLayerChannel()
            do return end
        end
        CTL:SendChatMessage("BULK", "layer", payload, "CHANNEL", nil, l_channel_num)
    end
end

C_Timer.After(1, function()
    WorldFrame:HookScript("OnMouseDown", function(self, button)
        AutoLayer:HandleAutoKick()
        ProccessQueue()
    end)
end)

local f = CreateFrame("Frame", "Test", UIParent)
f:SetScript("OnKeyDown", ProccessQueue)
f:SetPropagateKeyboardInput(true)
