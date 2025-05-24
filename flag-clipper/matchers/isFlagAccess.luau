local luau = require("@lute/luau")

local function isGameGlobal(expression: luau.AstExpr)
	return expression.tag == "global" and expression.name.text == "game"
end

local function isFlagCall(expression: luau.AstExpr)
	if expression.tag ~= "indexname" then
		return false
	end

	return isGameGlobal(expression.expression)
		and (expression.index.text == "DefineFastFlag" or expression.index.text == "GetFastFlag")
end

local function isFlagAccess(expr: luau.AstExpr, flagName: string): boolean
	if expr.tag ~= "call" then
		return false
	end

	return isFlagCall(expr.func)
		and #expr.arguments >= 1
		and expr.arguments[1].node.tag == "string"
		and expr.arguments[1].node.text == flagName
end

return isFlagAccess
