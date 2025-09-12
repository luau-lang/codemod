local FileVisitor = require("./file-visitor/FileVisitor")
local getFunctionSignature = require("./functionUtils").getFunctionSignature
local getTypeSignature = require("./typeUtils").getTypeSignature

return {
	FileVisitor = FileVisitor,
	getFunctionSignature = getFunctionSignature,
	getTableSignature = require("./tableUtils").getAnonymousTableSignature,
	getTypeSignature = getTypeSignature,
}

--[[
getClassSignature(tableNode: AstState): string
much trickier; we kinda need to scrape an entire file for this, and can't just extract from the initial declaration...
hmmmm
]]
