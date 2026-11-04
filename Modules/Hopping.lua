local addonName, addonTable = ...
addonTable.LibDeflate = LibStub("LibDeflate")

addonTable.send_queue = {}

local selected_layers = {}
local is_closed = true
local send

local HOPPER_FRAME_GLOBAL = "AutoLayerHopperFrame"
local hopperFrameListed = false

local lockdownWatcher

-- A layer request cannot work during a chat lockdown, so tell the player why. Both messages are local only.
function AutoLayer:NotifyChatLockdownBlockedRequest()
	if self.db.profile.lockdownRequestWarning and UIErrorsFrame then
		UIErrorsFrame:AddMessage(
			"AutoLayer: layer requests are unavailable during a chat lockdown (dungeon, raid, PvP or encounter).",
			1, 0.1, 0.1
		)
	end

	if self.db.profile.lockdownEndedMessage and not lockdownWatcher then
		lockdownWatcher = C_Timer.NewTicker(1, function(ticker)
			if addonTable.compat.InChatLockdown() then
				return
			end
			ticker:Cancel()
			lockdownWatcher = nil
			if AutoLayer.db.profile.lockdownEndedMessage then
				AutoLayer:Print("The chat lockdown is over, you can request a layer again.")
			end
		end)
	end
end

function AutoLayer:SendLayerRequest()
	if addonTable.compat.InChatLockdown() then
		self:DebugPrint("Chat messaging lockdown: layer request blocked")
		self:NotifyChatLockdownBlockedRequest()
		return
	end

	local res = ""
	local pendingLayerHop

	if addonTable.flavor == "bcc" then
		local scopeID = self:GetLayerZone()
		res = self:BuildLayerRequestHeader(scopeID) .. " "
		pendingLayerHop = {
			scopeID = scopeID,
			sentAt = time(),
		}
	elseif self.db.profile.layerSegments and addonTable.currentLayerSegment then
		self:DebugPrint("Using layer segment:", addonTable.currentLayerSegment)
		res = "<" .. addonTable.currentLayerSegment .. "> "
	end

	res = res .. "inv layer "
	res = res .. table.concat(selected_layers, ",")
	addonTable.compat.LeaveParty()
	table.insert(addonTable.send_queue, res)
	if pendingLayerHop then
		addonTable.pendingLayerHop = pendingLayerHop
		C_Timer.After(300, function()
			if addonTable.pendingLayerHop == pendingLayerHop then
				addonTable.pendingLayerHop = nil
			end
		end)
	end
	AutoLayer:DebugPrint("Sending layer request: " .. res)
	-- Auto-kick stays a manual action: it drains when the player sends a request, never on a timer.
	AutoLayer:HandleAutoKick()
	addonTable.ProcessQueue()

	-- Disable the send button to avoid the user from spam clicking it while the request is being processed.
	-- The button only exists while the hopper GUI is open, so /autolayer req must work without it.
	if send then
		send:SetDisabled(true)
		C_Timer.After(10, function()
			if send then
				send:SetDisabled(false)
			end
		end)
	end
end

