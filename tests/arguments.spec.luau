local arguments = require("../lib/arguments")

local function test_expectFailureWithNoArguments()
	local success, message = pcall(arguments.parse, {})

	assert(success == false)
	assert(typeof(message) == "string")
	-- assert(message:sub(7) == "Usage: ") -- TODO
end

local function test_expectFailureWhenOnlyFilePathProvided()
	local success, message = pcall(arguments.parse, { "transform.luau" })

	assert(success == false)
	assert(typeof(message) == "string")
	-- assert(message:sub(7) == "Usage: ") -- TODO
end

local function test_processCodemodAndSingleFile()
	local config = arguments.parse({ "transform.luau", "example.luau" })
	assert(config.codemodPath == "transform.luau")
	assert(#config.filePaths == 1)
	assert(config.filePaths[1] == "example.luau")
end

local function test_processCodemodAndMultipleFiles()
	local config = arguments.parse({ "transform.luau", "example.luau", "directory", "foo.luau" })
	assert(config.codemodPath == "transform.luau")
	assert(#config.filePaths == 3)
	assert(config.filePaths[1] == "example.luau")
	assert(config.filePaths[2] == "directory")
	assert(config.filePaths[3] == "foo.luau")
end

local function test_processWithCodemodOptions()
	local config = arguments.parse({ "transform.luau", "--name", "test", "example.luau" })
	assert(config.codemodPath == "transform.luau")
	assert(config.codemodOptions["name"] == "test")
	assert(#config.filePaths == 1)
	assert(config.filePaths[1] == "example.luau")
end

local function test_expectFailureWhenCodemodOptionValueNotPresent()
	local success, message = pcall(arguments.parse, { "transform.luau", "--name" })
	assert(success == false)
	assert(typeof(message) == "string")
	-- assert(message == "Missing value for 'name'") -- TODO
end

local function test_codemodOptionsButNoFilePath()
	local config = arguments.parse({ "transform.luau", "--name", "test" })
	assert(config.codemodPath == "transform.luau")
	assert(config.codemodOptions["name"] == "test")
	assert(#config.filePaths == 0)
end

test_expectFailureWithNoArguments()
test_expectFailureWhenOnlyFilePathProvided()
test_processCodemodAndSingleFile()
test_processCodemodAndMultipleFiles()
test_processWithCodemodOptions()
test_expectFailureWhenCodemodOptionValueNotPresent()
test_codemodOptionsButNoFilePath()
