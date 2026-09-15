local parser = require("@std/syntax/parser")
local printer = require("@std/syntax/printer")

local evaluate = require("../evaluate")
local simplify = require("../simplifyExpression")
local TrackReferences = require("../TrackReferences")

local function printSimplify(source: string)
	local expression = parser.parseexpr(source)
	local references = TrackReferences.new("FlagName", true, {})
	references:_visitExpressionForTesting(expression)

	local context: evaluate.EvaluateContext = {
		flagName = "FlagName",
		flagValue = true,
		references = references,
	}

	return printer.printnode(simplify(expression, context))
end

local function case(str: string, exp: string)
	local source = `{str}`
	local expected = `{exp}`

	local res = printSimplify(source)

	assert(res == expected, `{res} ~= {expected}`)
end

local function test_simplifyBinary()
	-- TODO: we don't do normal evaluations anymore
	-- assert(printSimplify("x and true") == "x ")
	-- assert(printSimplify("x and false") == "false")
	-- assert(printSimplify("true and x") == "x")
	-- assert(printSimplify("false and x") == "false ")

	-- assert(printSimplify("x or true") == "true")
	-- assert(printSimplify("x or false") == "x ")
	-- assert(printSimplify("true or x") == "true ")
	-- assert(printSimplify("false or x") == "x")

	assert(printSimplify("game:GetFastFlag('FlagName') and value") == "value")
	assert(printSimplify("value and game:GetFastFlag('FlagName')") == "value ")

	assert(printSimplify("game:GetFastFlag('FlagName') or value") == "game:GetFastFlag('FlagName') ")
	assert(printSimplify("value or game:GetFastFlag('FlagName')") == "game:GetFastFlag('FlagName')")
end

-- local function test_simplifyUnary()
-- 	assert(printSimplify("not true") == "false")
-- 	assert(printSimplify("not false") == "true")
-- end

local function test_simplifyIfExprRemoveElse()
	local source = "if game:GetFastFlag('FlagName') then 1 else 2"
	local expected = "1 "
	assert(printSimplify(source) == expected)
end

local function test_simplifyIfExprRemoveIf()
	local source = "if not game:GetFastFlag('FlagName') then 1 else 2"
	local expected = "2"
	assert(printSimplify(source) == expected)
end

local function test_keepComplicatedIfExpr()
	local source = "if x then 1 else 2"
	assert(printSimplify(source) == source)
end

local function test_simplifyIfExprRemoveIfKeepElseif()
	local source = "if not game:GetFastFlag('FlagName') then 1 elseif value then 2 else 3"
	local expected = "if value then 2 else 3"
	assert(printSimplify(source) == expected)
end

local function test_simplifyIfIntoElseif()
	local source = "if not game:GetFastFlag('FlagName') then 1 elseif game:GetFastFlag('FlagName') then 2 else 3"
	local expected = "2 "
	assert(printSimplify(source) == expected)
end

local function test_simplifyIfAndElseIf()
	local source = "if not game:GetFastFlag('FlagName') then 1 elseif not game:GetFastFlag('FlagName') then 2 else 3"
	local expected = "3"
	assert(printSimplify(source) == expected)
end

local function test_simplifyElseIfIntermediateCondition()
	local source = "if value then 1 elseif game:GetFastFlag('FlagName') then 2 else 3"
	local expected = "if value then 1 else 2 "
	assert(printSimplify(source) == expected)
end

local function test_simplifyElseIfMultipleLevels()
	local source = "if value then 1 elseif value2 then 2 elseif game:GetFastFlag('FlagName') then 3 else 4"
	local expected = "if value then 1 elseif value2 then 2 else 3 "
	assert(printSimplify(source) == expected)
end

local function test_removeKeyFromTable()
	local source = "{ FFlagFlagName = game:GetFastFlag('FlagName') }"
	local expected = "{ }"

	assert(printSimplify(source) == expected)
end

local function test_evaluateComputedKeyValueInTable()
	local source = "{ ['text-heading-medium'] = game:GetFastFlag('FlagName') }"
	local expected = "{ ['text-heading-medium'] = true }"

	assert(printSimplify(source) == expected)
end

local function test_setKeyToFalseInTable()
	local source = "{ featureIsDisabled = not game:GetFastFlag('FlagName') }"
	local expected = "{ featureIsDisabled = false }"

	assert(printSimplify(source) == expected)
end

local function test_simplifyFlagReferenceInCall()
	case("print(game:GetFastFlag('FlagName'))", "print(true)")
end

local function test_simplifyCompoundFlagReferenceInCall()
	case("print(not game:GetFastFlag('FlagName'))", "print(false)")
	case("print(game:GetFastFlag('FlagName') or arbitraryCondition)", "print(true)")
	case("print(not game:GetFastFlag('FlagName') and arbitraryCondition)", "print(false)")
end

return function()
	test_simplifyBinary()
	-- test_simplifyUnary()
	test_simplifyIfExprRemoveElse()
	test_simplifyIfExprRemoveIf()
	test_keepComplicatedIfExpr()
	test_simplifyIfExprRemoveIfKeepElseif()
	test_simplifyIfIntoElseif()
	test_simplifyIfAndElseIf()
	test_simplifyElseIfIntermediateCondition()
	test_simplifyElseIfMultipleLevels()
	test_removeKeyFromTable()
	test_evaluateComputedKeyValueInTable()
	test_setKeyToFalseInTable()
	test_simplifyFlagReferenceInCall()
	test_simplifyCompoundFlagReferenceInCall()
end
