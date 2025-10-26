local fs = require("@lute/fs")
local luau = require("@lute/luau")
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
	--- A set of AstLocals that are known to correspond to a flag access
	--- The locals can be a constant reference, or a function definition
	_locals: { [luau.AstLocal]: true },
	-- The locals that reference compound flag expressions
	_compoundExpressionLocals: { [luau.AstLocal]: true },
	--- A set of expressions that are known to correspond to a flag access
	--- This could be a local reference, or a require module
	_expressions: { [luau.AstExpr]: true },
	-- A set of compound expressions (x or y, x and y, not x, ...) that are known to correspond to a flag access.
	_compoundExpressions: { [luau.AstExprBinary | luau.AstExprUnary | luau.AstExprGroup | luau.AstExprLocal]: boolean },

	-- hmmm should I add support for functions too? idk seems a bit overhead

	--- A set of global function names that are known to correspond to a flag access
	--- Unlike flagLocalsSet, we do not track this via AstLocal reference, but just by the function name
	_globalNames: { [string]: true },
	--- Stores local variables that correspond to tables
	_localTableData: { [luau.AstLocal]: TableData },
	--- Stores expressions that correspond to tables, either directly or indirectly.
	_expressionTableData: { [luau.AstExpr]: TableData },
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
	self._visitor = visitor.createVisitor()

	self._compoundExpressions =
		{} :: { [luau.AstExprBinary | luau.AstExprUnary | luau.AstExprGroup | luau.AstExprLocal]: boolean }
	self._compoundExpressionLocals = {} :: { [luau.AstLocal]: boolean }

	self._visitor.visitExpression = function(node: luau.AstExpr)
		if isFlagAccess(node, flagName) then
			self._expressions[node] = true
		elseif isFlagFunction.isExprFlagFunction(node, flagName) then
			self._expressions[node] = true
		elseif isRequire(node) then
			local moduleInfo = getModuleInfo(node, flagName, flagValue, requireInfo, sourcemapData)
			if moduleInfo then
				if moduleInfo.isFlagModule then
					self._expressions[node] = true
				elseif moduleInfo.tableData then
					self._expressionTableData[node] = moduleInfo.tableData
				end
			end
		elseif node.tag == "local" then
			if self._locals[node["local"]] then
				if self._compoundExpressionLocals[node["local"]] ~= nil then
					self._compoundExpressions[node] = self._compoundExpressionLocals[node["local"]]
				end
				self._expressions[node] = true
			end
			if self._localTableData[node["local"]] then
				self._expressionTableData[node] = self._localTableData[node["local"]]
			end
		elseif node.tag == "global" then
			if self._globalNames[node.name.text] then
				self._expressions[node] = true
			end
		end
		return true
	end

	self._visitor.visitExpressionEnd = function(node: luau.AstExpr)
		if node.tag == "call" then
			local callExpr = node.func
			if self._expressions[callExpr] then
				self._expressions[node] = true
			end
		elseif node.tag == "indexname" then
			local tableData = self._expressionTableData[node.expression]

			if tableData then
				if table.find(tableData.flagProperties, node.index.text) then
					self._expressions[node] = true
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
			local toEval = if node.tag == "group" then node.expression :: luau.AstExprBinary else node

			if toEval.operator.text == "and" then
				if self._expressions[toEval.lhsoperand] or self._expressions[toEval.rhsoperand] then
					-- MYFlagVar and ...
					-- can we evaluate this expression to: true/false
					local conditionValue = flagValue
					if self._expressions[toEval.lhsoperand] then
						-- print("Evaluating", printer.printexpr(toEval.lhsoperand), self._compoundExpressions[toEval.lhsoperand])
						conditionValue = if self._compoundExpressions[toEval.lhsoperand] ~= nil
							then self._compoundExpressions[toEval.lhsoperand]
							else conditionValue
					else
						-- print("Evaluating", printer.printexpr(toEval.rhsoperand), self._compoundExpressions[toEval.rhsoperand])
						conditionValue = if self._compoundExpressions[toEval.rhsoperand] ~= nil
							then self._compoundExpressions[toEval.rhsoperand]
							else conditionValue
					end
					-- print("evaled as", conditionValue, printer.printexpr(node))
					if conditionValue == false then -- can only simplify to constant if one of the operands is FALSE!
						self._expressions[node] = true
						self._compoundExpressions[node] = false -- value depends on what is in the rhs and lhs
					end
				end
			elseif toEval.operator.text == "or" then
				if self._expressions[toEval.lhsoperand] or self._expressions[toEval.rhsoperand] then
					-- MYFlagVar or ...
					-- can we evaluate this expression to: true/false
					local conditionValue = flagValue
					if self._expressions[toEval.lhsoperand] then
						-- print("Evaluating", printer.printexpr(toEval.lhsoperand), self._compoundExpressions[toEval.lhsoperand])
						conditionValue = if self._compoundExpressions[toEval.lhsoperand] ~= nil
							then self._compoundExpressions[toEval.lhsoperand]
							else conditionValue
					else
						-- print("Evaluating", printer.printexpr(toEval.rhsoperand), self._compoundExpressions[toEval.rhsoperand])
						conditionValue = if self._compoundExpressions[toEval.rhsoperand] ~= nil
							then self._compoundExpressions[toEval.rhsoperand]
							else conditionValue
					end

					if conditionValue == true then
						-- true and x => true
						self._expressions[node] = true
						self._compoundExpressions[node] = true
						-- TO-DO: updates s.t value depends on what is in the rhs and lhs (like we do for AND statements above)
					end
				end
			end
		elseif node.tag == "unary" or (node.tag == "group" and node.expression.tag == "unary") then
			local toEval = if node.tag == "group" then node.expression :: luau.AstExprUnary else node
			if toEval.operator.text == "not" then
				if self._expressions[toEval.operand] then
					self._expressions[node] = true
					self._compoundExpressions[node] = if self._compoundExpressions[toEval.operand] ~= nil
						then not self._compoundExpressions[toEval.operand]
						else not flagValue
				end
			end
		end
	end

	self._visitor.visitLocalDeclarationEnd = function(node: luau.AstStatLocal)
		for idx, variable in node.variables do
			if #node.values < idx then
				break
			end

			local value = node.values[idx].node
			if self._expressions[value] then
				self._locals[variable.node] = true
				if self._compoundExpressions[value :: any] ~= nil then
					self._compoundExpressionLocals[variable.node] = self._compoundExpressions[value :: any]
				end
			end

			if self._expressionTableData[value] then
				self._localTableData[variable.node] = self._expressionTableData[value]
			end
		end
	end

	self._visitor.visitLocalFunction = function(node: luau.AstStatLocalFunction)
		if isFlagFunction.isStmtFlagFunction(node, flagName) then
			self._locals[node.name] = true
		end
		return true
	end

	self._visitor.visitFunction = function(node: luau.AstStatFunction)
		if isFlagFunction.isStmtFlagFunction(node, flagName) then
			if node.name.tag == "local" then
				self._locals[node.name["local"]] = true
			elseif node.name.tag == "global" then
				self._globalNames[node.name.name.text] = true
			end
		end
		return true
	end

	return setmetatable(self, TrackReferences)
