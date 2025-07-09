--[[
    Delete Variables and Functions Tests Module
    
    This module contains end-to-end tests for the remove-unused codemod.
    It verifies that the combination of findVariables and deleteVariables functions 
    correctly removes unused variables and functions from Lua/Luau code while preserving
    the integrity and semantics of the code.
    
    The tests use predefined test cases from deleteVariablesTestCases.luau.
]]
local parser = require("@batteries/syntax/parser")
local printer = require("@batteries/syntax/printer")
local findVariables = require("../findVariablesUtils").findVariables
local deleteVariables = require("../deleteVariables")
local testCases = require("./deleteVariablesTestCases")

--[[
    Normalizes a source code string to make comparisons reliable.
    It handles different line endings and whitespace inconsistencies.
    
    @param s The source code string to normalize.
    @return The normalized string.
]]
local function normalizeString(s)
	if not s then
		return ""
	end

	-- 1. Unify line endings to LF (\n)
	s = s:gsub("\r\n", "\n")

	-- 2. Unify indentation to use 4 spaces instead of tabs
	s = s:gsub("\t", "    ")

	-- 3. Replace non-breaking spaces (and other weird Unicode spaces)
	--    with standard spaces. The byte representation for non-breaking space
	--    in UTF-8 is 194, 160.
	s = s:gsub("\194\160", " ")

	-- 4. (Optional but recommended) Trim trailing whitespace from each line
	s = s:gsub("[ \t]+(\n)", "\n")

	-- 5. (Optional but recommended) Trim leading/trailing whitespace from the whole block
	s = s:match("^%s*(.-)%s*$")

	-- bc of how test-cases are typed this function is useful for just matching content of expected output
	return s
end

--[[
    Tests the deleteVariables functionality for a single test case.
    
    This function performs a complete unused variable removal process:
    1. Parse the input code
    2. Iteratively find and remove unused variables until none remain
    3. Verify the final output matches the expected output
    
    @param block The input Lua/Luau code block to process
    @param expectedOutput The expected code after removing unused variables
    @throws Assertion error if outputs don't match
]]
local function test_deleteVariables(block, expectedOutput)
	print("\n======================\nCurrent Case:")
	block = parser.parse(block)
	print(printer.print(block))
	local numDels = 1
	local _vars, dels
	while numDels > 0 do
		_vars, dels, numDels = findVariables(block)
		if numDels > 0 then
			block = deleteVariables(block, dels)
		end
	end
	local outputSrc = printer.print(block)
	print("Output:\n" .. outputSrc .. "\n" .. "======================")

	assert(normalizeString(outputSrc) == normalizeString(expectedOutput))
end

local function run()
	for src, expectedOutput in pairs(testCases) do
		test_deleteVariables(src, expectedOutput)
	end
end

return run
