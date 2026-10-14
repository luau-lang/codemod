local parser = require("@std/syntax/parser")
local isFlagFunction = require("../matchers/isFlagFunction")

local function parseStatement(source: string)
	local block = parser.parseBlock(source)
	assert(#block.statements == 1, "block must have one statement")
	return block.statements[1]
end

local function test_unrelatedStatement()
	local statement = parseStatement([[
		local x = 1
	]])

	assert(isFlagFunction.isStmtFlagFunction(statement, "FlagName") == false)
end

local function test_anonymousFunction()
	local statement = parseStatement([[
		local getFastFlag = function()
			return game:GetFastFlag("FlagName")
		end
	]])

	assert(statement.tag == "local")
	assert(#statement.values == 1)

	local expression = statement.values[1]

	assert(isFlagFunction.isExprFlagFunction(expression, "FlagName") == true)
end

local function test_localFunction()
	local statement = parseStatement([[
		local function getFastFlag()
			return game:GetFastFlag("FlagName")
		end
	]])

	assert(isFlagFunction.isStmtFlagFunction(statement, "FlagName") == true)
end

local function test_globalFunction()
	local statement = parseStatement([[
		function getFastFlag()
			return game:GetFastFlag("FlagName")
		end
	]])

	assert(isFlagFunction.isStmtFlagFunction(statement, "FlagName") == true)
end

return function()
	test_unrelatedStatement()
	test_anonymousFunction()
	test_localFunction()
	test_globalFunction()
end
