local _, addonTable = ...

-- Append settings migrations here, in order. Entry [n] runs once for every profile whose
-- migrationVersion is below n, so never reuse or reorder an existing number.
-- AceDB fills in new default keys on login, but it does not rewrite changed defaults:
-- that is what a migration step is for.
local migrations = {
	-- [1] = function(profile)
	--     profile.someOption = true
	-- end,
}

--- Runs every pending settings migration once for the current profile.
function AutoLayer:RunMigrations()
	local profile = self.db.profile
	local version = profile.migrationVersion or 0

	while migrations[version + 1] do
		local nextVersion = version + 1
		local ok, err = pcall(migrations[nextVersion], profile)
		if not ok then
			self:Print("|cffff0000ERROR:|r AutoLayer settings migration " .. nextVersion .. " failed: " .. tostring(err))
			break
		end
		version = nextVersion
	end

	profile.migrationVersion = version
end

addonTable.migrations = migrations
