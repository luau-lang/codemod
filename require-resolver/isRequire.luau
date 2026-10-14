local syntax = require("@std/syntax")

local function isRequire(node: syntax.CstExpr)
	return node.tag == "call"
		and node.func.tag == "global"
		and node.func.name.text == "require"
		and #node.arguments == 1
end

return isRequire
