local T = require("@batteries/syntax/ast_types")

local evaluate = require("./evaluate")

--- Simplifies a conditional based on the evaluated condition
--- Works for both if statements and if expressions
local function simplifyConditional(
	node: T.AstStatIf | T.AstExprIfElse,
	ctx: evaluate.EvaluateContext
): T.AstStat | T.AstExpr
	-- This is performed in post, so the conditional expression is already simplified
	local conditionResult = evaluate(node.condition, ctx)
	if conditionResult == true then
		-- Delete the elseif / else block
		return node.consequent
	end

	-- Handle if we have an elseif
	local elseifs = {}
	for _, elseifNode in node.elseifs do
		local elseifConditionResult = evaluate(elseifNode.condition, ctx)
		if elseifConditionResult == true then
			return elseifNode.consequent
		elseif elseifConditionResult == false then
			-- Skip (i.e. delete) the elseif node
			continue
		end

		table.insert(elseifs, elseifNode)
	end

	if conditionResult == false then
		-- If block must be deleted
		if #elseifs > 0 then
			-- Replace if with first else if
			local firstElseIf = table.remove(elseifs, 1)
			node["if"] = firstElseIf["elseif"]
			node["if"].text = "if"
			node.condition = firstElseIf.condition
			node["then"] = firstElseIf["then"]
			node.consequent = firstElseIf.consequent
			node.elseifs = elseifs

			return node
		else
			return node.antecedent
		end
	end

	node.elseifs = elseifs

	return node
end

return simplifyConditional
