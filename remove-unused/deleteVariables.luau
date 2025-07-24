local luau = require("@lute/luau")
local findVariablesUtils = require("./findVariablesUtils")
local visitor = require("@batteries/syntax/visitor")
local triviaHelpers = require("./helpers/triviaHelpers")
local handleLeadingTriviaInsertion = triviaHelpers.handleLeadingTriviaInsertion
local storeStatementTrivia = triviaHelpers.storeStatementTrivia
local handleVariableStatementTrivia = triviaHelpers.handleVariableStatementTrivia
local handleLeftoverTrivia = triviaHelpers.handleLeftoverTrivia

type deletionStore = findVariablesUtils.deletionStore

--[[
	Variable used to track edge cases where variable removal is prone to break logic.
	i.e. local x, y = functionThatReturnsTwoValues()
	If x or y is unused and we remove one of them, code will break
]]
local removalExceptions = 0

--[[
	Determines if we should keep all variables in a given statement. True if:
	- We are keeping the same number of variables as the statement originally had (we are not removing anything)
	- We have removed variables from a statement where multiple variables are assigned to a single function call. This will break code
	
	@param varsToKeep - The filtered variables
	@param valsToKeep - The filtered vaues
	@param varStatement - The original statement
	@param hasValues - True if the original statement had values (was initialization or assignment)
	@return true if we are keeping the statement as it originally was, false otherwise
]]
local function keepAllVariables(
	varsToKeep: luau.Punctuated<luau.AstLocal>,
	valsToKeep: luau.Punctuated<luau.AstExpr>,
	varStatement,
	hasValues
): boolean
	if #varsToKeep == #varStatement.variables then
		return true
	end

	if
		#varsToKeep > 0
		and #varsToKeep < #varStatement.variables
		and hasValues
		and #varStatement.values < #varStatement.variables
	then
		-- don't support deleting from statements where we assign multiple vars via a function call (unless all vars are unused)
		-- unused variables in such a statement are considered removal exceptions
		removalExceptions += #varStatement.variables - #varsToKeep
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
	varStatement: luau.AstStatLocal | luau.AstStatAssign,
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

local function handleVariableStatement(
	varStatement: luau.AstStatLocal | luau.AstStatAssign,
	deletions: deletionStore,
	isAssign: boolean
)
	local varsToKeep, valsToKeep = filterVariablesAndValues(varStatement, deletions, isAssign, varStatement.equals)
	return varsToKeep, valsToKeep
end

local function deleteVariables(block: luau.AstStatBlock, deletions: deletionStore)
	removalExceptions = 0
	local removalsVisitor = visitor.createVisitor()

	removalsVisitor.visitBlockEnd = function(block: luau.AstStatBlock)
		local filteredStatements = {}

		local removedTrivia = {} -- store trivia of removed statements so we can preserve it

		local priorKeptStatement = nil -- store most recently kept statement; if we have leftover removedTrivia after full block traversal, we can append to this statement

		for _, statement in block.statements do
			-- function removal is straightforward, we just omit the entire statement from filteredStatements
			if statement.tag == "localfunction" or statement.tag == "function" then
				if deletions[statement.name] then
					storeStatementTrivia(statement, removedTrivia)
					continue
				end
			elseif statement.tag == "local" or statement.tag == "assign" then
				local newVars, newVals
				-- get filtered statement variables and values
				newVars, newVals = handleVariableStatement(statement, deletions, statement.tag == "assign")
				if #newVars == 0 then -- if deleting all vars
					storeStatementTrivia(statement, removedTrivia)
					continue
				end
				statement.variables = newVars
				statement.values = newVals
			end
			if #removedTrivia > 0 then
				-- insert the leading trivia from previously removed statements to statement we are keeping
				handleLeadingTriviaInsertion(statement, removedTrivia)
			end
			priorKeptStatement = statement
			table.insert(filteredStatements, statement)
		end

		handleLeftoverTrivia(removedTrivia, priorKeptStatement)

		block.statements = filteredStatements
	end

	visitor.visitBlock(block, removalsVisitor)

	return block, removalExceptions
end

return deleteVariables
