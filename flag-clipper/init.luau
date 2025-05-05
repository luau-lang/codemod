local parser = require("@batteries/syntax/parser")
local printer = require("@batteries/syntax/printer")
local visitor = require("@batteries/syntax/visitor")
local T = require("@batteries/syntax/ast_types")

local codemod = require("./types")
local sourcemap = require("./require-resolver/sourcemap")
local requireTracer = require("./require-resolver/tracer")
local fileResolver = require("./require-resolver/resolver")

local isFlagAccess = require("@self/matchers/isFlagAccess")
local isFlagFunction = require("@self/matchers/isFlagFunction")
local isFlagModule = require("@self/matchers/isFlagModule")
local isRequiredFlagModule = require("@self/matchers/isRequiredFlagModule")
local simplifyExpression = require("@self/simplifyExpression")
local simplifyBlock = require("@self/simplifyBlock")

--- Global cache for sourcemap data
local SourcemapData: sourcemap.SourcemapData? = nil

local function inplaceReplace(old: T.AstExpr, new: T.AstExpr)
	if old == new then
		return
	end

	-- We abuse the fact that everything is table references, and inplace change the old node into the new one
	-- TODO: we should probably make mutability more explicit
	table.clear(old)

	for k, v in new do
		old[k] = v
	end
end

type Options = {
	flag: string,
	value: boolean,
	--- Path to a sourcemap file to resolve virtual requires.
	--- If not provided, defaults to an empty string
	sourcemap: string,
}

local function transform(ctx: codemod.Context<Options>)
	local result = parser.parsefile(ctx.source)
	local block = result.root

	print(`Removing {ctx.options.flag} as {ctx.options.value}`)

	-- Populate sourcemap data on first codemod execution
	if not SourcemapData and ctx.options.sourcemap ~= "" then
		print(`Parsing sourcemap at {ctx.options.sourcemap}`)
		SourcemapData = sourcemap.parseSourcemap(ctx.options.sourcemap)
	end

	-- Early check: if is a flag module, mark for deletion
	if isFlagModule(block, ctx.options.flag) then
		return codemod.DELETION_MARKER
	end

	local requireInfo = requireTracer.traceRequires(block, ctx.path, fileResolver.createFileResolver(SourcemapData))

	-- A set of AstLocals that are known to correspond to a flag access
	-- The locals can be a constant reference, or a function definition
	local flagLocalsSet = {}

	-- A set of global function names that are known to correspond to a flag access
	-- Unlike flagLocalsSet, we do not track this via AstLocal reference, but just by the function name
	local globalFunctionsSet = {}

	local flagVisitor = visitor.createVisitor()

	flagVisitor.visitLocalDeclaration = function(node: T.AstStatLocal)
		for idx, variables in node.variables do
			local value = node.values[idx]
			if value then
				if isFlagAccess(value.node, ctx.options.flag) then
					flagLocalsSet[variables.node] = true
				elseif isRequiredFlagModule(value.node, ctx.options.flag, requireInfo, SourcemapData) then
					flagLocalsSet[variables.node] = true
				end
			end
		end

		return true
	end

	flagVisitor.visitLocalFunction = function(node: T.AstStatLocalFunction)
		if isFlagFunction.isStmtFlagFunction(node, ctx.options.flag) then
			flagLocalsSet[node.name] = true
		end
		return true
	end

	flagVisitor.visitFunction = function(node: T.AstStatFunction)
		if isFlagFunction.isStmtFlagFunction(node, ctx.options.flag) then
			if node.name.tag == "local" then
				flagLocalsSet[node.name["local"]] = true
			elseif node.name.tag == "global" then
				globalFunctionsSet[node.name.name.text] = true
			end
		end
		return true
	end

	-- TODO: might want to double check the complexity here, since `simplifyExpression` is also recursive
	-- do we end up simplifying it twice?
	flagVisitor.visitExpressionEnd = function(expression: T.AstExpr)
		local simplifyCtx = {
			flagName = ctx.options.flag,
			flagValue = ctx.options.value,
			flagLocalsSet = flagLocalsSet,
			globalFunctionsSet = globalFunctionsSet,
		}
		local newExpression = simplifyExpression(expression, simplifyCtx)

		inplaceReplace(expression, newExpression)
	end

	flagVisitor.visitBlockEnd = function(block)
		-- TODO: should we be inplace editing?
		local simplifyCtx = {
			flagName = ctx.options.flag,
			flagValue = ctx.options.value,
			flagLocalsSet = flagLocalsSet,
			globalFunctionsSet = globalFunctionsSet,
		}
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
	transform = transform,
}
