--[[
    This function parses a selene.toml file to extract the exclude patterns,
    which are typically specified in a format like:
    
    ```toml
    exclude = [
        "path/to/exclude/*.lua",
        "another/path/**/*.lua"
    ]
    ```
    
    @param tomlContent - The content of the selene.toml file as a string
    @return - Array of exclusion patterns extracted from the file
]]
local function getSeleneExclude(tomlContent): { string }
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

--[[
    This function tests if a given file path should be excluded based on
    the patterns from selene.toml. It converts gitignore-style patterns
    to Lua patterns for matching.
    
    @param filePath - The path of the file to check
    @param excludePaths - Array of exclusion patterns from selene.toml
    @return - true if the file should be excluded, false otherwise
]]
local function exclude(filePath, excludePaths: { string }): boolean
	for _, pattern in ipairs(excludePaths) do
		-- Convert gitignore-style pattern to a Lua pattern
		local luaPattern = pattern:gsub("%.", "%%."):gsub("%*", ".*")

		-- Anchor the pattern to the beginning of the string
		if not luaPattern:match("^.*") then
			luaPattern = "^" .. luaPattern
		end

		-- Check if the file path matches this pattern
		if filePath:match(luaPattern) then
			return true -- File should be excluded
		end
	end

	return false -- File should be processed
end

return {
	getSeleneExclude = getSeleneExclude,
	excludeFile = exclude,
}
