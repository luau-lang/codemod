local visitor = require("@std/syntax/visitor")
local parser = require("@std/syntax/parser")
local fs = require("@lute/fs")
local luau = require("@lute/luau")
local commonHelpers = require("../commonHelpers")
local getTokenText = commonHelpers.getTokenText
local filter = commonHelpers.filter
local fileResolver = require("../../require-resolver/resolver")
local requireTracer = require("../../require-resolver/tracer")
local sourcemap = require("../../require-resolver/sourcemap")
local fileUtils = require("./fileUtils")
local containsRequire = fileUtils.containsRequire
local isRequire = require("../../require-resolver/isRequire")

export type VarMap = { [string | luau.AstLocal]: luau.AstExpr }
export type TypeMap = { [string]: luau.AstType }

type FileVisitorData = {
	mappingVisitor: visitor.Visitor,
	varMap: VarMap,
	typeMap: TypeMap,
	returnedVars: VarMap,
	anonymousReturns: { luau.AstExpr },
	reExports: { [string]: boolean },
	aliasMap: { [string]: string },
	sourcemapData: sourcemap.SourcemapData,
	returnExprs: { luau.AstExpr },
}

local FileVisitor = {}
FileVisitor.__index = FileVisitor

export type FileVisitor = setmetatable<FileVisitorData, typeof(FileVisitor)>

function FileVisitor.new(luauRcPath: string?, sourcemapPath: string?): FileVisitor
	local self = {}
	self.mappingVisitor = visitor.createVisitor()
	self.varMap = {}
	self.typeMap = {}
	self.returnedVars = {}
	self.anonymousReturns = {}
	self.returnExprs = {}
	self.reExports = {} -- imported modules that get re-exported; used to determine what files need to be queued for documentation
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
	self.reExports = {} -- essentially dependencies filtered by what is returned
	self.typeMap = {}
	self.returnedVars = {}
	self.anonymousReturns = {}
end

-- populates varMap, typeMap, and returnedVars from a file src
function FileVisitor:analyzeFile(filePath: string)
	self:resetMetadata()
	local src = fs.readfiletostring(filePath)
	local srcAST = parser.parse(src)
	visitor.visitBlock(srcAST, self.mappingVisitor)
	self:analyzeReturn(srcAST, filePath)
	self.returnedVars = filter(self.returnedVars, function(item)
		return not containsRequire(item)
	end) -- filter imports out of returned vars
end

function FileVisitor:apiVisitor(requireInfo: requireTracer.RequireTracerResult)
	local itemVisitor = visitor.createVisitor()
	itemVisitor.visitTableItem = function(item: luau.AstExprTableItem)
		self:analyzeReturnExpr(item.value, requireInfo)
	end
	itemVisitor.visitLocalReference = function(item: luau.AstLocal)
		self:analyzeReturnExpr(item, requireInfo)
	end
	itemVisitor.visitGlobal = function(item: luau.AstExprGlobal)
		self:analyzeReturnExpr(item, requireInfo)
	end
	return itemVisitor
end

function FileVisitor:getVariableValue(node: luau.AstExpr): (luau.AstExpr, string)
	local value = node
	local varName: string
	if node.tag == "local" then -- indicates returned expression is a variable
		varName = node.token.text
		value = self.varMap[varName]
	elseif node.tag == "global" then
		varName = node.name.text
		value = self.varMap[varName]
	end
	return value, varName
end

-- bug with returned table variables being duplicated (processed one as named as var, once as anonymous)
function FileVisitor:analyzeReturnExpr(node: luau.AstExpr, requireInfo: requireTracer.RequireTracerResult)
	local recursiveVisitor = self:apiVisitor(requireInfo)
	local value, varName = self:getVariableValue(node)

	if not value then
		return
	end

	if varName then -- named vars found in recursive process should be added to returns
		if self.returnedVars[varName] then -- prevent infinite loops
			return
		end
		self.returnedVars[varName] = value
	end

	if isRequire(value) then
		local requirePath = requireInfo[value].moduleName
		if not self.reExports[requirePath] then
			if sourcemap.isVirtualPath(requirePath) then
				assert(self.sourcemapData, "Encountered a virtual path, but no sourcemap information was available")
				requirePath = sourcemap.virtualPathToRealPath(self.sourcemapData, requirePath) or ""
			end
			self.reExports[requirePath] = true
		end
	elseif value.tag and value.tag == "function" or value.tag == "localfunction" then -- shouldn't recur on functions
		if not varName then
			table.insert(self.anonymousReturns, value)
		end
	else
		-- only want to save anonymous tables
		if not varName and value.tag and value.tag == "table" then
			table.insert(self.anonymousReturns, value)
		end
		visitor.visitExpression(value, recursiveVisitor)
	end
end

function FileVisitor:analyzeReturn(src: luau.AstStatBlock, path: string)
	local requireInfo =
		requireTracer.traceRequires(src, path, fileResolver.createFileResolver(self.sourcemapData, self.aliasMap))

	local returnStatement = src.statements[#src.statements]
	for key, expr in returnStatement.expressions do
		local value, _ = self:getVariableValue(expr.node)
		table.insert(self.returnExprs, value)
		self:analyzeReturnExpr(expr.node, requireInfo)
	end
end

return FileVisitor