end

function TrackReferences.visit(self: TrackReferences, block: luau.AstStatBlock)
	visitor.visitBlock(block, self._visitor)
end

function TrackReferences._visitExpressionForTesting(self: TrackReferences, expression: luau.AstExpr)
	visitor.visitExpression(expression, self._visitor)
end

function TrackReferences.isLocalReference(self: TrackReferences, astLocal: luau.AstLocal): boolean
	return self._locals[astLocal]
end

function TrackReferences.isGlobalReference(self: TrackReferences, globalName: string): boolean
	return self._globalNames[globalName]
end

--- Returns whether the provided expression is a reference to the flag being removed
--- Either a direct reference, or an indirect reference via a local
function TrackReferences.isReference(self: TrackReferences, expression: luau.AstExpr): boolean
	return self._expressions[expression] == true
end

function TrackReferences.isCompoundReference(self: TrackReferences, expression: luau.AstExpr): boolean
	return self._compoundExpressions[expression] ~= nil
end

function TrackReferences.isCompoundLocalReference(self: TrackReferences, astLocal: luau.AstLocal): boolean
	return self._compoundExpressionLocals[astLocal] ~= nil
end

function TrackReferences.getCompoundReferenceValue(self: TrackReferences, expression: luau.AstExpr): boolean
	return self._compoundExpressions[expression]
end

function TrackReferences.getCompoundLocalReferenceValue(self: TrackReferences, astLocal: luau.AstLocal): boolean
	return self._compoundExpressionLocals[astLocal]
end

local function getReturnedExpression(body: luau.AstStatBlock): luau.AstExpr?
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

	local expression = lastStmt.expressions[1].node
	return expression
end

--- Resolves the given expression to its require call, follows the require, then processes the
--- resulting file for relevant information.
function getModuleInfo(
	expression: luau.AstExpr,
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

	local contents = fs.readfiletostring(requirePath)
	local block = parser.parse(contents)
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
