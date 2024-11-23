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
end

function AutoLayer:HopGUI()
  if not is_closed then
    return
  end

  is_closed = false
  local frame = AceGUI:Create("Frame")
  frame:SetTitle("AutoLayer - Hopper")
  frame:SetWidth(350)
  frame:SetHeight(250)
  frame:SetStatusText("Beta feature")
  frame:SetLayout("Flow")

  -- Set a background color and padding
  frame:SetCallback("OnClose", function()
    is_closed = true
    selected_layers = {}
  end)

  -- Check if NovaWorldBuffs is installed
  if addonTable.NWB == nil then
    local desc = AceGUI:Create("Label")
    desc:SetText("You need to have the NovaWorldBuffs addon installed to use this feature.")
    desc:SetFullWidth(true)
    frame:AddChild(desc)
    return
  end

  -- Create a header for clarity
  local header = AceGUI:Create("Label")
  header:SetText("Select Layers to Hop to:")
  header:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
  header:SetFullWidth(true)
  header:SetJustifyH("CENTER")
  frame:AddChild(header)

  -- Multi-combo box for selecting layers
  local layer = AceGUI:Create("Dropdown")
  layer:SetLabel("Available Layers")
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

  -- Create send button
  local send = AceGUI:Create("Button")
  send:SetText("Send Layer Request")
  send:SetWidth(160)
  send:SetCallback("OnClick", function()
    AutoLayer:SendLayerRequest()
  end)
  send:SetDisabled(true)

  layer:SetList(layers)
  layer:SetCallback("OnValueChanged", function(_, _, v)
    local found = false
    for i, selected_layer in ipairs(selected_layers) do
      if selected_layer == v then
        table.remove(selected_layers, i)
        found = true
        break
      end
    end
    if not found then
      table.insert(selected_layers, v)
    end

    -- Enable or disable the Send button
    if #selected_layers > 0 then
      send:SetDisabled(false)
    else
      send:SetDisabled(true)
    end
  end)

  -- Add components to frame
  frame:AddChild(layer)
  frame:AddChild(send)
end
