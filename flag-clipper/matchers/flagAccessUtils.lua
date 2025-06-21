local luau = require("@lute/luau")

local function printTable(table, indent: number, result: boolean?)
	for k, v in pairs(table) do
		local indentString = string.rep("  ", indent)
		if not result then
			if type(v) == "table" and not tostring(k):find("Trivia") then
				print(indentString .. tostring(k) .. ": (table)")
				printTable(v, indent + 1, false)
			else
				print(indentString .. tostring(k) .. ": " .. tostring(v))
			end
		else
			if type(k) == "table" then
				print(
					indentString
						.. tostring((k.name and (k.name.text or k.text)) or k)
						.. ", line "
						.. tostring(if k.name and k.name.position then k.name.position.line else "")
						.. ": "
						.. tostring(v)
				)
			else
				print(
					indentString
						.. tostring((v.name and (v.name.text or v.text)) or v)
						.. ", line "
						.. tostring(if v.name and v.name.position then v.name.position.line else "")
				)
			end
		end
	end
end

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

local function isUIBloxFlagAccess(expr: luau.AstExpr, flagName: string): boolean
	-- Handle usage: UIBloxConfig.FlagName
	if expr.tag == "indexname" then
		-- return isUIBloxConfig(expr.expression) and expr.index.text == flagName
		return expr.index.text == flagName
	end

	-- Handle declaration in config table: { FlagName = boolean, ... } (hmmmmm)
	-- if expr.tag == "table" then
	-- 	for k, v in pairs(expr.entries) do
	-- 		print(k, v, v.key.text)
	-- 		for k2, v2 in pairs(v) do
	-- 			print(k2, v2)
	-- 		end
	-- 		-- if v.key.text == flagName then
	-- 		-- 	print("found flagName: " .. flagName)
	-- 		-- 	return true
	-- 		-- end
	-- 	end
	-- end

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
	-- -- can also do:
	-- return typeof(expression["local"].name.text) == "string" and expression["local"].name.text == "SafeFlags"
end

local function isCreateGetFFlagCall(expression: luau.AstExpr)
	if expression.tag ~= "indexname" then
		return false
	end

	return isSafeFlags(expression.expression) and expression.index.text == "createGetFFlag"
end

local function isFoundationFlagAccess(expression: luau.AstExpr, flagName: string)
	-- Handle direct flag calls: SafeFlags.createGetFFlag("flagName")()
	-- notice how Foundation flags call one layer deeper/more nested
	-- than the flag access currently expected by this module (game:DefineFastFlag/GetFastFlag())
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

local function isDefaultFlagAccess(expr: luau.AstExpr, flagName: string): boolean
	if expr.tag ~= "call" then
		return false
	end

	-- debug output
	-- if expr.func.tag == "call" then
	-- 	print("outer call tree:", expr.tag)
	-- 	printTable(expr.arguments, 0)
	-- 	if #expr.func.arguments >= 1 and expr.func.arguments[1].node.tag == "string" then
	-- 		print("isFlagAccess:", expr.func.tag, expr.func.arguments)
	-- 		print(expr.func.arguments[1].node.tag, expr.func.arguments[1].node.text)
	-- 		if expr.func.func then
	-- 			printTable(expr.func, 0)
	-- 		end
	-- 	end
	-- 	print("--------------------------------")
	-- end

	return isFlagCall(expr.func)
		and #expr.arguments >= 1
		and expr.arguments[1].node.tag == "string"
		and expr.arguments[1].node.text == flagName
end

local repoFlagMatch = {
	["Foundation"] = isFoundationFlagAccess,
	["LuaApps"] = isDefaultFlagAccess,
	["UIBlox"] = isUIBloxFlagAccess,
}

return {
	isUIBloxFlagAccess = isUIBloxFlagAccess,
	isFoundationFlagAccess = isFoundationFlagAccess,
	isDefaultFlagAccess = isDefaultFlagAccess,
	repoFlagMatch = repoFlagMatch,
	printTable = printTable,
}
