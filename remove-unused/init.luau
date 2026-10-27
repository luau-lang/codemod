--[[
    remove-unused codemod - Main Entry Point
    
    This codemod identifies and removes unused variables and functions from Lua/Luau code.

    The codemod supports integration with selene linting rules to respect
    file exclusions. It also handles iterative deletion in case removing some
    variables or functions makes others unused.
]]

local cst = require("@lute/syntax/mutablecst")
local fs = require("@std/fs")
local findVariables = require("./remove-unused/findVariablesUtils").findVariables
local deleteVariables = require("./remove-unused/deleteVariables")
local parser = require("@lute/syntax/parser")
local printer = require("@std/syntax/printer")
local helpers = require("./remove-unused/helpers/seleneHelpers")
local getSeleneExclude = helpers.getSeleneExclude
local excludeFile = helpers.excludeFile

local codemod = require("./lib/types")

-- Global cache for selene exclude patterns
local seleneExclude: { string } = {}

--[[
    Initialize the codemod with options.
    
    Loads the selene.toml configuration if provided to respect file exclusions.
    This allows the codemod to skip files that are excluded from linting.
    
    @param ctx - The initialization context containing options
]]
local function initialize(ctx: codemod.InitializationContext<Options>)
	if ctx.options.selene ~= "" then
		local seleneTomlSrc = fs.readFileToString(ctx.options.selene)
		seleneExclude = getSeleneExclude(seleneTomlSrc)
	end
end

--[[
    This function applies the following process:
    1. Parse the source code into an AST
    2. Check if the file is excluded by selene rules
    3. Iteratively find and remove unused functions and variables
       (since removing some variables may make others unused)
    4. Print the modified AST back to source code
    
    @param ctx - The transformation context containing the source code and path
    @return - The transformed source code with unused variables removed
]]
local function transform(ctx: codemod.Context<Options>)
	local result = parser.parseMutable(ctx.source)
	local block = result.root

	if not excludeFile(ctx.path, seleneExclude) then
		local numDeletions, removalExceptions = 1, 0
		local _vars, deletions
		while numDeletions > 0 do
			_vars, deletions, numDeletions = findVariables(block)
			numDeletions -= removalExceptions
			if numDeletions > 0 then
				block, removalExceptions = deleteVariables(block, deletions)
			end
		end
	else
		print(`Skipping {ctx.path} as per selene exlude`)
	end

	return printer.printFile({ root = block, eof = result.eof })
end

return {
	options = {
		{ name = "selene", kind = "string" },
	},
	initialize = initialize,
	transform = transform,
}
