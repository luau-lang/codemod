local luau = require("@lute/luau")

local visitor = require("@batteries/syntax/visitor")
local printTable = require("../flag-clipper/matchers/flagAccessUtils").printTable

export type scope = {
	[string]: luau.AstExpr,
}

export type variableStore = {
	[luau.AstExpr]: number,
}

local function excludeVarName(varName: string): boolean
	-- Skip underscore-prefixed (intentionally unused)
	if varName:sub(1, 1) == "_" then
		return true
	end
	return false
end

-- handles nodes (representing a declared variable)
local function handleVarDeclaration(nodes, variables: variableStore, scopeStack: { scope })
	if nodes then
		for _, v in nodes do
			if v.node then
				if not excludeVarName(v.node.name.text) then
					variables[v.node] = 0
					scopeStack[#scopeStack][v.node.name.text] = v.node
				end
			end
		end
	end
end

local function handleAssign(assignedVars, variables: variableStore)
	if assignedVars then
		for _, v in assignedVars do
			if v.node then
				if not variables[v.node["local"]] then
					printTable(v, 1)
				else
					variables[v.node["local"]] -= 1
				end
			end
		end
	end
end

local function handleVarReference(node: luau.AstStatLocal, variables: variableStore)
	if variables[node["local"]] then
		variables[node["local"]] += 1
	else
		print("reference to untracked var:", node["local"].name.text) -- this will prompt for function params, for ... vars, etc
	end
end

local function searchScopeStack(scopeStack: { scope }, varName: string, variables: variableStore)
	-- check all vars in current scope; if not found, go to next deepest scope (search up the scope tree)
	local curScope = #scopeStack
	print("Searching Scope Stack for", varName)
	while curScope > 0 do
		print(" curScope Keys")
		for k, v in pairs(scopeStack[curScope]) do
			print(" " .. k)
		end
		if scopeStack[curScope][varName] then
			-- increment var
			local varReference = scopeStack[curScope][varName]
			variables[varReference] += 1
			break
		end
		curScope -= 1
	end
end

-- function that traverses the block, finds variable declarations/references, and populates a deletions table for that block
local function findVariables(block: luau.AstStatBlock)
	local deletions = {}
	local variables: variableStore = {} -- stores varReference : useCount for use in deletion
	local scopeStack: { scope } = {} -- stack-esque table that stores varName : varReference at each level of scope

	local getVarsVisitor = visitor.createVisitor()

	-- scope changing visits (i think these will handle all scope changes but we'll see)
	getVarsVisitor.visitBlock = function(block)
		table.insert(scopeStack, {}) -- push to stack
		return true
	end
	getVarsVisitor.visitBlockEnd = function(block)
		table.remove(scopeStack, #scopeStack) -- pop from top of stack
	end

	-- ============ DECLARATIONS: local declarations, functions (and parameters), ... ============
	-- our linters are fine with unused for/for in variables... so perhaps we ignore
	getVarsVisitor.visitLocalDeclaration = function(expression: luau.AstStatLocal)
		handleVarDeclaration(expression.variables, variables, scopeStack)
		return true
	end
	-- same process for local and normal functions (don't know what a typed function is)
	getVarsVisitor.visitLocalFunction = function(expression: luau.AstStatLocalFunction)
		-- we care abt func.name.name; func parameters are not considered unused if they have no uses
		-- handleVarNodes(expression.body.parameters, variables) -- don't necesarilly need this bc linter is mad
		if expression.name then
			variables[expression.name] = 0
			scopeStack[#scopeStack][expression.name.name.text] = expression.name
		end
		return true
	end

	-- ============ REFERENCES: local references, type references, ... (what else hmmm) ============
	getVarsVisitor.visitLocalReference = function(expression: luau.AstExprLocal)
		-- only can care abt expression['local']
		-- these expressions store the original variable reference in local (local.name has text and position)
		-- we can use to match w/ declaration
		handleVarReference(expression, variables)
		return true
	end

	getVarsVisitor.visitTypeReference = function(expression: luau.AstTypeReference)
		if expression.prefix then
			-- need to search thru scopeStack for variable w/ same name
			local varName = expression.prefix.text
			searchScopeStack(scopeStack, varName, variables)
		end
		return true
	end
	--hmm sadly, in context like: local typeTable = {...}, local x: typeTable.type
	-- visitTypeReference has no local pointer to typeTabel (for cases like this, we might need to keep track of scope)
	-- for accurately incrementing variable count with nothing but a varName to go off of

	-- edge case for references is assign;
	-- need to decrement count for variables in assign bc our linters don't consider this a use
	-- but visitLocal references picks it up
	getVarsVisitor.visitAssign = function(expression: luau.AstStatAssign)
		-- care abt: values but don't want to increment references for variables getting assigned (our linter does not consider this a var usage)
		handleAssign(expression.variables, variables)
		return true
	end

	visitor.visitBlock(block, getVarsVisitor)
	print("Variables:")
	printTable(variables, 1, true)
	for var, refs in variables do
		if refs < 1 then
			table.insert(deletions, var)
		end
	end
	print("Deletions:")
	printTable(deletions, 1, true)
	return variables, deletions
end

return {
	findVariables = findVariables,
	searchScopeStack = searchScopeStack,
	handleAssign = handleAssign,
	handleVarDeclaration = handleVarDeclaration,
	handleVarReference = handleVarReference,
}
