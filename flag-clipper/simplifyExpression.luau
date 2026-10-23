local cst = require("@lute/syntax/mutablecst")
local printer = require("@std/syntax/printer")

local createConstantBoolean = require("./createConstantBoolean")
local evaluate = require("./evaluate")
local modified = require("./modified")
local simplifyConditional = require("./simplifyConditional")
local trivia = require("./trivia")

local function isConstantTrueValue(expression: cst.CstExpr, ctx: evaluate.EvaluateContext)
	local value = evaluate(expression, ctx)
	return value == true
end

local function isConstantFalseValue(expression: cst.CstExpr, ctx: evaluate.EvaluateContext)
	local value = evaluate(expression, ctx)
	return value == false
end

local function simplifyBinary(expression: cst.CstExprBinary, ctx: evaluate.EvaluateContext): cst.CstExpr
	if expression.operator.text == "and" then
		if isConstantTrueValue(expression.lhsOperand, ctx) then
			-- true and x => x
			ctx.references._simplifiedBinaries[expression.rhsOperand] = true
			return simplify(expression.rhsOperand, ctx)
		elseif isConstantFalseValue(expression.lhsOperand, ctx) then
			-- false and x => false
			ctx.references._simplifiedBinaries[expression.lhsOperand] = true
			return simplify(expression.lhsOperand, ctx)
		elseif isConstantTrueValue(expression.rhsOperand, ctx) then
			-- x and true => x
			ctx.references._simplifiedBinaries[expression.lhsOperand] = true
			return simplify(expression.lhsOperand, ctx)
		elseif isConstantFalseValue(expression.rhsOperand, ctx) then
			-- x and false => false
			ctx.references._simplifiedBinaries[expression.rhsOperand] = true
			return simplify(expression.rhsOperand, ctx)
		end
	elseif expression.operator.text == "or" then
		-- Handle the case for pseudo-ternaries (FlagValue and x or y)
		-- Due to precedence rules, this would be simplified originally to (x or y)
		-- We can check if 'x' is modified, and then simplify it further as a pseudo-ternary
		if modified.isModified(expression.lhsOperand) then
			if isConstantFalseValue(expression.lhsOperand, ctx) then
				ctx.references._simplifiedBinaries[expression.rhsOperand] = true
				return expression.rhsOperand
			else
				ctx.references._simplifiedBinaries[expression.lhsOperand] = true
				return expression.lhsOperand
			end
		end

		if isConstantTrueValue(expression.lhsOperand, ctx) then
			-- true or x => true
			ctx.references._simplifiedBinaries[expression.lhsOperand] = true
			return simplify(expression.lhsOperand, ctx)
		elseif isConstantFalseValue(expression.lhsOperand, ctx) then
			-- false or x => x
			ctx.references._simplifiedBinaries[expression.rhsOperand] = true
			return simplify(expression.rhsOperand, ctx)
		elseif isConstantTrueValue(expression.rhsOperand, ctx) then
			-- x or true => true
			ctx.references._simplifiedBinaries[expression.rhsOperand] = true
			return simplify(expression.rhsOperand, ctx)
		elseif isConstantFalseValue(expression.rhsOperand, ctx) then
			-- x or false => x
			ctx.references._simplifiedBinaries[expression.lhsOperand] = true
			return simplify(expression.lhsOperand, ctx)
		end
	end

	return expression
end

local function simplifyTable(expression: cst.CstExprTable, ctx: evaluate.EvaluateContext)
	local entries = {}
	for _, field in expression.entries do
		--- Remove fields from a table that directly reference the removed Flag
		if
			ctx.references:isReference(field.value)
			and not (ctx.references:isCompoundReference(field.value) or ctx.references._simplifiedBinaries[field.value])
		then
			continue
		end

		--- Evaluate references to the flag if available, and replace the fields in the table with the evaluation
		local constantEvaluation = evaluate(field.value, ctx)
		if constantEvaluation ~= nil then
			field.value = createConstantBoolean(
				constantEvaluation,
				trivia.getLeadingTrivia(field.value),
				trivia.getTrailingTrivia(field.value),
				field.value.location
			)
		end

		--- Remove fields from a table if they were simplified by the flag-clipper, and are now `nil`
		if modified.isModified(field.value) and field.value.tag == "nil" then
			continue
		end

		table.insert(entries, field)
	end
	expression.entries = entries
	return expression
end

local function simplifyCall(expression: cst.CstExprCall, ctx: evaluate.EvaluateContext)
	-- we only care abt call args
	for i, arg in expression.arguments do
		--- Evaluate references to the flag if available, and replace the args to the call with the evaluation
		local constantEvaluation = evaluate(arg, ctx)
		if constantEvaluation ~= nil then
			expression.arguments[i] = createConstantBoolean(
				constantEvaluation,
				trivia.getLeadingTrivia(arg),
				trivia.getTrailingTrivia(arg),
				arg.location
			)
		end
	end
	return expression
end

function simplify(expression: cst.CstExpr, ctx: evaluate.EvaluateContext): cst.CstExpr
	if expression.tag == "call" then
		return simplifyCall(expression, ctx)
	elseif expression.tag == "binary" then
		return simplifyBinary(expression, ctx)
	elseif expression.tag == "conditional" then
		return simplifyConditional(expression, ctx)
	elseif expression.tag == "table" then
		return simplifyTable(expression, ctx)
	end

	return expression
end

return simplify
