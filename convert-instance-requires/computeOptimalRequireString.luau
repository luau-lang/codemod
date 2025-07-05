local path = require("../lib/path")
local strings = require("../lib/strings")

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

local function isInitLuauFile(filepath: string)
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
		-- TODO: process config for aliases and consider best alias
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
