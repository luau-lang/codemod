local luau = require("@lute/luau")
local parser = require("@std/syntax/parser")
local tableUtils = require("./tableUtils")
local visitor = require("@std/syntax/visitor")

function trim(s)
	return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function test_getTableKeySignature()
	local testTable = [[{ key1 = 1, key2 = 2, ["key3"] = "aaaaa", }]]
	local testNode = parser.parseexpr(testTable)
	local entryNodes: { luau.AstExprTableItem } = {}
	local getEntriesVisitor = visitor.createVisitor()
	getEntriesVisitor.visitTableItem = function(node: luau.AstExprTableItem)
		table.insert(entryNodes, node)
		return true
	end
	visitor.visitExpression(testNode, getEntriesVisitor)
	-- visitor will visit keys in order; we will expect signatures in order
	local expectedSignatures = { "key1,", "key2,", "[key3]," } -- AST parser drops the quotes for 3rd key
	for i, entry in entryNodes do
		local result = tableUtils.getTableKeySignature(entry)
		assert(trim(result) == expectedSignatures[i], `Incorrectly printed {expectedSignatures[i]} as {result}`)
	end
end

local function test_getAnonymousTableSignature()
	local testTable = [[{ key1 = 1, key2 = 2, ["key3"] = "aaaaa", }]]
	local testNode = parser.parseexpr(testTable)
	local result = tableUtils.getAnonymousTableSignature(testNode)
	local expectedResult = "{ key1, key2, [key3], }"
	assert(trim(result) == expectedResult, `Incorrectly printed {expectedResult} as {result}`)
end

local function test_getLocalTableSignature()
	local testTable = [[local t: { string | number } = { key1 = 1, key2 = 2, ["key3"] = "aaaaa", }]]
	local testNode = parser.parse(testTable).statements[1]
	local var = testNode.variables[1].node
	local val = testNode.values[1].node
	local result = tableUtils.getLocalTableSignature(var, val, testNode.equals)
	local expectedResult = "t: { string | number } = { key1, key2, [key3], }"
	assert(trim(result) == expectedResult, `Incorrectly printed {expectedResult} as {result}`)
end

test_getTableKeySignature()
test_getAnonymousTableSignature()
test_getLocalTableSignature()
