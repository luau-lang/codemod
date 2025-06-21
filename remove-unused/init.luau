local luau = require("@lute/luau")
local findVariables = require("./remove-unused/findVariablesUtils").findVariables
local deleteVariables = require("./remove-unused/deleteVariables")
local parser = require("@batteries/syntax/parser")
local printer = require("@batteries/syntax/printer")

local codemod = require("./lib/types")

local function migration(ctx: codemod.Context<Options>)
	local result = parser.parsefile(ctx.source)
	local block = result.root

	local numDeletions = 1
	local _vars, deletions
	while numDeletions > 0 do
		_vars, deletions, numDeletions = findVariables(block)
		if numDeletions > 0 then
			block = deleteVariables(block, deletions)
		end
	end

	return printer.printfile({ root = block, eof = result.eof })
end

return migration
