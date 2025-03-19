local parser = require("@batteries/syntax/parser")
local printer = require("@batteries/syntax/printer")

local simplifyBlock = require("../simplifyBlock")

-- TODO: parser needs to handle EOF whitespace properly
local function FIXME_trailingWhitspace(str: string)
	local trailing_whitespace = ""
	local i = #str

	while i > 0 and (str:sub(i, i) == " " or str:sub(i, i) == "\t" or str:sub(i, i) == "\n" or str:sub(i, i) == "\r") do
		trailing_whitespace = str:sub(i, i) .. trailing_whitespace
		i = i - 1
	end

	return trailing_whitespace
end

local function apply(source: string, flagName: string?)
	flagName = flagName or "FlagName"
	local result = printer.print(simplifyBlock(parser.parse(source), flagName))

	if result ~= "" then
		return result .. FIXME_trailingWhitspace(source)
	else
		return result
	end
end

local function test_removeDefinition()
	local source = [[
		game:DefineFastFlag("FlagName", false)
	]]

	local expected = ""

	assert(apply(source, "FlagName") == expected)
end

local function test_removeGetterCall()
	local source = [[
		game:GetFastFlag("FlagName")
	]]

	local expected = ""

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
		if true then
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
		if false then
			local x = 1
		else
			local x = 2
		end
	]]

	local expected = [[
			local x = 2

	]]

	assert(apply(source) == expected)
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
		if false then
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

	assert(apply(source, "FlagName") == expected)
end

local function test_simplifyIfIntoElseif()
	local source = [[
		if false then
			local x = 1
		elseif true then
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
		if false then
			local x = 1
		elseif false then
			local x = 2
		else
			local x = 3
		end
	]]

	local expected = [[
			local x = 3

	]]

	assert(apply(source, "FlagName") == expected)
end

return function()
	test_removeDefinition()
	test_removeGetterCall()
	test_preservesUnrelatedCalls()
	test_simplifyVariableAssignment()
	test_simplifyIfStatementRemoveElse()
	test_simplifyIfStatementRemoveIf()
	test_keepComplicatedIf()
	-- TODO:
	-- test_simplifyIfStatementRemoveIfKeepElseif()
	-- test_simplifyIfIntoElseif()
	-- test_simplifyIfAndElseIf()
end
