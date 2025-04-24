local T = require("@batteries/syntax/ast_types")

local evaluate = require("./evaluate")

local function isConstantTrueValue(expression: T.AstExpr, ctx: evaluate.EvaluateContext)
	local value = evaluate(expression, ctx)
	return value == true
end

local function isConstantFalseValue(expression: T.AstExpr, ctx: evaluate.EvaluateContext)
	local value = evaluate(expression, ctx)
	return value == false
end

local function makePosition(startLine: number, startColumn: number, endLine: number, endColumn: number): T.Position
	return {
		begin = {
			line = startLine,
			column = startColumn,
		},
		["end"] = {
			line = endLine,
			column = endColumn,
		},
	}
end

local function makeConstant(value: boolean): T.AstExprConstantBool
	return {
		tag = "boolean",
		leadingTrivia = {},
		position = makePosition(0, 0, 0, 0), -- TODO
		text = tostring(value),
		trailingTrivia = {},
		value = value,
	}
end

local function simplifyUnary(expression: T.AstExprUnary, ctx: evaluate.EvaluateContext): T.AstExpr
	if expression.operator.text == "not" then
		if isConstantTrueValue(expression.operand, ctx) then
			return makeConstant(false)
		elseif isConstantFalseValue(expression.operand, ctx) then
			return makeConstant(true)
		end
	end

	return expression
end

local function simplifyBinary(expression: T.AstExprBinary, ctx: evaluate.EvaluateContext): T.AstExpr
	if expression.operator.text == "and" then
		if isConstantTrueValue(expression.lhsoperand, ctx) then
			-- true and x => x
			return simplify(expression.rhsoperand, ctx)
		elseif isConstantFalseValue(expression.lhsoperand, ctx) then
			-- false and x => false
			return simplify(expression.lhsoperand, ctx)
		elseif isConstantTrueValue(expression.rhsoperand, ctx) then
			-- x and true => x
			return simplify(expression.lhsoperand, ctx)
		elseif isConstantFalseValue(expression.rhsoperand, ctx) then
			-- x and false => false
			return simplify(expression.rhsoperand, ctx)
		end
	elseif expression.operator.text == "or" then
		if isConstantTrueValue(expression.lhsoperand, ctx) then
			-- true or x => true
			return simplify(expression.lhsoperand, ctx)
		elseif isConstantFalseValue(expression.lhsoperand, ctx) then
			-- false or x => x
			return simplify(expression.rhsoperand, ctx)
		elseif isConstantTrueValue(expression.rhsoperand, ctx) then
			-- x or true => true
			return simplify(expression.rhsoperand, ctx)
		elseif isConstantFalseValue(expression.rhsoperand, ctx) then
			-- x or false => x
			return simplify(expression.lhsoperand, ctx)
		end
	end

	return expression
end

--- TODO: this is pretty much a duplicate of the block variant, can we DRY?
local function simplifyConditional(expression: T.AstExprIfElse, ctx: evaluate.EvaluateContext): T.AstExpr
	local conditionResult = evaluate(expression.condition, ctx)
	if conditionResult == true then
		-- Delethe the elseif / else part
		return expression.consequent
	end

	-- Handle if we have an elseif
	local elseifs = {}
	for _, elseifNode in expression.elseifs do
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
		-- If part must be deleted
		if #elseifs > 0 then
			-- Replace if with first else if
			local firstElseIf = table.remove(elseifs, 1)
			expression["if"] = firstElseIf["elseif"]
			expression["if"].text = "if"
			expression.condition = firstElseIf.condition
			expression["then"] = firstElseIf["then"]
			expression.consequent = firstElseIf.consequent
			expression.elseifs = elseifs

			return expression
		else
			return expression.antecedent
		end
	end

	expression.elseifs = elseifs

	return expression
end

function simplify(expression: T.AstExpr, ctx: evaluate.EvaluateContext): T.AstExpr
	if expression.tag == "binary" then
		return simplifyBinary(expression, ctx)
	elseif expression.tag == "unary" then
		return simplifyUnary(expression, ctx)
	elseif expression.tag == "conditional" then
		return simplifyConditional(expression, ctx)
	end

	return expression
end

return simplify
