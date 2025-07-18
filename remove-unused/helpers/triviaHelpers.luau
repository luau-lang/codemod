local luau = require("@lute/luau")

--[[
    Inserts trivia at the beginning of a node's leading trivia.
    
    This function takes trivia extracted from removed statements and
    prepends it to the target node's existing leading trivia.
    Whitespace is normalized to avoid formatting issues.
    
    @param attachTo - The AST node to attach trivia to
    @param toInsert - The trivia to insert
    @return - The combined trivia
]]
local function insertLeadingTrivia(attachTo: luau.AstExpr, toInsert: { luau.AstExpr })
	local newTrivia = {}

	-- Process each trivia node to insert
	while #toInsert > 0 do
		local trivia = table.remove(toInsert, 1)
		for _, token in pairs(trivia) do
			-- Normalize whitespace but preserve comments exactly
			token.text = if token.tag == "whitespace" then token.text:gsub("[ \t]+", "") else token.text
			table.insert(newTrivia, token)
		end
	end

	-- Append the node's existing leading trivia
	for _, trivia in attachTo.leadingTrivia do
		table.insert(newTrivia, trivia)
	end

	return newTrivia
end

--[[    
    This function is responsible for finding the right node within a statement
    to attach trivia to. Different statement types store their leading trivia
    in different places, so we need to handle each case separately.
    
    The function traverses the statement structure to find the earliest
    syntax node where the trivia should be attached.
    
    @param statement - The AST statement to attach trivia to
    @param triviaToInsert - The trivia to insert
]]
local function handleLeadingTriviaInsertion(statement: luau.AstStat, triviaToInsert: { luau.AstExpr })
	-- Based on the statement type, find the appropriate node to attach trivia to
	if statement.tag == "expression" or statement.tag == "indexname" then
		-- Expression statements need to recurse to the inner expression
		handleLeadingTriviaInsertion(statement.expression, triviaToInsert)
	elseif statement.tag == "local" or statement.tag == "localfunction" then
		-- Local declarations use the localKeyword node
		if statement.localKeyword then
			statement.localKeyword.leadingTrivia = insertLeadingTrivia(statement.localKeyword, triviaToInsert)
		else
			statement.token.leadingTrivia = insertLeadingTrivia(statement.token, triviaToInsert)
		end
	elseif statement.tag == "function" then
		-- Function declarations use the functionKeyword node
		statement.functionKeyword.leadingTrivia = insertLeadingTrivia(statement.functionKeyword, triviaToInsert)
	elseif statement.tag == "assign" or statement.tag == "compoundassign" then
		-- Assignment statements need to attach to the first variable
		handleLeadingTriviaInsertion(statement.variables[1].node, triviaToInsert)
	elseif statement.tag == "conditional" then
		-- Conditional statements use the ifKeyword
		statement.ifKeyword.leadingTrivia = insertLeadingTrivia(statement.ifKeyword, triviaToInsert)
	elseif statement.tag == "for" or statement.tag == "forin" then
		-- For loops use the forKeyword
		statement.forKeyword.leadingTrivia = insertLeadingTrivia(statement.forKeyword, triviaToInsert)
	elseif statement.tag == "while" then
		-- While loops use the whileKeyword
		statement.whileKeyword.leadingTrivia = insertLeadingTrivia(statement.whileKeyword, triviaToInsert)
	elseif statement.tag == "repeat" then
		-- Repeat loops use the repeatKeyword
		statement.repeatKeyword.leadingTrivia = insertLeadingTrivia(statement.repeatKeyword, triviaToInsert)
	elseif statement.tag == "call" then
		-- Function calls need to recurse to the function expression
		handleLeadingTriviaInsertion(statement.func, triviaToInsert)
	elseif statement.tag == "global" then
		-- Global references use the name node
		statement.name.leadingTrivia = insertLeadingTrivia(statement.name, triviaToInsert)
	elseif statement.tag == "return" then
		-- Return statements use the returnKeyword
		statement.returnKeyword.leadingTrivia = insertLeadingTrivia(statement.returnKeyword, triviaToInsert)
	elseif statement.tag == "typealias" then
		if statement.export then
			statement.export.leadingTrivia = insertLeadingTrivia(statement.export, triviaToInsert)
		else
			statement.typeToken.leadingTrivia = insertLeadingTrivia(statement.typeToken, triviaToInsert)
		end
	end
