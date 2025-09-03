local visitor = require("@std/syntax/visitor")
local luau = require("@lute/luau")

type Visitor = (node: any, visitor: visitor.Visitor) -> boolean

local function isAnonymousFunction(node: luau.AstExpr)
	return node.tag == "function" and not node.name
end

local function isFunction(node: luau.AstExpr | luau.AstStat)
	return node.tag and node.tag == "localfunction" or node.tag == "function" or node.tag == "anonymousfunction"
end

local function getGeneric(node: luau.AstGenericType | luau.AstGenericPack)
	local res = ""
	res ..= getTokenText(node.name)
	if node.ellipsis then
		res ..= getTokenText(node.ellipsis)
	end
	if node.equals then
		res ..= getTokenText(node.equals)
	end
	if node.default then
		res ..= getTypeText(node.default)
	end
	return res
end

function getNodeText(node, apply: Visitor): string
	local text = ""
	if node then
		local textVisitor = visitor.createVisitor()
		textVisitor.visitToken = function(node: luau.Token)
			text ..= getTokenText(node)
			return true
		end
		apply(node, textVisitor)
	end
	return text
end

function getPunctuated(node, apply: (node: any) -> string): string
	local res = ""
	if node then
		for _, item in node do
			res ..= apply(item.node)
			res ..= getTokenText(item.separator)
		end
	end
	return res
end

function getTrivia(node: { luau.Trivia }): string
	local res = ""
	for a, item in node do
		res ..= item.text or ""
	end
	return res
end

function getTokenText(node: luau.Token): string
	if node and node.text then
		return getTrivia(node.leadingTrivia) .. node.text :: string .. getTrivia(node.trailingTrivia)
	else
		return ""
	end
end

function getTypeText(node: luau.AstType | luau.AstTypePack): string
	if node and (node.tag == "explicit" or node.tag == "generic" or node.tag == "variadic") then
		return getNodeText(node, visitor.visitTypePack)
	else
		return getNodeText(node, visitor.visitType)
	end
end

-- mashallah for visitLocal reference + visitGlobal
function findReferencedVariables(node: any): { [string]: boolean }
	local referencedVars = {}
	local referenceVisitor = visitor.createVisitor()
	referenceVisitor.visitLocalReference = function(node: luau.AstExprLocal)
		local referencedName = node.token.text
		referencedVars[referencedName] = true
		return true
	end

	referenceVisitor.visitGlobal = function(node: luau.AstExprGlobal)
		local referencedName = node.name.text
		referencedVars[referencedName] = true
		return true
	end

	visitor.visitExpression(node, referenceVisitor)

	return referencedVars
end

return {
	isAnonymousFunction = isAnonymousFunction,
	isFunction = isFunction,
	getNodeText = getNodeText,
	getTrivia = getTrivia,
	getTokenText = getTokenText,
	getTypeText = getTypeText,
	getPunctuated = getPunctuated,
	getGeneric = getGeneric,
	findReferencedVariables = findReferencedVariables,
}
