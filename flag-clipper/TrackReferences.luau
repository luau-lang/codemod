local fs = require("@std/fs")
local syntax = require("@std/syntax")
local parser = require("@std/syntax/parser")

local visitor = require("@std/syntax/visitor")

local fileResolver = require("../require-resolver/resolver")
local isRequire = require("../require-resolver/isRequire")
local sourcemap = require("../require-resolver/sourcemap")
local requireTracer = require("../require-resolver/tracer")

local isFlagAccess = require("./matchers/isFlagAccess")
local isFlagFunction = require("./matchers/isFlagFunction")
local isFlagModule = require("./matchers/isFlagModule")

local TrackReferences = {}
TrackReferences.__index = TrackReferences

--- Information about a table that is relevant for flag clipping
type TableData = {
	--- A list of properties that correspond to the flag that is being cleaned up
	flagProperties: { string },
	--[[
		A map of properties to other TableData, for nested table cases.
		For example:
		```luau
			local tbl = {
				other = {
					flagValue = game:GetFastFlag("FlagName")
				}
			}
		```
		In this case, the TableData for `tbl` would contain nested table data of `{ "other" = { flagProperties = { "flagValue" } }}`
	]]
	nestedTableData: { [string]: TableData },
}

type TrackReferencesData = {
	--- A set of AstLocals that are known to correspond to a flag access or an expression containing a flag which simplifies to a boolean literal
	--- The locals can be a constant reference, or a function definition
	_locals: { [syntax.CstLocal]: boolean },
	--- A set of expressions that are known to correspond to a flag access
	--- This could be a local reference, or a require module
	_expressions: { [syntax.CstExpr]: boolean },

	-- Cache for simplified binary expressions explicitly to avoid
	-- removing table entries that have had their values simplified to a direct flag reference
	-- for ex, suppose flag is true and we have: local table = { field = flag and something }
	-- expressions simplify from inside out (post-order)
	-- so we get to simplifying the table itself, we have: { field = flag }
	-- normally, these are removed but bc value was originally `flag and something` we want to keep entry
	-- so, we use this cache to catch such cases
	_simplifiedBinaries: { [syntax.CstExpr]: true },

	--- A set of global function names that are known to correspond to a flag access
	--- Unlike flagLocalsSet, we do not track this via AstLocal reference, but just by the function name
	_globalNames: { [string]: true },
	--- Stores local variables that correspond to tables
	_localTableData: { [syntax.CstLocal]: TableData },
	--- Stores expressions that correspond to tables, either directly or indirectly.
	_expressionTableData: { [syntax.CstExpr]: TableData },
	_visitor: visitor.Visitor,
}

--- Information about a required module
export type ModuleInfo = {
	--- Whether this module returns a direct flag reference / flag getter function.
	--- In these cases, this module will typically be deleted, and we can assume all usages of the
	--- required result to be flag references.
	isFlagModule: boolean,
	--- The resolved table information if the required module returns a table
	tableData: TableData?,
}

--- Global cache of 'file path' -> moduleInfo mapping
local FlagModuleFileCache: { [string]: ModuleInfo } = {}

export type TrackReferences = setmetatable<TrackReferencesData, typeof(TrackReferences)>

function TrackReferences.new(
	flagName: string,
	flagValue: boolean,
	requireInfo: requireTracer.RequireTracerResult,
	sourcemapData: sourcemap.SourcemapData?
): TrackReferences
	local self = {}
	self._locals = {}
	self._expressions = {}
	self._globalNames = {}
	self._localTableData = {}
	self._expressionTableData = {}
	self._simplifiedBinaries = {}
	self._visitor = visitor.create()

	self._visitor.visitExpr = function(node: syntax.CstExpr)
		if isFlagAccess(node, flagName) then
			self._expressions[node] = flagValue
		elseif isFlagFunction.isExprFlagFunction(node, flagName) then
			self._expressions[node] = flagValue
		elseif isRequire(node) then
			local moduleInfo = getModuleInfo(node, flagName, flagValue, requireInfo, sourcemapData)
			if moduleInfo then
				if moduleInfo.isFlagModule then
					self._expressions[node] = flagValue
				elseif moduleInfo.tableData then
					self._expressionTableData[node] = moduleInfo.tableData
				end
			end
		elseif node.tag == "local" then
			if self._locals[node["local"]] ~= nil then
				self._expressions[node] = self._locals[node["local"]]
			end
			if self._localTableData[node["local"]] then
				self._expressionTableData[node] = self._localTableData[node["local"]]
			end
		elseif node.tag == "global" then
			if self._globalNames[node.name.text] then
				self._expressions[node] = flagValue
			end
		end
		return true
	end

	self._visitor.visitExprEnd = function(node: syntax.CstExpr)
		if node.tag == "call" then
			local callExpr = node.func
			if self._expressions[callExpr] then
				self._expressions[node] = flagValue
			end
		elseif node.tag == "indexname" then
			local tableData = self._expressionTableData[node.expression]

			if tableData then
				if table.find(tableData.flagProperties, node.index.text) then
					self._expressions[node] = flagValue
				elseif tableData.nestedTableData[node.index.text] then
					self._expressionTableData[node] = tableData.nestedTableData[node.index.text]
				end
			end
		elseif node.tag == "table" then
			local tableData = { flagProperties = {}, nestedTableData = {} }

			for _, entry in node.entries do
				if entry.kind == "record" then
					if self._expressions[entry.value] then
						table.insert(tableData.flagProperties, entry.key.text)
					elseif self._expressionTableData[entry.value] then
						tableData.nestedTableData[entry.key.text] = self._expressionTableData[entry.value]
					end
				end
			end

			self._expressionTableData[node] = tableData
		elseif node.tag == "binary" or (node.tag == "group" and node.expression.tag == "binary") then -- local
			local toEval = if node.tag == "group" then node.expression :: syntax.CstExprBinary else node

			if toEval.operator.text == "and" then
				if self._expressions[toEval.lhsOperand] == false or self._expressions[toEval.rhsOperand] == false then
					self._expressions[node] = false
				elseif
					self._expressions[toEval.lhsOperand] == true and self._expressions[toEval.rhsOperand] == true
				then
					self._expressions[node] = true
				end
			elseif toEval.operator.text == "or" then
				if self._expressions[toEval.lhsOperand] == true or self._expressions[toEval.rhsOperand] == true then
					self._expressions[node] = true
				elseif
					self._expressions[toEval.lhsOperand] == false and self._expressions[toEval.rhsOperand] == false
				then
					self._expressions[node] = false
				end
			end
		elseif node.tag == "unary" or (node.tag == "group" and node.expression.tag == "unary") then
			local toEval = if node.tag == "group" then node.expression :: syntax.CstExprUnary else node
			if toEval.operator.text == "not" then
				if self._expressions[toEval.operand] ~= nil then
					self._expressions[node] = not self._expressions[toEval.operand]
				end
			end
		end
	end

	self._visitor.visitStatLocalDeclarationEnd = function(node: syntax.CstStatLocal)
		for idx, variable in node.variables do
			if #node.values < idx then
				break
			end

			local value = node.values[idx]
			if self._expressions[value] ~= nil then
				self._locals[variable] = self._expressions[value]
			end

			if self._expressionTableData[value] then
				self._localTableData[variable] = self._expressionTableData[value]
			end
		end
	end

	self._visitor.visitStatLocalFunction = function(node: syntax.CstStatLocalFunction)
		if isFlagFunction.isStmtFlagFunction(node, flagName) then
			self._locals[node.name] = flagValue
		end
		return true
	end

	self._visitor.visitStatFunction = function(node: syntax.CstStatFunction)
		if isFlagFunction.isStmtFlagFunction(node, flagName) then
			if node.name.tag == "local" then
				self._locals[node.name["local"]] = flagValue
			elseif node.name.tag == "global" then
				self._globalNames[node.name.name.text] = true
			end
		end
		return true
	end

	return setmetatable(self, TrackReferences)
