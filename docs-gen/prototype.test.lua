local visitor = require("@std/syntax/visitor")
local parser = require("@std/syntax/parser")
local prototypes = require("./prototype")

-- get

local testVisitor = visitor.createVisitor()
local function visitFunction(node: AstStatLocalFunction | AstStatFunction)
	local nodeSig = prototypes.getFunctionSignature(node)
	print(`Evaluated {node.name.name.text} function as:`, nodeSig, "\n")
	return true
end

testVisitor.visitLocalFunction = visitFunction

testVisitor.visitFunction = visitFunction

testVisitor.visitTypeAlias = function(node: luau.AstType)
	local typeSig = prototypes.getTypeSignature(node)
	print("visiting type")
	print(`Evaluated {node.name.text} type as:`, typeSig, "\n")
	return true
end

local testSrc = [[

type FileVisitor = {
    visitor: visitor.Visitor,
    varMap: varMap,
    typeMap: typeMap,
}

function getFileMap<T>(filePath: string, ...: T): (varMap, typeMap)
	local src = fs.readfiletostring(filePath)
    local srcAST = parser.parse(src)
    local VarMapVisitor = VarMapVisitor.new()
    VarMapVisitor.visitor.visitBlock(srcAST)
    return VarMapVisitor.varMap, VarMapVisitor.typeMap
end

local function getFunctionParameters(node: luau.AstStatFunction | luau.AstStatLocalFunction): string
    local res = ""
    res ..= getTokenText(node.openParens)
    local params: luau.Punctuated<AstLocal> = node.body.parameters
    for _, param in params do
        res ..= getFunctionParameter(param.node)
        res ..= getTokenText(param.separator)
    end
    res ..= getTokenText(node.closeParens)
    return res
end

return getFileMap
]]

local testAST = parser.parse(testSrc)
visitor.visitBlock(testAST, testVisitor)

-- just an eye-test file for now; will add more complex asserts later...

local FileVisitor = prototypes.FileVisitor.new()

FileVisitor:analyzeFile("../roblox/foundation/modules/foundation/src/Components/Accordion/init.lua")

print("\nTypes:")
for k, v in FileVisitor.typeMap do
	print(k, v)
end
print("\nVars:")
for k, v in FileVisitor.varMap do
	print(k, v)
end
print("\nReturned Vars:")
for k, v in FileVisitor.returnedVars do
	print(k, v.tag)
end
print("\n\Required Vars:")
for k, v in FileVisitor.requires do
	print(k, v)
end
-- print("\nDocumented Function Signatures")
-- FileVisitor:getFunctionDocumentation()
-- print("\nDocumented Type Signatures")
-- FileVisitor:getTypeDocumentation()
