local T = require("@batteries/syntax/ast_types")

local isFlagAccess = require("./isFlagAccess")

local function isFlagFunction(body: T.AstFunctionBody, flagName: string): boolean
	for _, stmt in body.body.statements do
		if stmt.tag == "return" and #stmt.expressions == 1 then
			return isFlagAccess(stmt.expressions[1].node, flagName)
		end
	end

	return false
end

local function isExprFlagFunction(expr: T.AstExpr, flagName: string): boolean
	if expr.tag == "function" then
		return isFlagFunction(expr.body, flagName)
	end

	return false
end

local function isStmtFlagFunction(stmt: T.AstStat, flagName: string): boolean
	if stmt.tag == "function" or stmt.tag == "localfunction" then
		return isFlagFunction(stmt.body, flagName)
	end

	return false
end

return {
	isExprFlagFunction = isExprFlagFunction,
	isStmtFlagFunction = isStmtFlagFunction,
}
