local luau = require("@lute/luau")
local commonHelpers = require("./commonHelpers")
local getTokenText, getPunctuated, getGeneric, getTypeText, getTrivia =
	commonHelpers.getTokenText,
	commonHelpers.getPunctuated,
	commonHelpers.getGeneric,
	commonHelpers.getTypeText,
	commonHelpers.getTrivia

--[[
getFunctionSignature(functionDeclarationNode: AstStatFunction | AstStatLocalFunction): string

want to extract everything but the function body itself; can use printer to print resultant string
maybe just fill the body with "..."
]]
local function getFunctionReturnSignature(node: luau.AstFunctionBody): string
	return getTokenText(node.returnSpecifier) .. getTypeText(node.returnAnnotation)
end

local function getFunctionGenerics(node: luau.AstFunctionBody): string
	local res = ""
	res ..= getTokenText(node.openGenerics)
	res ..= getPunctuated(node.generics, getGeneric)
	res ..= getPunctuated(node.genericPacks, getGeneric)
	res ..= getTokenText(node.closeGenerics)
	return res
end

local function getFunctionVarArgs(node: luau.AstFunctionBody): string
	return getTokenText(node.vararg) .. getTokenText(node.varargColon) .. getTypeText(node.varargAnnotation)
end

local function getFunctionParameter(node: AstLocal): string
	if node then
		return getTokenText(node.name) .. getTokenText(node.colon) .. getTypeText(node.annotation)
	end
	return ""
end

local function getFunctionParameters(node: luau.AstFunctionBody): string
	local res = ""
	res ..= getTokenText(node.openParens)
	-- need to handle varargs here
	local params: luau.Punctuated<AstLocal> = node.parameters
	res ..= getPunctuated(params, getFunctionParameter)
	res ..= getFunctionVarArgs(node)
	res ..= getTokenText(node.closeParens)
	return res
end

--[[
get name (astLocal or astExprGlobal, both have name token)
want to get function keyword
optionally localKeyword (only applies to local obvi)
then from body, we extract:
    - vararg (optional)
    - parameters (astLocals with type)
    - 
-- we'll want to expand to support extracting docs comments above function declaration; which we should process in special way
]]
function getFunctionSignature(node: luau.AstStatFunction | luau.AstStatLocalFunction | luau.AstExprAnonymousFunction): string
	local docsComments = if node.localKeyword then getTrivia(node.localKeyword) else getTrivia(node.functionKeyword)
	local functionName = getTokenText(if node.name then node.name.name else "") -- need to handle index name functions and : functions
	local functionKeyword, localKeyword = getTokenText(node.functionKeyword), getTokenText(node.localKeyword)
	local functionGenerics = getFunctionGenerics(node.body)
	local functionParams = getFunctionParameters(node.body) -- need to handle varargs
	local functionReturnSignature = getFunctionReturnSignature(node.body)
	return localKeyword
		.. functionKeyword
		.. functionName
		.. functionGenerics
		.. functionParams
		.. functionReturnSignature
end

return {
	getFunctionSignature = getFunctionSignature,
	getFunctionGenerics = getFunctionGenerics,
	getFunctionVarArgs = getFunctionVarArgs,
	getFunctionParameters = getFunctionParameters,
}
