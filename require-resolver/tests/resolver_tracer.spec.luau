local parser = require("@std/syntax/parser")

local resolver = require("../resolver")
local tracer = require("../tracer")

local function assertResolves(expr: string, value: string?, currentModuleName: string?)
	local block = parser.parse(`require({expr})`)
	assert(block)

	local expressionStmt = block.statements[1]
	assert(expressionStmt.tag == "expression")

	local call = expressionStmt.expression
	assert(call.tag == "call")

	local fileResolver = resolver.createFileResolver()
	local tracerResult = tracer.traceRequires(block, currentModuleName or "", fileResolver)

	local result = tracerResult[call]

	if result and value then
		assert(result.moduleName == value, `'{result.moduleName}' == '{value}'`)
	elseif result and not value then
		assert(false, `expected '{result.moduleName}' to be nil`)
	elseif not result and value then
		assert(false, `expected to resolve to '{value}', got nil`)
	end
end

local function test_resolvesGameGlobal()
	assertResolves("game", "game")
end

local function test_resolveAbsoluteIndexName()
	assertResolves("game.ReplicatedStorage.Module", "game/ReplicatedStorage/Module")
end

local function test_resolveAbsoluteIndexNameParent()
	assertResolves("game.ReplicatedStorage.Module.Parent", "game/ReplicatedStorage")
end

local function test_resolveAbsoluteIndexExpr()
	assertResolves("game.ReplicatedStorage['Module']", "game/ReplicatedStorage/Module")
end

local function test_resolveAbsoluteIndexExprParent()
	assertResolves("game.ReplicatedStorage.Module['Parent']", "game/ReplicatedStorage")
end

local function test_resolveGetService()
	assertResolves('game:GetService("ReplicatedStorage").Module', "game/ReplicatedStorage/Module")
end

local function test_resolveWaitForChild()
	assertResolves('game:WaitForChild("Module")', "game/Module")
end

local function test_resolveFindFirstChild()
	assertResolves('game:FindFirstChild("Module")', "game/Module")
end

local function test_recursiveFindFirstChildFails()
	assertResolves('game:FindFirstChild("Module", true)', nil)
end

local function test_resolveFindFirstAncestor()
	assertResolves('game.ReplicatedStorage.Module:FindFirstAncestor("ReplicatedStorage")', "game/ReplicatedStorage")
end

local function test_findFirstAncestorFailsIfMissing()
	assertResolves('game.ReplicatedStorage.Module:FindFirstAncestor("Other")', nil)
end

local function test_resolveRelativeToScript()
	assertResolves("script.Module", "game/ExampleScript/Module", "game/ExampleScript")
end

return function()
	test_resolvesGameGlobal()
	test_resolveAbsoluteIndexName()
	test_resolveAbsoluteIndexNameParent()
	test_resolveAbsoluteIndexExpr()
	test_resolveAbsoluteIndexExprParent()
	test_resolveGetService()
	test_resolveWaitForChild()
	test_resolveFindFirstChild()
	test_recursiveFindFirstChildFails()
	test_resolveFindFirstAncestor()
	test_findFirstAncestorFailsIfMissing()
	test_resolveRelativeToScript()
end
