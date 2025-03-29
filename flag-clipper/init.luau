local parser = require("@batteries/syntax/parser")
local printer = require("@batteries/syntax/printer")
local visitor = require("@batteries/syntax/visitor")
local T = require("@batteries/syntax/ast_types")

local codemod = require("../types")

local isFlagAccess = require("./matchers/isFlagAccess")
local isFlagFunction = require("./matchers/isFlagFunction")
local simplifyExpression = require("./simplifyExpression")
local simplifyBlock = require("./simplifyBlock")

local FLAG_NAME = "FlagName"

local function inplaceReplace(old: T.AstExpr, new: T.AstExpr)
	if old == new then
		return
	end

	-- We abuse the fact that everything is table references, and inplace change the old node into the new one
	-- TODO: we should probably make mutability more explicit
	table.clear(old)

	for k, v in new do
		old[k] = v
	end
end

return function(ctx: codemod.Context)
	local block = parser.parse(ctx.source)

	-- Steps:
	-- 1) Replace flag usages
	--		* game:DefineFastFlag -> if result used, <value>, else <nothing> (i.e, whether it's a statement call)
	--		* game:GetFastFlag -> <value>
	--		* local x = require(path), where path is a module that returns one of the above -> <value>
	--		* getFastFlag(), where getFastFlag is a function that returns game:GetFastFlag -> <value>
	-- 2) Simplify code
	--		* Expression simplification:
	--			* x and true 	/ true and x 	-> x
	--			* x and false 	/ false and x 	-> false
	--			* x or true 	/ true or x 	-> true
	--			* x or false 	/ false or x	-> false
	--			* not true -> false
	--			* not false -> true
	--			* if true then A else B -> A
	--			* if false then A else B -> B
	--		* Statement simplification:
	--			* local x; x = ... -> local x = ...
	--			* if true then A else B end -> A
	--			* if false then A else B end -> B
	--		* Remove unused variables
	--		* Remove unused function (particularly flag function)
	--		* Module simplification:
	--			* if FFlag module (returns game:DefineFastFlag, game:GetFastFlag, or a function that returns game:GetFastFlag) -> delete
	--				NOTE: must delete at end in case we need to access result

	-- early check: if FFlag module, mark for deletion and exit [cache that this is a fflag module for require resolution]
	-- mutable visitor:
	-- 	* local declaration
	--		- map variables to values
	--		- if variable points to flag call or flag getter function, store: map[AstLocal] = true
	--			- follow through requires
	--			- mark variable for deletion
	--	* local function definition
	--		- same as local declaration
	--	* global function definition
	--		- same as local declaration [we don't have an AstLocal, but that's fine, base off function name for now]
	--		- TODO: only support for basic function definitions? we can't handle functions in tables
	--	* expression (post processing)
	--		- simplify using basic rules defined above
	--		- when checking for const true / false values we can:
	--			- replace AstExprLocals with constant value if map[AstLocal] = true
	--			- replace result of AstExprCall with constant value if map[AstLocal] = true
	--			- TODO: try to evaluate more complex expressions?
	--	* if statement (post processing)
	--		- we should've already performed expression simplification
	--		- if condition = true, delete any elseif / else blocks
	--		- if condition = false, delete initial block
	--		- keep processing elseifs downwards
	--		- if flattened to a single block, unwrap the block
	--			- NOTE: since we need to unwrap the block, this might need to be done in block "(post processing)"
	--	* block (post processing)
	--		- delete any top level 'game:DefineFastFlag()' calls
	--		- delete any local variables, functions, global functions marked for deletion
	--		- perform if stmt flattening as required
	--		- simplify 'local x; x = ...'

	-- A set of AstLocals that are known to correspond to a flag access
	-- The locals can be a constant reference, or a function definition
	local flagLocalsSet = {}

	-- A set of global function names that are known to correspond to a flag access
	-- Unlike flagLocalsSet, we do not track this via AstLocal reference, but just by the function name
	local globalFunctionsSet = {}

	local flagVisitor = visitor.createVisitor()

	flagVisitor.visitLocalDeclaration = function(node: T.AstStatLocal)
		for idx, variables in node.variables do
			local value = node.values[idx]
			if value and isFlagAccess(value.node, FLAG_NAME) then
				flagLocalsSet[variables.node] = true
			end
		end

		return true
	end

	flagVisitor.visitLocalFunction = function(node: T.AstStatLocalFunction)
		if isFlagFunction.isStmtFlagFunction(node, FLAG_NAME) then
			flagLocalsSet[node.name] = true
		end
		return true
	end

	flagVisitor.visitFunction = function(node: T.AstStatFunction)
		if isFlagFunction.isStmtFlagFunction(node, FLAG_NAME) then
			if node.name.tag == "local" then
				flagLocalsSet[node.name["local"]] = true
			elseif node.name.tag == "global" then
				globalFunctionsSet[node.name.name.text] = true
			end
		end
		return true
	end

	-- TODO: might want to double check the complexity here, since `simplifyExpression` is also recursive
	-- do we end up simplifying it twice?
	flagVisitor.visitExpressionEnd = function(expression: T.AstExpr)
		local ctx = {
			flagName = FLAG_NAME,
			flagLocalsSet = flagLocalsSet,
			globalFunctionsSet = globalFunctionsSet,
		}
		local newExpression = simplifyExpression(expression, ctx)

		inplaceReplace(expression, newExpression)
	end

	flagVisitor.visitBlockEnd = function(block)
		-- TODO: should we be inplace editing?
		local ctx = {
			flagName = FLAG_NAME,
			flagLocalsSet = flagLocalsSet,
			globalFunctionsSet = globalFunctionsSet,
		}
		local newBlock = simplifyBlock(block, ctx)
		block.statements = newBlock.statements
	end

	visitor.visitBlock(block, flagVisitor)

	return printer.print(block) .. "\n"
end
