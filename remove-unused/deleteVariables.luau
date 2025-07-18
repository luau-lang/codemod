local luau = require("@lute/luau")
local findVariablesUtils = require("./findVariablesUtils")
local visitor = require("@batteries/syntax/visitor")
local triviaHelpers = require("./helpers/triviaHelpers")
local handleLeadingTriviaInsertion = triviaHelpers.handleLeadingTriviaInsertion
local extractStatementTrivia = triviaHelpers.extractStatementTrivia
local handleVariableStatementTrivia = triviaHelpers.handleVariableStatementTrivia

type deletionStore = findVariablesUtils.deletionStore

--[[
	Determines if we should keep all variables for early return in `filterVariablesAndValues`.
	
	True if:
	- We are keeping the same number of variables as the statement originally had (we are not removing anything)
	- We have removed variables from a statement where multiple variables are assigned to a single function call. This will break code
	
	@param varsToKeep - The filtered variables
	@param valsToKeep - The filtered vaues
	@param varStatement - The original statement
	@param hasValues - True if the original statement had values (was initialization or assignment)
	@return boolean, true if we are keeping the statement as it originally was, false otherwise
]]
local function keepAllVariables(varsToKeep, valsToKeep, varStatement, hasValues): boolean
	if #varsToKeep == #varStatement.variables then
		return true
	end

	-- don't support deleting from statements where we assign multiple vars via a function call (unless all vars are unused AKA varsToKeep is empty)
	if #varsToKeep > 0 and #varsToKeep < #varStatement.variables and hasValues and #varStatement.values < #varStatement.variables then
		return true
	end

	return false
end

--[[
	Function that filters a statement with variables based on our deletions store.
	
	All variable declarations, initializations, or assignments have a statement node with a `variables` and `values` property,
	so reassigning these effectively filters and transforms the statement.

	@param varStatement - The statement to filter
	@param deletions - Our deletions store, used to determine if a variable is deleted (variable AST nodes key into deletions)
	@param isAssign - If the statement is an assignment (i.e. a, b = 1, 2); indicates a different AST node structure
	@param hasValues - If the statement has values (we can declare variables without initializaing a value)
	@return `newVars` table containing the variable nodes to be kept 
	@return `newVals` table containing the corresponding value nodes of `newVars`
]]
local function filterVariablesAndValues(
	varStatement: luau.AstStat,
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

	if keepAllVariables(varsToKeep, valsToKeep, varStatement, hasValues) then
		return varStatement.variables, varStatement.values
	end

	if #varsToKeep > 0 then
		handleVariableStatementTrivia(varsToKeep, valsToKeep, statementTrailingTrivia)
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
		local filteredStatements = {} -- for each deleted statement, we store it's trivia
		-- whenever we come across a statement we are keeping, we append all the leading trivia in our store to the statement's existing leading trivia

		local removedTrivia = {} -- used to store trivia of removed statements so we can preserve it

		for _, statement in block.statements do
			-- function removal is straightforward, we just omit the entire statement from filteredStatements
			if statement.tag == "localfunction" or statement.tag == "function" then
				if deletions[statement.name] then
					extractStatementTrivia(statement, removedTrivia)
					continue
				end
			elseif statement.tag == "local" or statement.tag == "assign" then -- cheeky edge case! bc we don't consider assignments a use, we need to remove assignments of unused variables
				if #statement.variables == 0 then
					continue
				end
				local newVars, newVals
				 -- get filtered statement variables and values
				newVars, newVals = handleVariableStatement(statement, deletions, statement.tag == "assign")
				if #newVars == 0 then -- if deleting all vars
					extractStatementTrivia(statement, removedTrivia)
					continue
				end
				statement.variables = newVars
				statement.values = newVals
			end
			if #removedTrivia > 0 then
				-- insert the leading trivia from previously removed statements to statement we are keeping
				handleLeadingTriviaInsertion(statement, removedTrivia)
			end
			table.insert(filteredStatements, statement)
		end

		block.statements = filteredStatements
	end

	visitor.visitBlock(block, removalsVisitor)

	return block
end

return deleteVariables
