local syntax = require("@std/syntax")
local types = require("@std/syntax/types")
local visitor = require("@std/syntax/visitor")

--[[
	Pending edits to a single token. The CST is immutable, so instead of mutating trivia in place we
	accumulate edits per token and render each edited token into a replacement once a block is processed.
]]
export type TokenEdit = {
	prefix: string?,
	leadingTrivia: { syntax.Trivia }?,
	text: string?,
	trailingTrivia: { syntax.Trivia }?,
	suffix: string?,
}

export type TokenEdits = { [syntax.CstToken]: TokenEdit }

local function printTrivia(trivia: { syntax.Trivia }): string
	local parts = {}
	for _, t in trivia do
		table.insert(parts, t.text)
	end
	return table.concat(parts)
end

--[[
    If the trivia only contains whitespace or newlines,
    it's considered non-essential and is filtered out.
]]
local function filterTrailingTrivia(trivia: { syntax.Trivia }): { syntax.Trivia }
	for _, t in trivia do
		if t.tag == "comment" or t.tag == "blockcomment" then
			return trivia
		end
	end
	return {}
end

local function getFirstAndLastToken(node: syntax.CstNode): (syntax.CstToken, syntax.CstToken)
	local firstToken: syntax.CstToken? = nil
	local lastToken: syntax.CstToken? = nil
	local tokenFinder = visitor.create()
	tokenFinder.visitToken = function(token: syntax.CstToken)
		if not firstToken then
			firstToken = token
		end
		lastToken = token
		return false
	end
	visitor.visit(node, tokenFinder)
	assert(firstToken ~= nil and lastToken ~= nil)
	return firstToken, lastToken
end

local function getEdit(edits: TokenEdits, token: syntax.CstToken): TokenEdit
	local edit = edits[token]
	if edit then
		return edit
	end
	local newEdit: TokenEdit = {}
	edits[token] = newEdit
	return newEdit
end

-- Normalize whitespace but preserve comments exactly
local function printNormalizedTrivia(toAttach: { { syntax.Trivia } }): string
	local parts = {}
	for _, trivia in toAttach do
		for _, t in trivia do
			table.insert(parts, if t.tag == "whitespace" then (t.text:gsub("[ \t]+", "")) else t.text)
		end
	end
	return table.concat(parts)
end

--[[
    Inserts trivia extracted from removed statements before the leading trivia of the given token.
    Whitespace is normalized to avoid formatting issues.
]]
local function insertLeadingTrivia(edits: TokenEdits, token: syntax.CstToken, toInsert: { { syntax.Trivia } })
	local edit = getEdit(edits, token)
	edit.prefix = printNormalizedTrivia(toInsert) .. (edit.prefix or "")
	table.clear(toInsert)
end

--[[
    Appends trivia extracted from removed statements after the trailing trivia of the given token.
]]
local function appendTrailingTrivia(edits: TokenEdits, token: syntax.CstToken, toAppend: { { syntax.Trivia } })
	local edit = getEdit(edits, token)
	edit.suffix = (edit.suffix or "") .. printNormalizedTrivia(toAppend)
	table.clear(toAppend)
end

--[[
    @param statement - The statement being removed
    @param triviaDeposit - The table where extracted trivia will be stored
]]
local function storeStatementTrivia(statement: syntax.CstStat, triviaDeposit: { { syntax.Trivia } })
	local firstToken, lastToken = getFirstAndLastToken(statement)
	table.insert(triviaDeposit, firstToken.leadingTrivia)
	table.insert(triviaDeposit, filterTrailingTrivia(lastToken.trailingTrivia))
end

local function applyTokenEdits(edits: TokenEdits, replacements: types.Replacements)
	for token, edit in edits do
		replacements[token] = {
			content = (edit.prefix or "")
				.. printTrivia(edit.leadingTrivia or token.leadingTrivia)
				.. (edit.text or token.text)
				.. printTrivia(edit.trailingTrivia or token.trailingTrivia)
				.. (edit.suffix or ""),
			preserveTrivia = false,
		}
	end
end

return {
	getEdit = getEdit,
	getFirstAndLastToken = getFirstAndLastToken,
	storeStatementTrivia = storeStatementTrivia,
	insertLeadingTrivia = insertLeadingTrivia,
	appendTrailingTrivia = appendTrailingTrivia,
	applyTokenEdits = applyTokenEdits,
}
