local luau = require("@lute/luau")

local visitor = require("@batteries/syntax/visitor")

local isRequire = require("../require-resolver/isRequire")
local sourcemap = require("../require-resolver/sourcemap")
local requireTracer = require("../require-resolver/tracer")

local isFlagAccess = require("./matchers/isFlagAccess")
local isFlagFunction = require("./matchers/isFlagFunction")

local getModuleInfo = require("./getModuleInfo")

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
	--- A set of expressions that are known to correspond to a flag access
	--- This could be a local reference, or a require module
	_expressions: { [luau.AstExpr]: true },
	--- A set of global function names that are known to correspond to a flag access
	--- Unlike flagLocalsSet, we do not track this via AstLocal reference, but just by the function name
	_globalNames: { [string]: true },
	--- Stores local variables that correspond to tables
	_localTableData: { [luau.AstLocal]: TableData },
	--- Stores expressions that correspond to tables, either directly or indirectly.
	_expressionTableData: { [luau.AstExpr]: TableData },
	_visitor: visitor.Visitor,
}

export type TrackReferences = setmetatable<TrackReferencesData, typeof(TrackReferences)>

function TrackReferences.new(
	flagName: string,
	requireInfo: requireTracer.RequireTracerResult,
	sourcemapData: sourcemap.SourcemapData?,
	repo: string?
): TrackReferences
	local self = {}
	self._locals = {}
	self._expressions = {}
	self._globalNames = {}
	self._localTableData = {}
	self._expressionTableData = {}
	self._visitor = visitor.createVisitor()

	self._visitor.visitExpression = function(node: luau.AstExpr)
		if isFlagAccess(node, flagName, repo) then
			self._expressions[node] = true
		elseif isFlagFunction.isExprFlagFunction(node, flagName, repo) then
			self._expressions[node] = true
		elseif isRequire(node) then
			local moduleInfo = getModuleInfo(node, flagName, requireInfo, sourcemapData, repo)
			if moduleInfo then
				if moduleInfo.isFlagModule then
					self._expressions[node] = true
				elseif moduleInfo.tableData then
					self._expressionTableData[node] = moduleInfo.tableData
				end
			end
		elseif node.tag == "local" then
			if self._locals[node["local"]] then
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
			end

			if self._expressionTableData[value] then
				self._localTableData[variable.node] = self._expressionTableData[value]
			end
		end
	end

	self._visitor.visitLocalFunction = function(node: luau.AstStatLocalFunction)
		if isFlagFunction.isStmtFlagFunction(node, flagName, repo) then
			self._locals[node.name] = true
		end
		return true
	end

	self._visitor.visitFunction = function(node: luau.AstStatFunction)
		if isFlagFunction.isStmtFlagFunction(node, flagName, repo) then
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

return TrackReferences
