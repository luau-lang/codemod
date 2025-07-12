local path = require("../lib/path")
local strings = require("../lib/strings")

local configResolver = require("../config-resolver/resolver")

local lexicallyRelative = require("./lexicallyRelative")

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

return {
	computeBestAliasesPath = computeBestAliasesPath,
}
