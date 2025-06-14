local arguments = require("../lib/arguments")

local DRIVER_PATH = "CODEMOD"

local function test_expectFailureWithNoArguments()
	local success, message = pcall(arguments.parse, { DRIVER_PATH })

	assert(success == false)
	assert(typeof(message) == "string")
	-- assert(message:sub(7) == "Usage: ") -- TODO
end

local function test_expectFailureWhenOnlyFilePathProvided()
	local success, message = pcall(arguments.parse, { DRIVER_PATH, "transform.luau" })

	assert(success == false)
	assert(typeof(message) == "string")
	-- assert(message:sub(7) == "Usage: ") -- TODO
end

local function test_processCodemodAndSingleFile()
	local config = arguments.parse({ DRIVER_PATH, "transform.luau", "example.luau" })
	assert(config.migrationPath == "transform.luau")
	assert(#config.filePaths == 1)
	assert(config.filePaths[1] == "example.luau")
end

local function test_processCodemodAndMultipleFiles()
	local config = arguments.parse({ DRIVER_PATH, "transform.luau", "example.luau", "directory", "foo.luau" })
	assert(config.migrationPath == "transform.luau")
	assert(#config.filePaths == 3)
	assert(config.filePaths[1] == "example.luau")
	assert(config.filePaths[2] == "directory")
	assert(config.filePaths[3] == "foo.luau")
end

local function test_processWithCodemodOptions()
	local config = arguments.parse({ DRIVER_PATH, "transform.luau", "--name", "test", "example.luau" })
	assert(config.migrationPath == "transform.luau")
	assert(config.migrationOptions["name"] == "test")
	assert(#config.filePaths == 1)
	assert(config.filePaths[1] == "example.luau")
end

local function test_expectFailureWhenCodemodOptionValueNotPresent()
	local success, message = pcall(arguments.parse, { DRIVER_PATH, "transform.luau", "--name" })
	assert(success == false)
	assert(typeof(message) == "string")
	-- assert(message == "Missing value for 'name'") -- TODO
end

local function test_codemodOptionsButNoFilePath()
	local config = arguments.parse({ DRIVER_PATH, "transform.luau", "--name", "test" })
	assert(config.migrationPath == "transform.luau")
	assert(config.migrationOptions["name"] == "test")
	assert(#config.filePaths == 0)
end

local function test_dryRunFlag()
	local config = arguments.parse({ DRIVER_PATH, "--dry-run", "transform.luau", "example.luau" })
	assert(config.dryRun == true)
	assert(config.migrationPath == "transform.luau")
	assert(#config.filePaths == 1)
	assert(config.filePaths[1] == "example.luau")
end

local function test_unknownToolFlag()
	local success, message = pcall(arguments.parse, { DRIVER_PATH, "--unknown", "transform.luau", "example.luau" })
	assert(success == false)
	assert(typeof(message) == "string")
	-- assert(message == "Unknown flag '--unknown'") -- TODO
end

test_expectFailureWithNoArguments()
test_expectFailureWhenOnlyFilePathProvided()
test_processCodemodAndSingleFile()
test_processCodemodAndMultipleFiles()
test_processWithCodemodOptions()
test_expectFailureWhenCodemodOptionValueNotPresent()
test_codemodOptionsButNoFilePath()
test_dryRunFlag()
test_unknownToolFlag()
