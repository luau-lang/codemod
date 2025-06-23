local function getSeleneExclude(tomlContent): { string }
	-- takes in path of selene.toml
	-- look for exclude =
	-- then grab the patterns in between [] square brackets and return list
	local patterns = {}

	-- Isolate the content within the exclude = [...] block
	local excludeBlock = tomlContent:match("exclude%s*=%s*%[(.-)]")

	if excludeBlock then
		-- Iterate through all quoted strings within the block
		for pattern in excludeBlock:gmatch([["(.-)"]]) do
			table.insert(patterns, pattern)
		end
	end

	return patterns
end

local function exclude(filePath, excludePaths: { string }): boolean
	for _, pattern in ipairs(excludePaths) do
		-- Convert gitignore-style pattern to a Lua pattern
		local luaPattern = pattern:gsub("%.", "%%."):gsub("%*", ".*")
		-- print(luaPattern)
		-- Anchor the pattern to the beginning of the string
		if not luaPattern:match("^.*") then
			luaPattern = "^" .. luaPattern
		end

		if filePath:match(luaPattern) then
			return true
		end
	end
	return false
end

return {
	getSeleneExclude = getSeleneExclude,
	excludeFile = exclude,
}
