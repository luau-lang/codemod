local luau = require("@lute/luau")

local visitor = require("@std/syntax/visitor")

local function getFirstToken(expression: luau.AstExpr): luau.Token
	local firstToken: luau.Token? = nil
	local tokenFinder = visitor.create()
	tokenFinder.visitToken = function(token: luau.Token)
		if not firstToken then
			firstToken = token
		end
		return false
	end
	visitor.visitexpression(expression, tokenFinder)
	assert(firstToken ~= nil)
	return firstToken
end

local function getLastToken(expression: luau.AstExpr): luau.Token
	local lastToken: luau.Token? = nil
	local tokenFinder = visitor.create()
	tokenFinder.visitToken = function(token: luau.Token)
		lastToken = token
		return true
	end
	visitor.visitexpression(expression, tokenFinder)
	assert(lastToken ~= nil)
	return lastToken
end

local function getLeadingTrivia(expression: luau.AstExpr): { luau.Trivia }
	local token = getFirstToken(expression)
	return token.leadingtrivia
end

local function getTrailingTrivia(expression: luau.AstExpr): { luau.Trivia }
	local token = getLastToken(expression)
	return token.trailingtrivia
end

local function getItemFirstToken(item: luau.AstTableExprItem): luau.Token
	if item.kind == "record" then
		return item.key
	elseif item.kind == "general" then
		return item.indexeropen
	end
	return getFirstToken(item.value)
end

--- Leading trivia begins with a blank line when a newline comes before any comment, since the newline
--- ending the previous line belongs to the previous token's trailing trivia.
local function beginsWithBlankLine(trivia: { luau.Trivia }): boolean
	for _, piece in trivia do
		if piece.tag ~= "whitespace" then
			return false
		elseif string.find(piece.text, "\n") then
			return true
		end
	end
	return false
end

local function containsComment(trivia: { luau.Trivia }): boolean
	for _, piece in trivia do
		if piece.tag ~= "whitespace" then
			return true
		end
	end
	return false
end

--- Drops the blank lines that begin `trivia`, keeping the indentation and comments after them.
local function trimBlankLines(trivia: { luau.Trivia }): { luau.Trivia }
	local firstKept = 1
	while trivia[firstKept] and trivia[firstKept].tag == "whitespace" and string.find(trivia[firstKept].text, "\n") do
		firstKept += 1
	end
	return table.move(trivia, firstKept, #trivia, 1, {})
end

--- Joins `first` onto `second`, dropping the indentation that ends `first` so `second` supplies its own.
local function joinLeadingTrivia(first: { luau.Trivia }, second: { luau.Trivia }): { luau.Trivia }
	local lastKept = #first
	while lastKept > 0 and first[lastKept].tag == "whitespace" and not string.find(first[lastKept].text, "\n") do
		lastKept -= 1
	end

	local joined = table.move(first, 1, lastKept, 1, {})
	return table.move(second, 1, #second, #joined + 1, joined)
end

return {
	getLeadingTrivia = getLeadingTrivia,
	getTrailingTrivia = getTrailingTrivia,
	getItemFirstToken = getItemFirstToken,
	beginsWithBlankLine = beginsWithBlankLine,
	containsComment = containsComment,
	joinLeadingTrivia = joinLeadingTrivia,
	trimBlankLines = trimBlankLines,
}
