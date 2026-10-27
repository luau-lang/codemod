local cst = require("@lute/syntax/mutablecst")

local TrackReferences = require("./TrackReferences")
export type EvaluateContext = {
	read references: TrackReferences.TrackReferences,
	read flagValue: boolean,
}

--- Attempts to constantly evaluate an expression to either 'true' or 'false'
--- Returns a tri-state boolean.
--- If we cannot evaluate, returns 'nil'. Hence, you *must not* rely on truthiness/falsiness checks
local function evaluate(expression: cst.CstExpr, ctx: EvaluateContext): boolean?
	-- Note: we explicitly don't process a constant boolean into it's value
	-- This is because we don't want to end up simplifying unrelated expressions to the flag itself

	if expression.tag == "group" then -- unpack groups
		return evaluate(expression.expression, ctx)
	end

	if ctx.references:isReference(expression) then
		return ctx.references:getReferenceValue(expression)
	end

	return nil
end

return evaluate
