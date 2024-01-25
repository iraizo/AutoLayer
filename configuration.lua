---@diagnostic disable: inject-field
local addonName, addonTable = ...;

function AutoLayer:SetDebug(info, val)
    AutoLayer:DebugPrint("SetDebug", info, val)
    self.db.profile.debug = val
end

function AutoLayer:GetDebug(info)
    return self.db.profile.debug
end

function AutoLayer:SetEnabled(info, val)
    AutoLayer:DebugPrint("SetEnabled", info, val)
    self.db.profile.enabled = val
end

function AutoLayer:GetEnabled(info)
    return self.db.profile.enabled
end

function AutoLayer:SetSendMessage(info, val)
    AutoLayer:DebugPrint("SetSendMessage", info, val)
    self.db.profile.sendMessage = val
end

function AutoLayer:GetSendMessage(info)
    return self.db.profile.sendMessage
end

function AutoLayer:SetTriggers(info, val)
    AutoLayer:DebugPrint("SetTriggers", info, val)
    self.db.profile.triggers = val
end

function AutoLayer:GetTriggers(info)
    return self.db.profile.triggers
end

function AutoLayer:ParseTriggers()
    local triggers = {}
    for trigger in string.gmatch(self.db.profile.triggers, "%a+") do
        table.insert(triggers, trigger)
    end
    return triggers
end

function AutoLayer:SetBlacklist(info, val)
    AutoLayer:DebugPrint("SetBlacklist", info, val)
    self.db.profile.blacklist = val
end

function AutoLayer:GetBlacklist(info)
    return self.db.profile.blacklist
end

function AutoLayer:ParseBlacklist()
    local blacklist = {}
    for trigger in string.gmatch(self.db.profile.blacklist, "[^,]+") do
        table.insert(blacklist, trigger)
    end
    return blacklist
end

function AutoLayer:SetInvertKeywords(info, val)
    AutoLayer:DebugPrint("SetInvertKeywords", info, val)
    self.db.profile.invertKeywords = val
end

function AutoLayer:GetInvertKeywords(info)
    return self.db.profile.invertKeywords
end

function AutoLayer:ParseInvertKeywords()
    local invertKeywords = {}
    for keyword in string.gmatch(self.db.profile.invertKeywords, "[^,]+") do
        table.insert(invertKeywords, keyword)
    end
    return invertKeywords
end

local bunnyLDB = ...

function AutoLayer:Toggle()
    self.db.profile.enabled = not self.db.profile.enabled
    self:Print(self.db.profile.enabled and "enabled" or "disabled")

    if self.db.profile.enabled then
        addonTable.bunnyLDB.icon = "Interface\\Icons\\INV_Bijou_Green"
    else
        addonTable.bunnyLDB.icon = "Interface\\Icons\\INV_Bijou_Red"
    end
end
