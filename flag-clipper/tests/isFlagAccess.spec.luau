local parser = require("@std/syntax/parser")
local isFlagAccess = require("../matchers/isFlagAccess")

local function test_matchesDefineFastFlag()
	local expr = parser.parseExpr('game:DefineFastFlag("FlagName", false)')

	assert(isFlagAccess(expr, "FlagName") == true)
end

local function test_matchesGetFastFlag()
	local expr = parser.parseExpr('game:GetFastFlag("FlagName")')

	assert(isFlagAccess(expr, "FlagName") == true)
end

local function test_doesNotMatchAccessWithDifferentName()
	local expr = parser.parseExpr('game:GetFastFlag("OtherName")')

	assert(isFlagAccess(expr, "FlagName") == false)
end

local function test_matchesUIBloxFlagAccess()
	local expr = parser.parseExpr("UIBloxConfig.FlagName")

	assert(isFlagAccess(expr, "FlagName") == true)
end

local function test_matchesFoundationFlagAccess()
	local expr = parser.parseExpr('SafeFlags.createGetFFlag("FlagName")()')
	assert(isFlagAccess(expr, "FlagName") == true)
end

local function test_matchesFoundationBumpedFlagAccess()
	local expr = parser.parseExpr("Flags.FlagName")
	assert(isFlagAccess(expr, "FlagName2") == true)
end

local function test_matchesFoundationFlagsTableAccess()
	assert(isFlagAccess(parser.parseExpr("Flags.LaunchExperienceAction"), "LaunchExperienceAction") == true)
	assert(isFlagAccess(parser.parseExpr("FoundationFlags.FlagName"), "FlagName") == true)
	assert(isFlagAccess(parser.parseExpr("Foundation.Utility.Flags.FlagName"), "FlagName") == true)
end

local function test_doesNotMatchRequirePathNamedAsFlag()
	local expr = parser.parseExpr("Packages.Actions.LaunchExperienceAction")
	assert(isFlagAccess(expr, "LaunchExperienceAction") == false)
end

local function test_doesNotMatchNonFlagsIndex()
	assert(isFlagAccess(parser.parseExpr("script.Parent.FlagName"), "FlagName") == false)
	assert(isFlagAccess(parser.parseExpr("game.FlagName"), "FlagName") == false)
	assert(isFlagAccess(parser.parseExpr("props.FlagName"), "FlagName") == false)
end

local function test_matchesSetFastFlagForTesting()
	local expr = parser.parseExpr('game:SetFastFlagForTesting("FlagName")')
	assert(isFlagAccess(expr, "FlagName") == true)
end

local function test_matchesScopedFFlag()
	local expr = parser.parseExpr('setScopedFFlag("FlagName")')
	assert(isFlagAccess(expr, "FlagName") == true)
end

return function()
	test_matchesDefineFastFlag()
	test_matchesGetFastFlag()
	test_doesNotMatchAccessWithDifferentName()
	test_matchesUIBloxFlagAccess()
	test_matchesFoundationFlagAccess()
	test_matchesFoundationBumpedFlagAccess()
	test_matchesFoundationFlagsTableAccess()
	test_doesNotMatchRequirePathNamedAsFlag()
	test_doesNotMatchNonFlagsIndex()
	test_matchesSetFastFlagForTesting()
	test_matchesScopedFFlag()
end