function AutoLayer:SlashCommandRequest(input)
	if not is_closed then
		return self:Print("Hopper GUI is already open. Use either the GUI or slash commands, not both.")
	end

	selected_layers = {}
	local slash_layers = self:GetArgs(input, 1, 5)

	if slash_layers and slash_layers ~= "" then
		self:DebugPrint("Received slash command request for layers:", slash_layers)

		for layer in string.gmatch(slash_layers, '(%d+)') do
			table.insert(selected_layers, layer)
		end

		if #selected_layers == 0 then
			self:Print("No valid layers specified in the request. Use a comma-separated list of layer numbers. For example: /autolayer req 1,2,3")
			return
		end
	else
		local currentLayer = AutoLayer:getCurrentLayer()
		local nwbData = addonTable.NWB and addonTable.NWB.data
		local nwbLayers = nwbData and nwbData.layers or {}

		local layerNumbers = {}
		for layerNumber in pairs(nwbLayers) do
			layerNumbers[#layerNumbers + 1] = layerNumber
		end
		table.sort(layerNumbers)

		if currentLayer and currentLayer > 0 and #layerNumbers > 0 then
			self:DebugPrint("Received slash command request for all layers except current ( layer", currentLayer, ").")
			for _, layerNumber in ipairs(layerNumbers) do
				if layerNumber ~= currentLayer then
					table.insert(selected_layers, tostring(layerNumber))
				end
			end
		else
			self:DebugPrint("Received slash command request for all layers except current, but current layer is unknown. Requesting any layer.")
		end
	end

	AutoLayer:SendLayerRequest()
end

function AutoLayer:HopGUI()
	if not is_closed then
		return
	end

	is_closed = false
	local frame = addonTable.AceGUI:Create("Frame")
	frame:SetTitle("AutoLayer - Hopper")
	frame:SetWidth(400)
	frame:SetHeight(250)
	frame:SetLayout("Flow")

	-- Register the frame so it closes when pressing ESC. The global alias is re-pointed on
	-- every open, but the UISpecialFrames entry itself is only added once.
	_G[HOPPER_FRAME_GLOBAL] = frame.frame
	if not hopperFrameListed then
		tinsert(UISpecialFrames, HOPPER_FRAME_GLOBAL)
		hopperFrameListed = true
	end

	frame:SetCallback("OnClose", function(widget)
		is_closed = true
		selected_layers = {}
		send = nil
		if _G[HOPPER_FRAME_GLOBAL] == widget.frame then
			_G[HOPPER_FRAME_GLOBAL] = nil
		end
		-- Release the widget instead of leaking a new AceGUI frame on every open
		widget:Release()
	end)

	-- Create send button
	send = addonTable.AceGUI:Create("Button")
	send:SetText("Send Layer Request")
	send:SetWidth(160)
	send:SetCallback("OnClick", function()
		AutoLayer:SendLayerRequest()
	end)

	-- Check if NovaWorldBuffs is installed
	if addonTable.NWB == nil then
		local desc = addonTable.AceGUI:Create("Label")
		desc:SetText(
			"Please consider installing NovaWorldBuffs addon, it allows you to discover current layer and select layers to hop to."
		)
		desc:SetColor(1, 0, 0)
		desc:SetFullWidth(true)
		frame:AddChild(desc)
	else
		-- Create a header for clarity
		local header = addonTable.AceGUI:Create("Label")
		header:SetText("Select Layers to Hop to:")
		header:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
		header:SetFullWidth(true)
		header:SetJustifyH("CENTER")
		frame:AddChild(header)

		local currentLayerGroup = addonTable.AceGUI:Create("InlineGroup")
		currentLayerGroup:SetFullWidth(true)
		currentLayerGroup:SetLayout("Flow")

		local currentLayerDescriptionLabel = addonTable.AceGUI:Create("Label")
		currentLayerDescriptionLabel:SetText("Current Layer:")
		currentLayerDescriptionLabel:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
		currentLayerDescriptionLabel:SetWidth(120)
		currentLayerGroup:AddChild(currentLayerDescriptionLabel)

		local currentLayerLabel = addonTable.AceGUI:Create("Label")
		currentLayerLabel:SetFontObject(GameFontHighlightSmall)
		currentLayerLabel:SetWidth(170)
		currentLayerGroup:AddChild(currentLayerLabel)

		frame:AddChild(currentLayerGroup)

		-- Multi-combo box for selecting layers
		local layer = addonTable.AceGUI:Create("Dropdown")
		layer:SetLabel("Request Layers:")
		layer:SetFullWidth(true)
		layer:SetMultiselect(true)
		layer:SetWidth(300)

		local nwbData = addonTable.NWB and addonTable.NWB.data
		local nwbLayers = nwbData and nwbData.layers or {}

		local layerNumbers = {}
		for layerNumber in pairs(nwbLayers) do
			layerNumbers[#layerNumbers + 1] = layerNumber
		end
		table.sort(layerNumbers)

		local layers = {}
		for _, layerNumber in ipairs(layerNumbers) do
			layers[#layers + 1] = tostring(layerNumber)
		end

		-- Set previously selected values
		for _, selected_layer in ipairs(selected_layers) do
			layer:SetValue(selected_layer)
		end

		layer:SetList(layers)

		local function OnValueChanged(_, _, v, checked)
			local found = false
			for i, selected_layer in ipairs(selected_layers) do
				if selected_layer == v then
					if not checked then
						table.remove(selected_layers, i)
					end
					found = true
					break
				end
			end
			if checked and not found then
				table.insert(selected_layers, v)
			end

			-- Enable or disable the Send button
			if send then
				if #selected_layers > 0 then
					send:SetText("Send Layer Request")
				else
					send:SetText("Request Any Layer")
				end
			end
		end

		layer:SetCallback("OnValueChanged", OnValueChanged)

		local currentLayer = AutoLayer:getCurrentLayer()

		if currentLayer and currentLayer > 0 then
			-- autoselect all layers except the layer we're currently on
			for index, layerNumber in ipairs(layers) do
				if tonumber(layerNumber) ~= currentLayer then
					layer:SetItemValue(index, true)
					-- SetItemValue does not fire OnValueChanged, so the selection list is updated manually
					OnValueChanged(nil, nil, layerNumber, true)
				end
			end
		end

		local lastKnownLayer = nil
		local function UpdateLayerText() -- while UI open, monitors changes to 'NWB_CurrentLayer' and updates UI
			if is_closed then
				return
			end

			local currentLayer = AutoLayer:getCurrentLayer()

			if lastKnownLayer ~= currentLayer then
				if currentLayer and currentLayer > 0 then
					for _, widget in layer.pullout:IterateItems() do
						local itemLayer = tonumber(widget.userdata.value)
						if itemLayer == currentLayer then
							widget:SetText(widget.userdata.value .. " (current)")
							layer:SetMultiselect(layer:GetMultiselect()) -- the most decent way to trigger dropdown text update
						elseif itemLayer == lastKnownLayer then
							widget:SetText(widget.userdata.value)
							layer:SetMultiselect(layer:GetMultiselect())
						end
					end

					currentLayerLabel:SetText(currentLayer)
					currentLayerLabel:SetColor(0, 1, 0)
				else
					currentLayerLabel:SetText("Unknown (try to target an NPC)")
					currentLayerLabel:SetColor(1, 0, 0)
				end

				lastKnownLayer = currentLayer
			end

			C_Timer.After(0.5, UpdateLayerText)
		end
		UpdateLayerText()

		frame:AddChild(layer)
	end

	if #selected_layers == 0 then
		send:SetText("Request Any Layer")
	end
	frame:AddChild(send)

	-- Add a label explaining there is a cooldown on layering
	local cooldownLabel = addonTable.AceGUI:Create("Label")
	cooldownLabel:SetText("|cffff0000Note:|r Blizzard enforces an increasing cooldown on layering.\nThe more you attempt to layer, the longer it takes each time.|r")
	cooldownLabel:SetFullWidth(true)
	frame:AddChild(cooldownLabel)
end
