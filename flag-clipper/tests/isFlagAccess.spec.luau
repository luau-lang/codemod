local parser = require("@std/syntax/parser")
local isFlagAccess = require("../matchers/isFlagAccess")

local function test_matchesDefineFastFlag()
	local expr = parser.parseexpr('game:DefineFastFlag("FlagName", false)')

	assert(isFlagAccess(expr, "FlagName") == true)
end

local function test_matchesGetFastFlag()
	local expr = parser.parseexpr('game:GetFastFlag("FlagName")')

	assert(isFlagAccess(expr, "FlagName") == true)
end

local function test_doesNotMatchAccessWithDifferentName()
	local expr = parser.parseexpr('game:GetFastFlag("OtherName")')

	assert(isFlagAccess(expr, "FlagName") == false)
end

local function test_matchesUIBloxFlagAccess()
	local expr = parser.parseexpr("UIBloxConfig.FlagName")

	assert(isFlagAccess(expr, "FlagName") == true)
end

local function test_matchesFoundationFlagAccess()
	local expr = parser.parseexpr('SafeFlags.createGetFFlag("FlagName")()')
	assert(isFlagAccess(expr, "FlagName") == true)
end

local function test_matchesSetFastFlagForTesting()
	local expr = parser.parseexpr('game:SetFastFlagForTesting("FlagName")')
	assert(isFlagAccess(expr, "FlagName") == true)
end

local function test_matchesScopedFFlag()
	local expr = parser.parseexpr('setScopedFFlag("FlagName")')
	assert(isFlagAccess(expr, "FlagName") == true)
end

return function()
	test_matchesDefineFastFlag()
	test_matchesGetFastFlag()
	test_doesNotMatchAccessWithDifferentName()
	test_matchesUIBloxFlagAccess()
	test_matchesFoundationFlagAccess()
	test_matchesSetFastFlagForTesting()
	test_matchesScopedFFlag()
end
