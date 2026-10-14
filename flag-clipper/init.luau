local parser = require("@std/syntax/parser")
local printer = require("@std/syntax/printer")
local syntax = require("@std/syntax")
local visitor = require("@std/syntax/visitor")

local codemod = require("./lib/types")
local sourcemap = require("./require-resolver/sourcemap")
local requireTracer = require("./require-resolver/tracer")
local fileResolver = require("./require-resolver/resolver")

local Rewriter = require("@self/Rewriter")
local TrackReferences = require("@self/TrackReferences")
local evaluate = require("@self/evaluate")
local isFlagModule = require("@self/matchers/isFlagModule")
local simplifyExpression = require("@self/simplifyExpression")
local simplifyBlock = require("@self/simplifyBlock")

--- Global cache for sourcemap data
local SourcemapData: sourcemap.SourcemapData? = nil

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
	local result = parser.parse(ctx.source)
	local block = result.root

	local requireInfo = requireTracer.traceRequires(block, ctx.path, fileResolver.createFileResolver(SourcemapData))
	local references = TrackReferences.new(ctx.options.flag, ctx.options.value, requireInfo, SourcemapData)
	references:visit(block)

	-- Early check: if is a flag module, mark for deletion
	if isFlagModule(block, ctx.options.flag) then
		return codemod.DELETION_MARKER
	end

	local rewriter = Rewriter.new(references)
	local simplifyCtx: evaluate.EvaluateContext = {
		flagValue = ctx.options.value,
		references = references,
		rewriter = rewriter,
	}

	local flagVisitor = visitor.create()

	-- TODO: might want to double check the complexity here, since `simplifyExpression` is also recursive
	-- do we end up simplifying it twice?
	flagVisitor.visitExprEnd = function(expression: syntax.CstExpr)
		rewriter:replace(expression, simplifyExpression(expression, simplifyCtx))
	end

	flagVisitor.visitStatBlockEnd = function(block: syntax.CstStatBlock)
		simplifyBlock(block, simplifyCtx)
	end

	visitor.visitBlock(block, flagVisitor)

	return printer.printFile(result, rewriter.replacements)
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
