local path = require("../lib/path")
local strings = require("../lib/strings")

local configResolver = require("../config-resolver/resolver")

local aliases = require("./aliases")
local lexicallyRelative = require("./lexicallyRelative")

local function isInitLuauFile(filepath: string): boolean
	return strings.startsWith(path.basename(filepath), "init.")
end

--- Computes the optimal require string from 2 file system paths
local function computeOptimalRequireString(from: string, to: string)
	local fromInitLuau = isInitLuauFile(from)
	if fromInitLuau then
		from = assert(path.dirname(from))
	end

	if isInitLuauFile(to) then
		to = path.dirname(to)
	end

	local relativePath = lexicallyRelative(from, to)

	relativePath = strings.removeSuffix(strings.removeSuffix(relativePath, ".lua"), ".luau")

	if strings.startsWith(relativePath, "../") then
		local config = configResolver.resolveConfig(from)
		local aliasedPath = aliases.computeBestAliasesPath(to, config.aliases)

		-- TODO: how do we decide whether we want to use the alias instead?
		if aliasedPath and #aliasedPath < #relativePath then
			return aliasedPath
		end
	else
		if strings.startsWith(relativePath, "./") then
			if fromInitLuau then
				return (relativePath:gsub("^%./", "@self/"))
			end
		else
			return "./" .. relativePath
		end
	end

	return relativePath
end

return computeOptimalRequireString
