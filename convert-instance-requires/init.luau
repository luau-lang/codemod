--!strict
local luau = require("@lute/luau")
local process = require("@lute/process")

local parser = require("@std/syntax/parser")
local printer = require("@std/syntax/printer")

local path = require("./lib/path")
local codemod = require("./lib/types")

local query = require("@std/syntax/query")
local isRequire = require("./require-resolver/isRequire")
local fileResolver = require("./require-resolver/resolver")
local requireTracer = require("./require-resolver/tracer")
local sourcemap = require("./require-resolver/sourcemap")

local computeOptimalRequireString = require("@self/computeOptimalRequireString")

--- Global cache for sourcemap data
local SourcemapData: sourcemap.SourcemapData? = nil

local function createString(text: string): luau.AstExprConstantString
	return {
		tag = "string",
		leadingtrivia = {},
		position = { line = 0, column = 0 },
		text = text,
		trailingtrivia = {},
		quoteStyle = "double",
		blockDepth = 0,
	}
end

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

	local requireCalls = query.selectExpression(result.root, function(node: luau.AstExpr): luau.AstExprCall?
		if isRequire(node) then
			assert(node.tag == "call", "Luau")

			-- Skip requires that are already string-based
			if node.arguments[1].node.tag == "string" then
				return nil
			end

			return node
		end
		return nil
	end)

	for _, call in requireCalls do
		assert(call, "Luau")

		local requireCallInfo = requireInfo[call]
		if not requireCallInfo then
			continue
		end

		local requirePath = requireCallInfo.moduleName
		if sourcemap.isVirtualPath(requirePath) then
			requirePath = sourcemap.virtualPathToRealPath(SourcemapData, requirePath)
		end

		if not requirePath then
			continue
		end

		local stringRequirePath = computeOptimalRequireString(ctx.path, requirePath)
		call.arguments[1].node = createString(stringRequirePath)
	end

	return printer.printfile(result)
end

return {
	options = {
		{ name = "sourcemap", kind = "string" },
	},
	initialize = initialize,
	transform = transform,
}
