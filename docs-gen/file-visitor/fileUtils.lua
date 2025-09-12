local visitor = require("@std/syntax/visitor")
local json = require("@batteries/json")
local fs = require("@lute/fs")
local luau = require("@lute/luau")
local isRequire = require("../../require-resolver/isRequire")

function exprContainsRequire(node: luau.AstExpr)
	-- see if require exists at all in expression (bc it cud be index/indexname require, etc)
	local hasRequire = false
	local reqVisitor = visitor.createVisitor()
	reqVisitor.visitExpression = function(node: luau.AstExpr)
		hasRequire = hasRequire or isRequire(node)
		return true
	end

	local _succ, _res = pcall(function()
		visitor.visitExpression(node, reqVisitor)
	end)

	return hasRequire
end

local function parseAliases(content: string): { [string]: string }
	local ok, data = pcall(function()
		return json.deserialize(content)
	end)

	if not ok or type(data) ~= "table" or type(data.aliases) ~= "table" then
		return {}
	end

	local aliases = {}
	for k, v in pairs(data.aliases) do
		aliases[k] = v
	end
	return aliases
end

local function getAliasMap(luauRcPath: string?): { [string]: string }
	if not luauRcPath then
		return {}
	end
	local luauRcContent = fs.readfiletostring(luauRcPath)
	return parseAliases(luauRcContent)
end

return {
	containsRequire = exprContainsRequire,
	getAliasMap = getAliasMap,
}
