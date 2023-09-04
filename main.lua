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
        enabled = {
            type = 'toggle',
            name = 'Enabled',
            desc = 'Enable/Disable AutoLayer',
            set = 'SetEnabled',
            get = 'GetEnabled',
            order = 0,
        },

        debug = {
            type = 'toggle',
            name = 'Debug',
            desc = 'Enable/Disable debug messages',
            set = 'SetDebug',
            get = 'GetDebug',
            order = 1,
        },

        triggers = {
            type = 'input',
            name = 'Triggers',
            desc = 'The triggers that will cause the invite message to be sent, seperated by commas',
            set = 'SetTriggers',
            get = 'GetTriggers',
        },

        autokick = {
            type = 'toggle',
            name = 'Auto kick',
            desc = 'Enable/Disable kicks the last member out if the group is full',
            set = function(info, val)
                AutoLayer.db.profile.autokick = val
            end,
            get = function(info)
                return AutoLayer.db.profile.autokick
            end,
            order = 2,
        },

        blacklist = {
            type = 'input',
            name = 'Blacklist',
            desc = 'The opposite of triggers, if it matches those words in a message it wont invite, seperated by commas',
            set = 'SetBlacklist',
            get = 'GetBlacklist',
        },

        minimap = {
            type = 'toggle',
            name = 'Hide minimap icon',
            desc = 'Hide/Show the minimap icon',
            order = 4,
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
        },
    }
}

local defaults = {
    profile = {
        enabled = true,
        debug = false,
        triggers = "layer, Layer",
        sendMessage = false,
        blacklist = "wts, wtb, guild, lf, lfm, player, enchant",
        layered = 0,
        minimap = {
            hide = false,
        },
        autokick = true
    }
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

    ---@diagnostic disable-next-line: missing-fields
    local bunnyLDB = LibStub("LibDataBroker-1.1"):NewDataObject("AutoLayer", {
        type = "data source",
        text = "AutoLayer",
        icon = icon,
        OnClick = function()
            AutoLayer:Toggle()
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("AutoLayer")
            tooltip:AddLine("Click to toggle AutoLayer")
            tooltip:AddLine("Layered " .. self.db.profile.layered .. " players")

            if addonTable.NWB ~= nil then
                if addonTable.NWB.currentLayer == 0 then
                    tooltip:AddLine("Current layer: unknown, target an NPC")
                else
                    tooltip:AddLine("Current layer: " .. addonTable.NWB.currentLayer)
                end
            end
        end,
    })

    addonTable.bunnyLDB = bunnyLDB

    minimap_icon:Register("AutoLayer", bunnyLDB, self.db.profile.minimap)
end

function AutoLayer:DebugPrint(...)
    if self.db.profile.debug then
        self:Print(...)
    end
end
