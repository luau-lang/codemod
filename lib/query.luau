local syntax = require("@std/syntax")

local visitor = require("@std/syntax/visitor")

--- Selects a list of expressions from the provided block that match the provided predicate.
--- Useful for defining declarative-based programs, where the matched nodes are mutated for the migration
local function selectExpression<T>(block: syntax.CstStatBlock, predicate: (syntax.CstExpr) -> T?): { T }
	local nodes = {}
	local finder = visitor.create()

	finder.visitExpr = function(node)
		local result = predicate(node)
		if result then
			table.insert(nodes, result)
		end

		return true
	end

	visitor.visitBlock(block, finder)

	return nodes
end

return {
	selectExpression = selectExpression,
}
