local parser = require("@std/syntax/parser")
local isFlagModule = require("../matchers/isFlagModule")

local function test_emptyBlock()
	local block = parser.parseblock([[

	]])

	assert(isFlagModule(block, "FlagName") == false)
end

local function test_blockWithNoReturn()
	local block = parser.parseblock([[
		local x = 1
	]])

	assert(isFlagModule(block, "FlagName") == false)
end

local function test_blockWithReturnNoExpression()
	local block = parser.parseblock([[
		return
	]])

	assert(isFlagModule(block, "FlagName") == false)
end

local function test_blockWithUnrelatedReturn()
	local block = parser.parseblock([[
		return "value"
	]])

	assert(isFlagModule(block, "FlagName") == false)
end

local function test_blockWithDefinitionReturn()
	local block = parser.parseblock([[
		return game:DefineFastFlag("FlagName")
	]])

	local result, kind = isFlagModule(block, "FlagName")
	assert(result == true)
	assert(kind == "constant")
end

local function test_blockWithGetReturn()
	local block = parser.parseblock([[
		return game:GetFastFlag("FlagName")
	]])

	local result, kind = isFlagModule(block, "FlagName")
	assert(result == true)
	assert(kind == "constant")
end

local function test_blockWithFunctionReturn()
	local block = parser.parseblock([[
		return function()
			return game:GetFastFlag("FlagName")
		end
	]])

	local result, kind = isFlagModule(block, "FlagName")
	assert(result == true)
	assert(kind == "function")
end

local function test_blockWithVariableReturnPointingToFunction()
	local block = parser.parseblock([[
		local function getFFlag()
			return game:GetFastFlag("FlagName")
		end

		return getFFlag
	]])

	local result, kind = isFlagModule(block, "FlagName")
	assert(result == true)
	assert(kind == "function")
end

return function()
	test_emptyBlock()
	test_blockWithNoReturn()
	test_blockWithReturnNoExpression()
	test_blockWithUnrelatedReturn()
	test_blockWithDefinitionReturn()
	test_blockWithGetReturn()
	test_blockWithFunctionReturn()
	test_blockWithVariableReturnPointingToFunction()
end
