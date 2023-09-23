local addonName, addonTable = ...
addonTable.LibDeflate = LibStub("LibDeflate")
addonTable.LibSerialize = LibStub("LibSerialize")

addonTable.send_queue = {}
addonTable.receive_queue = {}

local selected_layers = {}
local is_closed = true

function AutoLayer:SendLayerRequest()
  local res = "LFL "
  res = res .. table.concat(selected_layers, ",")

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
  -- make frame as small as possible
  frame:SetWidth(300)
  AutoLayer:DebugPrint(res)
  frame:SetHeight(200)
  frame:SetStatusText("Beta feature")

  if addonTable.NWB == nil then
    -- add text to frame
    local desc = AceGUI:Create("Label")
    desc:SetText("You need to have the NovaWorldBuffs addon installed to use this feature.")
    frame:AddChild(desc)
    return
  end

  frame:SetCallback("OnClose", function()
    is_closed = true
  end)

  -- multi combo box
  local layer = AceGUI:Create("Dropdown")
  layer:SetLabel("Select Layer")
  layer:SetMultiselect(true)

  local count = 0;
  local layers = {}
  for _ in pairs(addonTable.NWB.data.layers) do
    count = count + 1
    table.insert(layers, tostring(count))
  end

  for _, selected_layer in ipairs(selected_layers) do
    layer:SetValue(selected_layer)
  end

  -- add send button under it
  local send = AceGUI:Create("Button")
  send:SetText("Send")
  send:SetWidth(100)
  send:SetCallback("OnClick", function()
    AutoLayer:SendLayerRequest()
  end)

  send:SetDisabled(true)

  layer:SetList(layers)
  layer:SetCallback("OnValueChanged", function(_, _, v)
    for i, selected_layer in ipairs(selected_layers) do
      if selected_layer == v then
        table.remove(selected_layers, i)
        if #selected_layers == 0 then
          send:SetDisabled(true)
        end
        return
      end
    end
    send:SetDisabled(false)
    table.insert(selected_layers, v)
  end)

  local desc = AceGUI:Create("Label")
  desc:SetText(
    "This feature is still in beta, feedback is appreciated.\n This will send a message into the lookingforgroup channel where autolayer users will respond accordingly.\n|cFF00FF00This should now be fixed!|r");

  frame:AddChild(layer)
  frame:AddChild(send)
  frame:AddChild(desc)
end
