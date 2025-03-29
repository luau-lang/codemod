local parser = require("@batteries/syntax/parser")

local evaluate = require("../evaluate")

local function evaluateExpr(source: string, flag: string?, value: boolean?)
	local ctx = {
		flagName = flag or "FlagName",
		flagValue = if value == nil then true else value,
		flagLocalsSet = {},
		globalFunctionsSet = {},
	}
	return evaluate(parser.parseexpr(source), ctx)
end

local function test_constantEvaluation()
	assert(evaluateExpr("true") == true)
	assert(evaluateExpr("false") == false)
end

local function test_evaluateFlagAccess()
	assert(evaluateExpr("game:GetFastFlag('FlagName')", "FlagName", true) == true)
	assert(evaluateExpr("game:GetFastFlag('FlagName')", "FlagName", false) == false)
	assert(evaluateExpr("game:GetFastFlag('OtherFlagName')", "FlagName", true) == nil)

	assert(evaluateExpr("game:DefineFastFlag('FlagName', false)", "FlagName", true) == true)
	assert(evaluateExpr("game:DefineFastFlag('FlagName', false)", "FlagName", false) == false)
	assert(evaluateExpr("game:DefineFastFlag('OtherFlagName', false)", "FlagName", true) == nil)
end

local function test_evaluateLocalVariableAsTrue()
	local block = parser.parse([[
		local flagValue = ...
		print(flagValue)
	]])
	assert(#block.statements == 2)

	local definition = block.statements[1]
	assert(definition.tag == "local")
	assert(#definition.variables == 1)

	local flagLocalsSet = { [definition.variables[1].node] = true }

	local call = block.statements[2]
	assert(call.tag == "expression")
	assert(call.expression.tag == "call")
	assert(#call.expression.arguments == 1)

	local expr = call.expression.arguments[1].node

	local ctx = {
		flagName = "FlagName",
		flagValue = true,
		flagLocalsSet = flagLocalsSet,
		globalFunctionsSet = {},
	}

	assert(evaluate(expr, ctx) == true)
end

local function test_evaluateLocalVariableAsFalse()
	local block = parser.parse([[
		local flagValue = ...
		print(flagValue)
	]])
	assert(#block.statements == 2)

	local definition = block.statements[1]
	assert(definition.tag == "local")
	assert(#definition.variables == 1)

	local flagLocalsSet = { [definition.variables[1].node] = true }

	local call = block.statements[2]
	assert(call.tag == "expression")
	assert(call.expression.tag == "call")
	assert(#call.expression.arguments == 1)

	local expr = call.expression.arguments[1].node

	local ctx = {
		flagName = "FlagName",
		flagValue = false,
		flagLocalsSet = flagLocalsSet,
		globalFunctionsSet = {},
	}

	assert(evaluate(expr, ctx) == false)
end

local function test_evaluateIgnoreUnknownVariables()
	local block = parser.parse([[
		local flagValue = ...
		print(flagValue)
	]])
	assert(#block.statements == 2)

	local definition = block.statements[1]
	assert(definition.tag == "local")
	assert(#definition.variables == 1)

	local call = block.statements[2]
	assert(call.tag == "expression")
	assert(call.expression.tag == "call")
	assert(#call.expression.arguments == 1)

	local expr = call.expression.arguments[1].node

	local ctx = {
		flagName = "FlagName",
		flagValue = true,
		flagLocalsSet = {},
		globalFunctionsSet = {},
	}

	assert(evaluate(expr, ctx) == nil)
end

local function test_evaluateLocalCallAsTrue()
	local block = parser.parse([[
		local function getFlagValue() end
		getFlagValue()
	]])
	assert(#block.statements == 2)

	local call = block.statements[2]
	assert(call.tag == "expression")
	assert(call.expression.tag == "call")
	assert(call.expression.func.tag == "local")

	local flagLocalsSet = { [call.expression.func["local"]] = true }

	local ctx = {
		flagName = "FlagName",
		flagValue = true,
		flagLocalsSet = flagLocalsSet,
		globalFunctionsSet = {},
	}

	assert(evaluate(call.expression, ctx) == true)
end

local function test_evaluateLocalCallAsFalse()
	local block = parser.parse([[
		local function getFlagValue() end
		getFlagValue()
	]])
	assert(#block.statements == 2)

	local call = block.statements[2]
	assert(call.tag == "expression")
	assert(call.expression.tag == "call")
	assert(call.expression.func.tag == "local")

	local flagLocalsSet = { [call.expression.func["local"]] = true }

	local ctx = {
		flagName = "FlagName",
		flagValue = false,
		flagLocalsSet = flagLocalsSet,
		globalFunctionsSet = {},
	}

	assert(evaluate(call.expression, ctx) == false)
end

local function test_evaluateIgnoreUnknownLocalCall()
	local block = parser.parse([[
		local function getRandomValue() end
		getRandomValue()
	]])
	assert(#block.statements == 2)

	local call = block.statements[2]
	assert(call.tag == "expression")

	local ctx = {
		flagName = "FlagName",
		flagValue = false,
		flagLocalsSet = {},
		globalFunctionsSet = {},
	}

	assert(evaluate(call.expression, ctx) == nil)
end

local function test_evaluateGlobalCallAccess()
	local expr = parser.parseexpr("globalCall()")
	local ctx = {
		flagName = "FlagName",
		flagValue = true,
		flagLocalsSet = {},
		globalFunctionsSet = {
			["globalCall"] = true,
		},
	}
	assert(evaluate(expr, ctx) == true)

	expr = parser.parseexpr("globalCall()")
	ctx = {
		flagName = "FlagName",
		flagValue = false,
		flagLocalsSet = {},
		globalFunctionsSet = {
			["globalCall"] = true,
		},
	}
	assert(evaluate(expr, ctx) == false)

	expr = parser.parseexpr("randomGlobalCall()")
	ctx = {
		flagName = "FlagName",
		flagValue = false,
		flagLocalsSet = {},
		globalFunctionsSet = {
			["globalCall"] = true,
		},
	}
	assert(evaluate(expr, ctx) == nil)
end

return function()
	test_constantEvaluation()
	test_evaluateFlagAccess()
	test_evaluateLocalVariableAsTrue()
	test_evaluateLocalVariableAsFalse()
	test_evaluateIgnoreUnknownVariables()
	test_evaluateLocalCallAsTrue()
	test_evaluateLocalCallAsFalse()
	test_evaluateIgnoreUnknownLocalCall()
	test_evaluateGlobalCallAccess()
end
