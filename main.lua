---@diagnostic disable: inject-field

local addonName, addonTable = ...;

AutoLayer = LibStub("AceAddon-3.0"):NewAddon("AutoLayer", "AceConsole-3.0", "AceEvent-3.0")
AceGUI = LibStub("AceGUI-3.0")
local minimap_icon = LibStub("LibDBIcon-1.0")

local options = {
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
                    type = 'toggle',
                    name = 'Enabled',
                    desc = 'Enable or disable AutoLayer.',
                    set = 'SetEnabled',
                    get = 'GetEnabled',
                    order = 1,
                },
                debug = {
                    type = 'toggle',
                    name = 'Debug Mode',
                    desc = 'Enable or disable debug messages.',
                    set = 'SetDebug',
                    get = 'GetDebug',
                    order = 2,
                },
                minimap = {
                    type = 'toggle',
                    name = 'Hide Minimap Icon',
                    desc = 'Show or hide the minimap icon.',
                    set = function(info, val)
                        AutoLayer.db.profile.minimap.hide = val
                        if val then
                            minimap_icon:Hide("AutoLayer")
                        else
                            minimap_icon:Show("AutoLayer")
                        end
                    end,
                    get = function(info)
                        return AutoLayer.db.profile.minimap.hide
                    end,
                    order = 3,
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
                    type = 'input',
                    name = 'Invite Triggers',
                    desc = 'Comma-separated words to trigger inviting a player.',
                    set = 'SetTriggers',
                    get = 'GetTriggers',
                    order = 1,
                },
                blacklist = {
                    type = 'input',
                    name = 'Blacklist',
                    desc = 'Comma-separated words to ignore messages containing them.',
                    set = 'SetBlacklist',
                    get = 'GetBlacklist',
                    order = 2,
                },
                invertKeywords = {
                    type = 'input',
                    name = 'Invert Keywords',
                    desc = 'Comma-separated words to exclude specific layers.',
                    set = 'SetInvertKeywords',
                    get = 'GetInvertKeywords',
                    order = 3,
                },
                inviteWhisper = {
                    type = 'toggle',
                    name = 'Whisper Invites',
                    desc = 'Send a whisper to players when inviting them.',
                    set = function(info, val)
                        AutoLayer.db.profile.inviteWhisper = val
                    end,
                    get = function(info)
                        return AutoLayer.db.profile.inviteWhisper
                    end,
                    order = 4,
                },
                inviteWhisperTemplate = {
                    type = 'input',
                    name = 'Whisper Template',
                    desc = 'Template for invite whispers. Use %s for layer number.',
                    set = function(info, val)
                        AutoLayer.db.profile.inviteWhisperTemplate = val
                    end,
                    get = function(info)
                        return AutoLayer.db.profile.inviteWhisperTemplate
                    end,
                    order = 5,
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
                    type = 'toggle',
                    name = 'Mute Sounds',
                    desc = 'Mute party-related sounds while AutoLayer is active.',
                    set = function(info, val)
                        AutoLayer.db.profile.mutesounds = val
                        if val then
                            AutoLayer:MuteAnnoyingSounds()
                        else
                            AutoLayer:UnmuteAnnoyingSounds()
                        end
                    end,
                    get = function(info)
                        return AutoLayer.db.profile.mutesounds
                    end,
                    order = 1,
                },
                turnOffWhileRaidAssist = {
                    type = 'toggle',
                    name = 'Disable in Raid Assist',
                    desc = 'Turn off AutoLayer functionality when you are raid assist.',
                    set = function(info, val)
                        AutoLayer.db.profile.turnOffWhileRaidAssist = val
                    end,
                    get = function(info)
                        return AutoLayer.db.profile.turnOffWhileRaidAssist
                    end,
                    order = 2,
                },
                autokick = {
                    type = 'toggle',
                    name = 'Auto-Kick on Full',
                    desc = '|cffFF0000Requires manual interaction.|r Kicks the last member if the group is full.',
                    set = function(info, val)
                        AutoLayer.db.profile.autokick = val
                    end,
                    get = function(info)
                        return AutoLayer.db.profile.autokick
                    end,
                    order = 3,
                },
            },
        },
    },
}

local defaults = {
    profile = {
        enabled = true,
        debug = false,
        triggers = "layer",
        blacklist = "wts,wtb,lfm,lfg,ashen,auto inv,autoinv,pst for,guild,raid,enchant,player,what layer,which layer",
        invertKeywords = "not,off,except,but,out,other than,besides,apart from",
        inviteWhisper = true,
        inviteWhisperTemplate = "Inviting you to layer %s...",
        mutesounds = true,
        layered = 0,
        minimap = {
            hide = false,
        },
        autokick = false,
        turnOffWhileRaidAssist = true,
    }
}

local annoyingSounds = {
	567490, -- invite sent
	567451, -- invite accepted
	539839, 540356, 540778, 540941, 540984, 542585, 542862, 540287, 540579, 541222, 542952, 542659, 539901, 541298, 543146, 543174 -- "they can't join our group"
}


---@diagnostic disable-next-line: duplicate-set-field
function AutoLayer:OnInitialize()
    LibStub("AceConfig-3.0"):RegisterOptionsTable("AutoLayer", options)
    self.db = LibStub("AceDB-3.0"):New("AutoLayerDB", defaults)
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("AutoLayer", "AutoLayer")
    local icon = ""

    if self.db.profile.enabled then
        icon = "Interface\\Icons\\INV_Bijou_Green"
    else
        icon = "Interface\\Icons\\INV_Bijou_Red"
    end

    if self.db.profile.mutesounds then
        self:MuteAnnoyingSounds()
    end

    ---@diagnostic disable-next-line: missing-fields
    local bunnyLDB = LibStub("LibDataBroker-1.1"):NewDataObject("AutoLayer", {
        type = "data source",
        text = "AutoLayer",
        icon = icon,

        -- listen for right click
        OnClick = function(self, button)
            if button == "LeftButton" then
                AutoLayer:Toggle()
            end

            if button == "RightButton" then
                AutoLayer:HopGUI()
            end
        end,

        onMouseUp = function(self, button)
            print(button)
            AutoLayer:Toggle()
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("AutoLayer")
            tooltip:AddLine("Left-click to toggle AutoLayer")
            tooltip:AddLine("Right-click to hop layers")
            tooltip:AddLine("Layered " .. self.db.profile.layered .. " players")
            
            if addonTable.NWB ~= nil then
                local currentLayer = AutoLayer:getCurrentLayer()
                if currentLayer == 0 then
                    tooltip:AddLine("Current layer: unknown, target an NPC")
                else
                    tooltip:AddLine("Current layer: " .. currentLayer)
                end
            end
        end,
    })

    addonTable.bunnyLDB = bunnyLDB

    local frame = CreateFrame("Frame", "MuteSoundFrame")
    frame.MuteSoundFile = MuteSoundFile
    minimap_icon:Register("AutoLayer", bunnyLDB, self.db.profile.minimap)
end

function AutoLayer:MuteAnnoyingSounds()
	for _, soundFileId in pairs(annoyingSounds) do
		MuteSoundFile(soundFileId)
	end
end

function AutoLayer:UnmuteAnnoyingSounds()
	for _, soundFileId in pairs(annoyingSounds) do
		UnmuteSoundFile(soundFileId)
	end
end

function AutoLayer:DebugPrint(...)
    if self.db.profile.debug then
        self:Print(...)
    end
end
