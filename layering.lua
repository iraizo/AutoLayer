local CTL = _G.ChatThrottleLib

local player_cache = {}

---@diagnostic disable-next-line:inject-field
function AutoLayer:ProcessMessage(_, msg, name)
    if not self.db.profile.enabled then
        return
    end

    local triggers = self:ParseTriggers()

    for _, trigger in ipairs(triggers) do
        --self:DebugPrint("Checking trigger", trigger, "against message", msg)
        -- use gmatch to match the trigger anywhere in the message, case insensitive
        if string.match(msg, trigger) then
            self:DebugPrint("Matched trigger", trigger, "in message", msg)

            -- check if we've already invited this player in the last 5 minutes
            for i, player in ipairs(player_cache) do
                if player.name == name and player.time + 300 > time() then
                    self:DebugPrint("Already invited", name, "in the last 5 minutes")
                    return
                end

                -- delete players from cache that are over 5 minutes old
                if player.time + 300 < time() then
                    self:DebugPrint("Removing ", player.name, " from cache")
                    table.remove(player_cache, i)
                end
            end

            InviteUnit(name)
            CTL:SendChatMessage("NORMAL", name, self.db.profile.myMessage, "WHISPER", nil, name)

            self.db.profile.layered = self.db.profile.layered + 1

            table.insert(player_cache, {
                name = name,
                time = time()
            })
            return
        end
    end
end

AutoLayer:RegisterEvent("CHAT_MSG_CHANNEL", "ProcessMessage")
AutoLayer:RegisterEvent("CHAT_MSG_WHISPER", "ProcessMessage")
AutoLayer:RegisterEvent("CHAT_MSG_GUILD", "ProcessMessage")
