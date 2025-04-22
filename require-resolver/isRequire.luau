local T = require("@batteries/syntax/ast_types")

local function isRequire(node: T.AstExprCall)
	return node.func.tag == "global" and node.func.name.text == "require" and #node.arguments == 1
end

return isRequire
