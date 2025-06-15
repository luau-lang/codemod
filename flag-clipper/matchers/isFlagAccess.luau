local luau = require("@lute/luau")
local flagAccessUtils = require("./flagAccessUtils")
local isDefaultFlagAccess = flagAccessUtils.isDefaultFlagAccess
local repoFlagMatch = flagAccessUtils.repoFlagMatch

local function isFlagAccess(expr: luau.AstExpr, flagName: string, repo: string?): boolean
	if repo then
		return repoFlagMatch[repo](expr, flagName)
	else
		return isDefaultFlagAccess(expr, flagName)
	end
end

return isFlagAccess
