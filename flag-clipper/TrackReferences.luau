local visitor = require("@batteries/syntax/visitor")
local T = require("@batteries/syntax/ast_types")

local isRequire = require("../require-resolver/isRequire")
local sourcemap = require("../require-resolver/sourcemap")
local requireTracer = require("../require-resolver/tracer")

local isFlagAccess = require("./matchers/isFlagAccess")
local isFlagFunction = require("./matchers/isFlagFunction")

local getModuleInfo = require("./getModuleInfo")

local TrackReferences = {}
TrackReferences.__index = TrackReferences

type TableData = {
	flagProperties: { string },
}

type TrackReferencesData = {
	--- A set of AstLocals that are known to correspond to a flag access
	--- The locals can be a constant reference, or a function definition
	_locals: { [T.AstLocal]: true },
	--- A set of expressions that are known to correspond to a flag access
	--- This could be a local reference, or a require module
	_expressions: { [T.AstExpr]: true },
	--- A set of global function names that are known to correspond to a flag access
	--- Unlike flagLocalsSet, we do not track this via AstLocal reference, but just by the function name
	_globalNames: { [string]: true },
	--- Stores local variables that correspond to tables, and the relevant properties inside of that table that
	--- correspond to a flag
	_tableData: { [T.AstLocal]: TableData },
	_externalTableData: { [T.AstExpr]: TableData },
	_visitor: visitor.Visitor,
}

export type TrackReferences = setmetatable<TrackReferencesData, typeof(TrackReferences)>

function TrackReferences.new(
	flagName: string,
	requireInfo: requireTracer.RequireTracerResult,
	sourcemapData: sourcemap.SourcemapData?
): TrackReferences
	local self = {}
	self._locals = {}
	self._expressions = {}
	self._globalNames = {}
	self._tableData = {}
	self._externalTableData = {}
	self._visitor = visitor.createVisitor()

	self._visitor.visitExpression = function(node: T.AstExpr)
		if isFlagAccess(node, flagName) then
			self._expressions[node] = true
		elseif isFlagFunction.isExprFlagFunction(node, flagName) then
			self._expressions[node] = true
		elseif isRequire(node) then
			local moduleInfo = getModuleInfo(node, flagName, requireInfo, sourcemapData)
			if moduleInfo then
				if moduleInfo.isFlagModule then
					self._expressions[node] = true
				elseif moduleInfo.tableData then
					self._externalTableData[node] = moduleInfo.tableData
				end
			end
		elseif node.tag == "local" then
			if self._locals[node["local"]] then
				self._expressions[node] = true
			end
		elseif node.tag == "global" then
			if self._globalNames[node.name.text] then
				self._expressions[node] = true
			end
		end
		return true
	end

	self._visitor.visitExpressionEnd = function(node: T.AstExpr)
		if node.tag == "call" then
			local callExpr = node.func
			if self._expressions[callExpr] then
				self._expressions[node] = true
			end
		elseif node.tag == "indexname" then
			local tableData = if node.expr.tag == "local"
				then self._tableData[node.expr["local"]]
				else self._externalTableData[node.expr]

			if tableData and table.find(tableData.flagProperties, node.index.text) then
				self._expressions[node] = true
			end
		end
	end

	self._visitor.visitLocalDeclarationEnd = function(node: T.AstStatLocal)
		for idx, variable in node.variables do
			if #node.values < idx then
				break
			end

			local value = node.values[idx].node
			if self._expressions[value] then
				self._locals[variable.node] = true
			end

			if value.tag == "table" then
				local tableData = { flagProperties = {} }

				for _, entry in value.entries do
					if entry.kind == "record" then
						if self._expressions[entry.value] then
							table.insert(tableData.flagProperties, entry.key.text)
						end
					end
				end

				self._tableData[variable.node] = tableData
			elseif self._externalTableData[value] then
				self._tableData[variable.node] = self._externalTableData[value]
			end
		end
	end

	self._visitor.visitLocalFunction = function(node: T.AstStatLocalFunction)
		if isFlagFunction.isStmtFlagFunction(node, flagName) then
			self._locals[node.name] = true
		end
		return true
	end

	self._visitor.visitFunction = function(node: T.AstStatFunction)
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

function TrackReferences.visit(self: TrackReferences, block: T.AstStatBlock)
	visitor.visitBlock(block, self._visitor)
end

function TrackReferences._visitExpressionForTesting(self: TrackReferences, expression: T.AstExpr)
	visitor.visitExpression(expression, self._visitor)
end

function TrackReferences.isLocalReference(self: TrackReferences, astLocal: T.AstLocal): boolean
	return self._locals[astLocal]
end

function TrackReferences.isGlobalReference(self: TrackReferences, globalName: string): boolean
	return self._globalNames[globalName]
end

--- Returns whether the provided expression is a reference to the flag being removed
--- Either a direct reference, or an indirect reference via a local
function TrackReferences.isReference(self: TrackReferences, expression: T.AstExpr): boolean
	return self._expressions[expression] == true
end

return TrackReferences
