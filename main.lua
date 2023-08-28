AutoLayer = LibStub("AceAddon-3.0"):NewAddon("AutoLayer", "AceConsole-3.0")
local CTL = _G.ChatThrottleLib

local triggers = { "layer" }
local blacklist = { "guild", "Guild", "Wts", "Wtb", "wts", "wtb", "GUILD", "WTS", "WTB" }
local invite_queue = {}
local should_send_party_welcome = false
local group_count = 0

function AutoLayer:ProcessQueue()
    for i, invite in ipairs(invite_queue) do
        local delta = time() - invite.time;
        local name = invite.name;
        -- if someone asked for an invite 10 seconds ago, dont invite him
        if delta >= 10 then
            AutoLayer:Print("Invitation ask from " .. name .. " expired")
            return
        end

        AutoLayer:Print("Invited " .. name)
        CTL:SendChatMessage("NORMAL", name,
            "[AutoLayer] Automatically invited you to the group, please accept the invite.",
            "WHISPER", nil, name)
        InviteUnit(name)
        table.remove(invite_queue, i)
    end
end

function AutoLayer:OnInitialize()
    local name = GetChannelName("Party")
    group_count = GetNumGroupMembers()
    -- CTL:SendChatMessage("NORMAL", "Party", "Welcome to the autolayer service, tips per mail are appreciated!",
    --    "PARTY", nil, name)

    WorldFrame:HookScript("OnMouseDown", function(self, button)
        AutoLayer:ProcessQueue()
    end)

    local f = CreateFrame("Frame", "Test", UIParent)
    f:SetScript("OnKeyDown", AutoLayer.ProcessQueue)
    f:SetPropagateKeyboardInput(true)

    local party_frame = CreateFrame("Frame")

    party_frame:RegisterEvent("GROUP_ROSTER_UPDATE")

    party_frame:SetScript("OnEvent", function(self, event, ...)
        if GetNumGroupMembers() > group_count then
            AutoLayer:Print("Group size increased")
            should_send_party_welcome = true
        end
        group_count = GetNumGroupMembers()
    end)

    local chat_frame = CreateFrame("Frame")
    chat_frame:RegisterEvent("CHAT_MSG_CHANNEL")

    chat_frame:SetScript("OnEvent", function(self, event, ...)
        local text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, languageID, lineID, guid, bnSenderID, isMobile, isSubtitle, hideSenderInLetterbox, supressRaidIcons
        = ...

        -- dont wanna invite myself
        if playerName == UnitName("player") then
            return
        end

        --C_PartyInfo.InviteUnit(playerName)"
        -- iterates over all possible triggers, if a text message contains those words the player will get invited
        for _, trigger in ipairs(triggers) do
            if string.match(text, trigger) then
                for _, blacklisted_keyword in ipairs(blacklist) do
                    if string.match(text, blacklisted_keyword) then
                        AutoLayer:Print("Found blacklisted keyword: " .. blacklisted_keyword .. " from " .. playerName)
                        return
                    end
                end

                table.insert(invite_queue, {
                    name = playerName,
                    time = time()
                })
                AutoLayer:Print("Found trigger: " .. text .. " from " .. playerName)
            end
        end
    end)

    AutoLayer:Print("Loaded.")
end

-- function NWB:recalcMinimapLayerFrame(zoneID, event, unit)
--[[
C_Timer.After(1, function()
    local children = { UIParent:GetChildren() }
    for i, child in ipairs(children) do
        local name = child:GetName()
        if string.match(name, "MinimapLayerFrame") then
            print(name)
            print("AutoLayer: Found MinimapCluster")
            local minimap_children = { child:GetChildren() }

            for _, minimap_child in ipairs(minimap_children) do
                for _, another_one in ipairs(minimap_child) do
                    print(another_one:GetName())
                end
            end
        end
    end
end)
--]]
