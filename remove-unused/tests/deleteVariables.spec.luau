--[[
this is essentially end to end testing of the full migration;
these tests assume findVariables works and just test deletion functionality

test set up similar to findVariables tests

import test cases table
define function that takes in block param
repeatedly:
    calls findVariables on block
    calls deleteVariables on block
until there are no vars to delete
asserts output == expected output
]]
local parser = require("@batteries/syntax/parser")
local printer = require("@batteries/syntax/printer")
local findVariables = require("../findVariablesUtils").findVariables
local deleteVariables = require("../deleteVariables")
local testCases = require("./deleteVariablesTestCases")

---
--- Normalizes a source code string to make comparisons reliable.
--- It handles different line endings and whitespace inconsistencies.
---
-- @param s The source code string to normalize.
-- @return The normalized string.
local function normalizeString(s)
	if not s then
		return ""
	end

	-- 1. Unify line endings to LF (\n)
	s = s:gsub("\r\n", "\n")

	-- 2. Unify indentation to use 4 spaces instead of tabs
	s = s:gsub("\t", "    ")

	-- 3. CRITICAL: Replace non-breaking spaces (and other weird Unicode spaces)
	--    with standard spaces. The byte representation for non-breaking space
	--    in UTF-8 is 194, 160.
	s = s:gsub("\194\160", " ")

	-- 4. (Optional but recommended) Trim trailing whitespace from each line
	s = s:gsub("[ \t]+(\n)", "\n")

	-- 5. (Optional but recommended) Trim leading/trailing whitespace from the whole block
	s = s:match("^%s*(.-)%s*$")

	return s
end

local function test_deleteVariables(block, expectedOutput)
	print()
	print("======================")
	print("Current Case:")
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
	print("Output:")
	print(outputSrc)

	print("======================")

	assert(normalizeString(outputSrc) == normalizeString(expectedOutput))
end

local function run()
	for src, expectedOutput in pairs(testCases) do
		test_deleteVariables(src, expectedOutput)
	end
end

run()
