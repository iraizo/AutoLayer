local addonName, addonTable = ...;
local CTL = _G.ChatThrottleLib

local player_cache = {}

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
function AutoLayer:ProcessMessage(event, msg, name)
    if not self.db.profile.enabled then
        return
    end

    local name_without_realm = ({ strsplit("-", name) })[1]
    if name_without_realm == UnitName("player") then
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

                    -- TODO: add || check with realm name removed from name

                    if player.name == name_without_realm and player.time + 300 > time() then
                        self:DebugPrint("Already invited", name, "in the last 5 minutes")
                        return
                    end
                end
            end

            -- cooldown of 1 minute always applying if not whispering
            table.insert(player_cache, { name = name, time = time() - 230 })
            --end

            if addonTable.NWB ~= nil and addonTable.NWB.currentLayer ~= 0 then
                CTL:SendChatMessage("NORMAL", name, "[AutoLayer] invited to layer " .. addonTable.NWB.currentLayer,
                    "WHISPER", nil,
                    name)
            end

            ---@diagnostic disable-next-line: undefined-global
            InviteUnit(name)

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
    end

    if segments[2] == "declines" then
        table.insert(player_cache, { name = segments[1], time = time() })
        self:DebugPrint("Adding ", segments[1], " to cache, reason: declined invite")
    end
end

AutoLayer:RegisterEvent("CHAT_MSG_CHANNEL", "ProcessMessage")
AutoLayer:RegisterEvent("CHAT_MSG_WHISPER", "ProcessMessage")
AutoLayer:RegisterEvent("CHAT_MSG_GUILD", "ProcessMessage")
AutoLayer:RegisterEvent("CHAT_MSG_SYSTEM", "ProcessSystemMessages")
