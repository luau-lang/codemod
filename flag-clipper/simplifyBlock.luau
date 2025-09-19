local luau = require("@lute/luau")
local visitor = require("@std/syntax/visitor")

local createConstantBoolean = require("./createConstantBoolean")
local evaluate = require("./evaluate")
local simplifyConditional = require("./simplifyConditional")
local trivia = require("./trivia")

--- Simplify expressions that directly reference the flag (or its inverse)
local function simplifyConstantExpression(ctx: evaluate.EvaluateContext, expression: luau.AstExpr): luau.AstExpr?
	local constantEvaluation = evaluate(expression, ctx)
	if constantEvaluation ~= nil then
		return createConstantBoolean(
			constantEvaluation,
			trivia.getLeadingTrivia(expression),
			trivia.getTrailingTrivia(expression)
		)
	end

	return nil
end

--- Checks to see if the provided expression has a reference to the provided local.
--- e.g., for the local `value`, and the expression `call(value)`, return true.
local function expressionReferencesLocal(expression: luau.AstExpr, loc: luau.AstLocal)
	local isReferencingLocal = false

	local referenceVisitor = visitor.createVisitor()
	referenceVisitor.visitLocalReference = function(reference: luau.AstExprLocal)
		if loc == reference["local"] then
			isReferencingLocal = true
			return false
		end
		return true
	end
	visitor.visitExpression(expression, referenceVisitor)

	return isReferencingLocal
end


local function simplifyFlagAssignments(statement: luau.AstStatLocal | luau.AstStatAssign, ctx: evaluate.EvaluateContext)
	for _, expression in statement.values do
		local simplified = simplifyConstantExpression(ctx, expression.node)
		if simplified then
			expression.node = simplified
		end
	end
end

local function simplifyBlock(block: luau.AstStatBlock, ctx: evaluate.EvaluateContext): luau.AstStatBlock
	local statements = {}

	for _, statement in block.statements do
		if statement.tag == "expression" then
			-- Skip (i.e. delete) any top level flag access calls (game:DefineFastFlag / game:GetFastFlag)
			if ctx.references:isReference(statement.expression) then
				continue
			end
			table.insert(statements, statement)
		elseif statement.tag == "local" then
			-- Skip (i.e. delete) if all variables are marked for deletion
			local shouldDelete = true
			for _, variable in statement.variables do
				if not ctx.references:isLocalReference(variable.node) then
					shouldDelete = false
					break
				end
			end

			if shouldDelete then
				continue
			end

			simplifyFlagAssignments(statement, ctx)

			table.insert(statements, statement)
		elseif statement.tag == "localfunction" then
			-- Skip (i.e. delete) if local function is marked for deletion
			if ctx.references:isLocalReference(statement.name) then
				continue
			end

			table.insert(statements, statement)
		elseif statement.tag == "function" then
			-- Skip (i.e. delete) if local function is marked for deletion
			if statement.name.tag == "local" and ctx.references:isLocalReference(statement.name["local"]) then
				continue
			elseif statement.name.tag == "global" and ctx.references:isGlobalReference(statement.name.name.text) then
				continue
			end

			table.insert(statements, statement)
		elseif statement.tag == "assign" then
			-- Skip (i.e. delete) if any assignment target is a flag reference
			local shouldDelete = false
			for _, variable in statement.variables do
				if ctx.references:isReference(variable.node) then
					shouldDelete = true
					break
				end
			end

			if shouldDelete then
				continue
			end

			simplifyFlagAssignments(statement, ctx)

			table.insert(statements, statement)
		elseif statement.tag == "return" then
			for _, expression in statement.expressions do
				local simplified = simplifyConstantExpression(ctx, expression.node)
				if simplified then
					expression.node = simplified
				end
			end

			table.insert(statements, statement)
		elseif statement.tag == "conditional" then
			local simplified = simplifyConditional(statement, ctx)
			if simplified == nil then
				-- Conditional is removed
				continue
			elseif simplified.tag == "conditional" then
				table.insert(statements, simplified)
			elseif simplified.tag == "block" then
				-- If processed down to a block, flatten with the main block
				for i, otherStatement in simplified.statements do
					-- Simplify 'local x = value; x = ...' after the block was removed
					if
						i == 1
						and otherStatement.tag == "assign"
						and #statements > 0
						and #otherStatement.variables == 1
						and #otherStatement.values == 1
					then
						local assigningTo = otherStatement.variables[1].node
						local previousStatement = statements[#statements]
						if
							assigningTo.tag == "local"
							and previousStatement.tag == "local"
							and #previousStatement.variables == 1
							and previousStatement.variables[1].node == assigningTo["local"]
							and not expressionReferencesLocal(otherStatement.values[1].node, assigningTo["local"])
						then
							previousStatement.variables[1].node.name.trailingTrivia = assigningTo.token.trailingTrivia
							previousStatement.equals = otherStatement.equals
							previousStatement.values = otherStatement.values
							continue
						end
					end

					table.insert(statements, otherStatement)
				end
				-- if statements from simplified conditional terminate the outer block, return early & don't add subsequent statements
				if statements[#statements].tag == "return" or statements[#statements].tag == "break" then
					break
				end
			else
				error(
					`simplifyIf should only return a conditional statement or block of statements, but got {simplified.tag}`
				)
			end
		else
			table.insert(statements, statement)
		end
	end

	return {
		tag = "block",
		statements = statements,
	}
end

return simplifyBlock
