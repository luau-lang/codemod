local T = require("@batteries/syntax/ast_types")

local isFlagAccess = require("./isFlagAccess")

type FlagReferenceContext = {
	read flagName: string,
	read flagLocalsSet: { [T.AstLocal]: true },
	read globalFunctionsSet: { [string]: true },
}

--- Returns whether the provided expression is a reference to the flag being removed
--- Either a direct reference, or an indirect reference via a local
local function isFlagReference(expression: T.AstExpr, ctx: FlagReferenceContext)
	if isFlagAccess(expression, ctx.flagName) then
		return true
	elseif expression.tag == "local" then
		local isLocalReferencingFlag = ctx.flagLocalsSet[expression["local"]]
		if isLocalReferencingFlag then
			return true
		end
	elseif expression.tag == "call" then
		local callExpr = expression.func
		if callExpr.tag == "local" then
			local isLocalReferencingFlag = ctx.flagLocalsSet[callExpr["local"]]
			if isLocalReferencingFlag then
				return true
			end
		elseif callExpr.tag == "global" then
			local isGlobalReferencingFlag = ctx.globalFunctionsSet[callExpr.name.text]
			if isGlobalReferencingFlag then
				return true
			end
		end
	end

	return false
end

return isFlagReference
