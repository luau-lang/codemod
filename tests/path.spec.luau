local path = require("../lib/path")

local function test_joinPathRelative()
	assert(path.joinPath("base", "file.lua") == "base/file.lua")
	assert(path.joinPath("base/", "file.lua") == "base/file.lua")
	assert(path.joinPath("base/", "./file.lua") == "base/file.lua")
	assert(path.joinPath("base/", ".") == "base/")
end

test_joinPathRelative()
