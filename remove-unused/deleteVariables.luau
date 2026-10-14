local syntax = require("@std/syntax")
local types = require("@std/syntax/types")
local findVariablesUtils = require("./findVariablesUtils")
local visitor = require("@std/syntax/visitor")
local printer = require("@std/syntax/printer")
local triviaHelpers = require("./helpers/triviaHelpers")

type deletionStore = findVariablesUtils.deletionStore
type TokenEdits = triviaHelpers.TokenEdits

type VariableStatement = syntax.CstStatLocal | syntax.CstStatAssign

--[[
	The variables and values of a variable statement that survive deletion, by their index in the original statement.
]]
type FilteredStatement = {
	statement: VariableStatement,
	varIndices: { number },
	valIndices: { number },
}

--[[
	Determines if we should keep all variables in a given statement. True if:
	- We are keeping the same number of variables as the statement originally had (we are not removing anything)
	- We have removed variables from a statement where multiple variables are assigned to a single function call. This will break code
	  i.e. local x, y = functionThatReturnsTwoValues()
	  Unused variables in such a statement are counted as removal exceptions.

	@return true if we are keeping the statement as it originally was, false otherwise
	@return the number of removal exceptions
]]
local function keepAllVariables(numVarsToKeep: number, varStatement: VariableStatement): (boolean, number)
	if numVarsToKeep == #varStatement.variables then
		return true, 0
	end

	if numVarsToKeep > 0 and varStatement.equals ~= nil and #varStatement.values < #varStatement.variables then
		return true, #varStatement.variables - numVarsToKeep
	end

	return false, 0
end

