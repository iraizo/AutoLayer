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

test("NWBdatabase lookup uses realm and faction", function()
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
