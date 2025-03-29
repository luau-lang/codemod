local codemod = require("../init").transform
local types = require("../../types")

local function apply(source: string, flagName: string?, value: boolean?)
	flagName = flagName or "FlagName"
	value = if value == nil then true else value
	return codemod({ path = "", source = source, options = { flag = flagName, value = value } })
end

local function test_markFlagModuleForDeletion()
	local source = [[
		return function()
			return game:GetFastFlag("FlagName")
		end
	]]

	assert(apply(source) == types.DELETION_MARKER)
end

return function()
	test_markFlagModuleForDeletion()
end
