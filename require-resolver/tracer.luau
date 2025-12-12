local luau = require("@lute/luau")
local visitor = require("@std/syntax/visitor")

local isRequire = require("./isRequire")
local resolver = require("./resolver")

type RequireTracer = visitor.Visitor & {
	_requireCalls: { luau.AstExprCall },
	_locals: { [luau.AstLocal]: luau.AstExpr },
}

local function newRequireTracer(): RequireTracer
	local traceVisitor = visitor.create() :: RequireTracer
	traceVisitor._requireCalls = {}
	traceVisitor._locals = {}

	traceVisitor.visitExprTypeAssertion = function()
		--  suppress `require() :: any`
		return false
	end

	traceVisitor.visitExprCall = function(node)
		if isRequire(node) then
			table.insert(traceVisitor._requireCalls, node)
		end

		return true
	end

	traceVisitor.visitStatLocalDeclaration = function(node: luau.AstStatLocal)
		for i = 1, math.min(#node.variables, #node.values) do
			local variable = node.variables[i].node
			local value = node.values[i].node
			traceVisitor._locals[variable] = value
		end

		return true
	end

	traceVisitor.visitStatAssign = function(node: luau.AstStatAssign)
		for _, var in node.variables do
			-- locals that are assigned don't have a known expression
			if var.node.tag == "local" then
				traceVisitor._locals[var.node["local"]] = nil
			end
		end

		return true
	end

	return traceVisitor
end

local function getDependent(tracer: RequireTracer, node: luau.AstExpr): luau.AstExpr?
	if node.tag == "local" then
		return tracer._locals[node["local"]]
	elseif node.tag == "indexname" then
		return node.expression
	elseif node.tag == "index" then
		return node.expression
	elseif node.tag == "call" and node.self then
		assert(node.func.tag == "indexname")
		return node.func.expression
	elseif node.tag == "group" then
		return node.expression
	end

	return nil
end

export type RequireTracerResult = { [luau.AstExprCall]: resolver.ModuleInfo }

local function processTracer(
	tracer: RequireTracer,
	resolver: resolver.Resolver,
	currentModuleName: resolver.ModuleName
): RequireTracerResult
	local work = table.create(#tracer._requireCalls, (nil :: any) :: luau.AstExpr)

	for _, call in tracer._requireCalls do
		table.insert(work, call.arguments[1].node)
	end

	-- push all dependent expressions to the work stack; note that the vector is modified during traversal
	do
		local i = 1
		while i <= #work do
			local dependent = getDependent(tracer, work[i])
			if dependent then
				table.insert(work, dependent)
			end
			i += 1
		end
	end

	-- resolve all expressions to a module info
	local exprMap = {}
	local currentModuleContext: resolver.ModuleInfo = { moduleName = currentModuleName }
	for i = #work, 1, -1 do
		local expression = work[i]

		if exprMap[expression] then
			continue
		end

		local info = nil

		local dependent = getDependent(tracer, expression)
		if dependent then
			local context: resolver.ModuleInfo? = exprMap[dependent]
			if context and (expression.tag == "local" or expression.tag == "group") then
				info = context
			else
				info = resolver(context, expression)
			end
		else
			info = resolver(currentModuleContext, expression)
		end

		if info then
			exprMap[expression] = info
		end
	end

	-- resolve all requires according to their argument
	local result = {}
	for _, call in tracer._requireCalls do
		local argument = call.arguments[1].node
		if exprMap[argument] then
			result[call] = exprMap[argument]
		else
			result[call] = nil
		end
	end

	return result
end

local function traceRequires(block: luau.AstStatBlock, from: resolver.ModuleName, resolver: resolver.Resolver)
	local traceVisitor = newRequireTracer()
	visitor.visitblock(block, traceVisitor)
	return processTracer(traceVisitor, resolver, from)
end

return {
	newRequireTracer = newRequireTracer,
	processTracer = processTracer,
	traceRequires = traceRequires,
}
