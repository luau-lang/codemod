local luau = require("@lute/luau")

local TrackReferences = require("./TrackReferences")
export type EvaluateContext = {
	read references: TrackReferences.TrackReferences,
	read flagValue: boolean,
}

--- Attempts to constantly evaluate an expression to either 'true' or 'false'
--- Returns a tri-state boolean.
--- If we cannot evaluate, returns 'nil'. Hence, you *must not* rely on truthiness/falsiness checks
local function evaluate(expression: luau.AstExpr, ctx: EvaluateContext): boolean?
	-- Note: we explicitly don't process a constant boolean into it's value
	-- This is because we don't want to end up simplifying unrelated expressions to the flag itself
	if ctx.references:isReference(expression) then
		return ctx.flagValue
	end

	if expression.tag == "unary" and ctx.references:isReference(expression.operand) then
		return not ctx.flagValue
	end

	return nil
end

return evaluate
