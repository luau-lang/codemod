local computeOptimalRequireString = require("../computeOptimalRequireString")

function test_SMOKETEST()
	-- TODO: separate
	local from = "src/client/WeatherClient/init.client.lua"

	assert(computeOptimalRequireString(from, "src/shared/Remotes.lua") == "../shared/Remotes")
	assert(computeOptimalRequireString(from, "src/client/RainModule.lua") == "./RainModule")
	assert(computeOptimalRequireString(from, "src/client/SnowModule.lua") == "./SnowModule")

	from = "src/client/AdminClient/Warning/init.lua"
	assert(computeOptimalRequireString(from, "Packages/Promise.lua") == "../../../Packages/Promise")

	from = "src/client/AdminClient/init.client.lua"
	assert(computeOptimalRequireString(from, "src/client/AdminClient/Warning.lua") == "@self/Warning")
	assert(computeOptimalRequireString(from, "src/client/AdminClient/Warning/init.lua") == "@self/Warning")
end

test_SMOKETEST()
