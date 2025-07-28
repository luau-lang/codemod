local luau = require("@lute/luau")

local parser = require("@std/syntax/parser")
local printer = require("@std/syntax/printer")
local visitor = require("@std/syntax/visitor")

local codemod = require("./lib/types")
local sourcemap = require("./require-resolver/sourcemap")
local requireTracer = require("./require-resolver/tracer")
local fileResolver = require("./require-resolver/resolver")

local TrackReferences = require("@self/TrackReferences")
local isFlagModule = require("@self/matchers/isFlagModule")
local modified = require("@self/modified")
local simplifyExpression = require("@self/simplifyExpression")
local simplifyBlock = require("@self/simplifyBlock")

--- Global cache for sourcemap data
local SourcemapData: sourcemap.SourcemapData? = nil

local function inplaceReplace(old: luau.AstExpr, new: luau.AstExpr, references: TrackReferences.TrackReferences)
	if old == new then
		return
	end

	-- We abuse the fact that everything is table references, and inplace change the old node into the new one
	-- TODO: we should probably make mutability more explicit
	table.clear(old)

	for k, v in new do
		old[k] = v
	end

	-- Since `new` expr is now replacing `old`, we need to update the references mapping as it works
	-- based on table pointer equality
	references._expressions[old] = references._expressions[new]

	modified.setModified(old)
end

type Options = {
	flag: string,
	value: boolean,
	--- Path to a sourcemap file to resolve virtual requires.
	--- If not provided, defaults to an empty string
	sourcemap: string,
}

local function initialize(ctx: codemod.InitializationContext<Options>)
	print(`Removing {ctx.options.flag} as {ctx.options.value}`)

	-- Populate sourcemap data on first codemod execution
	if ctx.options.sourcemap ~= "" then
		print(`Parsing sourcemap at {ctx.options.sourcemap}`)
		SourcemapData = sourcemap.parseSourcemap(ctx.options.sourcemap)
	end
end

local function transform(ctx: codemod.Context<Options>)
	local result = parser.parsefile(ctx.source)
	local block = result.root

	local requireInfo = requireTracer.traceRequires(block, ctx.path, fileResolver.createFileResolver(SourcemapData))
	local references = TrackReferences.new(ctx.options.flag, requireInfo, SourcemapData)
	references:visit(block)

	-- Early check: if is a flag module, mark for deletion
	if isFlagModule(block, ctx.options.flag) then
		return codemod.DELETION_MARKER
	end

	local flagVisitor = visitor.createVisitor()

	local simplifyCtx = {
		flagName = ctx.options.flag,
		flagValue = ctx.options.value,
		references = references,
	}

	-- TODO: might want to double check the complexity here, since `simplifyExpression` is also recursive
	-- do we end up simplifying it twice?
	flagVisitor.visitExpressionEnd = function(expression: luau.AstExpr)
		local newExpression = simplifyExpression(expression, simplifyCtx)
		inplaceReplace(expression, newExpression, references)
	end

	flagVisitor.visitBlockEnd = function(block)
		local newBlock = simplifyBlock(block, simplifyCtx)
		block.statements = newBlock.statements
	end

	visitor.visitBlock(block, flagVisitor)

	return printer.printfile({ root = block, eof = result.eof })
end

return {
	options = {
		{ name = "flag", kind = "string" },
		{ name = "value", kind = "boolean", default = true },
		{ name = "sourcemap", kind = "string", default = "" },
	},
	initialize = initialize,
	transform = transform,
}
