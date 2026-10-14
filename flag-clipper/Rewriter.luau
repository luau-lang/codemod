--[[
	The CST produced by `@std/syntax` is immutable, so the flag-clipper cannot edit nodes in place. Instead, the
	Rewriter records what each node *effectively* looks like after simplification, and keeps a replacements map in
	sync so that the file can be reprinted via `printer.printFile(result, rewriter.replacements)`.

	A node can be rewritten in one of the following ways:
	- aliased: the expression is replaced by another expression (e.g. `true and x` => `x`)
	- constant: the expression is replaced by a boolean literal (e.g. `game:GetFastFlag("Flag")` => `true`)
	- re-rendered: the node keeps its identity but some of its children change (table entries removed, block
	  statements removed / inlined, conditional branches removed, a local declaration merged with an assignment)

	Simplification is performed post-order, so a node's replacement is rendered only after all of its descendants
	have been rewritten. Queries (`view`, `isReference`, `leadingTrivia`, `visit`, ...) look through rewrites, so that
	simplification logic sees the tree as if it had been modified in place.
]]

local printer = require("@std/syntax/printer")
local syntax = require("@std/syntax")
local syntaxTypes = require("@std/syntax/types")
local visitor = require("@std/syntax/visitor")

local TrackReferences = require("./TrackReferences")

local Rewriter = {}
Rewriter.__index = Rewriter

type Constant = {
	value: boolean,
	leadingTrivia: { syntax.Trivia },
	trailingTrivia: { syntax.Trivia },
}

--- A token printed with (optionally) different text or trailing trivia
export type TokenOverride = {
	token: syntax.CstToken,
	text: string?,
	trailingTrivia: { syntax.Trivia }?,
}

export type ConditionalBody = syntax.CstStatBlock | syntax.CstExpr
export type ConditionalElseIf = syntax.CstElseIfStat | syntax.CstElseIfExpr

--- The effective structure of a conditional (if statement or if expression) after branches are removed
export type ConditionalParts = {
	ifKeyword: TokenOverride,
	condition: syntax.CstExpr,
	thenKeyword: syntax.CstToken,
	thenBody: ConditionalBody,
	elseifs: { ConditionalElseIf },
	elseKeyword: TokenOverride?,
	elseBody: ConditionalBody?,
	endKeyword: syntax.CstToken?,
}

--- `local x` merged with a following `x = value`, producing `local x = value`
export type LocalMerge = {
	nameTrailingTrivia: { syntax.Trivia },
	equals: syntax.CstToken,
	values: syntax.CstPunctuated<syntax.CstExpr>,
}

type RewriterData = {
	references: TrackReferences.TrackReferences,
	replacements: syntaxTypes.Replacements,

	--[[
		Expressions which were simplified to an operand of a binary expression. These are used to avoid removing table
		entries whose values were simplified down to a direct flag reference.
		For example, if the flag is true and we have `local tbl = { field = flag and something }`, the entry
		simplifies to `{ field = something }`, so we must not remove it as if it was `{ field = flag }`.
	]]
	simplifiedBinaries: { [syntax.CstExpr]: true },

	_aliases: { [syntax.CstExpr]: syntax.CstExpr },
	_constants: { [syntax.CstExpr]: Constant },
	--[[
		There are some types of simplifications where we only want to apply them if an expression was previously
		modified by the flag-clipper tool.

		For example, in the following cases:
		```luau
		if true then
			...
		end

		local tbl = {
			value = nil
		}
		```

		we would like to keep the if statement as-is, or leave the `value` key in `tbl`, if that is what the source was like.
		However, if they came from the following input source:

		```luau
		if FlagValue then
			...
		end

		local tbl = {
			value = if FlagValue then nil else DEPRECATED_VALUE
		}
		```
		then we would like to clean them up further (remove the if block, and remove the value key).
	]]
	_modified: { [syntax.CstExpr]: true },
	_tableEntries: { [syntax.CstExprTable]: { syntax.CstTableExprItem } },
	_blockStatements: { [syntax.CstStatBlock]: { syntax.CstStat } },
	_conditionals: { [syntax.CstNode]: ConditionalParts },
	_localMerges: { [syntax.CstStatLocal]: LocalMerge },
}

export type Rewriter = setmetatable<RewriterData, typeof(Rewriter)>

