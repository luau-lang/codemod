local syntax = require("@std/syntax")

local function isStringLiteral(expression: syntax.CstExpr?, text: string): boolean
	return expression ~= nil and expression.tag == "string" and expression.value.text == text
end

local function isGameGlobal(expression: syntax.CstExpr)
	return expression.tag == "global" and expression.name.text == "game"
end

local function isFlagCall(expression: syntax.CstExpr)
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

local function isStandardFlagAccess(expr: syntax.CstExpr, flagName: string): boolean
	if expr.tag ~= "call" then
		return false
	end

	return isFlagCall(expr.func) and #expr.arguments >= 1 and isStringLiteral(expr.arguments[1], flagName)
end

local function isSetScopedFFlag(expression: syntax.CstExpr, flagName: string): boolean
	if expression.tag ~= "call" then
		return false
	end

	local isSetScopedFFlag = (expression.func.tag == "global" and expression.func.name.text == "setScopedFFlag")
		or (expression.func.tag == "local" and expression.func.token.text == "setScopedFFlag")

	return isSetScopedFFlag and #expression.arguments >= 1 and isStringLiteral(expression.arguments[1], flagName)
end

local function isUIBloxFlagAccess(expr: syntax.CstExpr, flagName: string): boolean
	-- Handle usage: UIBloxConfig.FlagName
	if expr.tag == "indexname" and expr.index.text == flagName then
		local base = expr.expression
		return (base.tag == "local" and base["local"].name.text == "UIBloxConfig")
			or (base.tag == "global" and base.name.text == "UIBloxConfig")
	end

	-- TO-DO: Handle removing declaration in config table: { FlagName = boolean, ... }
	return false
end

local function isSafeFlags(expression: syntax.CstExpr)
	if expression.tag == "global" then
		return expression.name.text == "SafeFlags"
	elseif expression.tag == "local" then
		return expression.token.text == "SafeFlags"
	end
	return false
end

local function isCreateGetFFlagCall(expression: syntax.CstExpr)
	if expression.tag ~= "indexname" then
		return false
	end

	return isSafeFlags(expression.expression) and expression.index.text == "createGetFFlag"
end

local function isFoundationFlagAccess(expression: syntax.CstExpr, flagName: string)
	-- Handle direct flag calls: SafeFlags.createGetFFlag("flagName")()
	if expression.tag == "call" then
		local func = expression.func
		if func.tag == "call" then
			return isCreateGetFFlagCall(func.func)
				and #func.arguments >= 1
				and isStringLiteral(func.arguments[1], flagName)
		end
	end

	-- Handle flag property access: Flags.FlagName (for assignments like Flags.FlagName = props.boolean)
	if expression.tag == "indexname" then
		local unversionedFlagName = flagName:gsub("%d+$", "")
		return expression.index.text == unversionedFlagName
	end

	return false
end

local function isFlagAccess(expr: syntax.CstExpr, flagName: string): boolean
	return isStandardFlagAccess(expr, flagName)
		or isSetScopedFFlag(expr, flagName)
		or isFoundationFlagAccess(expr, flagName)
		or isUIBloxFlagAccess(expr, flagName)
end

return isFlagAccess
