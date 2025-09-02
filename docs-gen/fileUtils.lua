local visitor = require("@std/syntax/visitor")
local parser = require("@std/syntax/parser")
local json = require("@batteries/json")
local fs = require("@lute/fs")
local luau = require("@lute/luau")
local commonHelpers = require("./commonHelpers")
local getTokenText, findReferencedVariables = commonHelpers.getTokenText, commonHelpers.findReferencedVariables
local isRequire = require("../require-resolver/isRequire")
local fileResolver = require("../require-resolver/resolver")
local requireTracer = require("../require-resolver/tracer")
local sourcemap = require("../require-resolver/sourcemap")

--[[
fundamental helpers prototyping

- createVarMap(file)
parse file into block
iterate over block statements
visit localDeclarations, functions, localFunctions (can take inspiration from remove-unused fs)
if local (function or var), map AstLocal ref to the value node
if global, map name (string) to value node

hmmm since for a file, we only care abt global scoped functions/vars, we might be able to map string names rather than nodes

return map
Special case for this function is when used in init, we need to require resolve for required vars


- createTypeMap(file)
similar to above but for types...
]]

type VarMap = { [string | luau.AstLocal]: luau.AstExpr }
type TypeMap = { [string]: luau.AstType }

type FileVisitor = {
	mappingVisitor: visitor.Visitor,
	varMap: VarMap,
	typeMap: TypeMap,
}

type StatementValue = luau.AstStatLocal | luau.AstStatFunction | luau.AstStatLocalFunction
type ReturnsValues = StatementValue | { StatementValue }

local FileVisitor = {}
FileVisitor.__index = FileVisitor

function getCallNode(node: luau.AstExpr)
	local reqVisitor = visitor.createVisitor()
	local callNode = nil
	reqVisitor.visitCall = function(node)
		callNode = if node.func.name and node.func.name.text == "require" then node else callNode
		return true
	end
	visitor.visitExpression(node, reqVisitor)
	return callNode
end

function containsRequire(node: luau.AstExpr)
	-- see if require exists at all in expression (bc it cud be index/indexname require, etc)
	local hasRequire = false
	local reqVisitor = visitor.createVisitor()
	reqVisitor.visitExpression = function(node: luau.AstExpr)
		hasRequire = hasRequire or isRequire(node)
		return true
	end
	visitor.visitExpression(node, reqVisitor)
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

function FileVisitor.new(luauRcPath: string?, sourcemapPath: string?)
	local self = {}
	self.mappingVisitor = visitor.createVisitor()
	self.varMap = {}
	self.requireCalls = {}
	self.dependencies = {}
	self.exports = {} -- essentially dependencies filtered by what is returned
	self.typeMap = {}
	self.returnedVars = {}
	self.aliasMap = getAliasMap(luauRcPath)
	self.sourcemapData = sourcemapPath and sourcemap.parseSourcemap(sourcemapPath)

	local currentScope = 0 -- 1 represents file level scope; we only care abt mapping variables/functions that are on this file-level scope
	-- use visitBlock to keep track of scope
	self.mappingVisitor.visitBlock = function(node: luau.AstStatBlock)
		currentScope += 1
		return true
	end
	self.mappingVisitor.visitBlockEnd = function(node: luau.AstStatBlock)
		currentScope -= 1
		return true
	end

	local function getFuncName(node: any)
		if currentScope == 1 then -- only get variables at file scope
			local nodeName = getTokenText(node.name.name)
			self.varMap[nodeName] = node
		end
		return true
	end

	-- need to handle punctuated for local
	self.mappingVisitor.visitLocalDeclaration = function(node: luau.AstStatLocal)
		if currentScope == 1 then
			for ind, var in node.variables do
				self.varMap[var.node.name.text] = node.values[math.min(ind, #node.values)].node
				if containsRequire(node.values[math.min(ind, #node.values)].node) then
					self.requireCalls[var.node.name.text] = getCallNode(node.values[math.min(ind, #node.values)].node)
				end
			end
		end
	end
	self.mappingVisitor.visitLocalFunction = getFuncName
	self.mappingVisitor.visitFunction = getFuncName

	self.mappingVisitor.visitTypeAlias = function(node: luau.AstTypeAlias)
		local typeName = node.name.text
		self.typeMap[typeName] = node
		return true
	end

	return setmetatable(self, FileVisitor)
end

-- populates varMap, typeMap, and returnedVars from a file src
function FileVisitor:analyzeFile(filePath: string)
	local src = fs.readfiletostring(filePath)
	local srcAST = parser.parse(src)
	visitor.visitBlock(srcAST, self.mappingVisitor)
	self.returnedVars = getReturnedNodesMap(srcAST, self.varMap)
	self:getDependencies(srcAST, filePath)
end

-- kinda a redudant step...? catches and filters out vars not at file scope (bc these vars will not be in varMap)
-- also separates required vars from declared vars
function filterVarMap(filterBy: { string }, varMap: VarMap): VarMap
	local vars = {}
	for _, key in filterBy do
		if varMap[key] then
			vars[key] = varMap[key] -- only keep nodes in our varMap
		end
	end
	return vars
end

-- adds variables references in the passed node to the passed table
-- used for handling anonymous values, tables/function calls so we can resolve
function handleAnonymous(node: luau.AstExpr, toInsert: { any })
	for var, _ in findReferencedVariables(node.node or node) do
		table.insert(toInsert, var)
	end
end

function handleReturnedVariables(varName: string, returns: { any }, varMap: VarMap)
	if varMap[varName] and varMap[varName].tag == "table" or varMap[varName].tag == "call" then
		handleAnonymous(varMap[varName], returns)
	else
		table.insert(returns, varName)
	end
end

-- we can probably simplify this and just visit call findReferencesVariables on the return statement...
function getReturns(src: luau.AstStatBlock, varMap: VarMap): { string }
	-- naively, return has to be last statement in a block
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
			local varName = expr.node.token.text
			handleReturnedVariables(varName, returns, varMap)
		else
			-- if anonymous value, find local references and
			handleAnonymous(expr, returns)
		end
	end

	return returns
end

function getReturnedNodesMap(src: luau.AstStatBlock, varMap: VarMap): VarMap
	return filterVarMap(getReturns(src, varMap), varMap)
end

function FileVisitor:getDependencies(src: luau.AstStatBlock, path: string)
	local requireInfo =
		requireTracer.traceRequires(src, path, fileResolver.createFileResolver(self.sourcemapData, self.aliasMap))

	for var, requireCall in self.requireCalls do
		local requireCallInfo = requireInfo[requireCall]
		if not requireCallInfo then
			print("missing require info for", var, requireCall)
			continue
		end
		local requirePath = requireCallInfo.moduleName
		if sourcemap.isVirtualPath(requirePath) then
			assert(self.sourcemapData, "Encountered a virtual path, but no sourcemap information was available")
			requirePath = sourcemap.virtualPathToRealPath(self.sourcemapData, requirePath) or ""
		end
		table.insert(self.dependencies, requirePath)
		if self.returnedVars[var] then
			table.insert(self.exports, requirePath)
		end
	end
end

return {
	FileVisitor = FileVisitor,
}
