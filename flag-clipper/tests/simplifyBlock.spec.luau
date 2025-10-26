local parser = require("@std/syntax/parser")
local printer = require("@std/syntax/printer")

local evaluate = require("../evaluate")
local simplifyBlock = require("../simplifyBlock")
local TrackReferences = require("../TrackReferences")

local repoToFlagName: { [string]: string } = {
	["Foundation"] = 'SafeFlags.createGetFFlag("FlagName")()',
	["LuaApps"] = 'game:GetFastFlag("FlagName")',
	["UIBlox"] = "UIBloxConfig.FlagName",
}

local function apply(source: string, flagName: string?, flagValue: boolean?)
	flagName = flagName or "FlagName"
	flagValue = if flagValue ~= nil then flagValue else true

	local references = TrackReferences.new(flagName or "FlagName", flagValue :: boolean, {})

	local context: evaluate.EvaluateContext = {
		flagName = flagName,
		flagValue = flagValue,
		references = references,
	}

	local parseResult = parser.parsefile(source)
	references:visit(parseResult.root)
	parseResult.root = simplifyBlock(parseResult.root, context)
	return printer.printfile(parseResult)
end

local function test_removeDefinition()
	local source = [[
		game:DefineFastFlag("FlagName", false)
	]]

	local expected = [[
	]]

	assert(apply(source, "FlagName") == expected)
end

local function test_removeGetterCall()
	local source = [[
		game:GetFastFlag("FlagName")
	]]

	local expected = [[
	]]

	assert(apply(source, "FlagName") == expected)
end

local function test_preservesUnrelatedCalls()
	local source = [[
		game:GetFastFlag("OtherName")
		game:GetFastFlag("OtherName")
	]]

	assert(apply(source, "FlagName") == source)
end

local function test_simplifyIfStatementRemoveElse()
	local source = [[
		if game:GetFastFlag("FlagName") then
			local x = 1
		else
			local x = 2
		end
	]]

	local expected = [[
			local x = 1
	]]

	assert(apply(source) == expected)
end

local function test_simplifyIfStatementRemoveIf()
	local source = [[
		if game:GetFastFlag("FlagName") then
			local x = 1
		else
			local x = 2
		end
	]]

	local expected = [[
			local x = 2
	]]

	assert(apply(source, "FlagName", false) == expected)
end

local function test_keepComplicatedIf()
	local source = [[
		if x then
			local x = 1
		else
			local x = 2
		end
	]]

	assert(apply(source, "FlagName") == source)
end

local function test_simplifyIfStatementRemoveIfKeepElseif()
	local source = [[
		if game:GetFastFlag("FlagName") then
			local x = 1
		elseif value then
			local x = 2
		else
			local x = 3
		end
	]]

	local expected = [[
		if value then
			local x = 2
		else
			local x = 3
		end
	]]

	assert(apply(source, "FlagName", false) == expected)
end

local function test_simplifyIfIntoElseif()
	local source = [[
		if false then
			local x = 1
		elseif game:GetFastFlag("FlagName") then
			local x = 2
		else
			local x = 3
		end
	]]

	local expected = [[
		if false then
			local x = 1
		else
			local x = 2
		end
	]]

	assert(apply(source, "FlagName") == expected)
end

local function test_simplifyElseIfIntermediateCondition()
	local source = [[
		if value then
			local x = 1
		elseif game:GetFastFlag("FlagName") then
			local x = 2
		else
			local x = 3
		end
	]]

	local expected = [[
		if value then
			local x = 1
		else
			local x = 2
		end
	]]

	assert(apply(source, "FlagName") == expected)
end

local function test_simplifyElseIfMultipleLevels()
	local source = [[
		if value then
			local x = 1
		elseif value2 then
			local x = 2
		elseif game:GetFastFlag("FlagName") then
			local x = 3
		else
			local x = 4
		end
	]]

	local expected = [[
		if value then
			local x = 1
		elseif value2 then
			local x = 2
		else
			local x = 3
		end
	]]

	assert(apply(source, "FlagName") == expected)
end

local function test_simplifyIfAndElseIf()
	local source = [[
		if game:GetFastFlag("FlagName") then
			local x = 1
		elseif game:GetFastFlag("FlagName") then
			local x = 2
		else
			local x = 3
		end
	]]

	local expected = [[
			local x = 3
	]]

	assert(apply(source, "FlagName", false) == expected)
end

local function test_simplifyBlockIntoNothing()
	local source = [[
		if game:GetFastFlag("FlagName") then
			local x = 1
		end
	]]

	local expected = [[
	]]

	assert(apply(source, "FlagName", false) == expected)
