--!strict
local process = require("@lute/process")

local parser = require("@std/syntax/parser")
local printer = require("@std/syntax/printer")
local syntax = require("@std/syntax")
local syntaxTypes = require("@std/syntax/types")

local path = require("./lib/path")
local codemod = require("./lib/types")

local query = require("./lib/query")
local isRequire = require("./require-resolver/isRequire")
local fileResolver = require("./require-resolver/resolver")
local requireTracer = require("./require-resolver/tracer")
local sourcemap = require("./require-resolver/sourcemap")

local computeOptimalRequireString = require("@self/computeOptimalRequireString")

--- Global cache for sourcemap data
local SourcemapData: sourcemap.SourcemapData? = nil

type Options = {
	sourcemap: string,
}

local function initialize(ctx: codemod.InitializationContext<Options>)
	print(`Parsing sourcemap at {ctx.options.sourcemap}`)
	local absoluteSourcemapLocation = path.joinPath(process.cwd(), ctx.options.sourcemap)
	SourcemapData = sourcemap.parseSourcemap(absoluteSourcemapLocation)
end

local function transform(ctx: codemod.Context<Options>)
	assert(SourcemapData, "no sourcemap data")

	local result = parser.parse(ctx.source)

	local requireInfo =
		requireTracer.traceRequires(result.root, ctx.path, fileResolver.createFileResolver(SourcemapData))

	local requireCalls = query.selectExpression(result.root, function(node: syntax.CstExpr): syntax.CstExprCall?
		if node.tag == "call" and isRequire(node) then
			-- Skip requires that are already string-based
			if node.arguments[1].tag == "string" then
				return nil
			end

			return node
		end
		return nil
	end)

	local replacements: syntaxTypes.Replacements = {}

	for _, call in requireCalls do
		local requireCallInfo = requireInfo[call]
		if not requireCallInfo then
			continue
		end

		local requirePath: string? = requireCallInfo.moduleName
		if requirePath and sourcemap.isVirtualPath(requirePath) then
			requirePath = sourcemap.virtualPathToRealPath(SourcemapData, requirePath)
		end

		if not requirePath then
			continue
		end

		local stringRequirePath = computeOptimalRequireString(ctx.path, requirePath)
		replacements[call.arguments[1]] = { content = `"{stringRequirePath}"`, preserveTrivia = false }
	end

	return printer.printFile(result, replacements)
end

return {
	options = {
		{ name = "sourcemap", kind = "string" },
	},
	initialize = initialize,
	transform = transform,
}
