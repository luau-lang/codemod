local luau = require("@lute/luau")
local printer = require("@std/syntax/printer")

local createConstantBoolean = require("./createConstantBoolean")
local evaluate = require("./evaluate")
local modified = require("./modified")
local simplifyConditional = require("./simplifyConditional")
local trivia = require("./trivia")

local function isConstantTrueValue(expression: luau.AstExpr, ctx: evaluate.EvaluateContext)
	local value = evaluate(expression, ctx)
	return value == true
end

local function isConstantFalseValue(expression: luau.AstExpr, ctx: evaluate.EvaluateContext)
	local value = evaluate(expression, ctx)
	return value == false
end

local function simplifyBinary(expression: luau.AstExprBinary, ctx: evaluate.EvaluateContext): luau.AstExpr
	if expression.operator.text == "and" then
		if isConstantTrueValue(expression.lhsoperand, ctx) then
			-- true and x => x
			ctx.references._simplifiedBinaries[expression.rhsoperand] = true
			return simplify(expression.rhsoperand, ctx)
		elseif isConstantFalseValue(expression.lhsoperand, ctx) then
			-- false and x => false
			ctx.references._simplifiedBinaries[expression.lhsoperand] = true
			return simplify(expression.lhsoperand, ctx)
		elseif isConstantTrueValue(expression.rhsoperand, ctx) then
			-- x and true => x
			ctx.references._simplifiedBinaries[expression.lhsoperand] = true
			return simplify(expression.lhsoperand, ctx)
		elseif isConstantFalseValue(expression.rhsoperand, ctx) then
			-- x and false => false
			ctx.references._simplifiedBinaries[expression.rhsoperand] = true
			return simplify(expression.rhsoperand, ctx)
		end
	elseif expression.operator.text == "or" then
		-- Handle the case for pseudo-ternaries (FlagValue and x or y)
		-- Due to precedence rules, this would be simplified originally to (x or y)
		-- We can check if 'x' is modified, and then simplify it further as a pseudo-ternary
		if modified.isModified(expression.lhsoperand) then
			if isConstantFalseValue(expression.lhsoperand, ctx) then
				ctx.references._simplifiedBinaries[expression.rhsoperand] = true
				return expression.rhsoperand
			else
				ctx.references._simplifiedBinaries[expression.lhsoperand] = true
				return expression.lhsoperand
			end
		end

		if isConstantTrueValue(expression.lhsoperand, ctx) then
			-- true or x => true
			ctx.references._simplifiedBinaries[expression.lhsoperand] = true
			return simplify(expression.lhsoperand, ctx)
		elseif isConstantFalseValue(expression.lhsoperand, ctx) then
			-- false or x => x
			ctx.references._simplifiedBinaries[expression.rhsoperand] = true
			return simplify(expression.rhsoperand, ctx)
		elseif isConstantTrueValue(expression.rhsoperand, ctx) then
			-- x or true => true
			ctx.references._simplifiedBinaries[expression.rhsoperand] = true
			return simplify(expression.rhsoperand, ctx)
		elseif isConstantFalseValue(expression.rhsoperand, ctx) then
			-- x or false => x
			ctx.references._simplifiedBinaries[expression.lhsoperand] = true
			return simplify(expression.lhsoperand, ctx)
		end
	end

	return expression
end

local function simplifyTable(expression: luau.AstExprTable, ctx: evaluate.EvaluateContext)
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
				trivia.getTrailingTrivia(field.value)
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

local function simplifyCall(expression: luau.AstExprCall, ctx: evaluate.EvaluateContext)
	-- we only care abt call args
	local args = {}
	for _, arg in expression.arguments do
		--- Evaluate references to the flag if available, and replace the args to the call with the evaluation
		local constantEvaluation = evaluate(arg.node, ctx)
		if constantEvaluation ~= nil then
			arg.node = createConstantBoolean(
				constantEvaluation,
				trivia.getLeadingTrivia(arg.node),
				trivia.getTrailingTrivia(arg.node)
			)
		end

		table.insert(args, arg)
	end
	expression.arguments = args
	return expression
end

function simplify(expression: luau.AstExpr, ctx: evaluate.EvaluateContext): luau.AstExpr
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
