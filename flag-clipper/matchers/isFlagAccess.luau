local T = require("@batteries/syntax/ast_types")

local function isGameGlobal(expr: T.AstExpr)
	return expr.tag == "global" and expr.name.text == "game"
end

local function isFlagCall(expr: T.AstExpr)
	if expr.tag ~= "indexname" then
		return false
	end

	return isGameGlobal(expr.expr) and (expr.index.text == "DefineFastFlag" or expr.index.text == "GetFastFlag")
end

local function isFlagAccess(expr: T.AstExpr, flagName: string): boolean
	if expr.tag ~= "call" then
		return false
	end

	return isFlagCall(expr.func)
		and #expr.arguments >= 1
		and expr.arguments[1].node.tag == "string"
		and expr.arguments[1].node.text == flagName
end

return isFlagAccess
