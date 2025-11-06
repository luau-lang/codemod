local luau = require("@lute/luau")

local evaluate = require("./evaluate")

--- Simplifies a conditional based on the evaluated condition
--- Works for both if statements and if expressions
local function simplifyConditional(
	node: luau.AstStatIf | luau.AstExprIfElse,
	ctx: evaluate.EvaluateContext
): luau.AstStat | luau.AstExpr
	-- This is performed in post, so the conditional expression is already simplified
	local conditionResult = evaluate(node.condition, ctx)
	if conditionResult == true then
		-- Delete the elseif / else block
		if node.kind == "stat" then
			return node.thenblock
		else
			return node.thenexpr
		end
	end

	-- Handle if we have an elseif
	local elseifs: { luau.AstStatElseIf | luau.AstExprIfElseIfs } = {}
	for _, elseifNode in node.elseifs do
		local elseifConditionResult = evaluate(elseifNode.condition, ctx)
		if elseifConditionResult == true then
			-- Replace the else block with the contents of this node
			-- Do not progress any further (as further conditions are no longer reachable)
			node.elsekeyword = elseifNode.elseifkeyword
			node.elsekeyword.text = "else"
			node.elsekeyword.trailingtrivia = elseifNode.thenkeyword.trailingtrivia
			if node.kind == "stat" then
				node.elseblock = elseifNode.thenblock
			else
				node.elseexpr = elseifNode.thenexpr
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

			node.ifkeyword = (firstElseIf.elseifkeyword :: any) :: luau.Token<"if">
			node.ifkeyword.text = "if"
			node.condition = firstElseIf.condition
			node.thenkeyword = firstElseIf.thenkeyword
			if node.kind == "stat" then
				node.thenblock = firstElseIf.thenblock
			else
				node.thenexpr = firstElseIf.thenexpr
			end
			node.elseifs = elseifs

			return node
		else
			return if node.kind == "stat" then node.elseblock else node.elseexpr
		end
	end

	node.elseifs = elseifs

	return node
end

return simplifyConditional
