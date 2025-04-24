local parser = require("@batteries/syntax/parser")
local printer = require("@batteries/syntax/printer")

local evaluate = require("../evaluate")
local simplify = require("../simplifyExpression")

local function printSimplify(source: string)
	local context: evaluate.EvaluateContext = {
		flagName = "",
		flagValue = true,
		flagLocalsSet = {},
		globalFunctionsSet = {},
	}

	return printer.printexpr(simplify(parser.parseexpr(source), context))
end

local function test_simplifyBinary()
	assert(printSimplify("x and true") == "x ")
	assert(printSimplify("x and false") == "false")
	assert(printSimplify("true and x") == "x")
	assert(printSimplify("false and x") == "false ")

	assert(printSimplify("x or true") == "true")
	assert(printSimplify("x or false") == "x ")
	assert(printSimplify("true or x") == "true ")
	assert(printSimplify("false or x") == "x")
end

local function test_simplifyUnary()
	assert(printSimplify("not true") == "false")
	assert(printSimplify("not false") == "true")
end

return function()
	test_simplifyBinary()
	test_simplifyUnary()
end
