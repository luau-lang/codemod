local visitor = require("@std/syntax/visitor")
local parser = require("@std/syntax/parser")
local fs = require("@lute/fs")
local luau = require("@lute/luau")
local commonHelpers = require("./commonHelpers")
local getTokenText, findReferencedVariables = commonHelpers.getTokenText, commonHelpers.findReferencedVariables
local getFunctionSignature = require("./functionUtils").getFunctionSignature
local getTypeSignature = require("./typeUtils").getTypeSignature
local isRequire = require("../require-resolver/isRequire")
local fileResolver = require("../require-resolver/resolver")
local requireTracer = require("../require-resolver/tracer")

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

function FileVisitor.new()
	local self = {}
	self.mappingVisitor = visitor.createVisitor()
	self.varMap = {}
	self.requires = {}
	self.typeMap = {}
	self.returnedVars = {}
	-- ... implement visitor

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
				if isRequire(node.values[math.min(ind, #node.values)].node) then
					self.requires[var.node.name.text] = node.values[math.min(ind, #node.values)].node
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
end

-- some eye test/debug funcs
function FileVisitor:getFunctionDocumentation()
	-- get function signatures
	for name, val in self.returnedVars do
		if val.tag and (val.tag == "localfunction" or val.tag == "function") then
			print(`{name} Signature:\n` .. getFunctionSignature(val))
		end
	end
end
function FileVisitor:getTypeDocumentation()
	-- get type signatures
	for name, val in self.typeMap do
		print(`{name} Signature:\n` .. getTypeSignature(val))
	end
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
			table.insert(returns, expr.node.token.text)
		elseif expr.node.tag == "global" then
			table.insert(returns, expr.node.name.text)
		else
			-- or just inshallah with visitLocalReference and visitGlobal (can ideally pick up everything for us)
			-- then match against varMap
			for var, _ in findReferencedVariables(expr.node) do
				table.insert(returns, var)
			end
		end
	end

	return returns
end

function getReturnedNodesMap(src: luau.AstStatBlock, varMap: VarMap): VarMap
	return filterVarMap(getReturns(src, varMap), varMap)
end

--[[
Need util for getting `require` vars from file
Will use this for special case, init.lua

For init.lua, we care abt all returned variables and will need to resolve requires
To figure out what files they correspond to
General path:
	- walk module, find init
	- find returned variables (i.e exports)
	- resolve their values;
		- if a require: resolve require and parse corresponding file
		- otherwise: use existing function/type utils to document the variable

For non init files, we only care abt non-requires, so we can filter these out

We should have a set of FileVisitor utils for dealing with requires
Limitations: for require resolver to work, we need sourcemap data.... not sure how feasible this is outside of roblox projects?
]]


-- do we also want to have function for getting types used in return values?
-- for classes, we should also get functions used in return values...
-- is it also useful to have a file return signature? Type of the return...?

--[[
resolveVar(var: string | AstLocal, varMap)

as easy as returning var map entry... maybe not
complexity comes in handling vars used in values for given var; can recursively process...?

resolveReturn(node: luau.)
]]

return {
	FileVisitor = FileVisitor,
}
