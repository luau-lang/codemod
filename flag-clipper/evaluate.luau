local T = require("@batteries/syntax/ast_types")

local isFlagReference = require("./matchers/isFlagReference")

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
	elseif isFlagReference(expression, ctx) then
		return ctx.flagValue
	end

	return nil
end

return evaluate
