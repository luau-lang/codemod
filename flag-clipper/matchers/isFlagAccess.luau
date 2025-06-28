local luau = require("@lute/luau")

local function isGameGlobal(expression: luau.AstExpr)
	return expression.tag == "global" and expression.name.text == "game"
end

local function isFlagCall(expression: luau.AstExpr)
	if expression.tag ~= "indexname" then
		return false
	end

	return isGameGlobal(expression.expression)
		and (
			expression.index.text == "DefineFastFlag"
			or expression.index.text == "GetFastFlag"
			or expression.index.text == "SetFastFlagForTesting"
		)
end

local function isStandardFlagAccess(expr: luau.AstExpr, flagName: string): boolean
	if expr.tag ~= "call" then
		return false
	end

	return isFlagCall(expr.func)
		and #expr.arguments >= 1
		and expr.arguments[1].node.tag == "string"
		and expr.arguments[1].node.text == flagName
end

local function isSetScopedFFlag(expression: luau.AstExpr, flagName: string): boolean
	if expression.tag ~= "call" then
		return false
	end

	local isSetScopedFFlag = (expression.func.tag == "global" and expression.func.name.text == "setScopedFFlag")
		or (expression.func.tag == "local" and expression.func.token.text == "setScopedFFlag")

	return isSetScopedFFlag
		and #expression.arguments >= 1
		and expression.arguments[1].node.tag == "string"
		and expression.arguments[1].node.text == flagName
end

local function isUIBloxFlagAccess(expr: luau.AstExpr, flagName: string): boolean
	-- Handle usage: UIBloxConfig.FlagName
	if expr.tag == "indexname" and expr.index.text == flagName then
		return (expr.expression["local"] and expr.expression["local"].name.text == "UIBloxConfig")
			or (expr.expression.name and expr.expression.name.text == "UIBloxConfig")
	end

	-- TO-DO: Handle removing declaration in config table: { FlagName = boolean, ... }
	return false
end

local function isSafeFlags(expression: luau.AstExpr)
	if expression.tag ~= "local" and expression.tag ~= "global" then
		return false
	end
	if expression.tag == "global" then
		return expression.name.text == "SafeFlags"
	end
	return typeof(expression.token.text) == "string" and expression.token.text == "SafeFlags"
end

local function isCreateGetFFlagCall(expression: luau.AstExpr)
	if expression.tag ~= "indexname" then
		return false
	end

	return isSafeFlags(expression.expression) and expression.index.text == "createGetFFlag"
end

local function isFoundationFlagAccess(expression: luau.AstExpr, flagName: string)
	-- Handle direct flag calls: SafeFlags.createGetFFlag("flagName")()
	if expression.tag == "call" then
		if expression.func.tag == "call" then
			return isCreateGetFFlagCall(expression.func.func)
				and #expression.func.arguments >= 1
				and expression.func.arguments[1].node.tag == "string"
				and expression.func.arguments[1].node.text == flagName
		end
	end

	-- Handle flag property access: Flags.FlagName (for assignments like Flags.FlagName = props.boolean)
	if expression.tag == "indexname" then
		return expression.index and expression.index.text == flagName
	end

	return false
end

local function isFlagAccess(expr: luau.AstExpr, flagName: string): boolean
	return isStandardFlagAccess(expr, flagName)
		or isSetScopedFFlag(expr, flagName)
		or isFoundationFlagAccess(expr, flagName)
		or isUIBloxFlagAccess(expr, flagName)
end

return isFlagAccess
