local luau = require("@lute/luau")
local visitor = require("@std/syntax/visitor")
local commonHelpers = require("./commonHelpers")
local getLocal = commonHelpers.getLocal
local getTokenText = commonHelpers.getTokenText
local getNodeText = commonHelpers.getNodeText
local getTrivia = commonHelpers.getTrivia

local function isListTable(node: luau.AstExprTable): boolean
	local entries = node.entries
	if not entries[1] then
		return false
	end -- can't determine if there are no entries in table
	return entries[1].kind == "list"
end

local function getTableKeySignature(entry: luau.AstExprTableItem)
	local keyText = ""
	if entry.kind == "general" then
		keyText ..= getTokenText(entry.indexerOpen)
		keyText ..= getNodeText(entry.key, visitor.visitExpression)
		keyText ..= getTokenText(entry.indexerClose)
	elseif entry.kind == "record" then
		keyText = getTokenText(entry.key)
	end
	keyText = commonHelpers.trim(keyText)
	keyText ..= getTokenText(entry.separator)
	return keyText
end

local function getTableKeys(entries: { luau.AstExprTableItem })
	local keys = ""
	for _, entry in entries do
		keys ..= getTableKeySignature(entry)
	end
	return keys
end

local function getAnonymousTableSignature(node: luau.AstExprTable): string
	if not node then
		return ""
	end
	-- if list, document name and type; a little tricker if anonymous since we need to infer type of list items
	if isListTable(node) then
		-- not sure how to handle this best
		return ""
	else -- else, document full table brackets and keys (not values) (keys)
		return getTokenText(node.openBrace) .. getTableKeys(node.entries) .. getTokenText(node.closeBrace)
	end
end

local function getLocalTableSignature(var: luau.AstLocal, value: luau.AstExprTable, equals: luau.Token): string
	local varText = getLocal(var)
	local tableText = getAnonymousTableSignature(value)
	return varText .. getTokenText(equals) .. tableText
end

return {
	getAnonymousTableSignature = getAnonymousTableSignature,
	getLocalTableSignature = getLocalTableSignature,
	getTableKeySignature = getTableKeySignature,
	getTableKeys = getTableKeys,
}
