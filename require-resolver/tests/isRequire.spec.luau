local parser = require("@std/syntax/parser")
local isRequire = require("../isRequire")

local function test_matchesStringRequire()
	local expr = parser.parseexpr('require("./path/to/file")')

	assert(expr.tag == "call")
	assert(isRequire(expr) == true)
end

local function test_matchesRobloxGlobalRequire()
	local expr = parser.parseexpr("require(game.ReplicatedStorage.Module)")

	assert(expr.tag == "call")
	assert(isRequire(expr) == true)
end

local function test_matchesRobloxLocalRequire()
	local expr = parser.parseexpr("require(value.Parent)")

	assert(expr.tag == "call")
	assert(isRequire(expr) == true)
end

local function test_doesNotMatchOtherCall()
	local expr = parser.parseexpr('call("hello!")')

	assert(expr.tag == "call")
	assert(isRequire(expr) == false)
end

return function()
	test_matchesStringRequire()
	test_matchesRobloxGlobalRequire()
	test_matchesRobloxLocalRequire()
	test_doesNotMatchOtherCall()
end
