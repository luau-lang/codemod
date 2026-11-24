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

local function test_doesNotMatchUnrelatedIndexWithSameName()
	for _, source in { "policy.FlagName", "Flags.FlagName", "a.b.FlagName" } do
		local expr = parser.parseExpr(source)
		assert(isFlagAccess(expr, "FlagName") == false)
		assert(isFlagAccess(expr, "FlagName2") == false)
	end
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
	test_doesNotMatchUnrelatedIndexWithSameName()
	test_matchesSetFastFlagForTesting()
	test_matchesScopedFFlag()
end
