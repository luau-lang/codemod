local parser = require("@std/syntax/parser")
local printer = require("@std/syntax/printer")
local testCases = require("./deleteVariablesTestCases")
local normalizeString = require("../helpers/testHelpers").normalizeString
local codemod = require("../")

local function apply(source: string)
	return codemod.transform({
		path = "",
		source = source,
		options = { selene = "" },
	})
end

--[[    
    This function verifies the output of a complete removal process for a single test case.
    
    @param block - The input Lua/Luau code block to process
    @param expectedOutput - The expected code after removing unused functions/variables
    @throws Assertion error if outputs don't match
]]
local function test_deleteVariables(block, expectedOutput)
	print("\n======================\nCurrent Case:")
	local output = apply(block)
	block = parser.parseblock(block)
	print(printer.printnode(block))
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
