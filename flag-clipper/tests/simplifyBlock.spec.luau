local parser = require("@batteries/syntax/parser")
local printer = require("@batteries/syntax/printer")

local evaluate = require("../evaluate")
local simplifyBlock = require("../simplifyBlock")
local TrackReferences = require("../TrackReferences")

local function apply(source: string, flagName: string?, flagValue: boolean?)
	flagName = flagName or "FlagName"
	flagValue = if flagValue ~= nil then flagValue else true

	local references = TrackReferences.new(flagName or "FlagName", {})

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

local function test_simplifyVariableAssignment()
	local source = [[
		local x
		x = function()
			return true
		end
	]]

	local expected = [[
		local x = function()
			return true
		end
	]]

	assert(apply(source) == expected)
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
			local x = 2
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

return function()
	test_removeDefinition()
	test_removeGetterCall()
	test_preservesUnrelatedCalls()
	-- TODO:
	-- test_simplifyVariableAssignment()
	test_simplifyIfStatementRemoveElse()
	test_simplifyIfStatementRemoveIf()
	test_keepComplicatedIf()
	test_simplifyIfStatementRemoveIfKeepElseif()
	test_simplifyIfIntoElseif()
	test_simplifyIfAndElseIf()
	test_simplifyBlockIntoNothing()
end
