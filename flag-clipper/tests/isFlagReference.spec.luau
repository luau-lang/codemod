local parser = require("@batteries/syntax/parser")

local isFlagReference = require("../matchers/isFlagReference")

local function isReference(source: string, flag: string?)
	local ctx = {
		flagName = flag or "FlagName",
		flagLocalsSet = {},
		globalFunctionsSet = {},
	}
	return isFlagReference(parser.parseexpr(source), ctx)
end

local function test_directFlagAccess()
	assert(isReference("game:GetFastFlag('FlagName')", "FlagName") == true)
	assert(isReference("game:GetFastFlag('OtherFlagName')", "FlagName") == false)

	assert(isReference("game:DefineFastFlag('FlagName', false)", "FlagName") == true)
	assert(isReference("game:DefineFastFlag('OtherFlagName', false)", "FlagName") == false)
end

local function test_flagAccessViaLocalVariable()
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
		flagLocalsSet = flagLocalsSet,
		globalFunctionsSet = {},
	}

	assert(isFlagReference(expr, ctx) == true)
end

local function test_ignoreUnknownLocalVariables()
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
		flagLocalsSet = {},
		globalFunctionsSet = {},
	}

	assert(isFlagReference(expr, ctx) == false)
end

local function test_flagAccessViaLocalCall()
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
		flagLocalsSet = flagLocalsSet,
		globalFunctionsSet = {},
	}

	assert(isFlagReference(call.expression, ctx) == true)
end

local function test_ignoreUnknownLocalCalls()
	local block = parser.parse([[
		local function getRandomValue() end
		getRandomValue()
	]])
	assert(#block.statements == 2)

	local call = block.statements[2]
	assert(call.tag == "expression")

	local ctx = {
		flagName = "FlagName",
		flagLocalsSet = {},
		globalFunctionsSet = {},
	}

	assert(isFlagReference(call.expression, ctx) == false)
end

local function test_flagAccessViaGlobalCall()
	local expr = parser.parseexpr("globalCall()")
	local ctx = {
		flagName = "FlagName",
		flagLocalsSet = {},
		globalFunctionsSet = {
			["globalCall"] = true,
		},
	}
	assert(isFlagReference(expr, ctx) == true)

	expr = parser.parseexpr("randomGlobalCall()")
	ctx = {
		flagName = "FlagName",
		flagValue = false,
		flagLocalsSet = {},
		globalFunctionsSet = {
			["globalCall"] = true,
		},
	}
	assert(isFlagReference(expr, ctx) == false)
end

return function()
	test_directFlagAccess()
	test_flagAccessViaLocalVariable()
	test_ignoreUnknownLocalVariables()
	test_flagAccessViaLocalCall()
	test_ignoreUnknownLocalCalls()
	test_flagAccessViaGlobalCall()
end
