local functionUtils = require("./functionUtils")
local parser = require("@std/syntax/parser")

function trim(s)
	return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function testFunctionSignature(functionSrc: string, expectedSig: string)
	local srcNode = parser.parse(functionSrc)
	local funcNode = srcNode.statements[1]
	local result = trim(functionUtils.getFunctionSignature(funcNode))
	-- strip whitespace at start and end for simplicity
	assert(result == expectedSig, `{result} does not match: {expectedSig}`)
	print(`Correctly got signature: {result}\nfor:\n{functionSrc}`)
end

local function test_getFunctionGenerics()
	local src = "function <T...>() return end"
	local srcNode = parser.parseexpr(src)
	local result = functionUtils.getFunctionGenerics(srcNode.body)
	assert(result == "<T...>", `{result} does not match: <T...>`)
end

local function test_getFunctionVarArgs()
	local src = "function (...: string) return end"
	local srcNode = parser.parseexpr(src)
	local result = functionUtils.getFunctionVarArgs(srcNode.body)
	assert(result == "...: string", `{result} does not match: ...: string`)
end

local function test_getFunctionParameters()
	local src = "function (a: string, b: number) return end"
	local srcNode = parser.parseexpr(src)
	local result = functionUtils.getFunctionParameters(srcNode.body)
	assert(result == "(a: string, b: number) ", `{result} does not match: (a: string, b: number) `)
end

local function test_getLocalFunctionSignature()
	local localFunc = [[
	local function f<T>(a: T, b: string, ...: T): T
		return a
	end
    ]]
	local sig = "local function f<T>(a: T, b: string, ...: T): T"
	testFunctionSignature(localFunc, sig)
end

local function test_getGlobalFunctionSignature()
	local globalFunc = [[
	function f<T>(a: T, b: string, ...: T): T
		return a
	end
    ]]
	local sig = "function f<T>(a: T, b: string, ...: T): T"
	testFunctionSignature(globalFunc, sig)
end

local function test_getAnonymousFunctionSignature()
	local anonymousFunc = [[
	function <T>(a: T, b: string, ...: T): T
		return a 
	end
	]]
	local sig = "function <T>(a: T, b: string, ...: T): T"
	local srcNode = parser.parseexpr(anonymousFunc) -- parsing as expression will ensure this src string is evaluated as anonymous
	local result = trim(functionUtils.getFunctionSignature(srcNode))
	-- strip whitespace at start and end for simplicity
	assert(result == sig, `{result} does not match: {sig}`)
end

local function test_indexFunctionSignature()
	local indexFunc = [[
	function f.foo<T>(a: T, b: string, ...: T): T
		return a
	end
    ]]
	local sig = "function f.foo<T>(a: T, b: string, ...: T): T"
	testFunctionSignature(indexFunc, sig)
	indexFunc = [[
	function f:foo<T>(a: T, b: string, ...: T): T
		return a
	end
    ]]
	sig = "function f:foo<T>(a: T, b: string, ...: T): T"
	testFunctionSignature(indexFunc, sig)
end

local function test_getFunctionSignature()
	test_getAnonymousFunctionSignature()
	test_getGlobalFunctionSignature()
	test_getLocalFunctionSignature()
	test_indexFunctionSignature()
end

test_getFunctionGenerics()
test_getFunctionVarArgs()
test_getFunctionParameters()
test_getFunctionSignature()
