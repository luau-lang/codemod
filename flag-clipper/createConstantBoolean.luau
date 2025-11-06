local luau = require("@lute/luau")

local function createConstantBoolean(
	value: boolean,
	leadingTrivia: { luau.Trivia },
	trailingTrivia: { luau.Trivia }
): luau.AstExprConstantBool
	return {
		tag = "boolean",
		value = value,
		text = tostring(value) :: "true" | "false",
		leadingtrivia = leadingTrivia,
		trailingtrivia = trailingTrivia,
		position = { line = 0, column = 0 },
	}
end

return createConstantBoolean
