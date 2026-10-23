local cst = require("@lute/syntax/mutablecst")

local function createConstantBoolean(
	value: boolean,
	leadingTrivia: { cst.Trivia },
	trailingTrivia: { cst.Trivia },
	location: cst.Span
): cst.CstExprConstantBool
	return {
		location = location,
		kind = "expr",
		tag = "boolean",
		value = value,
		token = {
			leadingTrivia = leadingTrivia,
			location = location,
			text = tostring(value) :: "true" | "false",
			trailingTrivia = trailingTrivia,
			kind = "token",
		},
	}
end

return createConstantBoolean
