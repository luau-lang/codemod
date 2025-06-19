local parser = require("@batteries/syntax/parser")
local findVariablesUtils = require("../findVariablesUtils")
local testCases = require("./findVariablesTestCases")
local printTable = require("../../flag-clipper/matchers/flagAccessUtils").printTable

-- local searchScopeStack = findVariablesUtils.searchScopeStack
-- local handleVarDeclaration = findVariablesUtils.handleVarDeclaration
-- local handleVarReference = findVariablesUtils.handleVarReference
-- local handleAssign = findVariablesUtils.handleAssign
local findVariables = findVariablesUtils.findVariables

local function cntTableEntries(t)
	local i = 0
	for _, _ in pairs(t) do
		i += 1
	end
	return i
end

local function outputMatch(output: findVariablesUtils.variableStore, expectedOutput)
	local passedCases = 0
	for var, numUses in output do
		local varName = var.name.text :: string
		local varDeclarationLine = var.name.position.line
		local outputMatchKey = varName .. "_" .. tostring(varDeclarationLine)
		assert(numUses == expectedOutput[outputMatchKey])
		passedCases += 1
	end
	local totalCases = cntTableEntries(expectedOutput)
	print(`Correctly tracked {passedCases}/{totalCases} variables`)
	assert(passedCases == totalCases)
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
	outputMatch(outputVars, expectedOutput)
	print("======================")
end

for src, expectedOutput in pairs(testCases) do
	test_findVariables(src, expectedOutput)
end
-- hmmm, do we want individual tests for scopeStack and findingVariableDecs/Refs? i feel like we can just test all as one...

-- local example = require("../example")
-- print(example[1])
-- local exampleSrc = parser.parse(example[1])
-- print("Printing Example Source Code from Root")
-- printTable(exampleSrc, 0)
