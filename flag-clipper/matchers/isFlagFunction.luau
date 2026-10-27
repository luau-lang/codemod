local syntax = require("@std/syntax")

local isFlagAccess = require("./isFlagAccess")

local function isFlagFunction(func: syntax.CstExprFunction, flagName: string): boolean
	for _, stmt in func.body.statements do
		if stmt.tag == "return" and #stmt.expressions == 1 then
			return isFlagAccess(stmt.expressions[1], flagName)
		end
	end

	return false
end

local function isExprFlagFunction(expr: syntax.CstExpr, flagName: string): boolean
	if expr.tag == "function" then
		return isFlagFunction(expr, flagName)
	end

	return false
end

local function isStmtFlagFunction(stmt: syntax.CstStat, flagName: string): boolean
	if stmt.tag == "function" or stmt.tag == "localfunction" then
		return isFlagFunction(stmt.func, flagName)
	end

	return false
end

return {
	isExprFlagFunction = isExprFlagFunction,
	isStmtFlagFunction = isStmtFlagFunction,
}
