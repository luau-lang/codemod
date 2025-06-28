local luau = require("@lute/luau")
local findVariablesUtils = require("./findVariablesUtils")
local visitor = require("@batteries/syntax/visitor")
local triviaHelpers = require("./helpers/triviaHelpers")
local handleLeadingTriviaInsertion = triviaHelpers.handleLeadingTriviaInsertion
local extractStatementTrivia = triviaHelpers.extractStatementTrivia

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

local function deleteVariables(block: luau.AstStatBlock, deletions: deletionStore)
	local removalsVisitor = visitor.createVisitor()

	removalsVisitor.visitBlockEnd = function(block: luau.AstStatBlock)
		local filteredStatements = {}
		local priorTrivia = {}

		for _, statement in block.statements do
			-- need to store this so we get leading trivia of statement pre-removal
			-- we delete function declarations, variable declarations, and variable assignments (will we need to delete function assingments too...?)
			-- for each deleted statement, we store it's trivia (what ever non-code (comments, whitespace) is between the prior statement and the current) in a table
			-- whenever we come across a statement we are keeping, we append all the leading trivia in our store to the statement's existing leading trivia
			-- this ensures we preserve comments (and kinda formatting)
			if statement.tag == "localfunction" or statement.tag == "function" then
				if deletions[statement.name] then
					extractStatementTrivia(statement, priorTrivia)
					continue
				end
			elseif statement.tag == "local" or statement.tag == "assign" then -- cheeky edge case! bc we don't consider assignments a use, we need to remove assignments of unused variables
				if #statement.variables == 0 then
					continue
				end
				local newVars, newVals
				newVars, newVals = handleVariableStatement(statement, deletions, statement.tag == "assign") -- reassign statement variables and values
				if #newVars == 0 then -- if deleting all vars
					extractStatementTrivia(statement, priorTrivia)
					continue
				end
				statement.variables = newVars
				statement.values = newVals
			end
			if #priorTrivia > 0 then
				-- if we have stored leading trivia from deleted statements and are keeping the current statement,
				-- insert the leading trivia from previously removed statements
				handleLeadingTriviaInsertion(statement, priorTrivia) -- when we remove a statement fully, we need to preserve it's trivia by attaching to the next statement
			end
			table.insert(filteredStatements, statement)
		end

		block.statements = filteredStatements
	end

	visitor.visitBlock(block, removalsVisitor)

	return block
end

return deleteVariables