end

--[[    
    This function extracts the leading trivia from a statement based on its type.
    It focuses on statement types that can be deleted by our unused variable removal.
    
    @param statement - The AST statement to extract trivia from
    @return - The leading trivia of the statement, or nil if not found
]]
local function getStatementLeadingTrivia(statement: luau.AstStat)
	-- Extract leading trivia based on statement type
	return if statement.tag == "assign"
		then statement.variables[1].node.token.leadingTrivia
		elseif statement.tag == "local" or statement.tag == "localfunction" then statement.localKeyword.leadingTrivia
		elseif statement.tag == "function" then statement.functionKeyword.leadingTrivia
		else nil
end

--[[    
    This function examines trailing trivia and keeps it only if it contains
    actual comments. If the trivia only contains whitespace or newlines,
    it's considered non-essential and is filtered out.
    
    @param trivia - The trivia to filter
    @return - The filtered trivia, or an empty table if no comments found
]]
local function filterTrailingTrivia(trivia)
	for _, t in pairs(trivia) do
		if t.tag == "comment" then
			return trivia -- Keep all trivia if we found a comment
		end
	end
	return {}
end

--[[    
    This function recursively extracts trailing trivia from a statement based on its type.
    Different statement types store their trailing trivia in different places,
    so we need specialized handling for each case.
    
    @param statement - The AST statement to extract trailing trivia from
    @return - The trailing trivia of the statement
]]
local function getStatementTrailingTrivia(statement: luau.AstStat)
	local trailingTrivia = {}

	-- Handle statements with values (like assignments or declarations with values)
	if statement.values and #statement.values > 0 then
		-- Get trivia from the last value in the statement
		if statement.values[#statement.values].node.trailingTrivia then
			-- Direct access for primitive values
			trailingTrivia = statement.values[#statement.values].node.trailingTrivia
		elseif statement.values[#statement.values].node.tag == "local" then
			-- Special handling for local variable references
			trailingTrivia = statement.values[#statement.values].node.token.trailingTrivia
		else
			-- Recursive handling for complex expressions
			trailingTrivia = getStatementTrailingTrivia(statement.values[#statement.values].node)
		end
	else
		-- Handle different statement types without values
		if statement.tag == "table" then
			-- Table literals - trivia is on the closing brace
			trailingTrivia = statement.closeBrace.trailingTrivia
		elseif statement.tag == "index" then
			-- Index expressions - trivia is on the closing brackets
			trailingTrivia = statement.closeBrackets.trailingTrivia
		elseif statement.tag == "indexname" then
			-- Named index expressions - trivia is on the index
			trailingTrivia = statement.index.trailingTrivia
		elseif statement.tag == "call" then
			-- Function calls - trivia is on the closing parenthesis
			trailingTrivia = statement.closeParens.trailingTrivia
		elseif statement.tag == "local" then
			-- Local declarations - trivia is on the last variable's name
			trailingTrivia = statement.variables[#statement.variables].node.name.trailingTrivia
		elseif statement.tag == "localfunction" or statement.tag == "function" then
			-- Function declarations - trivia is on the end keyword
			trailingTrivia = statement.body.endKeyword.trailingTrivia
		end
	end

	return filterTrailingTrivia(trailingTrivia)
end

--[[
    This function collects all trivia (comments and whitespace) from a statement
    that is going to be removed, so that the trivia can be preserved and
    reattached to other statements.
    
    @param statement - The AST statement to extract trivia from
    @param triviaDeposit - The table where extracted trivia will be stored
]]
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
