local visitor = require("@std/syntax/visitor")
local json = require("@batteries/json")
local fs = require("@lute/fs")
local luau = require("@lute/luau")
local commonHelpers = require("../commonHelpers")
local findReferencedVariables = commonHelpers.findReferencedVariables
local isAnonymousFunction = commonHelpers.isAnonymousFunction
local isRequire = require("../../require-resolver/isRequire")

function getRequireCallNodes(node: luau.AstExpr)
	local reqVisitor = visitor.createVisitor()
	local callNodes = {}
	reqVisitor.visitCall = function(node)
		if node.func.name and node.func.name.text == "require" then
			table.insert(callNodes, node)
		end
		return true
	end

	visitor.visitExpression(node, reqVisitor)
	return callNodes
end

function exprContainsRequire(node: luau.AstExpr)
	-- see if require exists at all in expression (bc it cud be index/indexname require, etc)
	local hasRequire = false
	local reqVisitor = visitor.createVisitor()
	reqVisitor.visitExpression = function(node: luau.AstExpr)
		hasRequire = hasRequire or isRequire(node)
		return true
	end

	local _succ, _res = pcall(function()
		visitor.visitExpression(node, reqVisitor)
	end)

	return hasRequire
end

local function parseAliases(content: string): { [string]: string }
	local ok, data = pcall(function()
		return json.deserialize(content)
	end)

	if not ok or type(data) ~= "table" or type(data.aliases) ~= "table" then
		return {}
	end

	local aliases = {}
	for k, v in pairs(data.aliases) do
		aliases[k] = v
	end
	return aliases
end

local function getAliasMap(luauRcPath: string?)
	if not luauRcPath then
		return {}
	end
	local luauRcContent = fs.readfiletostring(luauRcPath)
	return parseAliases(luauRcContent)
end

-- kinda a redudant step...? catches and filters out vars not at file scope (bc these vars will not be in varMap)
-- also filters required vars from declared vars
function filterVarMap(filterBy: { string }, varMap: VarMap): VarMap
	local vars = {}
	for _, key in filterBy do
		if varMap[key] and not exprContainsRequire(varMap[key]) then
			vars[key] = varMap[key] -- only keep nodes in our varMap
		end
	end
	return vars
end

-- adds variables references in the passed node to the passed table
-- used for handling anonymous values, tables/function calls so we can resolve
function handleAnonymous(node: luau.AstExpr, toInsert: { any }, varMap: VarMap)
	-- if anonymous functions should be specifically handled
	if isAnonymousFunction(node.node or node) then
		-- hmmmm; this is a bad solution
		varMap["anonymousReturn"] = node.node or node
		table.insert(toInsert, "anonymousReturn")
	else
		-- for other anonymous variables, we can just find references
		for var, _ in findReferencedVariables(node.node or node) do
			table.insert(toInsert, var)
		end
	end
end

function handleReturnedVariables(varName: string, returns: { any }, varMap: VarMap)
	if varMap[varName] and varMap[varName].tag == "table" or varMap[varName].tag == "call" then
		handleAnonymous(varMap[varName], returns, varMap)
	end

	table.insert(returns, varName)
end

-- we can probably simplify this and just visit call findReferencesVariables on the return statement...
function getReturnValues(src: luau.AstStatBlock, varMap: VarMap): { string }
	-- return has to be last statement in a block
	local returnStatement = src.statements[#src.statements]
	local returns = {}

	-- if we return variables, we want to flag those variables for documentation
	-- if we return anonymous value(s), we want to traverse these to find referenced variables
	-- one other case (edge/special):
	--  if the returned var is a table or function call, we should follow the anonymous value process
	for _, expr in returnStatement.expressions do
		if expr.node.tag == "local" then -- indicates returned expression is a variable
			local varName = expr.node.token.text
			handleReturnedVariables(varName, returns, varMap)
		elseif expr.node.tag == "global" then
			local varName = expr.node.name.text
			handleReturnedVariables(varName, returns, varMap)
		else
			handleAnonymous(expr, returns, varMap)
		end
	end

	return returns
end

function getReturnedNodesMap(src: luau.AstStatBlock, varMap: VarMap): VarMap
	return filterVarMap(getReturnValues(src, varMap), varMap)
end

return {
	filterRequire = filterRequire,
	getCallNode = getRequireCallNodes,
	containsRequire = exprContainsRequire,
	getAliasMap = getAliasMap,
	getReturnedNodesMap = getReturnedNodesMap,
	getReturnValues = getReturnValues,
}
