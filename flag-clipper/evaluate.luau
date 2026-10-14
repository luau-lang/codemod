local syntax = require("@std/syntax")

local Rewriter = require("./Rewriter")
local TrackReferences = require("./TrackReferences")

export type EvaluateContext = {
	read references: TrackReferences.TrackReferences,
	read rewriter: Rewriter.Rewriter,
	read flagValue: boolean,
}

--- Attempts to constantly evaluate an expression to either 'true' or 'false'
--- Returns a tri-state boolean.
--- If we cannot evaluate, returns 'nil'. Hence, you *must not* rely on truthiness/falsiness checks
local function evaluate(expression: syntax.CstExpr, ctx: EvaluateContext): boolean?
	-- Note: we explicitly don't process a constant boolean into it's value
	-- This is because we don't want to end up simplifying unrelated expressions to the flag itself

	local effective = ctx.rewriter:view(expression)
	if effective == nil then
		return nil
	end

	if effective.tag == "group" then -- unpack groups
		return evaluate(effective.expression, ctx)
	end

	if ctx.rewriter:isReference(effective) then
		return ctx.rewriter:getReferenceValue(effective)
	end

	return nil
end

return evaluate
