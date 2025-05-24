local luau = require("@lute/luau")

local function isRequire(node: luau.AstExpr)
	return node.tag == "call"
		and node.func.tag == "global"
		and node.func.name.text == "require"
		and #node.arguments == 1
end

return isRequire
