-- Run from the repo root: lua5.1 Modules/Libs/AutoLayerUtil.test.lua

local chunk = assert(loadfile("Modules/Libs/AutoLayerUtil.lua"))
local addonTable = {}
chunk("AutoLayer", addonTable)
local util = addonTable.util

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
		print("PASS " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end

local function assertLayers(actual, expected, label)
	assert(#actual == #expected, (label or "") .. " expected " .. #expected .. " layers, got " .. #actual)
	for i = 1, #expected do
		assert(actual[i] == expected[i], (label or "") .. " layer " .. i .. " expected " .. expected[i] .. ", got " .. tostring(actual[i]))
	end
end

test("NWB <= 3.41 flat layer data is numbered 1..N", function()
	local layers = {
		[1453] = {rendTimer = 0},
		[1454] = {rendTimer = 0},
		[1455] = {rendTimer = 0},
	}
	assertLayers(util.GetNWBLayerNumbers(layers, 1), {1, 2, 3})
end)

test("NWB 3.48 nested layer data counts only the requested world", function()
	local layers = {
		[1] = {
			[1453] = {rendTimer = 0},
			[1454] = {rendTimer = 0},
		},
		[2] = {
			[1948] = {rendTimer = 0},
		},
	}
	assertLayers(util.GetNWBLayerNumbers(layers, 1), {1, 2}, "Azeroth")
	assertLayers(util.GetNWBLayerNumbers(layers, 2), {1}, "Outland")
	assertLayers(util.GetNWBLayerNumbers(layers, 3), {}, "unknown world")
	assertLayers(util.GetNWBLayerNumbers(layers, nil), {}, "no world")
end)

test("empty or missing NWB layer data yields no layers", function()
	assertLayers(util.GetNWBLayerNumbers(nil), {})
	assertLayers(util.GetNWBLayerNumbers({}), {})
	assertLayers(util.GetNWBLayerNumbers({[1] = {}, [2] = {}}, 1), {})
end)

test("NWB storage resolves from the current segment", function()
	local nested = {
		[1] = {[1454] = {}},
		[2] = {[1955] = {}},
	}
	assert(util.GetNWBStorageID(nested, nil, "AZ") == 1)
	assert(util.GetNWBStorageID(nested, nil, "OL") == 2)
end)

test("NWB storage falls back to NWB_CurrentLayerZoneID when the segment is unknown", function()
	local nested = {
		[1] = {[1454] = {}},
		[2] = {[1955] = {}},
	}
	assert(util.GetNWBStorageID(nested, 1955, nil) == 2)
	assert(util.GetNWBStorageID(nested, 1454, nil) == 1)
	assert(util.GetNWBStorageID(nested, 9999, nil) == 1)
	assert(util.GetNWBStorageID(nested, nil, nil) == 1)
end)

test("NWB segment wins over a stale NWB_CurrentLayerZoneID", function()
	local nested = {
		[1] = {[1454] = {}},
		[2] = {[1955] = {}},
	}
	assert(util.GetNWBStorageID(nested, 1955, "AZ") == 1)
end)

local SEGMENT_MAP_IDS = {AZ = 947, OL = 1945}

local function mapInfoGetter(parents)
	return function(mapID)
		local parent = parents[mapID]
		if parent == nil then
			return nil
		end
		return {mapID = mapID, parentMapID = parent}
	end
end

test("layer segment matches a zone nested under a continent", function()
	local parents = {[1420] = 1415, [1415] = 947, [947] = 0}
	assert(util.ResolveLayerSegment(1420, mapInfoGetter(parents), SEGMENT_MAP_IDS, {}) == "AZ")
end)

test("layer segment matches a segment root with no parent", function()
	local getMapInfo = function()
		error("the segment root must match before asking for map info")
	end
	assert(util.ResolveLayerSegment(947, getMapInfo, SEGMENT_MAP_IDS, {}) == "AZ")
	assert(util.ResolveLayerSegment(1945, getMapInfo, SEGMENT_MAP_IDS, {}) == "OL")
end)

test("layer segment uses the nearest override on the parent chain", function()
	local parents = {[1941] = 1415, [1415] = 947, [947] = 0}
	assert(util.ResolveLayerSegment(1941, mapInfoGetter(parents), SEGMENT_MAP_IDS, {[1941] = "OL"}) == "OL")
	assert(util.ResolveLayerSegment(1941, mapInfoGetter(parents), SEGMENT_MAP_IDS, {[1415] = "OL"}) == "OL")
end)

test("layer segment resolves a top-level Forever map through its override", function()
	assert(util.ResolveLayerSegment(2521, mapInfoGetter({[2521] = 947, [947] = 0}), SEGMENT_MAP_IDS, {[2521] = "ZI"}) == "ZI")
	assert(util.ResolveLayerSegment(2665, mapInfoGetter({[2665] = 0}), SEGMENT_MAP_IDS, {[2665] = "ZI"}) == "ZI")
end)

test("layer segment stops cleanly for nil, zero, missing maps and unclassified maps", function()
	local parents = {[1420] = 1415, [1415] = 947, [947] = 0}
	local getMapInfo = mapInfoGetter(parents)
	assert(util.ResolveLayerSegment(nil, getMapInfo, SEGMENT_MAP_IDS, {}) == nil)
	assert(util.ResolveLayerSegment(0, getMapInfo, SEGMENT_MAP_IDS, {}) == nil)
	assert(util.ResolveLayerSegment(2999, getMapInfo, SEGMENT_MAP_IDS, {}) == nil)
	assert(util.ResolveLayerSegment(1415, mapInfoGetter({[1415] = 0}), SEGMENT_MAP_IDS, {}) == nil)
end)

test("layer segment does not loop forever on a cyclic parent chain", function()
	local parents = {[100] = 101, [101] = 100}
	assert(util.ResolveLayerSegment(100, mapInfoGetter(parents), SEGMENT_MAP_IDS, {}) == nil)
end)

test("layer segment uses an override even when that map row is missing", function()
	-- Forever can ship a child row whose parent ID (e.g. the Ruins of Lordaeron orphan) has no
	-- GetMapInfo entry; the override must short-circuit the walk before map info is requested.
	local parents = {[998] = 908}
	assert(util.ResolveLayerSegment(998, mapInfoGetter(parents), SEGMENT_MAP_IDS, {[908] = "AZ"}) == "AZ")
end)

test("only world, continent and zone maps can report an unclassified segment", function()
	assert(util.IsOpenWorldMapType(1) == true, "world")
	assert(util.IsOpenWorldMapType(2) == true, "continent")
	assert(util.IsOpenWorldMapType(3) == true, "zone")
	assert(util.IsOpenWorldMapType(nil) == false, "nil")
	for _, mapType in ipairs({0, 4, 5, 6}) do
		assert(util.IsOpenWorldMapType(mapType) == false, "map type " .. mapType)
	end
end)

test("NWB database lookup uses realm and faction", function()
	local layers = {[1] = {[1454] = {}}}
	local db = {
		global = {
			["My Realm"] = {
				Horde = {layers = layers},
				Alliance = {},
			},
		},
	}
	assert(util.GetNWBLayerTable(db, "My Realm", "Horde") == layers)
	assert(util.GetNWBLayerTable(db, "My Realm", "Alliance") == nil)
	assert(util.GetNWBLayerTable(db, "Other Realm", "Horde") == nil)
	assert(util.GetNWBLayerTable(nil, "My Realm", "Horde") == nil)
end)

test("nested layout is detected regardless of key order or non-numeric keys", function()
	local layers = {
		version = "3.48",
		[1] = {[1453] = {}, [1454] = {}},
		[2] = {[1948] = {}},
	}
	for _ = 1, 20 do
		assertLayers(util.GetNWBLayerNumbers(layers, 1), {1, 2}, "Azeroth")
		assertLayers(util.GetNWBLayerNumbers(layers, 2), {1}, "Outland")
	end
end)

print(string.format("autolayer_util_test: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
