local addonName, addonTable = ...
addonTable.LibDeflate = LibStub("LibDeflate")
addonTable.LibSerialize = LibStub("LibSerialize")

addonTable.send_queue = {}
addonTable.receive_queue = {}

local selected_layers = {}
local is_closed = true
local hopperSessionID = {}

-- Layer request anti-spam cooldown
local LAYER_REQUEST_COOLDOWN = 10
local lastLayerRequestTime = 0

function AutoLayer:SendLayerRequest()
	-- 10s anti-spam cooldown (applies to GUI button and slash command)
	local now = GetTime and GetTime() or time()
	if lastLayerRequestTime and (now - lastLayerRequestTime) < LAYER_REQUEST_COOLDOWN then
		local remaining = math.ceil(LAYER_REQUEST_COOLDOWN - (now - lastLayerRequestTime))
		self:Print(("Layer request is on cooldown (%ds)."):format(remaining))
		return
	end
	lastLayerRequestTime = now

	local res = "inv layer "
	res = res .. table.concat(selected_layers, ",")

	-- Send hidden pool metadata to all active layer channels so recipients can enforce pool filtering
	local pool = self.GetLayerPoolKey and self:GetLayerPoolKey() or "AZEROTH"
	local channels = addonTable.layerChannels or {}
	local sentPoolMeta = false
	for _, channelName in ipairs(channels) do
		local channel_num = GetChannelName(channelName)
		if channel_num and channel_num > 0 then
			if C_ChatInfo and C_ChatInfo.SendAddonMessage then
				C_ChatInfo.SendAddonMessage("ALP", "POOL|" .. pool, "CHANNEL", channel_num)
				sentPoolMeta = true
			elseif SendAddonMessage then
				SendAddonMessage("ALP", "POOL|" .. pool, "CHANNEL", channel_num)
				sentPoolMeta = true
			end
		end
	end

	-- Fallback: if dynamic channel list is unavailable/not yet joined, send metadata via current active channel
	if not sentPoolMeta and addonTable.activeLayerChannel then
		local activeChannelNum = GetChannelName(addonTable.activeLayerChannel)
		if activeChannelNum and activeChannelNum > 0 then
			if C_ChatInfo and C_ChatInfo.SendAddonMessage then
				C_ChatInfo.SendAddonMessage("ALP", "POOL|" .. pool, "CHANNEL", activeChannelNum)
				sentPoolMeta = true
			elseif SendAddonMessage then
				SendAddonMessage("ALP", "POOL|" .. pool, "CHANNEL", activeChannelNum)
				sentPoolMeta = true
			end
		end
	end
	self:DebugPrint("[POOL_META_SEND]", "pool=", pool)

	LeaveParty()
	table.insert(addonTable.send_queue, res)
	self:Print("Layer request sent.")
	AutoLayer:DebugPrint("Sending layer request: " .. res)
	ProcessQueue()
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

		if addonTable.NWB == nil then
			self:Print("Cannot auto-select layers: NovaWorldBuffs is not installed. Specify layers manually, e.g. /autolayer req 1,2,3")
			return
		end

		local count = 0
		local currentLayerNum = tonumber(NWB_CurrentLayer)
		for _ in pairs(addonTable.NWB.data.layers) do
			count = count + 1
			if count ~= currentLayerNum then
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
		hopperSessionID = {} -- invalidate any running UpdateLayerText timer loops
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

		layer:SetList(layers)

		-- Restore previously selected values (must be after SetList, which resets item state)
		for _, selected_layer in ipairs(selected_layers) do
			layer:SetItemValue(selected_layer, true)
		end

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

		local currentLayer = tonumber(NWB_CurrentLayer)

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
		hopperSessionID = {} -- unique table reference per GUI open; used to cancel stale timer loops
		local function UpdateLayerText() -- while UI open, constantly monitors changes to 'NWB_CurrentLayer' and updates UI
			if is_closed then
				return -- session ended, stop the loop
			end

			local currentLayer = tonumber(NWB_CurrentLayer)

			-- If the GUI was opened before we knew our layer, auto-select once the layer becomes known.
			-- This prevents the Send button from staying disabled until the window is reopened.
			if currentLayer and currentLayer > 0 and (not lastKnownLayer or lastKnownLayer <= 0) and #selected_layers == 0 then
				for i in ipairs(layers) do
					if i ~= currentLayer then
						layer:SetItemValue(i, true)
						OnValueChanged(nil, nil, i, true) -- SetItemValue doesn't fire callbacks
					end
				end
			end

			if currentLayer and lastKnownLayer ~= currentLayer then
				if currentLayer > 0 then
					if layer.pullout then
						for i, widget in layer.pullout:IterateItems() do
							if widget.userdata.value == lastKnownLayer then
								widget:SetText(lastKnownLayer)
								layer:SetMultiselect(layer:GetMultiselect()) -- the most decent way to trigger dropdown text update
							elseif widget.userdata.value == currentLayer then
								widget:SetText(currentLayer .. " (current)")
								layer:SetMultiselect(layer:GetMultiselect()) -- the most decent way to trigger dropdown text update
							end
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

			local capturedSession = hopperSessionID
			C_Timer.After(0.5, function()
				if capturedSession ~= hopperSessionID then return end -- stale session, discard
				UpdateLayerText()
			end)
		end
		UpdateLayerText()

		frame:AddChild(layer)
	end

	frame:AddChild(send)
end
