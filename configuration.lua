local addonName, addonTable = ...;

---@diagnostic disable: inject-field
function AutoLayer:SetMessage(info, val)
    AutoLayer:Print("SetMyMessage", info, val)
    self.db.profile.myMessage = val
end

function AutoLayer:GetMessage(info)
    return self.db.profile.myMessage
end

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

function AutoLayer:SetTriggers(info, val)
    AutoLayer:DebugPrint("SetTriggers", info, val)
    self.db.profile.triggers = val
end

function AutoLayer:GetTriggers(info)
    return self.db.profile.triggers
end

function AutoLayer:ParseTriggers()
    local triggers = {}
    for trigger in string.gmatch(self.db.profile.triggers, "[^,]+") do
        table.insert(triggers, trigger)
    end
    return triggers
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
