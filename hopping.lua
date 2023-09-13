local addonName, addonTable = ...
addonTable.LibDeflate = LibStub("LibDeflate")
addonTable.LibSerialize = LibStub("LibSerialize")

addonTable.send_queue = {}
addonTable.receive_queue = {}

local selected_layers = {}
local is_closed = true

function AutoLayer:SendLayerRequest()
  local compressed = addonTable.LibDeflate:CompressDeflate(addonTable.LibSerialize:Serialize(selected_layers))
  -- if anyone knows how to make this UTF-8 compliant (any other encoding func, this would be helpful)
  local encoded = addonTable.LibDeflate:EncodeForPrint(compressed)
  AutoLayer:Print(selected_layers)
  table.insert(addonTable.send_queue, encoded)
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
  frame:SetHeight(200)
  frame:SetStatusText("Beta feature")

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
    for _, v in ipairs(selected_layers) do
      AutoLayer:DebugPrint(v)
    end

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

  -- add space between button and desc


  local desc = AceGUI:Create("Label")
  desc:SetText(
    "This sends a layer hop request to other addon users. If they are on the selected layer, they will invite you to their group.\ntest");

  frame:AddChild(layer)
  frame:AddChild(send)
  frame:AddChild(desc)
end
