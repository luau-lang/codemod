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

	The `isModified` and `setModified` functions are utilities to determine if a given expression was previously
	modified by the flag clipping tool, to check for these cases.
]]

local luau = require("@lute/luau")

--- Check whether the given expression was modified by the flag-clipper tool
local function isModified(expression: luau.AstExpr): boolean
	return (expression :: any)._modified == true
end

--- Mark the given expression as modified
local function setModified(expression: luau.AstExpr)
	(expression :: any)._modified = true
end

-- Check whether the given expression is marked as compound
-- explicitly to avoid removing table entries that have had their values simplified to a direct flag reference
-- for ex, suppose flag is true and we have: local table = { field = flag and something }
-- expressions simplify from inside out (post-order)
-- so we get to simplifying the table itself, we have: { field = flag }
-- normally, these are removed but bc value was originally `flag and something` we want to keep entry
-- so, we provide a unique marker to catch these cases
local function isCompound(expression: luau.AstExpr): boolean
	return (expression :: any)._compound == true
end

local function setCompound(expression: luau.AstExpr)
	(expression :: any)._compound = true
end

return {
	isModified = isModified,
	setModified = setModified,
	isCompound = isCompound,
	setCompound = setCompound,
}
