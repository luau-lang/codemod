local luau = require("@lute/luau")
local findVariablesUtils = require("./findVariablesUtils")
local visitor = require("@batteries/syntax/visitor")

type deletionStore = findVariablesUtils.deletionStore

local function filterVariablesAndValues(
	varStatement: luau.AstStatLocal,
	deletions: deletionStore,
	isAssign: boolean,
	hasValues: boolean?
)
	local varsToKeep, valsToKeep = {}, {}
	local statementTrailingTrivia = if hasValues
		then varStatement.values[#varStatement.values].node.trailingTrivia
		else varStatement.variables[#varStatement.variables].node.name.trailingTrivia
	for i = 1, #varStatement.variables do
		local deletionsKey = if isAssign
			then varStatement.variables[i].node["local"]
			else varStatement.variables[i].node
		if not deletions[deletionsKey] then -- keep the variable and the value it is assigned
			table.insert(varsToKeep, varStatement.variables[i])
			if hasValues then
				table.insert(valsToKeep, varStatement.values[i])
			end
		end
	end

	if #varsToKeep < #varStatement.variables and hasValues and #varStatement.values < #varStatement.variables then
		-- Note: need to watch out for edge case:
		-- don't support deleting from statements where we assign multiple vars via a function call (unless all vars are unused)
		-- and some are used while some are not, i.e: local a, b = returnTwoVals() a gets used, b
		-- does not, bc if removed b it breaks functionality
		return varStatement.variables, varStatement.values
	end

	if #varsToKeep > 0 then
		-- the last var we keep needs to have a space, the last val we keep needs to preserve the original last vals trailing trivia
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
	return varsToKeep, valsToKeep
end

local function handleVariableStatement(varStatement: luau.AstStatLocal, deletions: deletionStore, isAssign: boolean)
	local varsToKeep, valsToKeep = filterVariablesAndValues(varStatement, deletions, isAssign, varStatement.equals)
	return varsToKeep, valsToKeep
end

local function handleLeadingTrivia(attachTo: luau.AstExpr, toInsert: { lua.AstExpr })
	local newTrivia = {}
	while #toInsert > 0 do
		-- 	-- Strip spaces and tabs from trivia.text unless it is a comment
		local trivia = table.remove(toInsert, #toInsert)
		for _, token in pairs(trivia) do
			token.text = if token.tag == "whitespace" then token.text:gsub("[ \t]+", "") else token.text
			table.insert(newTrivia, token)
		end
	end
	for _, trivia in attachTo.leadingTrivia do
		table.insert(newTrivia, trivia)
	end
	return newTrivia
end

local function insertLeadingTrivia(statement: luau.AstStat, triviaToInsert: { luau.AstExpr })
	-- i want to insert
	-- need to handle bunch of diff types of tags to insert trivia at appropriate point;
	-- essentially want to get leading trivia of syntactically earliest node in statement

	if statement.tag == "expression" or statement.tag == "indexname" then
		-- recur on expressions till we find something with leading trivia
		insertLeadingTrivia(statement.expression, triviaToInsert)
	elseif statement.tag == "local" or statement.tag == "localfunction" then
		if statement.localKeyword then
			statement.localKeyword.leadingTrivia = handleLeadingTrivia(statement.localKeyword, triviaToInsert)
		else
			statement.token.leadingTrivia = handleLeadingTrivia(statement.token, triviaToInsert)
		end
	elseif statement.tag == "function" then
		statement.functionKeyword.leadingTrivia = handleLeadingTrivia(statement.functionKeyword, triviaToInsert)
	elseif statement.tag == "assign" or statement.tag == "compoundassign" then
		-- recur till we find something with leading trivia
		insertLeadingTrivia(statement.variables[1].node, triviaToInsert)
	elseif statement.tag == "conditional" then
		statement.ifKeyword.leadingTrivia = handleLeadingTrivia(statement.ifKeyword, triviaToInsert)
	elseif statement.tag == "for" or statement.tag == "forin" then
		statement.forKeyword.leadingTrivia = handleLeadingTrivia(statement.forKeyword, triviaToInsert)
	elseif statement.tag == "while" then
		statement.whileKeyword.leadingTrivia = handleLeadingTrivia(statement.whileKeyword, triviaToInsert)
	elseif statement.tag == "repeat" then
		statement.repeatKeyword.leadingTrivia = handleLeadingTrivia(statement.repeatKeyword, triviaToInsert)
	elseif statement.tag == "call" then
		-- recur till we find something with leading trivia
		insertLeadingTrivia(statement.func, triviaToInsert)
	elseif statement.tag == "return" then
		statement.returnKeyword.leadingTrivia = handleLeadingTrivia(statement.returnKeyword, triviaToInsert)
	end
end

local function getStatementLeadingTrivia(statement: luau.AstStat)
	-- only type of statements we worry abt are those we can delete
	return if statement.tag == "assign"
		then statement.variables[1].node["local"].leadingTrivia
		elseif statement.tag == "local" or statement.tag == "localfunction" then statement.localKeyword.leadingTrivia
		elseif statement.tag == "function" then statement.functionKeyword.leadingTrivia
		else nil
end

local function deleteVariables(block: luau.AstStatBlock, deletions: deletionStore)
	local removalsVisitor = visitor.createVisitor()

	removalsVisitor.visitBlockEnd = function(block: luau.AstStatBlock)
		local filteredStatements = {}
		local priorLeadingTrivia = {}

		for _, statement in block.statements do
			local statementLeadingTrivia
			-- need to store this so we get leading trivia of statement pre-removal
			-- we delete function declarations, variable declarations, and variable assignments (will we need to delete function assingments too...?)
			-- for each deleted statement, we store it's leading trivia (what ever non-code (comments, whitespace) is between the prior statement and the current) in a table
			-- whenever we come across a statement we are keeping, we append all the leading trivia in our store to the statement's existing leading trivia
			-- this ensures we preserve comments and relevant whitespace (mostly newlines)
			if statement.tag == "localfunction" or statement.tag == "function" then
				if deletions[statement.name] then
					statementLeadingTrivia = getStatementLeadingTrivia(statement)
					table.insert(priorLeadingTrivia, statementLeadingTrivia)
					continue
				end
			elseif statement.tag == "local" or statement.tag == "assign" then -- cheeky edge case! bc we don't consider assignments a use, we need to remove assignments of unused variables
				if #statement.variables == 0 then
					continue
				end
				local newVars
				newVars, statement.values = handleVariableStatement(statement, deletions, statement.tag == "assign") -- reassign statement variables and values
				if #newVars == 0 then -- if deleting all vars
					statementLeadingTrivia = getStatementLeadingTrivia(statement) -- get trivia from original statement
					table.insert(priorLeadingTrivia, statementLeadingTrivia)
					continue
				end
				statement.variables = newVars
			end
			if #priorLeadingTrivia > 0 then
				-- if we have stored leading trivia from deleted statements and are keeping the current statement,
				-- insert the leading trivia from previously removed statements
				insertLeadingTrivia(statement, priorLeadingTrivia) -- when we remove a statement fully, we need to preserve it's leading trivia by attaching to the next statement
			end
			table.insert(filteredStatements, statement)
		end

		block.statements = filteredStatements
	end

	visitor.visitBlock(block, removalsVisitor)

	return block
end

return deleteVariables