function Rewriter.getThenBody(node: syntax.CstStatIf | syntax.CstExprIfElse | ConditionalElseIf): ConditionalBody
	local conditional = node :: any
	return conditional.thenBlock or conditional.thenExpr
end

local function printTrivia(trivia: { syntax.Trivia }): string
	local parts = table.create(#trivia)
	for _, item in trivia do
		table.insert(parts, item.text)
	end
	return table.concat(parts)
end

function Rewriter.new(references: TrackReferences.TrackReferences): Rewriter
	local self = {
		references = references,
		replacements = {},
		simplifiedBinaries = {},
		_aliases = {},
		_constants = {},
		_modified = {},
		_tableEntries = {},
		_blockStatements = {},
		_conditionals = {},
		_localMerges = {},
	}

	return setmetatable(self, Rewriter)
end

--- Returns the expression that `expression` was effectively rewritten to,
--- or nil if it was rewritten to a constant boolean
function Rewriter.view(self: Rewriter, expression: syntax.CstExpr): syntax.CstExpr?
	local current = expression
	while true do
		if self._constants[current] then
			return nil
		end

		local alias = self._aliases[current]
		if alias == nil then
			return current
		end
		current = alias
	end
end

--- Whether the given expression was replaced with a different expression by the flag-clipper
function Rewriter.isModified(self: Rewriter, expression: syntax.CstExpr): boolean
	return self._modified[expression] == true
end

--- Returns whether the provided expression is (effectively) a reference to the flag being removed
function Rewriter.isReference(self: Rewriter, expression: syntax.CstExpr): boolean
	local effective = self:view(expression)
	return effective ~= nil and self.references:isReference(effective)
end

function Rewriter.getReferenceValue(self: Rewriter, expression: syntax.CstExpr): boolean
	local effective = self:view(expression)
	assert(effective, "expected expression to be a flag reference")
	return self.references:getReferenceValue(effective)
end

function Rewriter.isCompoundReference(self: Rewriter, expression: syntax.CstExpr): boolean
	if not self:isReference(expression) then
		return false
	end

	local effective = self:view(expression)
	assert(effective, "Luau")
	return effective.tag == "unary"
		or effective.tag == "binary"
		or (effective.tag == "group" and self:isCompoundReference(effective.expression))
end

--- Prints the given node, applying all rewrites made so far
function Rewriter.print(self: Rewriter, node: syntax.CstNode): string
	return printer.printNode(node, self.replacements)
end

function Rewriter._printPunctuated<T>(self: Rewriter, list: syntax.CstPunctuated<T>): string
	local parts = {}
	for i, item in list do
		table.insert(parts, self:print(item :: any))
		local separator = list.separators[i]
		if separator then
			table.insert(parts, self:print(separator))
		end
	end
	return table.concat(parts)
end

function Rewriter._printTokenOverride(self: Rewriter, override: TokenOverride): string
	if override.text == nil and override.trailingTrivia == nil then
		return self:print(override.token)
	end

	return printTrivia(override.token.leadingTrivia)
		.. (override.text or override.token.text)
		.. printTrivia(override.trailingTrivia or override.token.trailingTrivia)
end

function Rewriter._setReplacement(self: Rewriter, node: syntax.CstNode, content: string)
	self.replacements[node] = { content = content, preserveTrivia = false }
end

--- Replaces the `old` expression with the `new` expression
function Rewriter.replace(self: Rewriter, old: syntax.CstExpr, new: syntax.CstExpr)
	if old == new then
		return
	end

	self._aliases[old] = new
	self._modified[old] = true
	self.simplifiedBinaries[old] = self.simplifiedBinaries[new]
	self:_setReplacement(old, self:print(new))
end

--- Replaces the expression with a boolean literal, preserving the expression's surrounding trivia
function Rewriter.setConstant(self: Rewriter, expression: syntax.CstExpr, value: boolean)
	local constant = {
		value = value,
		leadingTrivia = self:leadingTrivia(expression),
		trailingTrivia = self:trailingTrivia(expression),
	}

	self._constants[expression] = constant
	self._modified[expression] = nil
	self.simplifiedBinaries[expression] = nil
	self:_setReplacement(
		expression,
		printTrivia(constant.leadingTrivia) .. tostring(value) .. printTrivia(constant.trailingTrivia)
	)
end

function Rewriter.tableEntries(self: Rewriter, node: syntax.CstExprTable): { syntax.CstTableExprItem }
	return self._tableEntries[node] or node.entries
end

function Rewriter.setTableEntries(self: Rewriter, node: syntax.CstExprTable, entries: { syntax.CstTableExprItem })
	self._tableEntries[node] = entries

	local parts = { self:print(node.openBrace) }
	for _, entry in entries do
		table.insert(parts, self:print(entry :: any))
	end
	table.insert(parts, self:print(node.closeBrace))

	self:_setReplacement(node, table.concat(parts))
end

function Rewriter.statements(self: Rewriter, block: syntax.CstStatBlock): { syntax.CstStat }
	return self._blockStatements[block] or block.statements
end

function Rewriter.setStatements(self: Rewriter, block: syntax.CstStatBlock, statements: { syntax.CstStat })
	local current = self:statements(block)
	if #current == #statements then
		local unchanged = true
		for i, statement in statements do
			if current[i] ~= statement then
				unchanged = false
				break
			end
		end
		if unchanged then
			return
		end
	end

	self._blockStatements[block] = statements

	local parts = table.create(#statements)
	for _, statement in statements do
		table.insert(parts, self:print(statement))
	end

	self:_setReplacement(block, table.concat(parts))
end

function Rewriter.setConditional(self: Rewriter, node: syntax.CstStatIf | syntax.CstExprIfElse, parts: ConditionalParts)
	self._conditionals[node] = parts

	local output = {
		self:_printTokenOverride(parts.ifKeyword),
		self:print(parts.condition),
		self:print(parts.thenKeyword),
		self:print(parts.thenBody),
	}

	for _, elseifNode in parts.elseifs do
		table.insert(output, self:print(elseifNode.elseIfKeyword))
		table.insert(output, self:print(elseifNode.condition))
		table.insert(output, self:print(elseifNode.thenKeyword))
		table.insert(output, self:print(Rewriter.getThenBody(elseifNode)))
	end

	if parts.elseKeyword then
		table.insert(output, self:_printTokenOverride(parts.elseKeyword))
	end
	if parts.elseBody then
		table.insert(output, self:print(parts.elseBody))
	end
	if parts.endKeyword then
		table.insert(output, self:print(parts.endKeyword))
	end

	self:_setReplacement(node, table.concat(output))
end

function Rewriter.setLocalMerge(self: Rewriter, statement: syntax.CstStatLocal, merge: LocalMerge)
	assert(#statement.variables == 1, "can only merge local declarations with a single variable")
	self._localMerges[statement] = merge

	local variable = statement.variables[1]
	local output = {
		self:print(statement.localKeyword),
		printTrivia(variable.name.leadingTrivia),
		variable.name.text,
		printTrivia(merge.nameTrailingTrivia),
	}
	if variable.colon then
		table.insert(output, self:print(variable.colon))
	end
	if variable.annotation then
		table.insert(output, self:print(variable.annotation))
	end
	table.insert(output, self:print(merge.equals))
	table.insert(output, self:_printPunctuated(merge.values))

	self:_setReplacement(statement, table.concat(output))
end

--[[
	Visits the node using the provided visitor, traversing the tree as it looks after the rewrites made so far.
	Expressions which were replaced with constant booleans are not traversed into; `onConstant` is called instead.
]]
function Rewriter.visit(
	self: Rewriter,
	node: syntax.CstNode,
	base: visitor.Visitor,
	onConstant: ((leadingTrivia: { syntax.Trivia }, trailingTrivia: { syntax.Trivia }) -> ())?
)
	local effectiveVisitor = table.clone(base)

	local function visitBody(body: ConditionalBody)
		if body.kind == "stat" then
			visitor.visitBlock(body, effectiveVisitor)
		else
			visitor.visitExpression(body, effectiveVisitor)
		end
	end

	local function visitConditionalParts(parts: ConditionalParts)
		visitor.visitToken(parts.ifKeyword.token, effectiveVisitor)
		visitor.visitExpression(parts.condition, effectiveVisitor)
		visitor.visitToken(parts.thenKeyword, effectiveVisitor)
		visitBody(parts.thenBody)
		for _, elseifNode in parts.elseifs do
			visitor.visitToken(elseifNode.elseIfKeyword, effectiveVisitor)
			visitor.visitExpression(elseifNode.condition, effectiveVisitor)
			visitor.visitToken(elseifNode.thenKeyword, effectiveVisitor)
			visitBody(Rewriter.getThenBody(elseifNode))
		end
		if parts.elseKeyword then
			visitor.visitToken(parts.elseKeyword.token, effectiveVisitor)
		end
		if parts.elseBody then
			visitBody(parts.elseBody)
		end
		if parts.endKeyword then
			visitor.visitToken(parts.endKeyword, effectiveVisitor)
		end
	end

	effectiveVisitor.visitExpr = function(expression: syntax.CstExpr)
		local constant = self._constants[expression]
		if constant then
			if onConstant then
				onConstant(constant.leadingTrivia, constant.trailingTrivia)
			end
			return false
		end

		local alias = self._aliases[expression]
		if alias then
			visitor.visitExpression(alias, effectiveVisitor)
			return false
		end

		return base.visitExpr(expression)
	end

	effectiveVisitor.visitExprTable = function(expression: syntax.CstExprTable)
		local entries = self._tableEntries[expression]
		if entries == nil then
			return base.visitExprTable(expression)
		end

		if base.visitExprTable(expression) then
			visitor.visitToken(expression.openBrace, effectiveVisitor)
			for _, entry in entries do
				visitor.visit(entry :: any, effectiveVisitor)
			end
			visitor.visitToken(expression.closeBrace, effectiveVisitor)
		end
		return false
	end

	effectiveVisitor.visitExprIfElse = function(expression: syntax.CstExprIfElse)
		local parts = self._conditionals[expression]
		if parts == nil then
			return base.visitExprIfElse(expression)
		end

		if base.visitExprIfElse(expression) then
			visitConditionalParts(parts)
		end
		return false
	end

	effectiveVisitor.visitStatIf = function(statement: syntax.CstStatIf)
		local parts = self._conditionals[statement]
		if parts == nil then
			return base.visitStatIf(statement)
		end

		if base.visitStatIf(statement) then
			visitConditionalParts(parts)
		end
		return false
	end

	effectiveVisitor.visitStatBlock = function(block: syntax.CstStatBlock)
		local statements = self._blockStatements[block]
		if statements == nil then
			return base.visitStatBlock(block)
		end

		if base.visitStatBlock(block) then
			for _, statement in statements do
				visitor.visitStatement(statement, effectiveVisitor)
			end
			base.visitStatBlockEnd(block)
		end
		return false
	end

	effectiveVisitor.visitStatLocalDeclaration = function(statement: syntax.CstStatLocal)
		local merge = self._localMerges[statement]
		if merge == nil then
			return base.visitStatLocalDeclaration(statement)
		end

		if base.visitStatLocalDeclaration(statement) then
			visitor.visitToken(statement.localKeyword, effectiveVisitor)
			visitor.visit(statement.variables[1], effectiveVisitor)
			visitor.visitToken(merge.equals, effectiveVisitor)
			for i, value in merge.values do
				visitor.visitExpression(value, effectiveVisitor)
				local separator = merge.values.separators[i]
				if separator then
					visitor.visitToken(separator, effectiveVisitor)
				end
			end
			base.visitStatLocalDeclarationEnd(statement)
		end
		return false
	end

	visitor.visit(node, effectiveVisitor)
end

--- Returns the leading trivia of the first token of the (rewritten) expression
function Rewriter.leadingTrivia(self: Rewriter, expression: syntax.CstExpr): { syntax.Trivia }
	local result: { syntax.Trivia }? = nil

	local finder = visitor.create()
	finder.visitToken = function(token: syntax.CstToken)
		if result == nil then
			result = token.leadingTrivia
		end
		return false
	end

	self:visit(expression, finder, function(leadingTrivia)
		if result == nil then
			result = leadingTrivia
		end
	end)

	return result or {}
end

--- Returns the trailing trivia of the last token of the (rewritten) expression
function Rewriter.trailingTrivia(self: Rewriter, expression: syntax.CstExpr): { syntax.Trivia }
	local result: { syntax.Trivia }? = nil

	local finder = visitor.create()
	finder.visitToken = function(token: syntax.CstToken)
		result = token.trailingTrivia
		return false
	end

	self:visit(expression, finder, function(_, trailingTrivia)
		result = trailingTrivia
	end)

	return result or {}
end

return Rewriter
