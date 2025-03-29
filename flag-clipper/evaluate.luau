local T = require("@batteries/syntax/ast_types")

local isFlagAccess = require("./matchers/isFlagAccess")

export type EvaluateContext = {
	read flagName: string,
	read flagValue: boolean,
	read flagLocalsSet: { [T.AstLocal]: true },
	read globalFunctionsSet: { [string]: true },
}

--- Attempts to constantly evaluate an expression to either 'true' or 'false'
--- Returns a tri-state boolean.
--- If we cannot evaluate, returns 'nil'. Hence, you *must not* rely on truthiness/falsiness checks
local function evaluate(expression: T.AstExpr, ctx: EvaluateContext): boolean?
	if expression.tag == "boolean" then
		return expression.value
	elseif isFlagAccess(expression, ctx.flagName) then
		return ctx.flagValue
	elseif expression.tag == "local" then
		local isLocalReferencingFlag = ctx.flagLocalsSet[expression["local"]]
		if isLocalReferencingFlag then
			return ctx.flagValue
		end
		return nil
	elseif expression.tag == "call" then
		local callExpr = expression.func
		if callExpr.tag == "local" then
			local isLocalReferencingFlag = ctx.flagLocalsSet[callExpr["local"]]
			if isLocalReferencingFlag then
				return ctx.flagValue
			end
			return nil
		elseif callExpr.tag == "global" then
			local isGlobalReferencingFlag = ctx.globalFunctionsSet[callExpr.name.text]
			if isGlobalReferencingFlag then
				return ctx.flagValue
			end
			return nil
		end
	end

	return nil
end

return evaluate
