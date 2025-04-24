local T = require("@batteries/syntax/ast_types")

local isFlagAccess = require("./matchers/isFlagAccess")
local evaluate = require("./evaluate")
local simplifyConditional = require("./simplifyConditional")

type SimplifyContext = {
	flagName: string,
	flagLocalsSet: { [T.AstLocal]: true },
	globalFunctionsSet: { [string]: true },
}

local function space(count): T.Trivia
	return {
		tag = "whitespace",
		text = string.rep(" ", count),
		location = {}, -- TODO
	} :: any
end

local function simplifyBlock(block: T.AstStatBlock, ctx: evaluate.EvaluateContext): T.AstStatBlock
	local statements = {}

	for _, statement in block.statements do
		if statement.tag == "expression" then
			-- Skip (i.e. delete) any top level flag access calls (game:DefineFastFlag / game:GetFastFlag)
			if isFlagAccess(statement.expression, ctx.flagName) then
				continue
			end
			table.insert(statements, statement)
		elseif statement.tag == "local" then
			-- Skip (i.e. delete) if all variables are marked for deletion
			local shouldDelete = true
			for _, variable in statement.variables do
				if not ctx.flagLocalsSet[variable.node] then
					shouldDelete = false
					break
				end
			end

			if shouldDelete then
				continue
			end

			table.insert(statements, statement)
		elseif statement.tag == "localfunction" then
			-- Skip (i.e. delete) if local function is marked for deletion
			if ctx.flagLocalsSet[statement.name] then
				continue
			end

			table.insert(statements, statement)
		elseif statement.tag == "function" then
			-- Skip (i.e. delete) if local function is marked for deletion
			if statement.name.tag == "local" and ctx.flagLocalsSet[statement.name["local"]] then
				continue
			elseif statement.name.tag == "global" and ctx.globalFunctionsSet[statement.name.name.text] then
				continue
			end

			table.insert(statements, statement)
		elseif statement.tag == "assign" then
			-- Simplify 'local x; x = ...'
			if #statements > 0 and #statement.variables == 1 and #statement.values == 1 then
				local assigningTo = statement.variables[1].node
				if assigningTo.tag == "local" then
					local previousStatement = statements[#statements]
					if
						previousStatement.tag == "local"
						and #previousStatement.variables == 1
						and #previousStatement.values == 0
						and previousStatement.variables[1].node.name.text == assigningTo.token.text
					then
						-- TODO: trivia preservation?
						previousStatement.variables[1].node.name.trailingTrivia = { space(1) }
						previousStatement.equals = statement.equals
						table.insert(previousStatement.values, { node = statement.values[1].node })
						continue
					end
				end
			end

			table.insert(statements, statement)
		elseif statement.tag == "conditional" then
			local simplified = simplifyConditional(statement, ctx)
			if simplified.tag == "conditional" then
				table.insert(statements, simplified)
			elseif simplified.tag == "block" then
				-- If processed down to a block, flatten with the main block
				for _, otherStatement in simplified.statements do
					table.insert(statements, otherStatement)
				end
			else
				error(
					`simplifyIf should only return a conditional statement or block of statements, but got {simplified.tag}`
				)
			end
		else
			table.insert(statements, statement)
		end
	end

	return {
		tag = "block",
		statements = statements,
	}
end

return simplifyBlock
