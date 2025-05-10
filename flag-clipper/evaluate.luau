local T = require("@batteries/syntax/ast_types")

local TrackReferences = require("./TrackReferences")
export type EvaluateContext = {
	read references: TrackReferences.TrackReferences,
	read flagValue: boolean,
}

--- Attempts to constantly evaluate an expression to either 'true' or 'false'
--- Returns a tri-state boolean.
--- If we cannot evaluate, returns 'nil'. Hence, you *must not* rely on truthiness/falsiness checks
local function evaluate(expression: T.AstExpr, ctx: EvaluateContext): boolean?
	if expression.tag == "boolean" then
		return expression.value
	elseif ctx.references:isReference(expression) then
		return ctx.flagValue
	end

	return nil
end

return evaluate
