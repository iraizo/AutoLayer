AutoLayer = LibStub("AceAddon-3.0"):NewAddon("AutoLayer", "AceConsole-3.0")
local CTL = _G.ChatThrottleLib

local triggers = { "inv", "layer", "invite" }
local invite_queue = {}
local should_send_party_welcome = false
local group_count = 0

function AutoLayer:ProcessQueue()
    if should_send_party_welcome then
        local party_chat = GetChannelName("Party")
        CTL:SendChatMessage("NORMAL", "Party", "Welcome to the autolayer service, tips per mail are appreciated!",
            "PARTY", nil, party_chat)
        should_send_party_welcome = false
    end

    for i, playerName in ipairs(invite_queue) do
        AutoLayer:Print("Invited " .. playerName)
        InviteUnit(playerName)
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
                table.insert(invite_queue, playerName)
                --SendChatMessage("invite" .. playerName, "SAY", nil, nil)
                --C_PartyInfo.InviteUnit(playerName)

                --C_PartyInfo.InviteUnit(playerName)
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
