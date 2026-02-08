local addonName, addonTable = ...
addonTable.LibDeflate = LibStub("LibDeflate")
addonTable.LibSerialize = LibStub("LibSerialize")

addonTable.send_queue = {}
addonTable.receive_queue = {}

local selected_layers = {}
local is_closed = true

function AutoLayer:SendLayerRequest()
	local res = "inv layer "
	res = res .. table.concat(selected_layers, ",")
	LeaveParty()
	table.insert(addonTable.send_queue, res)
	AutoLayer:DebugPrint("Sending layer request: " .. res)
	ProccessQueue()
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
		self:DebugPrint("Received slash command request for all layers except current ( layer", NWB_CurrentLayer, ").")

		local count = 0
		for _ in pairs(addonTable.NWB.data.layers) do
			count = count + 1
			if count ~= NWB_CurrentLayer then
				table.insert(selected_layers, tostring(count))
			end
		end
	end

	if #selected_layers > 0 then
		AutoLayer:SendLayerRequest()
	end
end

function AutoLayer:HopGUI()
	if not is_closed then
		return
	end

	is_closed = false
	local frame = AceGUI:Create("Frame")
	frame:SetTitle("AutoLayer - Hopper")
	frame:SetWidth(400)
	frame:SetHeight(250)
	frame:SetStatusText("Beta feature")
	frame:SetLayout("Flow")

	-- Register the frame so it closes when pressing ESC
	_G["AutoLayerHopperFrame"] = frame.frame
	tinsert(UISpecialFrames, "AutoLayerHopperFrame")

	-- Set a background color and padding
	frame:SetCallback("OnClose", function()
		is_closed = true
		selected_layers = {}
	end)

	-- Create send button
	local send = AceGUI:Create("Button")
	send:SetText("Send Layer Request")
	send:SetWidth(160)
	send:SetCallback("OnClick", function()
		AutoLayer:SendLayerRequest()
	end)

	-- Check if NovaWorldBuffs is installed
	if addonTable.NWB == nil then
		local desc = AceGUI:Create("Label")
		desc:SetText(
			"Please consider installing NovaWorldBuffs addon, it allows you to discover current layer and select layers to hop to."
		)
		desc:SetColor(1, 0, 0)
		desc:SetFullWidth(true)
		frame:AddChild(desc)
	else
		-- Create a header for clarity
		local header = AceGUI:Create("Label")
		header:SetText("Select Layers to Hop to:")
		header:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
		header:SetFullWidth(true)
		header:SetJustifyH("CENTER")
		frame:AddChild(header)

		send:SetDisabled(true)

		local currentLayerGroup = AceGUI:Create("InlineGroup")
		currentLayerGroup:SetFullWidth(true)
		currentLayerGroup:SetLayout("Flow")

		local currentLayerDescriptionLabel = AceGUI:Create("Label")
		currentLayerDescriptionLabel:SetText("Current Layer:")
		currentLayerDescriptionLabel:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
		currentLayerDescriptionLabel:SetWidth(120)
		currentLayerGroup:AddChild(currentLayerDescriptionLabel)

		local currentLayerLabel = AceGUI:Create("Label")
		currentLayerLabel:SetFontObject(GameFontHighlightSmall)
		currentLayerLabel:SetWidth(170)
		currentLayerGroup:AddChild(currentLayerLabel)

		frame:AddChild(currentLayerGroup)

		-- Multi-combo box for selecting layers
		local layer = AceGUI:Create("Dropdown")
		layer:SetLabel("Request Layers:")
		layer:SetFullWidth(true)
		layer:SetMultiselect(true)
		layer:SetWidth(300)

		local count = 0
		local layers = {}
		for _ in pairs(addonTable.NWB.data.layers) do
			count = count + 1
			table.insert(layers, tostring(count))
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
			if #selected_layers > 0 then
				send:SetDisabled(false)
			else
				send:SetDisabled(true)
			end
		end

		layer:SetCallback("OnValueChanged", OnValueChanged)

		local currentLayer = NWB_CurrentLayer

		if currentLayer and currentLayer > 0 then
			-- autoselect all layers except the layer we're currently on
			for i in ipairs(layers) do
				if i ~= currentLayer then
					layer:SetItemValue(i, true)
					OnValueChanged(nil, nil, i, true) -- for god known reasons SetItemValue does not trigger OnValueChanged event so we have to do that manually :/
				end
			end
		end

		local lastKnownLayer = nil
		local function UpdateLayerText() -- while UI open, constantly monitors changes to 'NWB_CurrentLayer' and updates UI
			if is_closed then
				return
			end

			local currentLayer = NWB_CurrentLayer

			if currentLayer and lastKnownLayer ~= currentLayer then
				if currentLayer > 0 then
					for i, widget in layer.pullout:IterateItems() do
						if widget.userdata.value == lastKnownLayer then
							widget:SetText(lastKnownLayer)
							layer:SetMultiselect(layer:GetMultiselect()) -- the most decent way to trigger dropdown text update
						elseif widget.userdata.value == currentLayer then
							widget:SetText(currentLayer .. " (current)")
							layer:SetMultiselect(layer:GetMultiselect()) -- the most decent way to trigger dropdown text update
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

	frame:AddChild(send)
end
