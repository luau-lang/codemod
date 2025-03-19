local function runner()
	local tests = {
		"./isFlagAccess.spec",
		"./isFlagFunction.spec",
		"./isFlagModule.spec",
		-- "./simplify.spec",
		"./simplifyBlock.spec",
	}

	for _, path in tests do
		local suite = require(path) :: any
		assert(typeof(suite) == "function")
		suite()
	end
end

runner()
