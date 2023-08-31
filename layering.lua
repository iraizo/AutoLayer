local CTL = _G.ChatThrottleLib

local player_cache = {}

---@diagnostic disable-next-line:inject-field
function AutoLayer:ProcessMessage(event, msg, name)
    if not self.db.profile.enabled then
        return
    end

    local player_name = UnitName("player") .. "-" .. GetRealmName()
    if name == player_name then
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

                    if player.name == name and player.time + 300 > time() then
                        self:DebugPrint("Already invited", name, "in the last 5 minutes")
                        return
                    end
                end

                -- cooldown of 2,5 minutes always applying if not whispering
                table.insert(player_cache, { name = name, time = time() - 150 })
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
    if segments[2] == "joins" and self.db.profile.sendMessage then
        CTL:SendChatMessage("NORMAL", segments[1], self.db.profile.myMessage, "WHISPER", nil, segments[1])
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
