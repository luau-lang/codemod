local function runner()
	local tests = {
		"./deleteVariables.spec",
		"./findVariables.spec",
	}

	for _, path in tests do
		local suite = require(path) :: any
		assert(typeof(suite) == "function")
		suite()
	end
end

runner()