local luau = require("@lute/luau")

local visitor = require("@batteries/syntax/visitor")
local printTable = require("./helpers/testHelpers").printTable

export type scope = {
	[string]: luau.AstExpr,
}

export type variableStore = {
	[luau.AstExpr]: number,
}

export type deletionStore = {
	[luau.AstExpr]: boolean,
}

--[[
	Maps global function names to their AST nodes and reference counts.
	Used to track global functions that may be referenced before their definition.
]]
export type globalStore = {
	[string]: {
		ref: luau.AstExpr,
		beforeInitCnt: number,
	},
}

local function excludeVarName(varName: string): boolean
	-- Skip underscore-prefixed (intentionally unused)
	if varName:sub(1, 1) == "_" then
		return true
	end
	return false
end

--[[
	Traverses variable declaration statement to intitialize tracking of local references for each variable in the statement.

	@param vars - Table of variables in the statement
	@param variables - Variable store used to track variable usage
	@param scopeStack - Scope stack used to keep track of current scope; declared variables are added to the current scope
]]
local function handleVarDeclaration(declaredVars, variables: variableStore, scopeStack: { scope })
	if declaredVars then
		for _, v in declaredVars do
			if v.node then
				if not excludeVarName(v.node.name.text) then
					variables[v.node] = 0 -- Initialize usage count to 0
					scopeStack[#scopeStack][v.node.name.text] = v.node -- Add to current scope
				end
			end
		end
	end
end

--[[
	Handles variable assignments by decrementing their usage count.
	This is necessary because our linter doesn't consider the act of assigning to a variable as a "use", and these nodes are counted by visitLocalRereference.
	
	@param assignedVars - Array of variable nodes being assigned to
	@param assignedVals - Array of value nodes being assigned
	@param variables - Store tracking variable usage counts
]]
local function handleAssign(assignedVars, assignedVals, variables: variableStore)
	if assignedVars then
		for _, v in assignedVars do
			if v.node then
				if variables[v.node["local"]] then
					variables[v.node["local"]] -= 1
				end
			end
		end
	end
end

--[[
	Handles variable references by incrementing their usage count.
	
	@param node - The AST node representing the variable reference
	@param variables - Store tracking variable usage counts
]]
local function handleVarReference(node: luau.AstStatLocal, variables: variableStore)
	-- Local references store the original variable declaration in the 'local' field
	-- This allows us to match the reference with its declaration
	if variables[node["local"]] then
		variables[node["local"]] += 1
	end
end

--[[
	Searches the scope stack for a variable with the given name and increments its usage count if found.
	This function walks up the scope tree from current (innermost) to global (outermost) scope.
	
	@param scopeStack - Stack of scopes to search through
	@param varName - The name of the variable to find
	@param variables - Store tracking variable usage counts
]]
local function searchScopeStack(scopeStack: { scope }, varName: string, variables: variableStore)
	-- check all vars in current scope; if not found, go to next deepest scope (search up the scope tree)
	local curScope = #scopeStack
	while curScope > 0 do
		if scopeStack[curScope][varName] then
			local varReference = scopeStack[curScope][varName]
			variables[varReference] += 1
			break
		end
		curScope -= 1
	end
end

--[[	
	This function:
	1. Creates visitor callbacks for different AST node types
	2. Tracks variable and function declarations and references across scope
	5. Builds a deletion store of unused variables based on their usage count
	
	@param block - The AST block to analyze
	@return variables - Table mapping variable nodes to their usage counts
	@return deletions - Table of variable nodes marked for deletion (usage count = 0)
	@return numDeletions - Count of variables marked for deletion
]]
local function findVariables(block: luau.AstStatBlock)
	local deletions: deletionStore = {}
	local globals: globalStore = {} -- Stores global function references and call counts before definition
	local variables: variableStore = {} -- Stores varReference : useCount for use in deletion
	local scopeStack: { scope } = {} -- Stack-like table that stores varName : varReference at each level of scope

	local getVarsVisitor = visitor.createVisitor()

	getVarsVisitor.visitBlock = function(block)
		table.insert(scopeStack, {}) -- Push new scope frame to stack
		return true
	end
	getVarsVisitor.visitBlockEnd = function(block)
		table.remove(scopeStack, #scopeStack) -- Pop current scope from stack
	end

	getVarsVisitor.visitLocalDeclaration = function(statement: luau.AstStatLocal)
		handleVarDeclaration(statement.variables, variables, scopeStack)
		return true
	end

	--[[
		Processes local function declarations.
		Registers the function name AST reference in the store and scope.
		Note: Function parameters are not analyzed for usage as they're acceptable to be unused.
	]]
	getVarsVisitor.visitLocalFunction = function(statement: luau.AstStatLocalFunction)
		if not excludeVarName(statement.name.name.text) then
			variables[statement.name] = 0 -- Initialize usage count
			scopeStack[#scopeStack][statement.name.name.text] = statement.name -- Add to current scope
		end
		return true
	end

	--[[
		Processes global function definitions.
		Handles special case for global functions since they can be used before definition.
		We use the function name (string, not AST node name) to index into globals.
		When we find the function declaration, we then store the actual AST node reference.
	]]
	getVarsVisitor.visitFunction = function(statement: luau.AstStatLocalFunction)
		if statement.name.name then
			local funcName = statement.name.name.text
			if not excludeVarName(funcName) then
				if not globals[funcName] then
					globals[funcName] = {
						ref = statement.name,
						beforeInitCnt = 0,
					}
				else
					globals[statement.name.name.text].ref = statement.name
				end
				-- visitExpression will count the function definition as a use, so we decrement by one here
				variables[statement.name] = globals[statement.name.name.text].beforeInitCnt - 1
			end
			-- Global functions don't need to be added to scope stack since they're accessible everywhere
		end
		return true
	end

	getVarsVisitor.visitLocalReference = function(expression: luau.AstExprLocal)
		handleVarReference(expression, variables)
		return true
	end

	--[[
		Handles global function calls and references.
		Increments usage count for global functions that are already defined.
		For references before definition, tracks the count to apply later when definition is found.
	]]
	getVarsVisitor.visitGlobal = function(expression: luau.AstExprGlobal)
		local globalFuncName
		globalFuncName = expression.name.text
		if not globals[globalFuncName] then
			globals[globalFuncName] = {
				ref = nil,
				beforeInitCnt = 0,
			}
		end
		local globalFuncReference = globals[globalFuncName].ref
		if globalFuncReference then
			-- Function is already defined, increment its usage count
			variables[globalFuncReference] += 1
		else
			-- Function referenced before definition, track for later
			globals[globalFuncName].beforeInitCnt += 1
		end
		return true
	end

	--[[
		Processes type references which may refer to variables.
		Searches the scope stack for variables used in type expressions.
		For example, in code like `local x: SomeTypeExportingModule.SomeType`, the variable SomeTypeExportingModule would be referenced.
		The AST node accessed by visitTypeReference has no access to the "local" references we use as keys in our variable store,
		Thus, we search the scope stack to find the appropriate variable reference 
	]]
	getVarsVisitor.visitTypeReference = function(expression: luau.AstTypeReference)
		if expression.prefix then
			local varName = expression.prefix.text
			searchScopeStack(scopeStack, varName, variables)
		end
		return true
	end

	getVarsVisitor.visitAssign = function(expression: luau.AstStatAssign)
		handleAssign(expression.variables, expression.values, variables)
		return true
	end

	-- Execute the visitor on the block
	visitor.visitBlock(block, getVarsVisitor)

	-- Debug output of all variables and their usage counts
	print("Variables:")
	printTable(variables, 1, true)

	local numDeletions = 0
	for var, refs in variables do
		if refs < 1 then
			deletions[var] = true
			numDeletions += 1
		end
	end

	print("Deletions:")
	printTable(deletions, 1, true)
	return variables, deletions, numDeletions
end

return {
	findVariables = findVariables,
	searchScopeStack = searchScopeStack,
	handleAssign = handleAssign,
	handleVarDeclaration = handleVarDeclaration,
	handleVarReference = handleVarReference,
}
