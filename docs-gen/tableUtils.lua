local function getTableSignature(node: luau.AstExprTable)
	-- if list, document name and type
    return ""
	-- else, document full table without values (name, type, keys)
end

return {
	getTableSignature = getTableSignature,
}
