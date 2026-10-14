local syntax = require("@std/syntax")
local visitor = require("@std/syntax/visitor")

local evaluate = require("./evaluate")
local simplifyConditional = require("./simplifyConditional")

--- Checks to see if the provided expression has a reference to the provided local.
--- e.g., for the local `value`, and the expression `call(value)`, return true.
local function expressionReferencesLocal(
	expression: syntax.CstExpr,
	loc: syntax.CstLocal,
	ctx: evaluate.EvaluateContext
): boolean
	local isReferencingLocal = false

	local referenceVisitor = visitor.create()
	referenceVisitor.visitExprLocal = function(reference: syntax.CstExprLocal)
		if loc == reference["local"] then
			isReferencingLocal = true
			return false
		end
		return true
	end
	ctx.rewriter:visit(expression, referenceVisitor)

	return isReferencingLocal
end

--- Simplify expressions that directly reference the flag (or its inverse) to a boolean literal
local function simplifyPunctuated(expressions: syntax.CstPunctuated<syntax.CstExpr>, ctx: evaluate.EvaluateContext)
	for _, expression in expressions do
		local constantEvaluation = evaluate(expression, ctx)
		if constantEvaluation ~= nil then
			ctx.rewriter:setConstant(expression, constantEvaluation)
		end
	end
end

--- Simplifies the statements of a block, returning the statements that are kept
local function simplifyBlock(block: syntax.CstStatBlock, ctx: evaluate.EvaluateContext): { syntax.CstStat }
	local rewriter = ctx.rewriter
	local statements: { syntax.CstStat } = {}

	for _, statement in rewriter:statements(block) do
		if statement.tag == "expression" then
			-- Skip (i.e. delete) any top level flag access calls (game:DefineFastFlag / game:GetFastFlag)
			if rewriter:isReference(statement.expression) then
				continue
			end
			table.insert(statements, statement)
		elseif statement.tag == "local" then
			-- Skip (i.e. delete) if all variables are marked for deletion
			local shouldDelete = true
			for _, variable in statement.variables do
				if not ctx.references:isLocalReference(variable) then
					shouldDelete = false
					break
				end
			end

			if shouldDelete then
				continue
			end

			simplifyPunctuated(statement.values, ctx)

			table.insert(statements, statement)
		elseif statement.tag == "localfunction" then
			-- Skip (i.e. delete) if local function is marked for deletion
			if ctx.references:isLocalReference(statement.name) then
				continue
			end

			table.insert(statements, statement)
		elseif statement.tag == "function" then
			-- Skip (i.e. delete) if local function is marked for deletion
			local name = statement.name
			if name.tag == "local" and ctx.references:isLocalReference(name["local"]) then
				continue
			elseif name.tag == "global" and ctx.references:isGlobalReference(name.name.text) then
				continue
			end

			table.insert(statements, statement)
		elseif statement.tag == "assign" then
			-- Skip (i.e. delete) if any assignment target is a flag reference
			local shouldDelete = false
			for _, variable in statement.variables do
				if rewriter:isReference(variable) then
					shouldDelete = true
					break
				end
			end

			if shouldDelete then
				continue
			end

			simplifyPunctuated(statement.values, ctx)

			table.insert(statements, statement)
		elseif statement.tag == "return" then
			simplifyPunctuated(statement.expressions, ctx)

			table.insert(statements, statement)
		elseif statement.tag == "conditional" then
			local simplified = simplifyConditional(statement, ctx)
			if simplified == nil then
				-- Conditional is removed
				continue
			elseif simplified.kind == "stat" and simplified.tag == "conditional" then
				table.insert(statements, simplified)
			elseif simplified.kind == "stat" and simplified.tag == "block" then
				-- If processed down to a block, flatten with the main block
				for i, otherStatement in rewriter:statements(simplified) do
					-- Simplify 'local x = value; x = ...' after the block was removed
					if
						i == 1
						and otherStatement.tag == "assign"
						and #statements > 0
						and #otherStatement.variables == 1
						and #otherStatement.values == 1
					then
						local assigningTo = rewriter:view(otherStatement.variables[1])
						local previousStatement = statements[#statements]
						if
							assigningTo
							and assigningTo.tag == "local"
							and previousStatement.tag == "local"
							and #previousStatement.variables == 1
							and previousStatement.variables[1] == assigningTo["local"]
							and not expressionReferencesLocal(otherStatement.values[1], assigningTo["local"], ctx)
						then
							rewriter:setLocalMerge(previousStatement, {
								nameTrailingTrivia = assigningTo.token.trailingTrivia,
								equals = otherStatement.equals,
								values = otherStatement.values,
							})
							continue
						end
					end

					table.insert(statements, otherStatement)
				end
				-- if statements from simplified conditional terminate the outer block, return early & don't add subsequent statements
				local lastStatement = statements[#statements]
				if lastStatement and (lastStatement.tag == "return" or lastStatement.tag == "break") then
					break
				end
			else
				error(
					`simplifyConditional should only return a conditional statement or block of statements, but got {simplified.tag}`
				)
			end
		else
			table.insert(statements, statement)
		end
	end

	rewriter:setStatements(block, statements)

	return statements
end

return simplifyBlock