end

local function test_simplifyIfGroupCondition()
	local source = [[
		if (game:GetFastFlag("FlagName")) then
			local x = 1
		else
			local x = 2
		end
	]]

	local expected = [[
			local x = 1
	]]

	assert(apply(source, "FlagName", true) == expected)
end

local function test_simplifyAssignmentExpression()
	local source = [[
		variable = game:GetFastFlag("FlagName")
		variable2 = not game:GetFastFlag("FlagName")
		variable3 = (game:GetFastFlag("FlagName"))
		variable4 = (not game:GetFastFlag("FlagName"))
	]]

	local expected = [[
		variable = true
		variable2 = false
		variable3 = true
		variable4 = false
	]]

	assert(apply(source, "FlagName", true) == expected)
end

local function test_simplifyLocalExpression()
	local source = [[
		local variable = not game:GetFastFlag("FlagName")
		local variable2 = (not game:GetFastFlag("FlagName"))
	]]

	local expected = ""

	assert(apply(source, "FlagName", true):gsub("%s+", "") == expected)
end

local function test_simplifyAssignmentExpressionFlagFalse()
	local source = [[
		variable = game:GetFastFlag("FlagName")
		variable2 = not game:GetFastFlag("FlagName")
	]]

	local expected = [[
		variable = false
		variable2 = true
	]]

	assert(apply(source, "FlagName", false) == expected)
end

local function test_simplifyAssignmentAfterBlockCollapse()
	local source = [[
		local variable
		if game:GetFastFlag("FlagName") then
			variable = 1
		end
	]]

	local expected = [[
		local variable = 1
	]]

	assert(apply(source, "FlagName", true) == expected)
end

local function test_simplifyAssignmentWhenInitiallyAssignedToAValueAfterBlockCollapse()
	local source = [[
		local variable = true
		if game:GetFastFlag("FlagName") then
			variable = 1
		end
	]]

	local expected = [[
		local variable = 1
	]]

	assert(apply(source, "FlagName", true) == expected)
end

local function test_simplifyReassignment(repo: string)
	local source = [[local FlagName = ]] .. repoToFlagName[repo] .. [[

		FlagName = true
	]]

	local expected = [[
	]]
	assert(apply(source, "FlagName", true) == expected)
end

local function test_simplifyConditionalEarlyReturn()
	local source = [[
			if game:GetFastFlag("FlagName") then
				return 1
			end
			return 2
		]]
	local expected = [[
				return 1
		]]
	assert(apply(source) == expected)
end

local function test_dontSimplifyAssignmentIfVariableIsPresentOnRHS()
	local source = [[
		local variable = true
		if game:GetFastFlag("FlagName") then
			variable = apply(variable)
		end
	]]

	local expected = [[
		local variable = true
			variable = apply(variable)
	]]

	assert(apply(source, "FlagName", true) == expected)
end

local function test_simplifyReturn()
	assert(apply('return game:GetFastFlag("FlagName")', "FlagName", true) == "return true")
	assert(apply('return not game:GetFastFlag("FlagName")', "FlagName", true) == "return false")
end

local function test_simplifyReturnFlagFalse()
	assert(apply('return game:GetFastFlag("FlagName")', "FlagName", false) == "return false")
	assert(apply('return not game:GetFastFlag("FlagName")', "FlagName", false) == "return true")
end

return function()
	test_removeDefinition()
	test_removeGetterCall()
	test_preservesUnrelatedCalls()
	test_simplifyIfStatementRemoveElse()
	test_simplifyIfStatementRemoveIf()
	test_keepComplicatedIf()
	test_simplifyIfStatementRemoveIfKeepElseif()
	test_simplifyIfIntoElseif()
	test_simplifyElseIfIntermediateCondition()
	test_simplifyElseIfMultipleLevels()
	test_simplifyIfAndElseIf()
	test_simplifyIfGroupCondition()
	test_simplifyBlockIntoNothing()
	test_simplifyAssignmentExpression()
	test_simplifyLocalExpression()
	test_simplifyAssignmentExpressionFlagFalse()
	test_simplifyAssignmentAfterBlockCollapse()
	test_simplifyAssignmentWhenInitiallyAssignedToAValueAfterBlockCollapse()
	for repo, _v in repoToFlagName do
		test_simplifyReassignment(repo)
	end
	test_simplifyConditionalEarlyReturn()
	test_dontSimplifyAssignmentIfVariableIsPresentOnRHS()
	test_simplifyReturn()
	test_simplifyReturnFlagFalse()
end
