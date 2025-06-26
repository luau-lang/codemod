local luau = require("@lute/luau")

local visitor = require("@batteries/syntax/visitor")

local function getFirstToken(expression: luau.AstExpr): luau.Token
	local firstToken: luau.Token? = nil
	local tokenFinder = visitor.createVisitor()
	tokenFinder.visitToken = function(token: luau.Token)
		if not firstToken then
			firstToken = token
		end
		return false
	end
	visitor.visitExpression(expression, tokenFinder)
	assert(firstToken ~= nil)
	return firstToken
end

local function getLastToken(expression: luau.AstExpr): luau.Token
	local lastToken: luau.Token? = nil
	local tokenFinder = visitor.createVisitor()
	tokenFinder.visitToken = function(token: luau.Token)
		lastToken = token
		return true
	end
	visitor.visitExpression(expression, tokenFinder)
	assert(lastToken ~= nil)
	return lastToken
end

local function getLeadingTrivia(expression: luau.AstExpr): { luau.Trivia }
	local token = getFirstToken(expression)
	return token.leadingTrivia
end

local function getTrailingTrivia(expression: luau.AstExpr): { luau.Trivia }
	local token = getLastToken(expression)
	return token.trailingTrivia
end

return {
	getLeadingTrivia = getLeadingTrivia,
	getTrailingTrivia = getTrailingTrivia,
}
