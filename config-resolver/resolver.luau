local fs = require("@std/fs")
local json = require("@std/json")
local path = require("../lib/path")
local strings = require("../lib/strings")

export type LuauAlias = {
	path: string,
	originalName: string,
	configLocation: string,
}

export type LuauConfig = {
	aliases: { [string]: LuauAlias },
}

local CONFIG_FILENAME = ".luaurc"
local _configCache: { [string]: LuauConfig } = {}

local function defaultConfig(): LuauConfig
	return { aliases = {} }
end

local function isInitLuauFile(filepath: string)
	return strings.startsWith(path.basename(filepath), "init.")
end

local function parseConfig(filepath: string, baseConfig: LuauConfig)
	local directory = path.dirname(filepath)
	assert(directory, "expected filepath to have a directory part")

	local contents = fs.readFileToString(filepath)
	local decoded = json.deserialize(contents)
	assert(typeof(decoded) == "table", "expected .luaurc to contain a table")

	-- Clone the baseConfig to prevent mutating referenced tables
	local result = table.clone(baseConfig)

	-- TODO: handle other config options
	if (decoded :: any)["aliases"] then
		for alias, path in decoded["aliases"] do
			result.aliases[string.lower(alias)] = {
				path = path,
				originalName = alias,
				configLocation = directory,
			}
		end
	end

	return result
end

local function readConfigRecursive(directory: string)
	if _configCache[directory] then
		return _configCache[directory]
	end

	local result: LuauConfig = defaultConfig()
	local parentPath = path.dirname(directory)
	if parentPath then
		result = readConfigRecursive(parentPath)
	end

	local configPath = path.joinPath(directory, CONFIG_FILENAME)
	if fs.exists(configPath) then
		result = parseConfig(configPath, result)
	end

	_configCache[directory] = result
	return result
end

local function resolveConfig(filepath: string)
	local from = path.dirname(filepath)
	if not from then
		return defaultConfig()
	end

	if isInitLuauFile(filepath) then
		from = path.dirname(from)
		if not from then
			return defaultConfig()
		end
	end

	assert(from, "Luau")
	return readConfigRecursive(from)
end

return {
	resolveConfig = resolveConfig,
}
