local luau = require("@lute/luau")

local isFlagAccess = require("./isFlagAccess")

local function isFlagFunction(func: luau.AstExprFunction, flagName: string): boolean
	for _, stmt in func.body.statements do
		if stmt.tag == "return" and #stmt.expressions == 1 then
			return isFlagAccess(stmt.expressions[1].node, flagName)
		end
	end

	return false
end

local function isExprFlagFunction(expr: luau.AstExpr, flagName: string): boolean
	if expr.tag == "function" then
		return isFlagFunction(expr, flagName)
	end

	return false
end

local function isStmtFlagFunction(stmt: luau.AstStat, flagName: string): boolean
	if stmt.tag == "function" or stmt.tag == "localfunction" then
		local refinedStmt = stmt :: luau.AstStatFunction | luau.AstStatLocalFunction
		return isFlagFunction(refinedStmt.func, flagName)
	end

	return false
end

return {
	isExprFlagFunction = isExprFlagFunction,
	isStmtFlagFunction = isStmtFlagFunction,
}
