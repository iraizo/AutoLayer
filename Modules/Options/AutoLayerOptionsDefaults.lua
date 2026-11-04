local _, addonTable = ...

--- Default profile values. Existing profiles get missing keys on load (AceDB copyDefaults);
--- changed values are handled by migration.lua instead.
addonTable.defaults = {
	profile = {
		enabled = true,
		debug = false,
		triggers = "layer",
		ignorePrefixes = "[NWB]",
		blacklist = "wts,wtb,lfm,lfg,ashen,auto inv,autoinv,pst for,guild,raid,enchant,player,what layer,which layer,WorldBuffs",
		invertKeywords = "not,off,except,but,out,other than,besides,apart from",
		channelFiltering = "none",
		inviteWhisper = true,
		inviteWhisperTemplate = "Inviting you to layer {layer}...",
		inviteWhisperReminder = true,
		inviteWhisperTemplateReminder = "Please Leave Party after layer switch",
		mutesounds = true,
		guildOnly = false,
		hideAutoWhispers = true,
		hideSystemGroupMessages = true,
		lockdownRequestWarning = true,
		lockdownEndedMessage = true,
		overrideLootSettings = false,
		lootMethod = 0,
		lootThreshold = 2,
		layered = 0,
		minimap = {
			hide = false,
		},
		autokick = false,
		turnOffWhileRaidAssist = true,
		layerSegments = true,
		zoneMismatchWhisper = false,
		showLayerWarning = true,
		migrationVersion = 0,
	},
}
