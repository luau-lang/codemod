local syntax = require("@std/syntax")

local evaluate = require("./evaluate")
local simplifyConditional = require("./simplifyConditional")

local simplify: (expression: syntax.CstExpr, ctx: evaluate.EvaluateContext) -> syntax.CstExpr

local function isConstantTrueValue(expression: syntax.CstExpr, ctx: evaluate.EvaluateContext)
	local value = evaluate(expression, ctx)
	return value == true
end

local function isConstantFalseValue(expression: syntax.CstExpr, ctx: evaluate.EvaluateContext)
	local value = evaluate(expression, ctx)
	return value == false
end

local function simplifyBinary(expression: syntax.CstExprBinary, ctx: evaluate.EvaluateContext): syntax.CstExpr
	local simplifiedBinaries = ctx.rewriter.simplifiedBinaries
	local lhs, rhs = expression.lhsOperand, expression.rhsOperand

	if expression.operator.text == "and" then
		if isConstantTrueValue(lhs, ctx) then
			-- true and x => x
			simplifiedBinaries[rhs] = true
			return simplify(rhs, ctx)
		elseif isConstantFalseValue(lhs, ctx) then
			-- false and x => false
			simplifiedBinaries[lhs] = true
			return simplify(lhs, ctx)
		elseif isConstantTrueValue(rhs, ctx) then
			-- x and true => x
			simplifiedBinaries[lhs] = true
			return simplify(lhs, ctx)
		elseif isConstantFalseValue(rhs, ctx) then
			-- x and false => false
			simplifiedBinaries[rhs] = true
			return simplify(rhs, ctx)
		end
	elseif expression.operator.text == "or" then
		-- Handle the case for pseudo-ternaries (FlagValue and x or y)
		-- Due to precedence rules, this would be simplified originally to (x or y)
		-- We can check if 'x' is modified, and then simplify it further as a pseudo-ternary
		if ctx.rewriter:isModified(lhs) then
			if isConstantFalseValue(lhs, ctx) then
				simplifiedBinaries[rhs] = true
				return rhs
			else
				simplifiedBinaries[lhs] = true
				return lhs
			end
		end

		if isConstantTrueValue(lhs, ctx) then
			-- true or x => true
			simplifiedBinaries[lhs] = true
			return simplify(lhs, ctx)
		elseif isConstantFalseValue(lhs, ctx) then
			-- false or x => x
			simplifiedBinaries[rhs] = true
			return simplify(rhs, ctx)
		elseif isConstantTrueValue(rhs, ctx) then
			-- x or true => true
			simplifiedBinaries[rhs] = true
			return simplify(rhs, ctx)
		elseif isConstantFalseValue(rhs, ctx) then
			-- x or false => x
			simplifiedBinaries[lhs] = true
			return simplify(lhs, ctx)
		end
	end

	return expression
end

local function simplifyTable(expression: syntax.CstExprTable, ctx: evaluate.EvaluateContext): syntax.CstExpr
	local rewriter = ctx.rewriter
	local entries = {}
	local changed = false

	for _, field in rewriter:tableEntries(expression) do
		--- Remove fields from a table that directly reference the removed Flag
		if
			rewriter:isReference(field.value)
			and not (rewriter:isCompoundReference(field.value) or rewriter.simplifiedBinaries[field.value])
		then
			changed = true
			continue
		end

		--- Evaluate references to the flag if available, and replace the fields in the table with the evaluation
		local constantEvaluation = evaluate(field.value, ctx)
		if constantEvaluation ~= nil then
			rewriter:setConstant(field.value, constantEvaluation)
		end

		--- Remove fields from a table if they were simplified by the flag-clipper, and are now `nil`
		if rewriter:isModified(field.value) then
			local value = rewriter:view(field.value)
			if value and value.tag == "nil" then
				changed = true
				continue
			end
		end

		table.insert(entries, field)
	end

	if changed then
		rewriter:setTableEntries(expression, entries)
	end

	return expression
end

local function simplifyCall(expression: syntax.CstExprCall, ctx: evaluate.EvaluateContext): syntax.CstExpr
	-- we only care abt call args
	for _, arg in expression.arguments do
		--- Evaluate references to the flag if available, and replace the args to the call with the evaluation
		local constantEvaluation = evaluate(arg, ctx)
		if constantEvaluation ~= nil then
			ctx.rewriter:setConstant(arg, constantEvaluation)
		end
	end

	return expression
end

--- Simplifies the expression, returning the expression that it should be replaced with
--- (or the expression itself, if it should be kept)
function simplify(expression: syntax.CstExpr, ctx: evaluate.EvaluateContext): syntax.CstExpr
	local effective = ctx.rewriter:view(expression)
	if effective == nil then
		return expression
	end

	local result: syntax.CstExpr = effective
	if effective.tag == "call" then
		result = simplifyCall(effective, ctx)
	elseif effective.tag == "binary" then
		result = simplifyBinary(effective, ctx)
	elseif effective.tag == "conditional" then
		result = simplifyConditional(effective, ctx) :: syntax.CstExpr
	elseif effective.tag == "table" then
		result = simplifyTable(effective, ctx)
	end

	return if result == effective then expression else result
end

return simplify
