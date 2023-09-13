local addonName, addonTable = ...

-- All rights go to NovaWorldBuffs for this function
--Iterate table keys in alphabetical order.
function AutoLayer:pairsByKeys(t, f)
    local a = {};
    for n in pairs(t) do
        table.insert(a, n);
    end
    table.sort(a, f);
    local i = 0;
    local iter = function()
        i = i + 1;
        if (a[i] == nil) then
            return nil;
        else
            return a[i], t[a[i]];
        end
    end
    return iter;
end

function AutoLayer:HopGUI()
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("AutoLayer - Hopper")
    frame:SetStatusText("This will request hopping to a specific layer between addon users")

    -- multi combo box
    local layer = AceGUI:Create("Dropdown")
    layer:SetLabel("Layer")
    layer:SetList({
        ["1"] = "1",
        ["2"] = "2",
        ["3"] = "3",
        ["4"] = "4",
        ["5"] = "5",
        ["6"] = "6",
    })
    layer:SetValue("1")

    -- layer should select multiple
    layer:SetMultiselect(true)

    local count = 0;
    for k, v in AutoLayer:pairsByKeys(addonTable.NWB.data.layers) do
        count = count + 1;
        if (k == tonumber(layer)) then
            layerMsg = " (Layer " .. count .. ")";
            AutoLayer:Print(layerMsg)
        end
    end

    frame:AddChild(layer)
end