--[[
	Filters a statement with variables based on our deletions store.

	@return the kept variables and values, or nil if the statement is kept as is
	@return the number of removal exceptions
]]
local function filterVariablesAndValues(
	varStatement: VariableStatement,
	deletions: deletionStore
): (FilteredStatement?, number)
	local isAssign = varStatement.tag == "assign"
	local hasValues = varStatement.equals ~= nil
	local varIndices, valIndices = {}, {}

	for i, variable in varStatement.variables do
		local deletionsKey = if isAssign then (if variable.tag == "local" then variable["local"] else nil) else variable
		if not deletionsKey or not deletions[deletionsKey] then -- keep the variable and the value it is assigned
			table.insert(varIndices, i)
			if hasValues and varStatement.values[i] then
				table.insert(valIndices, i)
			end
		end
	end

	local keepAll, exceptions = keepAllVariables(#varIndices, varStatement)
	if keepAll then
		return nil, exceptions
	end

	return { statement = varStatement, varIndices = varIndices, valIndices = valIndices }, 0
end

local function statementFirstToken(filtered: FilteredStatement): syntax.CstToken
	local statement = filtered.statement
	if statement.tag == "local" then
		return statement.localKeyword
	end
	return (triviaHelpers.getFirstAndLastToken(statement.variables[filtered.varIndices[1]]))
end

local function statementLastToken(filtered: FilteredStatement): syntax.CstToken
	local statement = filtered.statement
	local lastNode: syntax.CstNode = if statement.equals
		then statement.values[filtered.valIndices[#filtered.valIndices]]
		else statement.variables[filtered.varIndices[#filtered.varIndices]]
	local _, lastToken = triviaHelpers.getFirstAndLastToken(lastNode)
	return lastToken
end

--[[
	Ensures the filtered statement keeps the leading trivia of the original statement and that the final variable and
	value do not have a separator (comma, etc) while preserving the original trailing trivia of the full statement.
]]
local function editVariableStatementTrivia(filtered: FilteredStatement, edits: TokenEdits)
	local statement = filtered.statement
	local originalFirst, originalLast = triviaHelpers.getFirstAndLastToken(statement)

	local firstToken = statementFirstToken(filtered)
	if firstToken ~= originalFirst then
		triviaHelpers.getEdit(edits, firstToken).leadingTrivia = originalFirst.leadingTrivia
	end

	local lastVarIndex = filtered.varIndices[#filtered.varIndices]
	local lastVarSeparator = statement.variables.separators[lastVarIndex]
	if lastVarSeparator then
		if statement.equals then
			-- keep the separator's trivia so the spacing before `=` is preserved
			triviaHelpers.getEdit(edits, lastVarSeparator).text = ""
		else
			local _, lastVarToken = triviaHelpers.getFirstAndLastToken(statement.variables[lastVarIndex])
			triviaHelpers.getEdit(edits, lastVarToken).trailingTrivia = originalLast.trailingTrivia
		end
	end

	if statement.equals and #filtered.valIndices > 0 then
		local lastToken = statementLastToken(filtered)
		if lastToken ~= originalLast then
			triviaHelpers.getEdit(edits, lastToken).trailingTrivia = originalLast.trailingTrivia
		end
	end
end

local function printFilteredStatement(filtered: FilteredStatement, replacements: types.Replacements): string
	local statement = filtered.statement
	local parts = {}
	local function print(node: syntax.CstNode)
		table.insert(parts, printer.printNode(node, replacements))
	end

	if statement.tag == "local" then
		print(statement.localKeyword)
	end
	for i, index in filtered.varIndices do
		print(statement.variables[index])
		local separator = statement.variables.separators[index]
		if separator and (i < #filtered.varIndices or statement.equals) then
			print(separator)
		end
	end
	if statement.equals then
		print(statement.equals)
		for i, index in filtered.valIndices do
			print(statement.values[index])
			local separator = statement.values.separators[index]
			if separator and i < #filtered.valIndices then
				print(separator)
			end
		end
	end

	return table.concat(parts)
end

--[[
	Computes the replacements that delete the given variables from the tree rooted at `block`.

	@return replacements to print the tree with
	@return the number of deletions that were not applied because removing them is unsafe
]]
local function deleteVariables(block: syntax.CstStatBlock, deletions: deletionStore): (types.Replacements, number)
	local removalExceptions = 0
	local replacements: types.Replacements = {}
	local edits: TokenEdits = {}
	local removalsVisitor = visitor.create()

	removalsVisitor.visitStatBlockEnd = function(block: syntax.CstStatBlock)
		local removedTrivia = {} -- store trivia of removed statements so we can preserve it
		local filteredStatements: { FilteredStatement } = {}

		-- store most recently kept statement; if we have leftover removedTrivia after full block traversal, we can append to this statement
		local priorKeptLastToken: syntax.CstToken? = nil

		for _, statement in block.statements do
			local filtered: FilteredStatement? = nil

			-- function removal is straightforward, we just omit the entire statement
			if statement.tag == "localfunction" or statement.tag == "function" then
				if deletions[statement.name] then
					triviaHelpers.storeStatementTrivia(statement, removedTrivia)
					replacements[statement] = { content = "", preserveTrivia = false }
					continue
				end
			elseif statement.tag == "local" or statement.tag == "assign" then
				local exceptions
				filtered, exceptions = filterVariablesAndValues(statement, deletions)
				removalExceptions += exceptions
				if filtered and #filtered.varIndices == 0 then -- if deleting all vars
					triviaHelpers.storeStatementTrivia(statement, removedTrivia)
					replacements[statement] = { content = "", preserveTrivia = false }
					continue
				end
			end

			local firstToken, lastToken
			if filtered then
				editVariableStatementTrivia(filtered, edits)
				table.insert(filteredStatements, filtered)
				firstToken, lastToken = statementFirstToken(filtered), statementLastToken(filtered)
			else
				firstToken, lastToken = triviaHelpers.getFirstAndLastToken(statement)
			end

			if #removedTrivia > 0 then
				-- insert the leading trivia from previously removed statements to statement we are keeping
				triviaHelpers.insertLeadingTrivia(edits, firstToken, removedTrivia)
			end
			priorKeptLastToken = lastToken
		end

		if #removedTrivia > 0 and priorKeptLastToken then
			triviaHelpers.appendTrailingTrivia(edits, priorKeptLastToken, removedTrivia)
		end

		triviaHelpers.applyTokenEdits(edits, replacements)
		for _, filtered in filteredStatements do
			replacements[filtered.statement] =
				{ content = printFilteredStatement(filtered, replacements), preserveTrivia = false }
		end
	end

	visitor.visitBlock(block, removalsVisitor)

	return replacements, removalExceptions
end

return deleteVariables
