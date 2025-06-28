local luau = require("@lute/luau")
local fs = require("@lute/fs")
local findVariables = require("./remove-unused/findVariablesUtils").findVariables
local deleteVariables = require("./remove-unused/deleteVariables")
local parser = require("@batteries/syntax/parser")
local printer = require("@batteries/syntax/printer")
local helpers = require("./remove-unused/helpers/seleneHelpers")
local getSeleneExclude = helpers.getSeleneExclude
local excludeFile = helpers.excludeFile

local codemod = require("./lib/types")

-- Global cache for selene exclude patterns
local seleneExclude: { string } = {}

local function initialize(ctx: codemod.InitializationContext<Options>)
	if ctx.options.selene ~= "" then
		local seleneTomlSrc = fs.readfiletostring(ctx.options.selene)
		seleneExclude = getSeleneExclude(seleneTomlSrc)
	end
end

local function transform(ctx: codemod.Context<Options>)
	local result = parser.parsefile(ctx.source)
	local block = result.root

	if not excludeFile(ctx.path, seleneExclude) then
		local numDeletions = 1
		local _vars, deletions
		while numDeletions > 0 do
			_vars, deletions, numDeletions = findVariables(block)
			if numDeletions > 0 then
				block = deleteVariables(block, deletions)
			end
		end
	end

	return printer.printfile({ root = block, eof = result.eof })
end

return {
	options = {
		{ name = "selene", kind = "string" },
	},
	initialize = initialize,
	transform = transform,
}
