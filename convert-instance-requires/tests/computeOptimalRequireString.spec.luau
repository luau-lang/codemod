local computeOptimalRequireString = require("../computeOptimalRequireString")

function test_requireSiblingFile()
	assert(computeOptimalRequireString("src/client/file.luau", "src/client/other.luau") == "./other")
end

function test_requireDescendantFile()
	assert(computeOptimalRequireString("src/client/file.luau", "src/client/folder/other.luau") == "./folder/other")
end

function test_requireFileInDifferentFolder()
	assert(computeOptimalRequireString("src/client/file.luau", "src/server/other.luau") == "../server/other")
end

function test_requireSiblingInitLuauFile()
	assert(computeOptimalRequireString("src/client/file.luau", "src/client/init.luau") == ".")
	assert(computeOptimalRequireString("src/client/file.luau", "src/client/init.lua") == ".")
end

function test_requireDescendantInitLuauFile()
	assert(computeOptimalRequireString("src/client/file.luau", "src/client/folder/init.luau") == "./folder")
	assert(computeOptimalRequireString("src/client/file.luau", "src/client/folder/init.lua") == "./folder")
end

function test_requireInitLuauFileInDifferentFolder()
	assert(computeOptimalRequireString("src/client/file.luau", "src/server/init.luau") == "../server")
	assert(computeOptimalRequireString("src/client/file.luau", "src/server/init.lua") == "../server")
end

function test_handleFromInitLuauFiles()
	local from = "src/client/WeatherClient/init.client.lua"
	assert(computeOptimalRequireString(from, "src/shared/Remotes.lua") == "../shared/Remotes")
	assert(computeOptimalRequireString(from, "src/client/RainModule.lua") == "./RainModule")
	assert(computeOptimalRequireString(from, "src/client/SnowModule.lua") == "./SnowModule")

	from = "src/client/project/Warning/init.lua"
	assert(computeOptimalRequireString(from, "Packages/Promise.lua") == "../../../Packages/Promise")
end

function test_handleFromInitLuauFileToSibling()
	local from = "src/client/project/init.client.lua"
	assert(computeOptimalRequireString(from, "src/client/project/Warning.lua") == "@self/Warning")
	assert(computeOptimalRequireString(from, "src/client/project/Warning/init.lua") == "@self/Warning")
end

function test_handleFromInitLuauFileToDescendant()
	local from = "src/client/project/init.client.lua"
	assert(computeOptimalRequireString(from, "src/client/project/Folder/Warning.lua") == "@self/Folder/Warning")
	assert(computeOptimalRequireString(from, "src/client/project/Folder/Warning/init.lua") == "@self/Folder/Warning")
end

test_requireSiblingFile()
test_requireDescendantFile()
test_requireFileInDifferentFolder()
test_requireSiblingInitLuauFile()
test_requireDescendantInitLuauFile()
test_requireInitLuauFileInDifferentFolder()
test_handleFromInitLuauFiles()
test_handleFromInitLuauFileToSibling()
test_handleFromInitLuauFileToDescendant()
