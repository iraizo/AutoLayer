local addonName, addonTable = ...

function AutoLayer:SetDebug(info, val)
	AutoLayer:DebugPrint("SetDebug", info, val)
	self.db.profile.debug = val
end

function AutoLayer:GetDebug(info)
	return self.db.profile.debug
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
		table.insert(triggers, string.lower("*" .. trigger .. "*"))
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

function AutoLayer:GetFilteredChannels(info)
	return self.db.profile.filteredChannels
end

function AutoLayer:ParseFilteredChannels()
	local filteredChannels = {}
	for channel in string.gmatch(self.db.profile.filteredChannels, "[^,]+") do
		table.insert(filteredChannels, string.lower(channel))
	end
	return filteredChannels
end

local bunnyLDB = ...

function AutoLayer:Toggle()
	self.db.profile.enabled = not self.db.profile.enabled
	self:Print(self.db.profile.enabled and "enabled" or "disabled")

	if self.db.profile.enabled then
		if self.db.profile.hideAutoWhispers then
			self.filterChatEventAutoLayerWhisperMessages()
		end
		if self.db.profile.hideSystemGroupMessages then
			self:filterChatEventSystemGroupMessages()
		end
		if self.db.profile.mutesounds then
			self:MuteAnnoyingSounds()
		end

		addonTable.bunnyLDB.icon = [[Interface\AddOns\AutoLayer_Vanilla\Textures\AutoLayer_enabled_icon]]
	else
		if self.db.profile.hideAutoWhispers then
			self.unfilterChatEventAutoLayerWhisperMessages()
		end
		if self.db.profile.hideSystemGroupMessages then
			self:unfilterChatEventSystemGroupMessages()
		end
		if self.db.profile.mutesounds then
			self:UnmuteAnnoyingSounds()
		end

		addonTable.bunnyLDB.icon = [[Interface\AddOns\AutoLayer_Vanilla\Textures\AutoLayer_disabled_icon]]
	end
end
