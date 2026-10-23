local cst = require("@lute/syntax/mutablecst")

local evaluate = require("./evaluate")

--- Simplifies a conditional based on the evaluated condition
--- Works for both if statements and if expressions
local function simplifyConditional(
	node: cst.CstStatIf | cst.CstExprIfElse,
	ctx: evaluate.EvaluateContext
): cst.CstStat | cst.CstExpr
	-- This is performed in post, so the conditional expression is already simplified
	local conditionResult = evaluate(node.condition, ctx)
	if conditionResult == true then
		-- Delete the elseif / else block
		if node.kind == "stat" then
			return node.thenBlock
		else
			return node.thenExpr
		end
	end

	-- Handle if we have an elseif
	local elseifs: { cst.CstElseIfStat | cst.CstElseIfExpr } = {}
	for _, elseifNode in node.elseifs do
		local elseifConditionResult = evaluate(elseifNode.condition, ctx)
		if elseifConditionResult == true then
			-- Replace the else block with the contents of this node
			-- Do not progress any further (as further conditions are no longer reachable)
			node.elseKeyword = elseifNode.elseIfKeyword
			node.elseKeyword.text = "else"
			node.elseKeyword.trailingTrivia = elseifNode.thenKeyword.trailingTrivia
			if node.kind == "stat" then
				node.elseBlock = elseifNode.thenBlock
			else
				node.elseExpr = elseifNode.thenExpr
			end
			break
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
			assert(firstElseIf ~= nil, "Luau")

			node.ifKeyword = (firstElseIf.elseIfKeyword :: any) :: cst.CstToken<"if">
			node.ifKeyword.text = "if"
			node.condition = firstElseIf.condition
			node.thenKeyword = firstElseIf.thenKeyword
			if node.kind == "stat" then
				node.thenBlock = firstElseIf.thenBlock
			else
				node.thenExpr = firstElseIf.thenExpr
			end
			node.elseifs = elseifs

			return node
		else
			return if node.kind == "stat" then node.elseBlock else node.elseExpr
		end
	end

	node.elseifs = elseifs

	return node
end

return simplifyConditional
