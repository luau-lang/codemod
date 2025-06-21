local luau = require("@lute/luau")

local visitor = require("@batteries/syntax/visitor")
local printTable = require("../flag-clipper/matchers/flagAccessUtils").printTable

export type scope = {
	[string]: luau.AstExpr,
}

export type variableStore = {
	[luau.AstExpr]: number,
}

export type deletionStore = {
	[luau.AstExpr]: number,
}

export type globalStore = { -- map global func name to AST node
	[string]: luau.AstExpr,
}

local function excludeVarName(varName: string): boolean
	-- Skip underscore-prefixed (intentionally unused)
	if varName:sub(1, 1) == "_" or varName:find("success") or varName:find("err") or varName:find("result") then
		return true
	end
	return false
end

-- handles nodes (representing a declared variable)
local function handleVarDeclaration(nodeVars, nodeValues, variables: variableStore, scopeStack: { scope })
	if nodeVars then
		for _, v in nodeVars do
			if v.node then
				if not excludeVarName(v.node.name.text) then
					-- we do want to consider it a use when we are assigning multiple vals to a singular val, bc removing one while others are used may break things
					if #nodeValues > 0 and #nodeVars > #nodeValues then
						variables[v.node] = 1
					else
						variables[v.node] = 0
					end
					scopeStack[#scopeStack][v.node.name.text] = v.node
				end
			end
		end
	end
end

local function handleAssign(assignedVars, assignedVals, variables: variableStore)
	if assignedVars then
		for _, v in assignedVars do
			if v.node then
				if variables[v.node["local"]] then
					-- we do want to consider it a use when we are assigning multiple vals to a singular val, bc removing one while others are used may break things
					if #assignedVars <= #assignedVals then
						variables[v.node["local"]] -= 1
					end
				end
			end
		end
	end
end

local function handleVarReference(node: luau.AstStatLocal, variables: variableStore)
	if variables[node["local"]] then
		variables[node["local"]] += 1
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
			local varReference = scopeStack[curScope][varName]
			variables[varReference] += 1
			break
		end
		curScope -= 1
	end
end

-- function that traverses the block, finds variable declarations/references, and populates a deletions table for that block
local function findVariables(block: luau.AstStatBlock)
	local deletions: deletionStore = {}
	local globals: globalStore = {}
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
		handleVarDeclaration(expression.variables, expression.values, variables, scopeStack)
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

	-- handle global function definitions
	getVarsVisitor.visitFunction = function(expression: luau.AstStatLocalFunction)
		if expression.name.name then
			globals[expression.name.name.text] = expression.name
			variables[expression.name] = 0
			-- dont think we need to add to scope stack bc how cud type reference (only thing that searches scope stack) prefix match w a global function...?
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

	-- handle's global function calls and references
	getVarsVisitor.visitExpression = function(expression: luau.AstExprGlobal)
		local globalFuncName
		if expression.tag == "global" and globals[expression.name.text] then -- this procs for function definition, call, and non-call ref so need to avoid double counting
			-- maybe can check if on same line as globalFuncReference (reference to definition...) to avoid double cnt
			globalFuncName = expression.name.text
		else
			return true
		end
		local globalFuncReference = globals[globalFuncName]
		local isDoubleReference = expression.tag == "global"
			and expression.name.position.line == globalFuncReference.name.position.line
		if globalFuncReference and not isDoubleReference then -- only count tracked global funcs (don't care abt stuff like print (built in funcs) etc)
			variables[globalFuncReference] += 1
		end
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
		handleAssign(expression.variables, expression.values, variables)
		return true
	end

	visitor.visitBlock(block, getVarsVisitor)

	print("Variables:")
	printTable(variables, 1, true)
	local numDeletions = 0
	-- calculating this here is dangerous bc we bypass some deletions in delete (declarations that have less values than vars)
	-- also just realizing, need to account for case where we define vars and then reassign w the above like case i.e
	-- local x, y
	-- local x, y = func()
	for var, refs in variables do
		if refs < 1 then
			-- table.insert(deletions, var)
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
