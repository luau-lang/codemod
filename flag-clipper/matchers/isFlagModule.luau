local T = require("@batteries/syntax/ast_types")

local isFlagAccess = require("./isFlagAccess")
local isFlagFunction = require("./isFlagFunction")

type FlagModuleKind =
	| "constant" -- Module returned game:DefineFastFlag() / game:GetFastFlag() directly
	| "function" -- Module returned a function that retrieves the FFlag value

local function isFlagModule(body: T.AstStatBlock, flagName: string): (boolean, FlagModuleKind)
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
	else
		return false :: any
	end
end

return isFlagModule
