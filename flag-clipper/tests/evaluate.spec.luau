local parser = require("@std/syntax/parser")
local Rewriter = require("../Rewriter")
local evaluate = require("../evaluate")
local TrackReferences = require("../TrackReferences")

local function apply(source: string, flagName: string?, flagValue: boolean?): boolean?
	local value = if flagValue ~= nil then flagValue else true

	local references = TrackReferences.new(flagName or "FlagName", value, {})

	local context: evaluate.EvaluateContext = {
		flagValue = value,
		references = references,
		rewriter = Rewriter.new(references),
	}

	local parseResult = parser.parseExpr(source)
	references:_visitExpressionForTesting(parseResult)
	return evaluate(parseResult, context)
end

local function test_evaluateFlagReference()
	assert(apply('game:GetFastFlag("FlagName")'), "Incorrectly evaluated flag reference as false")
end

local function test_evaluateGroupFlagReference()
	assert(apply('(game:GetFastFlag("FlagName"))'), "Incorrectly evaluated group flag reference as false")
end

local function test_evaluateUnary()
	assert(not apply('not game:GetFastFlag("FlagName")'), "Incorrectly evaluated unary flag reference as true")
end

-- should return nil
local function test_evaluateArbitrary()
	assert(apply("true") == nil, "Did not return nil for arbitrary boolean")
end

return function()
	test_evaluateFlagReference()
	test_evaluateGroupFlagReference()
	test_evaluateUnary()
	test_evaluateArbitrary()
end
