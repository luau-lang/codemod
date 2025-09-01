local visitor = require("@std/syntax/visitor")
local commonHelpers = require("./commonHelpers")
local getNodeText, getTrivia = commonHelpers.getNodeText, commonHelpers.getTrivia
--[[
getTypeSignature(typeNode: AstTypeAlias): string

need to handle:
    - if table: extract props and their types...
    - if intersection or union: extract member types

for documentation purpose, we might want to add links on custom types (non-native lua) used in a type signature
fortunately, type signature is just whole type so we can print it all :)
]]
function getTypeSignature(node: luau.AstTypeAlias): string
	local docsComments = if node.export then getTrivia(node.export) else getTrivia(node.typeToken)
	return getNodeText(node, visitor.visitStatement)
end

return {
	getTypeSignature = getTypeSignature,
}
