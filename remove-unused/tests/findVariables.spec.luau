local parser = require("@std/syntax/parser")
local findVariablesUtils = require("../findVariablesUtils")
local testCases = require("./findVariablesTestCases")

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
		local varDeclarationLine = var.name.location.beginLine
		print("Var Declaration Line", varDeclarationLine)
		local outputMatchKey = varName .. "_" .. tostring(varDeclarationLine)
		assert(numUses == expectedOutput[outputMatchKey])
		passedCases += 1
	end
	local totalCases = cntTableEntries(expectedOutput)
	print(`Correctly tracked {passedCases}/{totalCases} variables\n======================`)
	assert(passedCases == totalCases)
end

local function test_findVariables(codeBlock, expectedOutput)
	print("\n======================\nCurrent Case:")
	print(codeBlock)

	local block = parser.parseBlock(codeBlock)

	local outputVars, _outputDels = findVariables(block)
	outputMatch(outputVars, expectedOutput)
end

local function run()
	for src, expectedOutput in pairs(testCases) do
		test_findVariables(src, expectedOutput)
	end
end

return run
