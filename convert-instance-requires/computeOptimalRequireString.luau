local path = require("../lib/path")
local strings = require("../lib/strings")

local configResolver = require("../config-resolver/resolver")

local function lexicallyRelative(base: string, target: string)
	local basePathComponents = string.split(base, "/")
	local targetPathComponents = string.split(target, "/")

	local minSize = math.min(#basePathComponents, #targetPathComponents)
	local commonComponents = 0

	for i = 1, minSize do
		-- TODO: lowercase is only on windows / macOS
		if string.lower(basePathComponents[i]) == string.lower(targetPathComponents[i]) then
			commonComponents += 1
		else
			break
		end
	end

	local relativeComponents = {}

	for i = commonComponents + 1, #basePathComponents - 1 do
		table.insert(relativeComponents, "..")
	end

	for i = commonComponents + 1, #targetPathComponents do
		table.insert(relativeComponents, targetPathComponents[i])
	end

	local relativePath = table.concat(relativeComponents, "/")
	if relativePath == "" then
		return "."
	elseif
		#basePathComponents == commonComponents
		and #relativeComponents > 0
		and not strings.startsWith(relativePath, "../")
	then
		return "./" .. relativePath
	end

	return relativePath
end

local function isInitLuauFile(filepath: string): boolean
	return strings.startsWith(path.basename(filepath), "init.")
end

local function isAncestorOf(path: string, potentialAncestor: string): boolean
	-- TODO: lowercase is only on Windows / macOS
	return strings.startsWith(string.lower(path), string.lower(potentialAncestor))
end

local function resolveAliasLocation(alias: configResolver.LuauAlias): string
	return path.joinPath(alias.configLocation, alias.path)
end

local function computeBestAliasesPath(to: string, availableAliases: { [string]: configResolver.LuauAlias }): string?
	local result = nil

	for aliasName, aliasInfo in availableAliases do
		local aliasLocation = resolveAliasLocation(aliasInfo)

		if not isAncestorOf(to, aliasLocation) then
			continue
		end

		local remainder = lexicallyRelative(aliasLocation, to)
		local aliasedPath = "@" .. aliasInfo.originalName

		if #remainder > 0 and remainder ~= "." then
			if strings.startsWith(remainder, "./") then
				remainder = strings.removePrefix(remainder, "./")
			end
			aliasedPath ..= "/" .. remainder
		end

		if not result or #aliasedPath < #result then
			result = aliasedPath
		end
	end

	if result then
		result = strings.removeSuffix(strings.removeSuffix(result, ".lua"), ".luau")
	end

	return result
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
		local aliasedPath = computeBestAliasesPath(to, config.aliases)

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
