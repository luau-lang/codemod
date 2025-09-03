local visitor = require("@std/syntax/visitor")
local parser = require("@std/syntax/parser")
local fs = require("@lute/fs")
local luau = require("@lute/luau")
local commonHelpers = require("../commonHelpers")
local getTokenText = commonHelpers.getTokenText
local fileResolver = require("../../require-resolver/resolver")
local requireTracer = require("../../require-resolver/tracer")
local sourcemap = require("../../require-resolver/sourcemap")
local fileUtils = require("./fileUtils")

export type VarMap = { [string | luau.AstLocal]: luau.AstExpr }
export type TypeMap = { [string]: luau.AstType }

type FileVisitor = {
	mappingVisitor: visitor.Visitor,
	varMap: VarMap,
	typeMap: TypeMap,
}

local FileVisitor = {}
FileVisitor.__index = FileVisitor

function FileVisitor.new(luauRcPath: string?, sourcemapPath: string?)
	local self = {}
	self.mappingVisitor = visitor.createVisitor()
	self.varMap = {}
	self.requiredVars = {}
	self.dependencies = {}
	self.exports = {} -- essentially dependencies filtered by what is returned
	self.typeMap = {}
	self.returnedVars = {}
	self.aliasMap = fileUtils.getAliasMap(luauRcPath)
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
				if fileUtils.containsRequire(node.values[math.min(ind, #node.values)].node) then
					self.requiredVars[var.node.name.text] =
						fileUtils.getCallNode(node.values[math.min(ind, #node.values)].node)[1]
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

function FileVisitor:resetMetadata()
	self.varMap = {}
	self.requiredVars = {}
	self.dependencies = {}
	self.exports = {} -- essentially dependencies filtered by what is returned
	self.typeMap = {}
	self.returnedVars = {}
end

-- populates varMap, typeMap, and returnedVars from a file src
function FileVisitor:analyzeFile(filePath: string)
	self:resetMetadata()
	local src = fs.readfiletostring(filePath)
	local srcAST = parser.parse(src)
	visitor.visitBlock(srcAST, self.mappingVisitor)
	self.returnedVars = fileUtils.getReturnedNodesMap(srcAST, self.varMap)
	self:getDependencies(srcAST, filePath)
end

function FileVisitor:getRequiresFromVar(value: luau.AstExpr, requireInfo)
	-- find and insert direct requires call nodes in value
	for _, requireCall in fileUtils.getCallNode(value) do
		local requireCallInfo = requireInfo[requireCall]
		if not requireCallInfo then
			continue
		end
		local requirePath = requireCallInfo.moduleName
		if sourcemap.isVirtualPath(requirePath) then
			assert(self.sourcemapData, "Encountered a virtual path, but no sourcemap information was available")
			requirePath = sourcemap.virtualPathToRealPath(self.sourcemapData, requirePath) or ""
		end
		self.exports[requirePath] = true
	end
	-- recur on table entries
	local itemVisitor = visitor.createVisitor()
	itemVisitor.visitTableItem = function(node: luau.AstExprTableItem)
		self:getRequiresFromExpr(node.value, requireInfo)
	end
	visitor.visitExpression(value, itemVisitor)
end

function FileVisitor:getRequiresFromExpr(expr: luau.AstExpr, requireInfo)
	local value = expr
	if expr.tag == "local" then -- indicates returned expression is a variable
		local varName = expr.token.text
		value = self.varMap[varName]
	elseif expr.tag == "global" then
		local varName = expr.name.text
		value = self.varMap[varName]
	end
	if value.tag == "function" or value.tag == "localfunction" then
		return
	end
	self:getRequiresFromVar(value, requireInfo)
end

-- only relevant for init files really...
function FileVisitor:getDependencies(src: luau.AstStatBlock, path: string)
	local requireInfo =
		requireTracer.traceRequires(src, path, fileResolver.createFileResolver(self.sourcemapData, self.aliasMap))

	local returnStatement = src.statements[#src.statements]
	for key, expr in returnStatement.expressions do
		self:getRequiresFromExpr(expr.node, requireInfo)
	end
end

-- Big implementation note: align the procedures used to get exports and get returned variables
-- only difference is that for returned variables, we want to filter out requires. whereas for

return FileVisitor
