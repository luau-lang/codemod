local syntax = require("@std/syntax")

local Rewriter = require("./Rewriter")
local evaluate = require("./evaluate")

local getThenBody = Rewriter.getThenBody

--- Simplifies a conditional based on the evaluated condition
--- Works for both if statements and if expressions
--- Returns the conditional itself if it is kept, otherwise the body that replaces it (or nil if it is removed)
local function simplifyConditional(
	node: syntax.CstStatIf | syntax.CstExprIfElse,
	ctx: evaluate.EvaluateContext
): (Rewriter.ConditionalBody | syntax.CstStatIf)?
	-- This is performed in post, so the conditional expression is already simplified
	local conditionResult = evaluate(node.condition, ctx)
	if conditionResult == true then
		-- Delete the elseif / else block
		return getThenBody(node)
	end

	local parts: Rewriter.ConditionalParts = {
		ifKeyword = { token = node.ifKeyword },
		condition = node.condition,
		thenKeyword = node.thenKeyword,
		thenBody = getThenBody(node),
		elseifs = {},
		elseKeyword = if node.elseKeyword then { token = node.elseKeyword } else nil,
		elseBody = if node.kind == "stat" then node.elseBlock else node.elseExpr,
		endKeyword = if node.kind == "stat" then node.endKeyword else nil,
	}
	local changed = false

	-- Handle if we have an elseif
	for _, elseifNode: Rewriter.ConditionalElseIf in node.elseifs :: { Rewriter.ConditionalElseIf } do
		local elseifConditionResult = evaluate(elseifNode.condition, ctx)
		if elseifConditionResult == true then
			-- Replace the else block with the contents of this node
			-- Do not progress any further (as further conditions are no longer reachable)
			parts.elseKeyword = {
				token = elseifNode.elseIfKeyword,
				text = "else",
				trailingTrivia = elseifNode.thenKeyword.trailingTrivia,
			}
			parts.elseBody = getThenBody(elseifNode)
			changed = true
			break
		elseif elseifConditionResult == false then
			-- Skip (i.e. delete) the elseif node
			changed = true
			continue
		end

		table.insert(parts.elseifs, elseifNode)
	end

	if conditionResult == false then
		-- If block must be deleted
		local firstElseIf = table.remove(parts.elseifs, 1)
		if firstElseIf == nil then
			return parts.elseBody
		end

		-- Replace if with first else if
		parts.ifKeyword = { token = firstElseIf.elseIfKeyword, text = "if" }
		parts.condition = firstElseIf.condition
		parts.thenKeyword = firstElseIf.thenKeyword
		parts.thenBody = getThenBody(firstElseIf)
		changed = true
	end

	if changed then
		ctx.rewriter:setConditional(node, parts)
	end

	return node
end

return simplifyConditional
