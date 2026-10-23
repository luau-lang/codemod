local cst = require("@lute/syntax/mutablecst")

local visitor = require("@std/syntax/visitor")

local function getFirstToken(expression: cst.CstExpr): cst.CstToken
	local firstToken: cst.CstToken? = nil
	local tokenFinder = visitor.create()
	tokenFinder.visitToken = function(token: cst.CstToken)
		if not firstToken then
			firstToken = token
		end
		return false
	end
	visitor.visitExpression(expression, tokenFinder)
	assert(firstToken ~= nil)
	return firstToken
end

local function getLastToken(expression: cst.CstExpr): cst.CstToken
	local lastToken: cst.CstToken? = nil
	local tokenFinder = visitor.create()
	tokenFinder.visitToken = function(token: cst.CstToken)
		lastToken = token
		return true
	end
	visitor.visitExpression(expression, tokenFinder)
	assert(lastToken ~= nil)
	return lastToken
end

local function getLeadingTrivia(expression: cst.CstExpr): { cst.Trivia }
	local token = getFirstToken(expression)
	return token.leadingTrivia
end

local function getTrailingTrivia(expression: cst.CstExpr): { cst.Trivia }
	local token = getLastToken(expression)
	return token.trailingTrivia
end

return {
	getLeadingTrivia = getLeadingTrivia,
	getTrailingTrivia = getTrailingTrivia,
}
