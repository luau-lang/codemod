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

return lexicallyRelative
