local luau = require("@lute/luau")

local evaluate = require("./evaluate")
local simplifyConditional = require("./simplifyConditional")

local function isConstantTrueValue(expression: luau.AstExpr, ctx: evaluate.EvaluateContext)
	local value = evaluate(expression, ctx)
	return value == true
end

local function isConstantFalseValue(expression: luau.AstExpr, ctx: evaluate.EvaluateContext)
	local value = evaluate(expression, ctx)
	return value == false
end

type PseudoTernaryParts = {
	condition: luau.AstExpr,
	consequent: luau.AstExpr,
	antecedent: luau.AstExpr,
}

--- Checks if the provided expression is a "pseudo-ternary" (of the form 'x and y or z')
--- This typically corresponds to legacy code that is before if-else expressions.
--- However, for the sake of flag clipping, we can treat it in the same way
local function isPseudoTernary(expression: luau.AstExprBinary): PseudoTernaryParts?
	if expression.operator.text ~= "or" then
		return nil
	end

	if expression.lhsoperand.tag ~= "binary" then
		return nil
	end

	if expression.lhsoperand.operator.text ~= "and" then
		return nil
	end

	return {
		condition = expression.lhsoperand.lhsoperand,
		consequent = expression.lhsoperand.rhsoperand,
		antecedent = expression.rhsoperand,
	}
end

local function simplifyBinary(expression: luau.AstExprBinary, ctx: evaluate.EvaluateContext): luau.AstExpr
	local pseudoTernary = isPseudoTernary(expression)
	if pseudoTernary then
		if isConstantTrueValue(pseudoTernary.condition, ctx) then
			return pseudoTernary.consequent
		elseif isConstantFalseValue(pseudoTernary.condition, ctx) then
			return pseudoTernary.antecedent
		end
	end

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

--- Removes fields from a table that resolve to the removed Flag
local function simplifyTable(expression: luau.AstExprTable, ctx: evaluate.EvaluateContext)
	local entries = {}
	for _, field in expression.entries do
		if ctx.references:isReference(field.value) then
			continue
		end
		table.insert(entries, field)
	end
	expression.entries = entries
	return expression
end

function simplify(expression: luau.AstExpr, ctx: evaluate.EvaluateContext): luau.AstExpr
	if expression.tag == "binary" then
		return simplifyBinary(expression, ctx)
	elseif expression.tag == "conditional" then
		return simplifyConditional(expression, ctx)
	elseif expression.tag == "table" then
		return simplifyTable(expression, ctx)
	end

	return expression
end

return simplify
