local addonName, addonTable = ...
local compat = addonTable.compat
local util = addonTable.util

addonTable.options = {
	name = "AutoLayer",
	handler = AutoLayer,
	type = "group",
	args = {
		generalSettings = {
			type = "group",
			name = "General Settings",
			inline = true,
			order = 0,
			args = {
				enabled = {
					type = "toggle",
					name = "Enabled",
					desc = "Enable or disable AutoLayer.",
					set = "SetEnabled",
					get = "GetEnabled",
					order = 1,
				},
				debug = {
					type = "toggle",
					name = "Debug Mode",
					desc = "Enable or disable debug messages.",
					set = "SetDebug",
					get = "GetDebug",
					order = 2,
				},
				minimap = {
					type = "toggle",
					name = "Hide Minimap Icon",
					desc = "Show or hide the minimap icon.",
					set = "SetMinimapHidden",
					get = "GetMinimapHidden",
					order = 3,
				},
				guildOnly = {
					type = "toggle",
					name = "Guild Only",
					desc = "Only invite players from your guild.",
					set = function(info, val)
						AutoLayer.db.profile.guildOnly = val
					end,
					get = function(info)
						return AutoLayer.db.profile.guildOnly
					end,
					order = 4,
				},
			},
		},

		messagingSettings = {
			type = "group",
			name = "Messaging Settings",
			inline = true,
			order = 1,
			args = {
				triggers = {
					type = "input",
					name = "Invite Triggers",
					desc = "Comma-separated phrases to trigger inviting a player. Case insensitive",
					set = "SetTriggers",
					get = "GetTriggers",
					order = 1,
				},
				blacklist = {
					type = "input",
					name = "Blacklist",
					desc = "Comma-separated words to ignore messages containing them.",
					set = "SetBlacklist",
					get = "GetBlacklist",
					order = 2,
				},
				invertKeywords = {
					type = "input",
					name = "Invert Keywords",
					desc = "Comma-separated words to exclude specific layers.",
					set = "SetInvertKeywords",
					get = "GetInvertKeywords",
					order = 3,
				},
				channelFiltering = {
					type = "select",
					width = 1.2,
					name = "Filter Chat Channels",
					desc = "Select an option to perform inclusive or exclusive chat channel filtering.",
					values = {
						["none"] = "None",
						["inclusive"] = "Trigger only these channels",
						["exclusive"] = "Trigger all channels except",
					},
					set = "SetChannelFiltering",
					get = function(info)
						return AutoLayer.db.profile.channelFiltering
					end,
					order = 4,
				},
				filteredChannels = {
					type = "input",
					width = 1.8,
					name = "Channels names for filtering",
					desc = "Comma-separated channel names for filtering. * can be used as a wildcard",
					set = "SetFilteredChannels",
					get = function(info)
						return AutoLayer.db.profile.filteredChannels
					end,
					disabled = function()
						return AutoLayer.db.profile.channelFiltering == "none"
					end,
					order = 5,
				},
				inviteWhisper = {
					type = "toggle",
					name = "Whisper Invites",
					desc = "Send a whisper to players when inviting them.",
					set = function(info, val)
						AutoLayer.db.profile.inviteWhisper = val
					end,
					get = function(info)
						return AutoLayer.db.profile.inviteWhisper
					end,
					order = 6,
				},
				inviteWhisperTemplate = {
					type = "input",
					width = "double",
					name = "Whisper Template",
					desc = "Template for invite whispers. Use {layer} for layer number.",
					set = function(info, val)
						AutoLayer.db.profile.inviteWhisperTemplate = val
					end,
					get = function(info)
						return AutoLayer.db.profile.inviteWhisperTemplate
					end,
					validate = function(info, val)
						return util.CheckWhisperTemplateLength(val)
					end,
					order = 7,
				},
				inviteWhisperReminder = {
					type = "toggle",
					name = "Whisper Reminder Text",
					desc = "Send a reminder text to Leave Party after layer switch.",
					set = function(info, val)
						AutoLayer.db.profile.inviteWhisperReminder = val
					end,
					get = function(info)
						return AutoLayer.db.profile.inviteWhisperReminder
					end,
					order = 8,
				},
				inviteWhisperTemplateReminder = {
					type = "input",
					width = "double",
					name = "Whisper Template Second Line",
					desc = "Reminder to Leave Party after layer switch.",
					set = function(info, val)
						AutoLayer.db.profile.inviteWhisperTemplateReminder = val
					end,
					get = function(info)
						return AutoLayer.db.profile.inviteWhisperTemplateReminder
					end,
					validate = function(info, val)
						return util.CheckWhisperTemplateLength(val)
					end,
					order = 9,
				},
				ignorePrefixes = {
					type = "input",
					name = "Ignored Prefixes",
					desc = "Comma-separated message prefixes to ignore (match only at the start). Example: [NWB]",
					set = "SetIgnorePrefixes",
					get = "GetIgnorePrefixes",
					width = 1,
					order = 10,
				},
			},
		},

		soundAndBehavior = {
			type = "group",
			name = "Sound and Behavior",
			inline = true,
			order = 2,
			args = {
				mutesounds = {
					type = "toggle",
					name = "Mute Sounds",
					desc = "Mute party-related sounds while AutoLayer is active.",
					set = function(info, val)
						AutoLayer.db.profile.mutesounds = val
						AutoLayer:SyncRuntimeState()
					end,
					get = function(info)
						return AutoLayer.db.profile.mutesounds
					end,
					order = 1,
				},
				turnOffWhileRaidAssist = {
					type = "toggle",
					name = "Disable in Raid Assist",
					desc = "Turn off AutoLayer functionality when you are raid assist.",
					set = function(info, val)
						AutoLayer.db.profile.turnOffWhileRaidAssist = val
					end,
					get = function(info)
						return AutoLayer.db.profile.turnOffWhileRaidAssist
					end,
					order = 2,
				},
				autokick = {
					type = "toggle",
					name = "Auto-Kick on Full",
					desc = "|cffFF0000Requires manual interaction.|r Queues one offline/oldest candidate when the group is full.",
					set = function(info, val)
						AutoLayer.db.profile.autokick = val
					end,
					get = function(info)
						return AutoLayer.db.profile.autokick
					end,
					order = 3,
				},
				hideAutoWhispers = {
					type = "toggle",
					name = "Hide AddOn Whispers",
					desc = "Silence auto whispers sent out by AutoLayer",
					set = function(info, val)
						AutoLayer.db.profile.hideAutoWhispers = val
						AutoLayer:SyncRuntimeState()
					end,
					get = function(info)
						return AutoLayer.db.profile.hideAutoWhispers
					end,
					order = 4,
				},
				hideSystemGroupMessages = {
					type = "toggle",
					name = "Hide Group Notices",
					desc = 'Silence system group notices eg. "X has left the party"',
					set = function(info, val)
						AutoLayer.db.profile.hideSystemGroupMessages = val
						AutoLayer:SyncRuntimeState()
					end,
					get = function(info)
						return AutoLayer.db.profile.hideSystemGroupMessages
					end,
					order = 5,
				},
				layerSegments = {
					type = "toggle",
					name = addonTable.flavor == "bcc" and "Use Zone Filtering" or "Use Layer Segments",
					desc = addonTable.flavor == "bcc"
						and "Only invite players in the same zone."
						or "Only invite players in the same layer segment. (e.g. Azeroth, Outland). This avoids party members not layering due to being in a different area of the world that uses different layers.",
					set = function(info, val)
						AutoLayer.db.profile.layerSegments = val
					end,
					get = function(info)
						return AutoLayer.db.profile.layerSegments
					end,
					order = 6,
				},
				showLayerWarning = {
					type = "toggle",
					name = addonTable.flavor == "bcc" and "Layer Zone Warning" or "Layer Segment Warning",
					desc = addonTable.flavor == "bcc"
						and "Show a warning when joining a party in a different zone, while zone filtering is enabled."
						or "Show a warning when joining a party with a different layer segment, while the layer segment feature is enabled.",
					set = function(info, val)
						AutoLayer.db.profile.showLayerWarning = val
					end,
					get = function(info)
						return AutoLayer.db.profile.showLayerWarning
					end,
					disabled = function()
						return not AutoLayer.db.profile.layerSegments
					end,
					order = 7,
				},
				zoneMismatchWhisper = {
					type = "toggle",
					name = "Whisper on Zone Mismatch",
					desc = "Whisper a requester when zone filtering prevents an invite.",
					set = function(info, val)
						AutoLayer.db.profile.zoneMismatchWhisper = val
					end,
					get = function(info)
						return AutoLayer.db.profile.zoneMismatchWhisper
					end,
					order = 8,
					hidden = function()
						return addonTable.flavor ~= "bcc"
					end,
					disabled = function()
						return not AutoLayer.db.profile.layerSegments
					end,
				},
				lockdownRequestWarning = {
					type = "toggle",
					name = "Chat Lockdown Warning",
					desc = "Show an on-screen message (only visible to you) when a layer request is blocked because of a chat lockdown (e.g. in dungeons, raids, PvP or boss encounters).",
					set = function(info, val)
						AutoLayer.db.profile.lockdownRequestWarning = val
					end,
					get = function(info)
						return AutoLayer.db.profile.lockdownRequestWarning
					end,
					order = 9,
					hidden = function()
						return not compat.isForever
					end,
				},
				lockdownEndedMessage = {
					type = "toggle",
					name = "Chat Lockdown Over Message",
					desc = "Print a message in your chat (only visible to you) when a chat lockdown ends after a layer request was blocked by it.",
					set = function(info, val)
						AutoLayer.db.profile.lockdownEndedMessage = val
					end,
					get = function(info)
						return AutoLayer.db.profile.lockdownEndedMessage
					end,
					order = 10,
					hidden = function()
						return not compat.isForever
					end,
				},
			},
		},
		loot = {
			type = "group",
			name = "Loot Settings",
			inline = true,
			order = 3,
			args = {
				overrideLootSettings = {
					type = "toggle",
					name = "Override Loot Settings",
					desc = "Automatically set desired loot method and threshold when new players join the party.",
					set = function(info, val)
						AutoLayer.db.profile.overrideLootSettings = val
					end,
					get = function(info)
						return AutoLayer.db.profile.overrideLootSettings
					end,
					order = 1,
				},
				lootMethod = {
					type = "select",
					name = "Loot Method",
					desc = "Select the loot method to set when new players join the party.",
					values = {
						[0] = "Free For All",
						[1] = "Round Robin",
						[3] = "Group Loot",
						[4] = "Need Before Greed",
					},
					set = function(info, val)
						AutoLayer.db.profile.lootMethod = val
					end,
					get = function(info)
						return AutoLayer.db.profile.lootMethod
					end,
					order = 2,
				},
				lootThreshold = {
					type = "select",
					name = "Loot Threshold (for Group Loot)",
					desc = "Select the loot threshold to set when using group loot method.",
					values = {
						[2] = "|cff1EFF00Uncommon|r",
						[3] = "|cff0070DDRare|r",
						[4] = "|cffA335EEEpic|r",
					},
					set = function(info, val)
						AutoLayer.db.profile.lootThreshold = val
					end,
					get = function(info)
						return AutoLayer.db.profile.lootThreshold
					end,
					order = 3,
				},
			},
		},
	},
}