end

function TrackReferences.visit(self: TrackReferences, block: syntax.CstStatBlock)
	visitor.visitBlock(block, self._visitor)
end

function TrackReferences._visitExpressionForTesting(self: TrackReferences, expression: syntax.CstExpr)
	visitor.visitExpression(expression, self._visitor)
end

function TrackReferences.isLocalReference(self: TrackReferences, astLocal: syntax.CstLocal): boolean
	return self._locals[astLocal] ~= nil
end

function TrackReferences.isGlobalReference(self: TrackReferences, globalName: string): boolean
	return self._globalNames[globalName]
end

--- Returns whether the provided expression is a reference to the flag being removed
--- Either a direct reference, or an indirect reference via a local
function TrackReferences.isReference(self: TrackReferences, expression: syntax.CstExpr): boolean
	return self._expressions[expression] ~= nil
end

function TrackReferences.getReferenceValue(self: TrackReferences, expression: syntax.CstExpr): boolean
	return self._expressions[expression]
end

function TrackReferences.isCompoundReference(self: TrackReferences, expression: syntax.CstExpr): boolean
	return self._expressions[expression] ~= nil
		and (
			expression.tag == "unary"
			or expression.tag == "binary"
			or (expression.tag == "group" and self:isCompoundReference(expression.expression))
		)
end

local function getReturnedExpression(body: syntax.CstStatBlock): syntax.CstExpr?
	if #body.statements == 0 then
		return nil
	end

	local lastStmt = body.statements[#body.statements]
	if lastStmt.tag ~= "return" then
		return nil
	end

	if #lastStmt.expressions ~= 1 then
		return nil
	end

	local expression = lastStmt.expressions[1]
	return expression
end

--- Resolves the given expression to its require call, follows the require, then processes the
--- resulting file for relevant information.
function getModuleInfo(
	expression: syntax.CstExpr,
	flagName: string,
	flagValue: boolean,
	requireInfo: requireTracer.RequireTracerResult,
	sourcemapData: sourcemap.SourcemapData?
): ModuleInfo?
	if not isRequire(expression) then
		return nil
	end

	assert(expression.tag == "call")

	local requireCallInfo = requireInfo[expression]
	if not requireCallInfo then
		return nil
	end

	local requirePath = requireCallInfo.moduleName
	if sourcemap.isVirtualPath(requirePath) then
		assert(sourcemapData, "Encountered a virtual path, but no sourcemap information was available")
		requirePath = sourcemap.virtualPathToRealPath(sourcemapData, requirePath)
	end

	if not requirePath then
		return nil
	end

	if FlagModuleFileCache[requirePath] ~= nil then
		return FlagModuleFileCache[requirePath]
	end

	local contents = fs.readFileToString(requirePath)
	local block = parser.parseBlock(contents)
	assert(block)

	local result: ModuleInfo = { isFlagModule = false, tableData = nil }
	if isFlagModule(block, flagName) then
		result.isFlagModule = true
	else
		local returnedExpression = getReturnedExpression(block)
		if returnedExpression then
			requireInfo =
				requireTracer.traceRequires(block, requirePath, fileResolver.createFileResolver(sourcemapData))
			local references = TrackReferences.new(flagName, flagValue, requireInfo, sourcemapData)
			references:visit(block)
			result.tableData = references._expressionTableData[returnedExpression]
		end
	end

	FlagModuleFileCache[requirePath] = result
	return result
end

return TrackReferences
