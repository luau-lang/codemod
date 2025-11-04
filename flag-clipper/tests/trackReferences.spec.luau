local parser = require("@std/syntax/parser")

local TrackReferences = require("../TrackReferences")

local function isReference(source: string, flag: string?)
	local expression = parser.parseexpr(source)
	local references = TrackReferences.new(flag or "FlagName", true, {})
	references:_visitExpressionForTesting(expression)
	return references:isReference(expression)
end

local function test_directFlagAccess()
	assert(isReference("game:GetFastFlag('FlagName')", "FlagName") == true)
	assert(isReference("game:GetFastFlag('OtherFlagName')", "FlagName") == false)

	assert(isReference("game:DefineFastFlag('FlagName', false)", "FlagName") == true)
	assert(isReference("game:DefineFastFlag('OtherFlagName', false)", "FlagName") == false)
end

local function test_flagAccessViaLocalVariable()
	local block = parser.parse([[
		local flagValue = game:GetFastFlag("FlagName")
		print(flagValue)
	]])
	assert(#block.statements == 2)

	local call = block.statements[2]
	assert(call.tag == "expression")
	assert(call.expression.tag == "call")
	assert(#call.expression.arguments == 1)

	local expr = call.expression.arguments[1].node

	local references = TrackReferences.new("FlagName", true, {})
	references:visit(block)
	assert(references:isReference(expr) == true)
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

	local references = TrackReferences.new("FlagName", true, {})
	references:visit(block)
	assert(references:isReference(expr) == false)
end

local function test_flagAccessViaLocalCall()
	local block = parser.parse([[
		local function getFlagValue()
			return game:GetFastFlag("FlagName")
		end
		getFlagValue()
	]])
	assert(#block.statements == 2)

	local call = block.statements[2]
	assert(call.tag == "expression")
	assert(call.expression.tag == "call")
	assert(call.expression.func.tag == "local")

	local references = TrackReferences.new("FlagName", true, {})
	references:visit(block)
	assert(references:isReference(call.expression) == true)
end

local function test_ignoreUnknownLocalCalls()
	local block = parser.parse([[
		local function getRandomValue() end
		getRandomValue()
	]])
	assert(#block.statements == 2)

	local call = block.statements[2]
	assert(call.tag == "expression")

	local references = TrackReferences.new("FlagName", true, {})
	references:visit(block)
	assert(references:isReference(call.expression) == false)
end

local function test_flagAccessViaGlobalCall()
	local block = parser.parse([[
		function globalGetFlagValue()
			return game:GetFastFlag("FlagName")
		end
		globalGetFlagValue()
	]])
	assert(#block.statements == 2)

	local call = block.statements[2]
	assert(call.tag == "expression")
	assert(call.expression.tag == "call")
	assert(call.expression.func.tag == "global")

	local references = TrackReferences.new("FlagName", true, {})
	references:visit(block)
	assert(references:isReference(call.expression) == true)

	-- expr = parser.parseexpr("randomGlobalCall()")
	-- assert(references:isReference(expr) == false)
end

local function test_ignoreUnknownGlobalCalls()
	local block = parser.parse([[
		function globalRandomFunction()
		end
		globalRandomFunction()
	]])
	assert(#block.statements == 2)

	local call = block.statements[2]
	assert(call.tag == "expression")
	assert(call.expression.tag == "call")
	assert(call.expression.func.tag == "global")

	local references = TrackReferences.new("FlagName", true, {})
	references:visit(block)
	assert(references:isReference(call.expression) == false)
end

local function test_flagAccessViaTableIndex()
	local block = parser.parse([[
		local tbl = {
			flagValue = game:GetFastFlag("FlagName")
		}
		print(tbl.flagValue)
	]])
	assert(#block.statements == 2)

	local call = block.statements[2]
	assert(call.tag == "expression")
	assert(call.expression.tag == "call")
	assert(#call.expression.arguments == 1)

	local expression = call.expression.arguments[1].node
	assert(expression.tag == "indexname")

	local references = TrackReferences.new("FlagName", true, {})
	references:visit(block)
	assert(references:isReference(expression) == true)
end

local function test_ignoreUnknownTableReference()
	local block = parser.parse([[
		local tbl = {
			flagValue = game:GetFastFlag("FlagName")
		}
		print(tbl.otherProperty)
	]])
	assert(#block.statements == 2)

	local call = block.statements[2]
	assert(call.tag == "expression")
	assert(call.expression.tag == "call")
	assert(#call.expression.arguments == 1)

	local expression = call.expression.arguments[1].node
	assert(expression.tag == "indexname")

	local references = TrackReferences.new("FlagName", true, {})
	references:visit(block)
	assert(references:isReference(expression) == false)
end

local function test_flagAccessViaTableFunctionCall()
	local block = parser.parse([[
		local tbl = {
			flagValue = function()
				return game:GetFastFlag("FlagName")
			end
		}
		tbl.flagValue()
	]])
	assert(#block.statements == 2)

	local call = block.statements[2]
	assert(call.tag == "expression")
	assert(call.expression.tag == "call")
	assert(call.expression.func.tag == "indexname")

	local references = TrackReferences.new("FlagName", true, {})
	references:visit(block)

	assert(references:isReference(call.expression) == true)
end

local function test_flagAccessViaNestedTables()
	local block = parser.parse([[
		local tbl = {
			other = {
				flagValue = game:GetFastFlag("FlagName")
			}
		}
		print(tbl.other.flagValue)
	]])
	assert(#block.statements == 2)

	local call = block.statements[2]
	assert(call.tag == "expression")
	assert(call.expression.tag == "call")
	assert(#call.expression.arguments == 1)

	local expression = call.expression.arguments[1].node
	assert(expression.tag == "indexname")

	local references = TrackReferences.new("FlagName", true, {})
	references:visit(block)
	assert(references:isReference(expression) == true)
end

local function test_binaryFlagAccess()
	local block = parser.parse([[
		local x = not game:DefineFastFlag("FlagName") and arbitraryCondition -- definitively evaluates to false
		local y = game:DefineFastFlag("FlagName") or arbitraryCondition -- definitively evaluates to true
	]])

	assert(#block.statements == 2)

	local andFlagAccess = block.statements[1].values[1].node
	local orFlagAccess = block.statements[2].values[1].node

	local references = TrackReferences.new("FlagName", true, {})
	references:visit(block)

	assert(references:isReference(andFlagAccess) == true)
	assert(references:isReference(orFlagAccess) == true)
	assert(references:getReferenceValue(andFlagAccess) == false)
	assert(references:getReferenceValue(orFlagAccess) == true)
end

local function test_unaryFlagAccess()
	local block = parser.parse([[
		local x = not game:DefineFastFlag("FlagName")
	]])

	assert(#block.statements == 1)

	local unaryFlagAccess = block.statements[1].values[1].node

	local references = TrackReferences.new("FlagName", true, {})
	references:visit(block)

	assert(references:isReference(unaryFlagAccess) == true)
	assert(references:getReferenceValue(unaryFlagAccess) == false)
end

local function test_psuedoTernaryFlagAccess()
	local block = parser.parse([[
		local x = game:DefineFastFlag("FlagName") and (game:DefineFastFlag("FlagName") or abitraryCondition)
		local y = not game:DefineFastFlag("FlagName") or (not game:DefineFastFlag("FlagName") and arbitraryCondition)
	]])

	assert(#block.statements == 2)

	local a = block.statements[1].values[1].node
	local b = block.statements[2].values[1].node

	local references = TrackReferences.new("FlagName", true, {})
	references:visit(block)

	assert(references:isReference(a) == true)
	assert(references:getReferenceValue(a) == true)
	assert(references:isReference(b) == true)
	assert(references:getReferenceValue(b) == false)
end

local function test_falsePositiveCompoundFlagAccess()
	-- we only want to track a node if we can definitively simplify it's value to a boolean literal
	-- so nodes like (assuming Flag is true): Flag and someCondition
	-- should NOT be tracked
	local block = parser.parse([[
		local x = game:DefineFastFlag("FlagName") and arbitraryCondition
		local y = not game:DefineFastFlag("FlagName") or arbitraryCondition
		local z = game:DefineFastFlag("FlagName") and not game:DefineFastFlag("FlagName") or arbitraryCondition
	]])

	assert(#block.statements == 3)

	local andFlagAccess = block.statements[1].values[1].node
	local orFlagAccess = block.statements[2].values[1].node
	local psuedoTernaryFlagAccess = block.statements[3].values[1].node

	local references = TrackReferences.new("FlagName", true, {})
	references:visit(block)

	assert(references:isReference(andFlagAccess) == false)
	assert(references:isReference(orFlagAccess) == false)
	assert(references:isReference(psuedoTernaryFlagAccess) == false)
end

return function()
	test_directFlagAccess()
	test_flagAccessViaLocalVariable()
	test_ignoreUnknownLocalVariables()
	test_flagAccessViaLocalCall()
	test_ignoreUnknownLocalCalls()
	test_flagAccessViaGlobalCall()
	test_ignoreUnknownGlobalCalls()
	test_flagAccessViaTableIndex()
	test_ignoreUnknownTableReference()
	test_flagAccessViaTableFunctionCall()
	test_flagAccessViaNestedTables()
	test_binaryFlagAccess()
	test_unaryFlagAccess()
	test_psuedoTernaryFlagAccess()
	test_falsePositiveCompoundFlagAccess()
end
