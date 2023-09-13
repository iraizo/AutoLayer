local addonName, addonTable = ...;
local CTL = _G.ChatThrottleLib

local player_cache = {}
local kick_player = nil

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
    if name_without_realm == UnitName("player") then
        return
    end


    if channel:match(addonName) and addonTable.NWB ~= nil and addonTable.NWB.currentLayer ~= nil then
        local payload = addonTable.LibDeflate:DecodeForPrint(msg)

        if payload == nil then
            AutoLayer:DebugPrint("Failed to decode layer request")
            return
        end

        local decompressed = addonTable.LibDeflate:DecompressDeflate(payload)

        if decompressed == nil then
            AutoLayer:DebugPrint("Failed to decompress layer request")
            return
        end

        local success, layers = addonTable.LibSerialize:Deserialize(decompressed)

        if not success then
            AutoLayer:DebugPrint("Failed to decode layer request")
            return
        end

        AutoLayer:DebugPrint("Received layer request (encoded): " .. payload)
        AutoLayer:DebugPrint("Player " .. name .. " requested layer" .. table.concat(layers, ", "))
        for _, layer in ipairs(layers) do
            if layer == addonTable.NWB.currentLayer then
                InviteUnit(name)
                CTL:SendChatMessage("NORMAL", name, "[AutoLayer] invited to layer " .. addonTable.NWB.currentLayer,
                    "WHISPER", nil,
                    name)
                return
            end
        end

        return
    end


    local triggers = AutoLayer:ParseTriggers()

    for _, trigger in ipairs(triggers) do
        if string.find(string.lower(msg), "%f[%a]layer%f[%A]") then
            -- much efficency, much wow!
            local blacklist = AutoLayer:ParseBlacklist()
            for _, black in ipairs(blacklist) do
                if string.match(string.lower(msg), string.lower(black)) then
                    self:DebugPrint("Matched blacklist", black, "in message", msg)
                    return
                end
            end

            self:DebugPrint("Matched trigger", trigger, "in message", msg)

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

            return
        end
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
        if addonTable.NWB ~= nil and addonTable.NWB.currentLayer ~= 0 then
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

function JoinHoppingChannel()
    JoinChannelByName("AutoLayer", "autolayer")
    local channel_num = GetChannelName("AutoLayer")
    if channel_num == 0 then
        print("Failed to join death alerts channel")
    else
        print("Successfully joined deathlog channel.")
    end

    for i = 1, 10 do
        if _G['ChatFrame' .. i] then
            ChatFrame_RemoveChannel(_G['ChatFrame' .. i], "AutoLayers")
        end
    end
end

function ProccessQueue()
    if #addonTable.send_queue > 0 then
        local payload = table.remove(addonTable.send_queue, 1)
        local channel_num = GetChannelName("AutoLayer")
        if channel_num == 0 then
            JoinHoppingChannel()
            return
        end

        AutoLayer:DebugPrint("Sent layer request (encoded): " .. payload)

        CTL:SendChatMessage("BULK", "AutoLayer", payload, "CHANNEL", nil, channel_num)
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
