local luau = require("@lute/luau")

local visitor = require("@std/syntax/visitor")

local isFlagAccess = require("./isFlagAccess")
local isFlagFunction = require("./isFlagFunction")

type FlagModuleKind =
	| "constant" -- Module returned game:DefineFastFlag() / game:GetFastFlag() directly
	| "function" -- Module returned a function that retrieves the FFlag value

local function isFlagReference(body: luau.AstStatBlock, variable: luau.AstLocal, flagName: string): boolean
	-- TODO: re-use the TrackReferences set up
	-- Right now, it has a circular dependency

	local trackLocalsVisitor = visitor.createVisitor()
	local result = false

	trackLocalsVisitor.visitLocalDeclaration = function(node: luau.AstStatLocal)
		for i, var in node.variables do
			if var.node == variable then
				if #node.values >= i then
					local expr = node.values[i].node
					result = isFlagAccess(expr, flagName) or isFlagFunction.isExprFlagFunction(expr, flagName)
				end
				return false
			end
		end
		return true
	end

	trackLocalsVisitor.visitLocalFunction = function(node: luau.AstStatLocalFunction)
		if node.name == variable then
			result = isFlagFunction.isStmtFlagFunction(node, flagName)
			return false
		end

		return true
	end

	visitor.visitBlock(body, trackLocalsVisitor)

	return result
end

local function isFlagModule(body: luau.AstStatBlock, flagName: string): (boolean, FlagModuleKind)
	if #body.statements == 0 then
		return false :: any
	end

	local lastStmt = body.statements[#body.statements]
	if lastStmt.tag ~= "return" then
		return false :: any
	end

	if #lastStmt.expressions ~= 1 then
		return false :: any
	end

	local expression = lastStmt.expressions[1].node

	if isFlagFunction.isExprFlagFunction(expression, flagName) then
		return true, "function"
	elseif isFlagAccess(expression, flagName) then
		return true, "constant"
	elseif expression.tag == "local" then
		return isFlagReference(body, expression["local"], flagName), "function"
	else
		return false :: any
	end
end

return isFlagModule
