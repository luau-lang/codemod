local parser = require("@batteries/syntax/parser")

local evaluate = require("../evaluate")

local function evaluateExpr(source: string, flag: string?, value: boolean?)
	local ctx = {
		flagName = flag or "FlagName",
		flagValue = if value == nil then true else value,
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

return function()
	test_constantEvaluation()
	test_evaluateFlagAccess()
end
