local luau = require("@lute/luau")

local function insertLeadingTrivia(attachTo: luau.AstExpr, toInsert: { luau.AstExpr })
	local newTrivia = {}
	while #toInsert > 0 do
		local trivia = table.remove(toInsert, 1)
		for _, token in pairs(trivia) do
			token.text = if token.tag == "whitespace" then token.text:gsub("[ \t]+", "") else token.text -- Strip spaces and tabs from trivia.text unless it is a comment
			table.insert(newTrivia, token)
		end
	end
	for _, trivia in attachTo.leadingTrivia do
		table.insert(newTrivia, trivia)
	end
	return newTrivia
end

local function handleLeadingTriviaInsertion(statement: luau.AstStat, triviaToInsert: { luau.AstExpr })
	-- i want to insert
	-- need to handle bunch of diff types of tags to insert trivia at appropriate point;
	-- essentially want to insert triviaToInsert in the leading trivia of syntactically earliest node in statement

	if statement.tag == "expression" or statement.tag == "indexname" then
		-- recur till we find a node with leading trivia
		handleLeadingTriviaInsertion(statement.expression, triviaToInsert)
	elseif statement.tag == "local" or statement.tag == "localfunction" then
		if statement.localKeyword then
			statement.localKeyword.leadingTrivia = insertLeadingTrivia(statement.localKeyword, triviaToInsert)
		else
			statement.token.leadingTrivia = insertLeadingTrivia(statement.token, triviaToInsert)
		end
	elseif statement.tag == "function" then
		statement.functionKeyword.leadingTrivia = insertLeadingTrivia(statement.functionKeyword, triviaToInsert)
	elseif statement.tag == "assign" or statement.tag == "compoundassign" then
		-- recur till we find a node with leading trivia
		handleLeadingTriviaInsertion(statement.variables[1].node, triviaToInsert)
	elseif statement.tag == "conditional" then
		statement.ifKeyword.leadingTrivia = insertLeadingTrivia(statement.ifKeyword, triviaToInsert)
	elseif statement.tag == "for" or statement.tag == "forin" then
		statement.forKeyword.leadingTrivia = insertLeadingTrivia(statement.forKeyword, triviaToInsert)
	elseif statement.tag == "while" then
		statement.whileKeyword.leadingTrivia = insertLeadingTrivia(statement.whileKeyword, triviaToInsert)
	elseif statement.tag == "repeat" then
		statement.repeatKeyword.leadingTrivia = insertLeadingTrivia(statement.repeatKeyword, triviaToInsert)
	elseif statement.tag == "call" then
		-- recur till we find a node with leading trivia
		handleLeadingTriviaInsertion(statement.func, triviaToInsert)
	elseif statement.tag == "global" then
		statement.name.leadingTrivia = insertLeadingTrivia(statement.name, triviaToInsert)
	elseif statement.tag == "return" then
		statement.returnKeyword.leadingTrivia = insertLeadingTrivia(statement.returnKeyword, triviaToInsert)
	elseif statement.tag == "typealias" then
		statement.typeToken.leadingTrivia = insertLeadingTrivia(statement.typeToken, triviaToInsert)
	end
end

local function getStatementLeadingTrivia(statement: luau.AstStat)
	-- only type of statements we worry abt are those we can delete
	return if statement.tag == "assign"
		then statement.variables[1].node.token.leadingTrivia
		elseif statement.tag == "local" or statement.tag == "localfunction" then statement.localKeyword.leadingTrivia
		elseif statement.tag == "function" then statement.functionKeyword.leadingTrivia
		else nil
end

local function filterTrailingTrivia(trivia) -- naive but ignore trailing trivia that is just newlines
	for _, t in pairs(trivia) do
		if t.tag == "comment" then
			return trivia
		end
	end
	return {}
end

-- we shud be able to handle this recursively...
local function getStatementTrailingTrivia(statement: luau.AstStat)
	local trailingTrivia = {}
	-- if statmeent has values, just recur on down the node
	if statement.values then
		if statement.values[#statement.values].node.trailingTrivia then --covers primitive values
			trailingTrivia = statement.values[#statement.values].node.trailingTrivia
		elseif statement.values[#statement.values].node.tag == "local" then
			trailingTrivia = statement.values[#statement.values].node.token.trailingTrivia
		else
			trailingTrivia = getStatementTrailingTrivia(statement.values[#statement.values].node)
		end
	else
		if statement.tag == "table" then
			trailingTrivia = statement.closeBrace.trailingTrivia
		elseif statement.tag == "index" then
			trailingTrivia = statement.closeBrackets.trailingTrivia
		elseif statement.tag == "indexname" then
			trailingTrivia = statement.index.trailingTrivia
		elseif statement.tag == "call" then
			trailingTrivia = statement.closeParens.trailingTrivia
		elseif statement.tag == "local" then
			trailingTrivia = statement.variables[#statement.variables].node.name.trailingTrivia
		elseif statement.tag == "localfunction" or statement.tag == "function" then
			trailingTrivia = statement.body.endKeyword.trailingTrivia
		end
	end

	return filterTrailingTrivia(trailingTrivia)
end

local function extractStatementTrivia(statement: luau.AstStat, triviaDeposit)
	local statementLeadingTrivia, statementTrailingTrivia =
		getStatementLeadingTrivia(statement), getStatementTrailingTrivia(statement)
	table.insert(triviaDeposit, statementLeadingTrivia)
	table.insert(triviaDeposit, statementTrailingTrivia)
end

return {
	extractStatementTrivia = extractStatementTrivia,
	handleLeadingTriviaInsertion = handleLeadingTriviaInsertion,
}
