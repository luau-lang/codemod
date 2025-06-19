local parser = require("@batteries/syntax/parser")
local findVariablesUtils = require("../findVariablesUtils")
local testCases = require("./findVariablesTestCases")

-- local searchScopeStack = findVariablesUtils.searchScopeStack
-- local handleVarDeclaration = findVariablesUtils.handleVarDeclaration
-- local handleVarReference = findVariablesUtils.handleVarReference
-- local handleAssign = findVariablesUtils.handleAssign
local findVariables = findVariablesUtils.findVariables

local function outputMatch(output: findVariablesUtils.variableStore, expectedOutput)
	for var, numUses in output do
		local varName = var.name.text :: string
		local varDeclarationLine = var.name.position.line
		local outputMatchKey = varName .. "_" .. tostring(varDeclarationLine)
		assert(numUses == expectedOutput[outputMatchKey])
	end
	return true
end
-- we can perhaps use varName_declarationLine as a key instead of just varName for better
-- means of testing scope

local function test_findVariables(codeBlock, expectedOutput)
	print()
	print("======================")
	print("Current Case:")
	print(codeBlock)

	local block = parser.parse(codeBlock)

	local outputVars, outputDels = findVariables(block)

	print("======================")

	outputMatch(outputVars, expectedOutput)
end

for src, expectedOutput in pairs(testCases) do
	test_findVariables(src, expectedOutput)
end
-- hmmm, do we want individual tests for scopeStack and findingVariableDecs/Refs? i feel like we can just test all as one...
