local luau = require("@lute/luau")
local visitor = require("@batteries/syntax/visitor")

--[[
    If the trivia only contains whitespace or newlines,
    it's considered non-essential and is filtered out.
]]
local function filterTrailingTrivia(trivia)
	for _, t in pairs(trivia) do
		if t.tag == "comment" or t.tag == "blockcomment" then
			return trivia
		end
	end
	return {}
end

local function getStatementFirstAndLastToken(statement: luau.AstStat)
	local firstToken: luau.Token? = nil
	local lastToken: luau.Token? = nil
	local tokenFinder = visitor.createVisitor()
	tokenFinder.visitToken = function(token: luau.Token)
		if not firstToken then
			firstToken = token
		end
		lastToken = token
		return false
	end
	visitor.visitStatement(statement, tokenFinder)
	assert(firstToken ~= nil and lastToken ~= nil)
	return firstToken, lastToken
end

local function getStatementTrivia(statement: luau.AstStat)
	local firstToken, lastToken = getStatementFirstAndLastToken(statement)
	return firstToken.leadingTrivia, lastToken.trailingTrivia
end

local function attachTriviaInOrder(attachTo, toAttach: { luau.Trivia })
	while #toAttach > 0 do
		local trivia = table.remove(toAttach, 1)
		for _, token in pairs(trivia) do
			-- Normalize whitespace but preserve comments exactly
			token.text = if token.tag == "whitespace" then token.text:gsub("[ \t]+", "") else token.text
			table.insert(attachTo, token)
		end
	end
end

--[[
    Inserts trivia at the beginning of a node's leading trivia.
    
    This function takes trivia extracted from removed statements and
    prepends it to the target node's existing leading trivia.
    Whitespace is normalized to avoid formatting issues.
    
    @param attachTo - The AST node to attach trivia to
    @param toInsert - The trivia to insert
    @return - The combined trivia
]]
local function insertLeadingTrivia(attachTo: luau.Token, toInsert: { luau.Trivia })
	local newTrivia = {}

	-- Process each trivia node to insert
	attachTriviaInOrder(newTrivia, toInsert)

	-- Append the node's existing leading trivia
	for _, trivia in attachTo do
		table.insert(newTrivia, trivia)
	end

	return newTrivia
end

--[[
    @param statement - The AST statement to attach trivia to
    @param triviaToInsert - The trivia to insert
]]
local function handleLeadingTriviaInsertion(statement: luau.AstStat, triviaToInsert: { luau.Trivia })
	local leadingToken, _ = getStatementFirstAndLastToken(statement)
	leadingToken.leadingTrivia = insertLeadingTrivia(leadingToken.leadingTrivia, triviaToInsert)
end

--[[    
    @param statement - The AST statement to extract trailing trivia from
	@param toInsert -  trivia to append to the found trailing triva
    @return - The trailing trivia of the statement
]]
local function appendTrailingTrivia(statement: luau.AstStat, toAppend: { luau.Trivia })
	local _, trailingToken = getStatementFirstAndLastToken(statement)

	attachTriviaInOrder(trailingToken.trailingTrivia, toAppend)
end

--[[
    @param statement - The AST statement to extract trivia from
    @param triviaDeposit - The table where extracted trivia will be stored
]]
local function storeStatementTrivia(statement: luau.AstStat, triviaDeposit: { luau.Trivia })
	local statementLeadingTrivia, statementTrailingTrivia = getStatementTrivia(statement)

	table.insert(triviaDeposit, statementLeadingTrivia)
	table.insert(triviaDeposit, filterTrailingTrivia(statementTrailingTrivia))
end

--[[
	This function handles trivia reassignment of a filter variable statement (declaration, initialization, or assignment)

	It ensures the final variables and final value do not have a separator (comma, etc), are properly spaced, and preserve the original trailing trivia of the full statement.
	
	@param varsToKeep - The filtered AST variable nodes that are not being removed
	@param valsToKeep - The filtered AST value nodes that are not being removed
	@param statementTrailingTrivia - the trailing trivia of the original statement
]]
local function handleVariableStatementTrivia(
	varsToKeep: luau.Punctuated<luau.AstLocal>,
	valsToKeep: luau.Punctuated<luau.AstExpr>,
	statementTrailingTrivia: luau.Trivia
)
	-- Note: this function is only useful if we remove the original last variable in the statement, otherwise it's trivia will already be correct
	local hasValues = #valsToKeep > 0
	if varsToKeep[#varsToKeep].separator then
		if hasValues then
			varsToKeep[#varsToKeep].separator.text = ""
		else
			varsToKeep[#varsToKeep].separator = nil
			varsToKeep[#varsToKeep].node.name.trailingTrivia = statementTrailingTrivia
		end
	end
	if hasValues then
		valsToKeep[#valsToKeep].separator = nil
		valsToKeep[#valsToKeep].node.trailingTrivia = statementTrailingTrivia
	end
end

local function handleLeftoverTrivia(triviaToAppend: { luau.Trivia }, lastKeptStatement: luau.AstStat)
	if #triviaToAppend == 0 or not lastKeptStatement then
		return
	end

	-- append trivia in triviaToAppend to lastKeptStatement's trailingTrivia
	appendTrailingTrivia(lastKeptStatement, triviaToAppend)
end

return {
	storeStatementTrivia = storeStatementTrivia,
	handleLeadingTriviaInsertion = handleLeadingTriviaInsertion,
	handleVariableStatementTrivia = handleVariableStatementTrivia,
	handleLeftoverTrivia = handleLeftoverTrivia,
}
