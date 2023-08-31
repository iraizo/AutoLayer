local CTL = _G.ChatThrottleLib

local player_cache = {}

---@diagnostic disable-next-line:inject-field
function AutoLayer:ProcessMessage(event, msg, name)
    if not self.db.profile.enabled then
        return
    end

    if name == UnitName("player") then
        return
    end

    local triggers = AutoLayer:ParseTriggers()

    for _, trigger in ipairs(triggers) do
        if msg:find("%f[%a]layer%f[%A]") then
            -- much efficency, much wow!
            local blacklist = AutoLayer:ParseBlacklist()
            for _, black in ipairs(blacklist) do
                if string.match(msg, black) then
                    self:DebugPrint("Matched blacklist", black, "in message", msg)
                    return
                end
            end

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

            ---@diagnostic disable-next-line: undefined-global
            InviteUnit(name)

            if self.db.profile.sendMessage then
                CTL:SendChatMessage("NORMAL", name, self.db.profile.myMessage, "WHISPER", nil, name)
            end

            self.db.profile.layered = self.db.profile.layered + 1

            if event ~= "CHAT_MSG_WHISPER" then
                table.insert(player_cache, {
                    name = name,
                    time = time()
                })
            end
        end
    end
end

AutoLayer:RegisterEvent("CHAT_MSG_CHANNEL", "ProcessMessage")
AutoLayer:RegisterEvent("CHAT_MSG_WHISPER", "ProcessMessage")
AutoLayer:RegisterEvent("CHAT_MSG_GUILD", "ProcessMessage")
