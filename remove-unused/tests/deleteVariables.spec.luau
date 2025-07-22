local parser = require("@batteries/syntax/parser")
local printer = require("@batteries/syntax/printer")
local testCases = require("./deleteVariablesTestCases")
local normalizeString = require("../helpers/testHelpers").normalizeString
local codemod = require("../")

local function apply(source: string)
	return codemod.transform({
		path = "",
		source = source,
		options = { selene = ""},
	})
end

--[[    
    This function performs a complete removal process for a single test case:
    1. Parse the input code
    2. Iteratively find and remove unused functions/variables until none remain
    3. Verify the final output matches the expected output
    
    @param block The input Lua/Luau code block to process
    @param expectedOutput The expected code after removing unused functions/variables
    @throws Assertion error if outputs don't match
]]
local function test_deleteVariables(block, expectedOutput)
	print("\n======================\nCurrent Case:")
	local output = apply(block)
	block = parser.parse(block)
	print(printer.print(block))
	print("Output:\n" .. output .. "\n" .. "======================")
	print("Expected Output:\n" .. expectedOutput .. "\n" .. "======================")
	assert(normalizeString(output) == normalizeString(expectedOutput))
end

local function run()
	for src, expectedOutput in pairs(testCases) do
		test_deleteVariables(src, expectedOutput)
	end
end

return run
