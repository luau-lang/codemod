local codemod = require("../").transform
local types = require("../../lib/types")

local function apply(source: string, flagName: string?, value: boolean?)
	flagName = flagName or "FlagName"
	value = if value == nil then true else value
	return codemod({ path = "", source = source, options = { flag = flagName, value = value, sourcemap = "" } })
end

local function test_markFlagModuleForDeletion()
	local source = [[
		return function()
			return game:GetFastFlag("FlagName")
		end
	]]

	assert(apply(source) == types.DELETION_MARKER)
end

local function test_overallSingleFile()
	local source = [[
		print("Example Module")

		-- Remove references to the flag
		game:DefineFastFlag("FlagName")
		local flagValue = game:GetFastFlag("FlagName")

		-- Leave other flags alone
		game:DefineFastFlag("OtherFlagName")
		local otherFlagValue = game:GetFastFlag("OtherFlagName")

		-- Remove flag getter functions
		local function getFlagValueLocal()
			return game:GetFastFlag("FlagName")
		end

		function getFlagValueGlobal()
			return game:GetFastFlag("FlagName")
		end

		-- But leave unrelated functions alone, and keep the comments!
		local function getOtherFlagValueLocal()
			return game:GetFastFlag("OtherFlagName")
		end

		function getOtherFlagValueGlobal()
			return game:GetFastFlag("OtherFlagName")
		end

		-- Simplify if blocks
		print("Simplify code")

		if game:GetFastFlag("FlagName") then
			print("Fast flag enabled! Direct access")
		else
			print("Fast flag disabled. Direct access")
		end

		if flagValue then
			print("Fast flag enabled! Variable access")
		else
			print("Fast flag disabled. Variable access")
		end

		if getFlagValueLocal() then
			print("Fast flag enabled! Local call access")
		else
			print("Flag value disabled. Local call access")
		end

		if getFlagValueGlobal() then
			print("Fast flag enabled! Global call access")
		else
			print("Fast flag disabled. Global call access")
		end

		if not flagValue then
			print("Flag value disabled. Unary check")
		else
			print("Fast flag enabled! Unary check")
		end

		if flagValue and otherFlagValue then
			print("Both fast flags are enabled")
		else
			print("Both fast flags are not enabled")
		end

		if flagValue or randomFunctionCall() then
			print("Either the fast flag was enabled, or some other expression passed")
		else
			print("Neither the flag was enabled, nor did the other expression pass")
		end
	]]

	local expected = [[
		print("Example Module")

		-- Leave other flags alone
		game:DefineFastFlag("OtherFlagName")
		local otherFlagValue = game:GetFastFlag("OtherFlagName")

		-- But leave unrelated functions alone, and keep the comments!
		local function getOtherFlagValueLocal()
			return game:GetFastFlag("OtherFlagName")
		end

		function getOtherFlagValueGlobal()
			return game:GetFastFlag("OtherFlagName")
		end

		-- Simplify if blocks
		print("Simplify code")

			print("Fast flag enabled! Direct access")

			print("Fast flag enabled! Variable access")

			print("Fast flag enabled! Local call access")

			print("Fast flag enabled! Global call access")

			print("Fast flag enabled! Unary check")

		if otherFlagValue then
			print("Both fast flags are enabled")
		else
			print("Both fast flags are not enabled")
		end

			print("Either the fast flag was enabled, or some other expression passed")
	]]

	assert(apply(source) == expected)
end

local function test_compoundCondition()
	local source = [[
		if game:GetFastFlag("FlagName") or value then
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

local function test_compoundConditionWithUnary()
	local source = [[
		if value and not game:GetFastFlag("FlagName") then
			local x = 1
		else
			local x = 2
		end
	]]

	local expected = [[
			local x = 2
	]]

	assert(apply(source, "FlagName", true) == expected)
end

return function()
	test_markFlagModuleForDeletion()
	test_compoundCondition()
	test_compoundConditionWithUnary()
end
