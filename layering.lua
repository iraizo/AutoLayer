local addonName, addonTable = ...;
local CTL = _G.ChatThrottleLib

local playersInvitedRecently = {}
local recentLayerRequests = {}
local kick_player = nil

function AutoLayer:pruneCache()
    for i, cachedPlayer in ipairs(playersInvitedRecently) do
        -- delete players from cache that are over 5 minutes old
        if cachedPlayer.time + 300 < time() then
            self:DebugPrint("Removing ", cachedPlayer.name, " from cache")
            table.remove(playersInvitedRecently, i)
        end
    end
end

local function containsNumber(str, number)
    for match in string.gmatch(str, "%d+") do
        if tonumber(number) == tonumber(match) then
            return true
        end
    end
    return false
end

local function isNumberInList(number, list)
    for index, value in ipairs(list) do
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

function AutoLayer:ScanLayerFromNWB()
    for name in LibStub("AceAddon-3.0"):IterateAddons() do
        if name == "NovaWorldBuffs" then
            addonTable.NWB = LibStub("AceAddon-3.0"):GetAddon("NovaWorldBuffs")
            return
        end
    end
end

function AutoLayer:getCurrentLayer()
    if addonTable.NWB == nil then return end -- No NWB, nothing to do here
    -- If our layer is missing again, try to re-scan it once.
    if addonTable.NWB.currentLayer == nil or addonTable.NWB.currentLayer <= 0 then
        AutoLayer:ScanLayerFromNWB()
    end
    return tonumber(addonTable.NWB.currentLayer)
end

 -- Autoexec?
C_Timer.After(0.1, 
    function()
        AutoLayer:ScanLayerFromNWB()
        if addonTable.NWB == nil then
            AutoLayer:Print("Could not find NovaWorldBuffs, disabling NovaWorldBuffs integration")
        end
    end
)

---@diagnostic disable-next-line:inject-field
function AutoLayer:ProcessMessage(event, msg, name, _, channel)
    if not self.db.profile.enabled then
        return
    end

    local name_without_realm = removeRealmName(name)
    if name_without_realm == UnitName("player") then
        return
    end

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

    if string.find(msg, "%d+") then -- Uh oh, this player is picky and wants a specific layer!
        local currentLayer = AutoLayer:getCurrentLayer()
        if not currentLayer or currentLayer <= 0 then
            self:DebugPrint("Message requested a specific layer, but we don't know what layer we're in! NWB says: ", addonTable.NWB, addonTable.NWB.currentLayer)
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

        if (requestIsInverted and currLayerMatchesRequest) or (not requestIsInverted and not currLayerMatchesRequest) then
            self:DebugPrint("Request not satisfied. We are in layer ", currentLayer)
            return
        end
    end
    --If we got this far, then the message is a valid layer request that we can fulfill.

    -- check if we've already invited this player in the last 5 minutes
    if event ~= "CHAT_MSG_WHISPER" then -- If someone whispers us, that's fair game, they clearly want in
        AutoLayer:pruneCache()
        for i, cachedPlayer in ipairs(playersInvitedRecently) do
            if cachedPlayer.name == name_without_realm and cachedPlayer.time + 300 > time() then
                self:DebugPrint("Already invited", name, "in the last 5 minutes")
                return
            end
        end
    end


    ---@diagnostic disable-next-line: undefined-global
    InviteUnit(name) -- This specifically invites the player's name with realm, intended?

    table.insert(recentLayerRequests, name_without_realm)
    self:DebugPrint("Added", name_without_realm, "to list of recent layer requests, which is now: ", table.concat(recentLayerRequests, ", "))
    C_Timer.After(60, function()
        for i, listItem in ipairs(recentLayerRequests) do
            if listItem == name_without_realm then
                self:DebugPrint("Removed", name_without_realm, "from list of recent layer requests")
                table.remove(recentLayerRequests, i)
                break
            end
        end
    end)

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
        local playerNameWithoutRealm = removeRealmName(segments[1])

        -- Do AutoLayer stuff only if they actually asked for a layer
        -- (this may be a normal player we're inviting for different reasons)
        for i, cachedPlayerName in ipairs(recentLayerRequests) do
            if cachedPlayerName == playerNameWithoutRealm then
                self.db.profile.layered = self.db.profile.layered + 1
                table.insert(playersInvitedRecently, { name = playerNameWithoutRealm, time = time() - 100 })
                break -- Found the player, no need to continue checking
            end
        end      
    end

    -- X declines your invite
    if segments[2] == "declines" then
        local playerNameWithoutRealm = removeRealmName(segments[1])
        table.insert(playersInvitedRecently, { name = playerNameWithoutRealm, time = time() }) --Extend this timer, they don't want in right now
        self:DebugPrint("Adding ", playerNameWithoutRealm, " to cache, reason: declined invite")
    end

    if segments[3] == "invited" then
        local playerNameWithoutRealm = removeRealmName(segments[4])

        if playerNameWithoutRealm == "you" then return end -- X has invited you to group

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
            for i, cachedPlayerName in ipairs(recentLayerRequests) do
                if cachedPlayerName == playerNameWithoutRealm then
                    isPlayerInvited = true
                    break -- Found the player, no need to continue checking
                end
            end

            if not isPlayerInvited then
                return
            end

            -- Continue with the rest of the function if the player is in the list

            local finalMessage = "[AutoLayer] " .. string.format(self.db.profile.inviteWhisperTemplate, currentLayer)
            CTL:SendChatMessage("NORMAL", segments[4], finalMessage,
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
