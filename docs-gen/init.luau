local FileVisitor = require("./docs-gen/fileUtils").FileVisitor
local codemod = require("./lib/types")

type Options = {
	sourcemap: string,
	luauRc: string,
}

local function transform(ctx: codemod.Context<Options>)
	local prototypeVisitor = FileVisitor.new(ctx.options.luauRc, ctx.options.sourcemap)
	prototypeVisitor:analyzeFile(ctx.path)
	print("\nTypes:")
	for k, v in prototypeVisitor.typeMap do
		print(k, v)
	end
	print("\nVars:")
	for k, v in prototypeVisitor.varMap do
		print(k, v)
	end
	print("\nReturned Vars:")
	for k, v in prototypeVisitor.returnedVars do
		print(k, v.tag)
	end
	print("\nRequired Vars:")
	for k, v in prototypeVisitor.requireCalls do
		print(k, v)
	end
	print("\nDependency Paths:")
	for k, v in prototypeVisitor.dependencies do
		print(k, v)
	end
	print("\nExport Paths:")
	for k, v in prototypeVisitor.exports do
		print(k, v)
	end
	return ctx.source
end

return {
	options = {
		{ name = "sourcemap", kind = "string", default = "" },
		{ name = "luauRc", kind = "string", default = "" },
	},
	transform = transform,
}

--[[
getClassSignature(tableNode: AstState): string
much trickier; we kinda need to scrape an entire file for this, and can't just extract from the initial declaration...
hmmmm
]]
